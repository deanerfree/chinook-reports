defmodule ChinookReports.FormationTops do
  @moduledoc """
  Recompute the calculated columns of the `import_data["tops"]` table.

  Each formation row carries three groups — `"prognosis"`, `"samples"`,
  `"mwd_gamma"` — every one a `%{"md", "tvd", "isopach", "subsea"}` map. Only a
  few of those values are ever authored by a person:

    * `prognosis` md + subsea — entered from the operator's prognosis in the
      draft phase, then frozen. A prognosis top is a geologic surface, so its
      datum-stable value is the **subsea** depth; some sheets give a TVD
      instead, which we accept and convert.
    * `samples` / `mwd_gamma` md — the pick, entered while drilling.

  Everything else is derived here, and `recompute/2` is the single place that
  does it — the tops editor, the elevations editor (a KB change) and a survey
  update all funnel through it:

    * `tvd` — prognosis is `kb_elevation - subsea` (so it moves with any KB
      correction while the geologic pick stays put); samples/mwd **interpolate**
      the directional survey where it has data and **extrapolate** forward from
      the last station beyond it. Extrapolated groups carry `"method" =>
      "extrapolated"` (interpolated ones `"interpolated"`); prognosis carries
      no method.
    * `subsea` — prognosis keeps its given value (or `kb_elevation - tvd` when
      the sheet gave only a TVD); samples/mwd are `kb_elevation - tvd`.
    * `isopach` — the next formation's `tvd` minus this one's, within a group,
      taken in MD order; the deepest formation in a group has no isopach.
    * top-level `"difference_m"` — `samples.subsea - prognosis.subsea`

  A row is *provisional* when any of its samples/mwd groups was extrapolated
  (`provisional?/1`).
  """

  @groups ~w(prognosis samples mwd_gamma)
  @derived_groups ~w(samples mwd_gamma)

  @type survey_point :: %{required(String.t()) => number()}

  @doc """
  Recompute `formations` (a list of row maps, or the whole
  `%{"formations" => [...]}` map) against a directional survey and KB elevation.

  Options:

    * `:survey_points` — list of `%{"md" => .., "tvd" => ..}` (any order, other
      keys ignored). Fewer than two usable points disables interpolation:
      samples/mwd tvd then stays `nil`.
    * `:kb_elevation` — number; when `nil`, `subsea` is left `nil`.
  """
  @spec recompute(map() | [map()], keyword()) :: map() | [map()]
  def recompute(%{"formations" => formations} = tops, opts) do
    %{tops | "formations" => recompute(formations, opts)}
  end

  def recompute(formations, opts) when is_list(formations) do
    survey = prepare_survey(Keyword.get(opts, :survey_points, []))
    kb = numeric(Keyword.get(opts, :kb_elevation))

    formations
    |> Enum.map(&recompute_row(&1, survey, kb))
    |> fill_isopachs()
    |> Enum.map(&put_difference/1)
  end

  @doc """
  Recompute a report's `import_data["tops"]`, pulling the directional survey and
  KB elevation from the report. `overrides` can pass a not-yet-persisted
  `:kb_elevation` or `:formations` list (e.g. mid-edit).

  Returns the rebuilt tops map, or `nil` when the report carries no tops.
  """
  @spec recompute_for_report(struct(), keyword()) :: map() | nil
  def recompute_for_report(report, overrides \\ []) do
    import_data = report.import_data || %{}

    case import_data["tops"] do
      %{"formations" => formations} = tops ->
        formations = Keyword.get(overrides, :formations, formations)

        opts = [
          survey_points: survey_points(import_data),
          kb_elevation: Keyword.get(overrides, :kb_elevation, kb_elevation(report))
        ]

        %{tops | "formations" => recompute(formations, opts)}

      _ ->
        nil
    end
  end

  @doc """
  The KB elevation a tops recompute should use.

  For an imported report the authoritative value is the Kelly Bushing in
  `import_data["welldata"]["elevations"]` (the "Surface Location and Elevations"
  card) — the same datum the survey's own subsea values are referenced to. The
  typed `report_data.kb_elevation` is only a fallback for manually-created
  reports that carry no imported well data.
  """
  @spec kb_elevation(struct()) :: number() | nil
  def kb_elevation(report) do
    imported = get_in(report.import_data || %{}, ["welldata", "elevations", "kelly_bushing"])
    typed = report.report_data && report.report_data.kb_elevation
    numeric(imported) || numeric(typed)
  end

  defp survey_points(import_data) do
    (import_data["reservoir_data"] || [])
    |> Enum.flat_map(fn leg -> get_in(leg, ["survey", "survey_points"]) || [] end)
  end

  @doc "Deepest MD the directional survey reaches, or `nil` when there is no survey."
  @spec survey_reach(struct()) :: number() | nil
  def survey_reach(report) do
    (report.import_data || %{})
    |> survey_points()
    |> Enum.map(&numeric(&1["md"]))
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      mds -> Enum.max(mds)
    end
  end

  @doc "True when any of the row's samples/mwd tvd was extrapolated ahead of the survey."
  @spec provisional?(map()) :: boolean()
  def provisional?(row) do
    Enum.any?(@derived_groups, fn g -> get_in(row, [g, "method"]) == "extrapolated" end)
  end

  # ── one row ────────────────────────────────────────────────────────────────

  defp recompute_row(row, survey, kb) do
    Enum.reduce(@groups, row, fn g, acc ->
      Map.put(acc, g, recompute_group(g, Map.get(acc, g) || %{}, survey, kb))
    end)
  end

  # Prognosis is anchored on the geologic pick — datum-stable in *subsea* — and
  # its TVD is `kb - subsea`. Older / manually-entered prognoses that carry only
  # a TVD are honoured the other way round (subsea = `kb - tvd`).
  defp recompute_group("prognosis", grp, _survey, kb) do
    {tvd, ss} =
      case {numeric(grp["subsea"]), numeric(grp["tvd"])} do
        {ss, _} when is_number(ss) -> {kb_minus(kb, ss), ss}
        {nil, tvd} -> {tvd, kb_minus(kb, tvd)}
      end

    grp
    |> Map.put("tvd", round1(tvd))
    |> Map.put("subsea", round1(ss))
    |> Map.delete("method")
  end

  # Samples / MWD keep their MD pick; TVD comes off the directional survey.
  defp recompute_group(_group, grp, survey, kb) do
    {tvd, method} =
      case numeric(grp["md"]) do
        nil -> {nil, nil}
        md -> tvd_at(survey, md)
      end

    grp
    |> Map.put("tvd", round1(tvd))
    |> Map.put("subsea", round1(kb_minus(kb, tvd)))
    |> put_method(method)
  end

  defp kb_minus(kb, x) when is_number(kb) and is_number(x), do: kb - x
  defp kb_minus(_kb, _x), do: nil

  defp put_method(grp, nil), do: Map.delete(grp, "method")
  defp put_method(grp, method), do: Map.put(grp, "method", Atom.to_string(method))

  # ── survey interpolation / extrapolation ──────────────────────────────────

  # Sorted, de-duped `[{md, tvd}]` with both values present.
  defp prepare_survey(points) do
    points
    |> Enum.map(fn p -> {numeric(p["md"]), numeric(p["tvd"])} end)
    |> Enum.reject(fn {md, tvd} -> is_nil(md) or is_nil(tvd) end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.dedup_by(&elem(&1, 0))
  end

  defp tvd_at(survey, _md) when length(survey) < 2, do: {nil, nil}

  defp tvd_at(survey, md) do
    {first_md, _} = List.first(survey)
    {last_md, _} = List.last(survey)

    cond do
      md <= first_md ->
        {elem(List.first(survey), 1), :interpolated}

      md <= last_md ->
        {interp(survey, md), :interpolated}

      true ->
        # extrapolate: hold the slope of the last surveyed interval
        [{p_md, p_tvd}, {q_md, q_tvd}] = Enum.take(survey, -2)
        slope = (q_tvd - p_tvd) / (q_md - p_md)
        {q_tvd + slope * (md - q_md), :extrapolated}
    end
  end

  defp interp([{a_md, a_tvd}, {b_md, b_tvd} | rest], md) do
    if md <= b_md do
      a_tvd + (b_tvd - a_tvd) * (md - a_md) / (b_md - a_md)
    else
      interp([{b_md, b_tvd} | rest], md)
    end
  end

  # ── isopach (needs the neighbouring rows) ─────────────────────────────────

  defp fill_isopachs(rows) do
    Enum.reduce(@groups, rows, &fill_isopach_group(&2, &1))
  end

  defp fill_isopach_group(rows, group) do
    # rows carrying a tvd for this group, in depth order, keyed by original index
    ordered =
      rows
      |> Enum.with_index()
      |> Enum.filter(fn {row, _} -> is_number(get_in(row, [group, "tvd"])) end)
      |> Enum.sort_by(fn {row, _} -> get_in(row, [group, "tvd"]) end)

    isopachs =
      ordered
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [{row, idx}, {next, _}] ->
        {idx, round1(get_in(next, [group, "tvd"]) - get_in(row, [group, "tvd"]))}
      end)
      |> Map.new()

    rows
    |> Enum.with_index()
    |> Enum.map(fn {row, idx} ->
      put_in(row, [group, "isopach"], Map.get(isopachs, idx))
    end)
  end

  # ── difference_m ─────────────────────────────────────────────────────────

  defp put_difference(row) do
    diff =
      with s when is_number(s) <- get_in(row, ["samples", "subsea"]),
           p when is_number(p) <- get_in(row, ["prognosis", "subsea"]) do
        round1(s - p)
      else
        _ -> nil
      end

    Map.put(row, "difference_m", diff)
  end

  # ── helpers ──────────────────────────────────────────────────────────────

  defp numeric(nil), do: nil
  defp numeric(n) when is_number(n), do: n
  defp numeric(%Decimal{} = d), do: Decimal.to_float(d)

  defp numeric(s) when is_binary(s) do
    case Float.parse(String.trim(s)) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp numeric(_), do: nil

  defp round1(nil), do: nil
  defp round1(n) when is_number(n), do: Float.round(n / 1, 1)
end
