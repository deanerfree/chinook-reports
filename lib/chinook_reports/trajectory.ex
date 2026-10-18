defmodule ChinookReports.Trajectory do
  @moduledoc """
  Minimum-curvature wellbore trajectory integration.

  Turns a list of angular survey stations (measured depth, inclination and
  azimuth) into cartesian positions — TVD, north/south, east/west and the
  vertical section projected onto the surface→bottom azimuth.

  Used to derive a plotted trajectory from a *prognosed* (planned) survey, which
  the extraction only carries as angles, so it can be drawn against the actual
  survey and compared at total depth.
  """

  @type station :: %{md: number(), inc_deg: number(), azi_deg: number()}
  @type point :: %{
          md: float(),
          tvd: float(),
          north: float(),
          east: float(),
          vertical_section: float()
        }

  @doc """
  Integrate `stations` (sorted or unsorted) with the minimum-curvature method.

  Returns `[]` for fewer than two usable stations. The vertical section of every
  point is projected onto the azimuth from the wellhead to the final point.
  """
  @spec integrate([station()]) :: [point()]
  def integrate(stations) when is_list(stations) do
    case parse(stations) do
      [_, _ | _] = parsed -> build(parsed)
      _ -> []
    end
  end

  def integrate(_), do: []

  @doc """
  The trajectory at each of `stations`, for listing a planned path alongside an
  actual survey: `md`, `tvd`, `north`, `east`, `vertical_section` and
  `dogleg_severity` (°/30 m, `0.0` at the first station), sorted by MD with
  unusable stations dropped.

  A program that starts below surface is tied in vertically at the wellhead
  (see `tie_in_at_surface/1`); the tie-in point itself is not returned.
  """
  @spec stations([station()]) :: [map()]
  def stations(stations) when is_list(stations) do
    case parse(stations) do
      [] ->
        []

      parsed ->
        tied = tie_in_at_surface(parsed)

        dls =
          tied
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.map(fn [a, b] ->
            d_md = b.md - a.md
            if d_md > 0, do: interval(a, b).dogleg_deg / d_md * 30.0, else: 0.0
          end)

        tied
        |> build()
        |> Enum.zip([0.0 | dls])
        |> Enum.map(fn {p, d} -> Map.put(p, :dogleg_severity, d) end)
        |> Enum.drop(length(tied) - length(parsed))
    end
  end

  def stations(_), do: []

  @doc """
  Prepend a vertical station at the wellhead (MD 0) to MD-sorted `stations`
  that start below surface — a program typed in from the kick-off point down
  still starts vertical at the wellhead.
  """
  @spec tie_in_at_surface([station()]) :: [station()]
  def tie_in_at_surface([%{md: md} | _] = rows) when md > 0,
    do: [%{md: 0.0, inc_deg: 0.0, azi_deg: 0.0} | rows]

  def tie_in_at_surface(rows), do: rows

  @doc """
  Position (`md`, `tvd`, `north`, `east`) of the trajectory described by
  `stations` at measured depth `md`.

  Between stations the integrated positions are interpolated linearly; past the
  final station the hole is projected straight ahead on the last station's
  inclination and azimuth (the usual "projection to bit"). Returns `nil` when
  there are fewer than two usable stations or `md` is above the first one.
  """
  @spec position_at([station()], number()) ::
          %{md: float(), tvd: float(), north: float(), east: float()} | nil
  def position_at(stations, md) when is_number(md), do: hd(positions_at(stations, [md]))
  def position_at(_, _), do: nil

  @doc """
  `position_at/2` for each of `mds`, integrating `stations` once. Each entry is
  `nil` where `position_at/2` would be.
  """
  @spec positions_at([station()], [number()]) ::
          [%{md: float(), tvd: float(), north: float(), east: float()} | nil]
  def positions_at(stations, mds) when is_list(stations) and is_list(mds) do
    case parse(stations) do
      [_, _ | _] = parsed ->
        curve = build(parsed)
        last = List.last(parsed)

        Enum.map(mds, fn md ->
          if is_number(md) and md >= hd(curve).md, do: locate(curve, last, md)
        end)

      _ ->
        Enum.map(mds, fn _ -> nil end)
    end
  end

  def positions_at(_, mds) when is_list(mds), do: Enum.map(mds, fn _ -> nil end)

  defp locate(curve, last_station, md) do
    last = List.last(curve)

    if md >= last.md do
      project(last, last_station, md - last.md)
    else
      curve
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.find(fn [a, b] -> md >= a.md and md <= b.md end)
      |> interpolate(md)
    end
  end

  defp parse(stations) do
    stations
    |> Enum.map(&normalize_station/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.md)
    |> Enum.dedup_by(& &1.md)
  end

  defp project(p, station, d_md) do
    inc = deg2rad(station.inc_deg)
    azi = deg2rad(station.azi_deg)

    %{
      md: p.md + d_md,
      tvd: p.tvd + d_md * :math.cos(inc),
      north: p.north + d_md * :math.sin(inc) * :math.cos(azi),
      east: p.east + d_md * :math.sin(inc) * :math.sin(azi)
    }
  end

  defp interpolate([a, b], md) do
    f = if b.md == a.md, do: 0.0, else: (md - a.md) / (b.md - a.md)
    lerp = fn k -> Map.fetch!(a, k) + f * (Map.fetch!(b, k) - Map.fetch!(a, k)) end

    %{md: md * 1.0, tvd: lerp.(:tvd), north: lerp.(:north), east: lerp.(:east)}
  end

  defp build(stations) do
    positions =
      stations
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.reduce([%{md: hd(stations).md, tvd: 0.0, north: 0.0, east: 0.0}], fn [a, b], acc ->
        %{tvd: tvd, north: n, east: e} = hd(acc)
        {d_tvd, d_n, d_e} = segment(a, b)

        [%{md: b.md, tvd: tvd + d_tvd, north: n + d_n, east: e + d_e} | acc]
      end)
      |> Enum.reverse()

    %{north: fn_, east: fe} = List.last(positions)
    vs_azi = :math.atan2(fe, fn_)

    Enum.map(positions, fn p ->
      Map.put(
        p,
        :vertical_section,
        p.north * :math.cos(vs_azi) + p.east * :math.sin(vs_azi)
      )
    end)
  end

  @doc """
  Minimum-curvature step between two stations (`%{md, inc_deg, azi_deg}`):
  the change in TVD / north / east over the interval and its dogleg in degrees.
  """
  @spec interval(station(), station()) ::
          %{tvd: float(), north: float(), east: float(), dogleg_deg: float()}
  def interval(a, b) do
    {d_tvd, d_n, d_e, beta} = step(a, b)
    %{tvd: d_tvd, north: d_n, east: d_e, dogleg_deg: beta * 180.0 / :math.pi()}
  end

  # Minimum-curvature contribution of the interval between stations `a` and `b`.
  defp segment(a, b) do
    {d_tvd, d_n, d_e, _beta} = step(a, b)
    {d_tvd, d_n, d_e}
  end

  defp step(a, b) do
    i1 = deg2rad(a.inc_deg)
    i2 = deg2rad(b.inc_deg)
    a1 = deg2rad(a.azi_deg)
    a2 = deg2rad(b.azi_deg)
    d_md = b.md - a.md

    cos_beta =
      :math.cos(i2 - i1) - :math.sin(i1) * :math.sin(i2) * (1 - :math.cos(a2 - a1))

    beta = :math.acos(clamp(cos_beta, -1.0, 1.0))
    rf = if beta < 1.0e-9, do: 1.0, else: 2.0 / beta * :math.tan(beta / 2.0)
    half = d_md / 2.0 * rf

    d_tvd = half * (:math.cos(i1) + :math.cos(i2))
    d_n = half * (:math.sin(i1) * :math.cos(a1) + :math.sin(i2) * :math.cos(a2))
    d_e = half * (:math.sin(i1) * :math.sin(a1) + :math.sin(i2) * :math.sin(a2))

    {d_tvd, d_n, d_e, beta}
  end

  defp normalize_station(%{} = s) do
    md = num(s[:md] || s["md"])
    inc = num(s[:inc_deg] || s["inc_deg"] || s["inclination_deg"])
    azi = num(s[:azi_deg] || s["azi_deg"] || s["azimuth_deg"])

    if is_number(md) and is_number(inc) and is_number(azi) do
      %{md: md * 1.0, inc_deg: inc * 1.0, azi_deg: azi * 1.0}
    end
  end

  defp normalize_station(_), do: nil

  defp num(v) when is_number(v), do: v
  defp num(%Decimal{} = v), do: Decimal.to_float(v)

  defp num(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp num(_), do: nil

  defp deg2rad(d), do: d * :math.pi() / 180.0

  defp clamp(v, lo, _hi) when v < lo, do: lo
  defp clamp(v, _lo, hi) when v > hi, do: hi
  defp clamp(v, _lo, _hi), do: v
end
