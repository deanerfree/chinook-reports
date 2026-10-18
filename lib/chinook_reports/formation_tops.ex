defmodule ChinookReports.FormationTops do
  @moduledoc """
  Recompute the calculated columns of the `import_data["tops"]` table.

  Each formation row carries a `"prognosis"` group and the picks compared to
  it — `"samples"`, `"mwd_gamma"` (the drilling tops) and `"wireline"`
  (`compared_groups/0`) — every one a `%{"md", "tvd", "isopach", "subsea"}`
  map. Only a few of those values are ever authored by a person:

    * `prognosis` md + subsea — entered from the operator's prognosis in the
      draft phase, then frozen. A prognosis top is a geologic surface, so its
      datum-stable value is the **subsea** depth; some sheets give a TVD
      instead, which we accept and convert.
    * each compared group's md — the pick (from cuttings, the MWD gamma while
      drilling, or the wireline logs), entered at the wellsite.

  Everything else is derived here, and `recompute/2` is the single place that
  does it — the tops editor, the elevations editor (a KB change) and a survey
  update all funnel through it:

    * `tvd` — prognosis is `kb_elevation - subsea` (so it moves with any KB
      correction while the geologic pick stays put); compared groups **interpolate**
      the directional survey where it has data and **extrapolate** forward from
      the last station beyond it. Extrapolated groups carry `"method" =>
      "extrapolated"` (interpolated ones `"interpolated"`); prognosis carries
      no method.
    * `subsea` — prognosis keeps its given value (or `kb_elevation - tvd` when
      the sheet gave only a TVD); compared groups are `kb_elevation - tvd`.
    * `isopach` — the formation's vertical thickness: the next formation's
      `tvd` minus this one's, within a group, taken in depth order (see
      `isopachs/1` for the fallbacks when a TVD is missing); the deepest
      formation in a group has no isopach.
    * `difference` in each compared group — its `subsea - prognosis.subsea`
      (positive: the top came in high); the top-level `"difference_m"` is
      Samples' (what the Summary reports).

  A row is *provisional* when any of its compared groups was extrapolated
  (`provisional?/1`).
  """

  alias ChinookReports.Trajectory

  @groups ~w(prognosis samples mwd_gamma wireline)
  @derived_groups ~w(samples mwd_gamma wireline)

  @doc "The pick groups compared to Prognosis, in display order."
  @spec compared_groups() :: [String.t()]
  def compared_groups, do: @derived_groups

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
    |> fill_isopachs(survey)
    |> Enum.map(&put_difference/1)
  end

  @doc """
  Recompute a report's `import_data["tops"]`, pulling the directional survey and
  KB elevation from the report. `overrides` can pass a not-yet-persisted
  `:kb_elevation` or `:formations` list (e.g. mid-edit).

  A report with no `import_data["tops"]` yet starts one from its typed tops
  (`seeded_formations/1`), so a report set up in the wizard gets the same
  table; it's persisted with the next save that carries tops.

  Returns the rebuilt tops map, or `nil` when the report has no tops of
  either kind (and no `:formations` override).
  """
  @spec recompute_for_report(struct(), keyword()) :: map() | nil
  def recompute_for_report(report, overrides \\ []) do
    import_data = report.import_data || %{}

    case base_tops(report, overrides) do
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

  defp base_tops(report, overrides) do
    case {(report.import_data || %{})["tops"], seeded_formations(report)} do
      {%{"formations" => _} = tops, _} -> tops
      {_, [_ | _] = seeded} -> %{"formations" => seeded}
      _ -> if Keyword.has_key?(overrides, :formations), do: %{"formations" => []}
    end
  end

  @doc """
  The tops table a report set up in the wizard starts from: one row per typed
  formation top (`report_data.formation_tops`), named as typed, with its MD
  and subsea (or, lacking a subsea, its TVD) as the Prognosis pick and every
  compared group empty, ready to fill in while drilling.
  """
  @spec seeded_formations(struct()) :: [map()]
  def seeded_formations(%{report_data: %{formation_tops: [_ | _] = typed}}) do
    Enum.map(typed, fn top ->
      subsea = numeric(top.subsea)

      prognosis =
        if is_number(subsea),
          do: %{"md" => numeric(top.md), "subsea" => subsea},
          else: %{"md" => numeric(top.md), "tvd" => numeric(top.tvd)}

      @derived_groups
      |> Map.new(&{&1, %{}})
      |> Map.merge(%{"formation" => top.formation, "prognosis" => prognosis})
    end)
  end

  def seeded_formations(_report), do: []

  @doc """
  `sections` (top-level `import_data` keys about to be saved, e.g. an edited
  `"welldata"` or `"reservoir_data"`) plus the `"tops"` they imply, so a KB or
  survey edit and the tops it re-derives are persisted in one update. Returns
  `sections` unchanged when the report carries no tops.
  """
  @spec with_tops(struct(), map()) :: map()
  def with_tops(report, sections) do
    pending = %{report | import_data: Map.merge(report.import_data || %{}, sections)}

    case recompute_for_report(pending) do
      nil -> sections
      tops -> Map.put(sections, "tops", tops)
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

  @doc """
  KB to Ground: Kelly Bushing minus Ground Level, to the centimetre. Always
  derived, never taken as entered, so it can't disagree with the two
  elevations; `nil` unless both are present. Accepts numbers, Decimals or
  numeric strings (welldata, typed columns, or form text).
  """
  @spec kb_to_ground(term(), term()) :: float() | nil
  def kb_to_ground(ground_level, kelly_bushing) do
    case {numeric(ground_level), numeric(kelly_bushing)} do
      {gl, kb} when is_number(gl) and is_number(kb) -> Float.round((kb - gl) / 1, 2)
      _ -> nil
    end
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

  @doc "True when any of the row's compared groups' TVD was extrapolated ahead of the survey."
  @spec provisional?(map()) :: boolean()
  def provisional?(row), do: Enum.any?(@derived_groups, &extrapolated?(row, &1))

  @doc """
  True when the row's `group` pick lies beyond the actual survey, so its TVD
  and subsea are extrapolated from the last stations (and will firm up once
  the survey passes that depth).
  """
  @spec extrapolated?(map(), String.t()) :: boolean()
  def extrapolated?(row, group), do: get_in(row, [group, "method"]) == "extrapolated"

  # ── one row ────────────────────────────────────────────────────────────────

  defp recompute_row(row, survey, kb) do
    Enum.reduce(@groups, row, fn g, acc ->
      Map.put(acc, g, recompute_group(g, Map.get(acc, g) || %{}, survey, kb))
    end)
  end

  # Prognosis is anchored on the geologic pick — datum-stable in *subsea* — and
  # its TVD is `kb - subsea` — always our KB, so a TVD a plan gave (measured
  # from its own KB) is replaced; with no KB it's left blank and the isopach
  # comes from the subsea difference. Older / manually-entered prognoses that
  # carry only a TVD are honoured the other way round (subsea = `kb - tvd`).
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

  @doc """
  The isopach — vertical thickness — of each of `tops`, in the order given:
  the distance down to the next top in depth order. The deepest top, and any
  top without a depth, has none (`nil`).

  Each top is a map of numbers or `nil`:

    * `:md`, `:tvd`, `:subsea` — the top's depths (`:subsea` is an elevation,
      KB − TVD, so it decreases going down);
    * `:est_tvd` — a TVD estimated from the MD (off a survey or planned path,
      or the MD itself in a hole with no survey, taken as vertical), used only
      when neither of the others gives a thickness.

  A pair's thickness is the first of: the TVD difference; the subsea
  difference (needs no KB elevation); the estimated-TVD difference.
  """
  @spec isopachs([map()]) :: [float() | nil]
  def isopachs(tops) do
    by_index =
      tops
      |> Enum.with_index()
      |> Enum.filter(fn {top, _} -> depth_key(top) end)
      |> Enum.sort_by(fn {top, _} -> depth_key(top) end)
      |> Enum.chunk_every(2, 1, :discard)
      |> Map.new(fn [{top, i}, {next, _}] -> {i, round1(thickness(top, next))} end)

    for i <- 0..(length(tops) - 1)//1, do: Map.get(by_index, i)
  end

  # Where a top sits in the hole: by MD (tops follow the hole down), else TVD,
  # else depth below the subsea datum.
  defp depth_key(top) do
    cond do
      is_number(top[:md]) -> top[:md]
      is_number(top[:tvd]) -> top[:tvd]
      is_number(top[:est_tvd]) -> top[:est_tvd]
      is_number(top[:subsea]) -> -top[:subsea]
      true -> nil
    end
  end

  defp thickness(a, b) do
    cond do
      is_number(a[:tvd]) and is_number(b[:tvd]) -> b[:tvd] - a[:tvd]
      is_number(a[:subsea]) and is_number(b[:subsea]) -> a[:subsea] - b[:subsea]
      is_number(a[:est_tvd]) and is_number(b[:est_tvd]) -> b[:est_tvd] - a[:est_tvd]
      true -> nil
    end
  end

  @doc """
  A TVD for measured depth `md` estimated off `tvd_at` (a function of MD
  returning a TVD or `nil`, e.g. a survey or planned path), or the MD itself
  when there is no path to read (`tvd_at` is `nil`) — a hole with no survey
  is taken as vertical.
  """
  @spec estimate_tvd(number() | nil, (number() -> number() | nil) | nil) :: number() | nil
  def estimate_tvd(md, _tvd_at) when not is_number(md), do: nil
  def estimate_tvd(md, nil), do: md
  def estimate_tvd(md, tvd_at), do: tvd_at.(md)

  @doc """
  Derive the typed formation tops (`report_data.formation_tops`) on a report
  changeset — the typed counterpart of `recompute/2`:

    * `tvd` — `kb − subsea` where the top has a subsea (the geologic pick, so
      it moves with any KB correction), `kb` being *our* KB elevation
      (`kb_elevation/1`'s choice: Well Data's Kelly Bushing, else the typed
      one) — never a plan's, which is measured from another KB. A top with no
      subsea, or no KB to hand, keeps the TVD typed in.
    * `isopach` — always derived (`isopachs/1`); a top's estimated TVD is read
      off the directional program (`report_data.surveys`, by minimum
      curvature), or is its MD when there is no program.

  Runs when the report data or import data (Well Data's KB) changes; a report
  whose `report_data` was never saved (`id: nil`, see
  `Reports.ensure_report_data/1`) has no typed tops to derive. Leaves the
  changeset alone when nothing changes.
  """
  @spec put_typed_tops(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def put_typed_tops(%Ecto.Changeset{} = report) do
    case typed_report_data(report) do
      nil ->
        report

      report_data ->
        derived = derive_typed_tops(report_data, typed_kb(report, report_data))

        if derived == report_data,
          do: report,
          else: Ecto.Changeset.put_embed(report, :report_data, derived)
    end
  end

  defp typed_report_data(report) do
    case Ecto.Changeset.fetch_change(report, :report_data) do
      {:ok, %Ecto.Changeset{} = report_data} ->
        report_data

      _ ->
        with true <- Ecto.Changeset.changed?(report, :import_data),
             %{id: id} = data when not is_nil(id) <- report.data.report_data do
          Ecto.Changeset.change(data)
        else
          _ -> nil
        end
    end
  end

  defp typed_kb(report, report_data) do
    import_data = Ecto.Changeset.get_field(report, :import_data) || %{}

    numeric(get_in(import_data, ["welldata", "elevations", "kelly_bushing"])) ||
      numeric(Ecto.Changeset.get_field(report_data, :kb_elevation))
  end

  defp derive_typed_tops(report_data, kb) do
    tops = Ecto.Changeset.get_field(report_data, :formation_tops) || []
    mds = Enum.map(tops, &numeric(&1.md))
    planned = planned_tvds(Ecto.Changeset.get_field(report_data, :surveys) || [], mds)

    entries =
      tops
      |> Enum.zip(Enum.zip(mds, planned))
      |> Enum.map(fn {top, {md, planned_tvd}} ->
        subsea = numeric(top.subsea)

        %{
          md: md,
          tvd: round1(kb_minus(kb, subsea)) || numeric(top.tvd),
          subsea: subsea,
          est_tvd: planned_tvd
        }
      end)

    derived =
      Enum.zip_with(entries, isopachs(entries), fn e, isopach -> {e.tvd, isopach} end)

    if Enum.map(tops, &{numeric(&1.tvd), numeric(&1.isopach)}) == derived do
      report_data
    else
      rows =
        Enum.zip_with(tops, derived, fn top, {tvd, isopach} ->
          Ecto.Changeset.change(top, tvd: decimal(tvd), isopach: decimal(isopach))
        end)

      Ecto.Changeset.put_embed(report_data, :formation_tops, rows)
    end
  end

  defp decimal(nil), do: nil
  defp decimal(n), do: Decimal.from_float(n / 1)

  # TVD at each of `mds` along the directional program `surveys` (tied in
  # vertically at the wellhead); each MD itself when there's no usable program.
  defp planned_tvds(surveys, mds) do
    stations =
      surveys
      |> Enum.map(
        &%{md: numeric(&1.md), inc_deg: numeric(&1.inclination), azi_deg: numeric(&1.azimuth)}
      )
      |> Enum.filter(fn s -> Enum.all?(Map.values(s), &is_number/1) end)
      |> Enum.sort_by(& &1.md)
      |> Trajectory.tie_in_at_surface()

    if length(stations) >= 2 do
      stations
      |> Trajectory.positions_at(Enum.map(mds, &(&1 || -1.0)))
      |> Enum.map(&(&1 && &1.tvd))
    else
      Enum.map(mds, &estimate_tvd(&1, nil))
    end
  end

  defp fill_isopachs(rows, survey) do
    tvd_at = if length(survey) >= 2, do: &(survey |> tvd_at(&1) |> elem(0))

    Enum.reduce(@groups, rows, &fill_isopach_group(&2, &1, tvd_at))
  end

  defp fill_isopach_group(rows, group, tvd_at) do
    isopachs =
      rows
      |> Enum.map(fn row ->
        grp = Map.get(row, group) || %{}
        md = numeric(grp["md"])

        %{
          md: md,
          tvd: numeric(grp["tvd"]),
          subsea: numeric(grp["subsea"]),
          est_tvd: estimate_tvd(md, tvd_at)
        }
      end)
      |> isopachs()

    rows
    |> Enum.zip(isopachs)
    |> Enum.map(fn {row, isopach} -> put_in(row, [group, "isopach"], isopach) end)
  end

  # ── difference vs prognosis ──────────────────────────────────────────────

  defp put_difference(row) do
    prognosis = get_in(row, ["prognosis", "subsea"])

    row =
      Enum.reduce(@derived_groups, row, fn g, acc ->
        diff =
          with s when is_number(s) <- get_in(acc, [g, "subsea"]),
               p when is_number(p) <- prognosis do
            round1(s - p)
          end

        put_in(acc, [g, "difference"], diff)
      end)

    Map.put(row, "difference_m", get_in(row, ["samples", "difference"]))
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
