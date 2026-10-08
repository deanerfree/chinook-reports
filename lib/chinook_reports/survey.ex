defmodule ChinookReports.Survey do
  @moduledoc """
  Recomputes an imported directional survey (`reservoir_data[].survey`) after
  its stations are edited.

  Each station's MD, inclination and azimuth are the inputs; TVD, N/S, E/W,
  vertical section, dogleg severity (°/30 m) and subsea are derived by minimum
  curvature (`ChinookReports.Trajectory.interval/2`), with subsea = KB − TVD.

  Recomputation starts at the first station that differs from the stored
  survey. Stations above it keep the values the extractor wrote, so saving an
  untouched survey (or editing only remarks) changes nothing, and appending
  today's stations leaves history alone. The first station is tied in
  vertically (TVD = MD), as the extractor does. Recomputed rows project their
  vertical section onto the wellhead → final-station azimuth.

  `markers` (KOP, tops, Last Survey…) are positions at an MD along the survey;
  those at or below the first changed station are re-interpolated, and
  "Last Survey" follows the deepest station.
  """

  alias ChinookReports.Trajectory

  @derived ~w(tvd north_south east_west vertical_section dogleg_severity subsea)

  @doc "Keys computed from the station inputs."
  def derived_keys, do: @derived

  @doc """
  Recompute `new_points` (station maps with numeric `md` / `inclination_deg` /
  `azimuth_deg`, any order) against the stored `old_points`.

  Returns `{points, first_changed_md}` — points sorted by MD, and the MD from
  which values were recomputed (`nil` if nothing changed).
  """
  @spec recompute([map()], [map()], number() | nil) :: {[map()], number() | nil}
  def recompute(old_points, new_points, kb) do
    old = Enum.sort_by(old_points, & &1["md"])
    new = Enum.sort_by(new_points, & &1["md"])

    case first_change(old, new) do
      nil ->
        {Enum.zip_with(old, new, &Map.merge(&1, Map.drop(&2, @derived))), nil}

      k ->
        {kept, rest} = Enum.split(new, k)
        kept = Enum.zip_with(Enum.take(old, k), kept, &Map.merge(&1, Map.drop(&2, @derived)))

        computed =
          rest
          |> Enum.reduce({List.last(kept), []}, fn st, {prev, acc} ->
            p = advance(prev, st)
            {p, [p | acc]}
          end)
          |> elem(1)
          |> Enum.reverse()

        last = List.last(computed)
        vs_azi = :math.atan2(last["east_west"], last["north_south"])

        computed =
          Enum.map(computed, fn p ->
            p
            |> Map.put("vertical_section", vs(p, vs_azi))
            |> Map.put("subsea", kb && kb - p["tvd"])
          end)

        {kept ++ computed, Enum.at(new, k)["md"]}
    end
  end

  # Index of the first station whose inputs differ (or which was added/removed).
  defp first_change(old, new) do
    pairs = Enum.zip(old, new)

    case Enum.find_index(pairs, fn {o, n} -> inputs(o) != inputs(n) end) do
      nil when length(old) == length(new) -> nil
      nil -> length(pairs)
      i -> i
    end
  end

  defp inputs(p), do: {num(p["md"]), num(p["inclination_deg"]), num(p["azimuth_deg"])}

  defp advance(nil, st) do
    Map.merge(st, %{
      "tvd" => st["md"] * 1.0,
      "north_south" => 0.0,
      "east_west" => 0.0,
      "dogleg_severity" => 0.0
    })
  end

  defp advance(prev, st) do
    d = Trajectory.interval(station(prev), station(st))
    d_md = st["md"] - prev["md"]

    Map.merge(st, %{
      "tvd" => num(prev["tvd"]) + d.tvd,
      "north_south" => num(prev["north_south"]) + d.north,
      "east_west" => num(prev["east_west"]) + d.east,
      "dogleg_severity" => if(d_md > 0, do: d.dogleg_deg / d_md * 30.0, else: 0.0)
    })
  end

  defp station(p),
    do: %{md: p["md"] * 1.0, inc_deg: num(p["inclination_deg"]), azi_deg: num(p["azimuth_deg"])}

  defp vs(p, azi), do: p["north_south"] * :math.cos(azi) + p["east_west"] * :math.sin(azi)

  @doc """
  Re-place `markers` on `points`: those at or below `from_md` are interpolated
  (or, past the deepest station, projected straight ahead); "Last Survey" is
  moved to the deepest station. `from_md` of `nil` touches nothing.
  """
  @spec recompute_markers([map()], [map()], number() | nil, number() | nil) :: [map()]
  def recompute_markers(markers, _points, nil, _kb), do: markers
  def recompute_markers(markers, [], _from_md, _kb), do: markers

  def recompute_markers(markers, points, from_md, kb) do
    last = List.last(points)

    Enum.map(markers || [], fn m ->
      cond do
        m["event"] == "Last Survey" ->
          place(m, last["md"], points, kb)

        is_number(m["md"]) and m["md"] >= from_md ->
          place(m, m["md"], points, kb)

        true ->
          m
      end
    end)
  end

  defp place(m, md, points, kb) do
    pos = position(points, md)

    m
    |> Map.merge(pos)
    |> Map.put("md", md)
    |> Map.put("subsea", kb && kb - pos["tvd"])
  end

  @interp ~w(tvd north_south east_west vertical_section inclination_deg azimuth_deg)

  defp position(points, md) do
    case Enum.chunk_every(points, 2, 1, :discard)
         |> Enum.find(fn [a, b] -> md >= a["md"] and md <= b["md"] end) do
      [a, b] ->
        t = if b["md"] == a["md"], do: 0.0, else: (md - a["md"]) / (b["md"] - a["md"])
        Map.new(@interp, &{&1, num(a[&1]) + t * (num(b[&1]) - num(a[&1]))})

      nil ->
        project(List.last(points), md)
    end
  end

  # Straight ahead on the last station's inclination / azimuth.
  defp project(last, md) do
    d = max(md - last["md"], 0)
    inc = num(last["inclination_deg"]) * :math.pi() / 180
    azi = num(last["azimuth_deg"]) * :math.pi() / 180
    h = d * :math.sin(inc)
    vs_azi = :math.atan2(num(last["east_west"]), num(last["north_south"]))
    vs_gain = h * :math.cos(azi - vs_azi)

    Map.new(@interp, &{&1, num(last[&1])})
    |> Map.update!("tvd", &(&1 + d * :math.cos(inc)))
    |> Map.update!("north_south", &(&1 + h * :math.cos(azi)))
    |> Map.update!("east_west", &(&1 + h * :math.sin(azi)))
    |> Map.update!("vertical_section", &(&1 + vs_gain))
  end

  defp num(n) when is_number(n), do: n * 1.0
  defp num(_), do: 0.0
end
