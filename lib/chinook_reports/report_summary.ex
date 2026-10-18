defmodule ChinookReports.ReportSummary do
  @moduledoc """
  View model for the redesigned report page (`ReportPageLive`).

  `build/1` folds a report's raw `import_data` (Excel extraction / seed JSON)
  into the exact shape the Summary tab and its chart need — header identity,
  the tab bar with counts, the key-facts band, reservoir quality, the
  final-depths-vs-plan comparison, the drilling timeline, a short synopsis, and
  the props handed to the `ProfileChart` Svelte component.

  All access is nil-safe: a report with no `import_data` still builds, it just
  yields empty sections.
  """

  alias ChinookReports.{FormationTops, PlanComparison, Trajectory}

  # Reservoir quality colours — kept in step with `assets/svelte/ProfileChart.svelte`.
  @quality_colours %{
    "Very Good" => "#176935",
    "Good" => "#27ae60",
    "Fair" => "#f1c40f",
    "Poor" => "#e67e22",
    "Nil" => "#bdc3c7"
  }
  @quality_order ["Very Good", "Good", "Fair", "Poor", "Nil"]

  @diff_good "#176935"
  @diff_over "#e67e22"

  # Tops rows that mark a drilling event or marker rather than a formation:
  # TD, coring, fluid contacts, kick-off / casing points, heel, toe, landing.
  @non_formation ~r/^\s*(total\s*dep|td\s*$|start core|end core|kop\b|kick.?off|icp\b|scp\b|heel\b|toe\b|landing)|contact|casing pt|casing point|\/heel/i

  # Survey remarks that mark a projected (not measured) station.
  @extrapolated_remark ~r/extrapolat|^\s*td\s*$/i

  @compass ~w(N NE E SE S SW W NW)

  @timeline_keys [
    {"Spud", "spud_date"},
    {"Surface csg", "surface_casing"},
    {"Sample pt", "sample_point"},
    {"KOP", "kick_off_point"},
    {"Int. csg", "intermediate_casing_point"},
    {"Heel", "heel"},
    {"Final TD", "final_td"}
  ]

  @type t :: %{
          geometry: String.t(),
          layout: :vertical | :lateral,
          header: map(),
          tabs: [map()],
          facts: [map()],
          reservoir_quality: map() | nil,
          depths: map() | nil,
          vertical: map() | nil,
          timeline: [map()],
          synopsis: map(),
          chart_props: map()
        }

  @spec build(struct()) :: t()
  def build(report) do
    import_data = with_tops(report)
    well = import_data["welldata"] || %{}
    legs = import_data["reservoir_data"] || []
    leg = List.first(legs) || %{}
    survey = leg["survey"] || %{}
    log = leg["log_data"] || %{}

    # The report column wins over the imported value: it's what the wizard and
    # the Well Data editor set (e.g. switching an imported well to "Deviated").
    geometry = present(report.geometry) || well["well_geometry"] || ""
    kind = geometry |> to_string() |> String.downcase()
    layout = if kind in ["vertical", "deviated"], do: :vertical, else: :lateral

    stations = PlanComparison.plan_stations(report, survey)
    plan = Trajectory.integrate(stations)

    %{
      geometry: geometry,
      layout: layout,
      header: header(report, well, geometry),
      tabs: tabs(layout, import_data, legs),
      facts: facts(well, layout),
      reservoir_quality: reservoir_quality(log),
      depths: depths(well, survey, plan),
      vertical: vertical(layout, import_data, well, legs, survey, {kind == "deviated", stations}),
      timeline: timeline(well),
      synopsis: synopsis(import_data, well),
      chart_props: %{
        legs: legs,
        geometry: geometry,
        layout: to_string(layout),
        casing: well["casing_data"] || [],
        tops: get_in(import_data, ["tops", "formations"]) || [],
        elevations: well["elevations"] || %{},
        td: well["total_depth_actual"] || %{},
        plan: Enum.map(plan, &Map.take(&1, [:tvd, :vertical_section])),
        show_curves: layout == :lateral and is_list(log["curve_data_cleaned"]),
        overlay_curves: layout == :lateral and is_list(log["curve_data_cleaned"])
      }
    }
  end

  @doc """
  A one-card digest of a report for the Home dashboard: where the hole is now,
  the last formation it penetrated, time on well and — for a Deviated well —
  how far it sits off plan. Built on `build/1`, so it reads the same data the
  Summary tab does. `today` is injectable for tests.
  """
  @spec glance(struct(), Date.t()) :: map()
  def glance(report, today \\ Date.utc_today()) do
    summary = build(report)
    import_data = report.import_data || %{}
    td_md = num(get_in(import_data, ["welldata", "total_depth_actual", "md"]))
    tops = get_in(import_data, ["tops", "formations"]) || []
    spud = spud_date(report, import_data)
    td_date = final_td_date(report, import_data)

    off_plan =
      case summary.vertical do
        %{deviated: true, vs_plan: [_ | _] = rows} ->
          last = List.last(rows)
          "#{last.horizontal} m #{last.compass}"

        _ ->
          nil
      end

    %{
      id: report.id,
      well_name: summary.header.well_name,
      uwi: summary.header.uwi,
      operator: summary.header.operator,
      geometry: geometry_label(summary.geometry),
      depth: summary.header.td.md,
      last_formation: last_formation(tops, td_md),
      spud: spud && Date.to_iso8601(spud),
      td_date: td_date && Date.to_iso8601(td_date),
      # Stops counting once the well reached final TD.
      days_on_well: spud && max(Date.diff(td_date || today, spud), 0),
      off_plan: off_plan
    }
  end

  defp spud_date(%{spud_date: %NaiveDateTime{} = dt}, _), do: NaiveDateTime.to_date(dt)
  defp spud_date(_report, import_data), do: timing_date(import_data, "spud_date")

  defp final_td_date(%{final_td_date: %NaiveDateTime{} = dt}, _), do: NaiveDateTime.to_date(dt)
  defp final_td_date(_report, import_data), do: timing_date(import_data, "final_td")

  defp timing_date(import_data, key) do
    with date when is_binary(date) <-
           get_in(import_data, ["welldata", "well_timing", key, "date"]),
         {:ok, d} <- Date.from_iso8601(date) do
      d
    else
      _ -> nil
    end
  end

  @doc "Reservoir quality colour for a quality label (or grey)."
  def quality_colour(quality), do: Map.get(@quality_colours, quality, "#bdc3c7")

  # ── Header ────────────────────────────────────────────────────────────────

  defp header(report, well, geometry) do
    td = well["total_depth_actual"] || %{}

    field =
      [well["field_region"], well["province"]]
      |> Enum.reject(&(&1 in [nil, "", "-"]))
      |> Enum.join(", ")

    %{
      well_name: report.well_name || well["well_name"],
      uwi: report.unique_well_id || well["unique_well_id"],
      operator: report.operator || well["operator"],
      field: field,
      badges: ["Final report", geometry_label(geometry)] |> Enum.reject(&(&1 == "")),
      td: %{
        md: dist(td["md"]),
        tvd: dist(td["tvd"]),
        subsea: dist(td["subsea"])
      }
    }
  end

  defp geometry_label(nil), do: ""
  defp geometry_label(""), do: ""
  defp geometry_label(g), do: g |> to_string() |> String.capitalize()

  # A wizard-made report's tops table starts from its typed tops until the
  # Formation Tops tab first saves one (FormationTops.recompute_for_report/2).
  defp with_tops(report) do
    import_data = report.import_data || %{}

    case import_data["tops"] || ChinookReports.FormationTops.recompute_for_report(report) do
      nil -> import_data
      tops -> Map.put(import_data, "tops", tops)
    end
  end

  # ── Tabs ──────────────────────────────────────────────────────────────────

  defp tabs(layout, import_data, legs) do
    tops = length(get_in(import_data, ["tops", "formations"]) || [])

    surveys =
      legs |> Enum.map(&length(get_in(&1, ["survey", "survey_points"]) || [])) |> Enum.sum()

    mud_log = length(import_data["mud_log"] || [])
    daily = length(import_data["daily"] || [])

    base = [
      %{id: "summary", label: "Summary", count: nil},
      %{id: "well_data", label: "Well Data", count: nil},
      %{id: "formation_tops", label: "Formation Tops", count: nz(tops)}
    ]

    reservoir =
      if layout == :lateral, do: [%{id: "reservoir", label: "Reservoir", count: nil}], else: []

    base ++
      reservoir ++
      [
        %{id: "synopsis", label: "Synopsis", count: nil},
        %{id: "surveys", label: "Surveys", count: nz(surveys)},
        %{id: "timing", label: "Timing", count: nil},
        %{id: "hole_casing_mud_bits", label: "Hole · Casing · Mud · Bits", count: nil},
        %{id: "mud_log", label: "Mud Log", count: nz(mud_log)},
        %{id: "daily_reports", label: "Daily Reports", count: nz(daily)}
      ]
  end

  defp nz(0), do: nil
  defp nz(n), do: n

  # ── Key facts band ────────────────────────────────────────────────────────

  defp facts(well, layout) do
    timing = well["well_timing"] || %{}
    services = well["services"] || %{}
    dc = services["drilling_contractor"] || %{}

    rig =
      case {dc["company"], dc["rig"]} do
        {nil, _} -> nil
        {c, _r} when layout == :vertical -> to_string(c)
        {c, nil} -> to_string(c)
        {c, r} -> "#{c} · #{r}"
      end

    common = [
      {"Primary target", well["primary_target"]},
      {"Terminating zone", well["terminating_zone"]},
      {"Kelly Bottom", well["elevations"]["kelly_bushing"]},
      {"Ground Level", well["elevations"]["ground_level"]},
      {"Spud", timing_event(timing["spud_date"])},
      {"Final T.D.", timing_event(timing["final_td"])}
    ]

    tail =
      if layout == :vertical do
        [
          {"License", well["well_license"]},
          {"Classification", well["well_classification"]},
          {"Rig", rig}
        ]
      else
        [
          {"Rig", rig},
          {"Wellsite geology", get_in(services, ["wellsite_geology", "company"])},
          {"License", well["well_license"]}
        ]
      end

    (common ++ tail)
    |> Enum.map(fn {label, value} -> %{label: label, value: present(value)} end)
    |> Enum.reject(&is_nil(&1.value))
  end

  defp timing_event(nil), do: nil

  defp timing_event(%{} = e) do
    case {e["date"], e["time"]} do
      {nil, _} -> nil
      {date, nil} -> to_string(date)
      {date, time} -> "#{date}  ·  #{time}"
    end
  end

  # ── Reservoir quality ─────────────────────────────────────────────────────

  defp reservoir_quality(log) do
    summary = log["quality_summary"]

    rows =
      cond do
        is_list(summary) and summary != [] ->
          summary
          |> Enum.reject(&(&1["quality"] == "Total"))
          |> Enum.map(fn q ->
            %{
              quality: q["quality"],
              colour: quality_colour(q["quality"]),
              metres: round_num(q["metres"]),
              pct: fmt(q["percent"], 1)
            }
          end)

        is_list(log["intervals"]) ->
          from_intervals(log["intervals"])

        true ->
          []
      end

    case rows do
      [] -> nil
      rows -> %{total_m: rows |> Enum.map(& &1.metres) |> Enum.sum(), rows: rows}
    end
  end

  defp from_intervals(intervals) do
    totals =
      Enum.reduce(intervals, %{}, fn iv, acc ->
        Map.update(acc, iv["quality"], iv["interval"] || 0, &(&1 + (iv["interval"] || 0)))
      end)

    total = totals |> Map.values() |> Enum.sum()

    @quality_order
    |> Enum.map(fn q ->
      m = Map.get(totals, q, 0)

      %{
        quality: q,
        colour: quality_colour(q),
        metres: round_num(m),
        pct: if(total > 0, do: fmt(m / total * 100, 1), else: "0.0")
      }
    end)
    |> Enum.reject(&(&1.metres == 0))
  end

  # ── Final depths vs plan ──────────────────────────────────────────────────

  defp depths(well, survey, plan) do
    td = well["total_depth_actual"] || %{}
    actual_vs = survey |> last_survey_point() |> then(&(&1 && &1["vertical_section"]))

    actual = %{
      md: num(td["md"]),
      tvd: num(td["tvd"]),
      vs: num(actual_vs),
      subsea: num(td["subsea"])
    }

    planned =
      case List.last(plan) do
        %{} = p -> %{md: p.md, tvd: p.tvd, vs: p.vertical_section}
        _ -> nil
      end

    if planned == nil or is_nil(actual.md) do
      nil
    else
      d_md = delta(actual.md, planned.md)
      d_tvd = delta(actual.tvd, planned.tvd)
      d_vs = delta(actual.vs, planned.vs)

      %{
        actual: fmt_row(actual),
        planned: fmt_row(Map.put(planned, :subsea, nil)),
        diff: %{md: signed(d_md), tvd: signed(d_tvd), vs: signed(d_vs)},
        diff_colour: if((d_tvd || 0) < 0, do: @diff_good, else: @diff_over),
        note: depth_note(d_tvd, d_md)
      }
    end
  end

  defp last_survey_point(%{"survey_points" => pts}) when is_list(pts) and pts != [],
    do: List.last(pts)

  defp last_survey_point(_), do: nil

  defp fmt_row(row) do
    %{
      md: dist(row[:md]),
      tvd: dist(row[:tvd]),
      vs: dist(row[:vs]),
      subsea: dist(row[:subsea])
    }
  end

  defp delta(a, b) when is_number(a) and is_number(b), do: a - b
  defp delta(_, _), do: nil

  defp signed(nil), do: "—"
  defp signed(v) when v > 0, do: "+" <> dist(v)
  defp signed(v), do: dist(v)

  defp depth_note(nil, _), do: "No planned survey on file."

  defp depth_note(d_tvd, d_md) do
    md_part =
      if is_number(d_md) do
        " and #{dist(abs(d_md))} m #{if d_md < 0, do: "short", else: "long"} in measured depth"
      else
        ""
      end

    "TD landed #{dist(abs(d_tvd))} m #{if d_tvd < 0, do: "high", else: "low"} to plan" <>
      md_part <> "."
  end

  # ── Vertical wells: where the hole ended up ─────────────────────────────

  defp vertical(:lateral, _import_data, _well, _legs, _survey, _plan), do: nil

  defp vertical(:vertical, import_data, well, legs, survey, {deviated, stations}) do
    tops = get_in(import_data, ["tops", "formations"]) || []
    td = well["total_depth_actual"] || %{}
    td_md = num(td["md"])

    %{
      last_formation: last_formation(tops, td_md),
      target: target_top(tops, well["primary_target"]),
      max_gas: max_gas(legs, tops, get_in(well, ["units", "gas"])),
      depth: depth_status(td, survey),
      deviated: deviated,
      has_plan: stations != [],
      vs_plan: if(deviated, do: vs_plan(survey, stations))
    }
  end

  defp last_formation(tops, td_md), do: tops |> deepest_top(td_md) |> top_call()

  # Deepest real formation top at or above `max_md` (any depth when nil).
  defp deepest_top(tops, max_md) do
    tops
    |> Enum.filter(fn t ->
      md = top_md(t)
      formation_row?(t) and is_number(md) and (is_nil(max_md) or md <= max_md)
    end)
    |> Enum.max_by(&top_md/1, fn -> nil end)
  end

  defp target_top(_tops, target) when target in [nil, "", "-"], do: nil

  defp target_top(tops, target) do
    key = target |> to_string() |> String.trim() |> String.downcase()

    tops
    |> Enum.find(&(&1["formation"] |> to_string() |> String.trim() |> String.downcase() == key))
    |> case do
      nil -> %{formation: to_string(target), md: "—", subsea: "—", diff: "—", call: :not_reached}
      row -> top_call(row)
    end
  end

  defp formation_row?(t), do: not Regex.match?(@non_formation, to_string(t["formation"]))

  # A formation's actual top: the first set of tops that picked it — Samples,
  # then MWD / Gamma (the drilling tops), Wireline (FormationTops.compared_groups/0).
  defp actual_group(t) do
    Enum.find(ChinookReports.FormationTops.compared_groups(), &num(get_in(t, [&1, "md"])))
  end

  defp top_md(t), do: (g = actual_group(t)) && num(get_in(t, [g, "md"]))
  defp top_subsea(t), do: (g = actual_group(t)) && num(get_in(t, [g, "subsea"]))

  # That pick's difference to prognosis; tops saved before the per-group
  # differences only carry Samples' (`difference_m`).
  defp top_difference(t) do
    case actual_group(t) do
      nil -> nil
      "samples" -> num(get_in(t, ["samples", "difference"])) || num(t["difference_m"])
      g -> num(get_in(t, [g, "difference"]))
    end
  end

  defp top_call(nil), do: nil

  defp top_call(row) do
    diff = top_difference(row)

    %{
      formation: row["formation"],
      md: dist(top_md(row)),
      subsea: dist(top_subsea(row)),
      diff: signed(diff),
      # difference = actual subsea - prognosis subsea: positive came in high.
      call:
        cond do
          not is_number(diff) -> :no_prognosis
          abs(diff) < 0.05 -> :on_prognosis
          diff > 0 -> :high
          true -> :low
        end,
      provisional: FormationTops.provisional?(row)
    }
  end

  defp max_gas(legs, tops, units) do
    legs
    |> Enum.flat_map(fn leg ->
      log = leg["log_data"] || %{}
      null = get_in(log, ["curve_metadata", "null_value"])
      curve = log["curve_data_cleaned"] || log["curve_data_actual"] || []

      curve
      |> Enum.map(&{num(&1["md"]), num(&1["gas"])})
      |> Enum.filter(fn {md, gas} -> is_number(md) and is_number(gas) and gas != null end)
    end)
    |> Enum.max_by(&elem(&1, 1), fn -> nil end)
    |> case do
      nil ->
        nil

      {md, gas} ->
        %{
          value: fmt(gas, 0),
          units: present(units) || "units",
          md: dist(md),
          formation: formation_at(tops, md)
        }
    end
  end

  defp formation_at(tops, md) do
    case deepest_top(tops, md) do
      nil -> nil
      top -> top["formation"]
    end
  end

  defp depth_status(td, survey) do
    points = survey_points(survey)
    last = List.last(points)
    measured = Enum.reject(points, &extrapolated?/1)
    last_measured = List.last(measured)

    projected =
      if last && extrapolated?(last) && last_measured, do: last, else: nil

    %{
      md: dist(num(td["md"])),
      tvd: dist(num(td["tvd"])),
      subsea: dist(num(td["subsea"])),
      extrapolated: projected != nil,
      projected_from:
        projected &&
          dist(delta(num(projected["md"]), num(last_measured["md"]))),
      last_survey: last_measured && station_row(last_measured)
    }
  end

  # A survey station keeps the survey's own precision (up to 5 decimals) —
  # rounding a station misstates the wellpath.
  defp station_row(p) do
    %{
      md: survey(num(p["md"])),
      tvd: survey(num(p["tvd"])),
      inc: survey(num(p["inclination_deg"])),
      azi: survey(num(p["azimuth_deg"]))
    }
  end

  defp survey_points(%{"survey_points" => pts}) when is_list(pts),
    do: Enum.filter(pts, &is_number(num(&1["md"])))

  defp survey_points(_), do: []

  defp extrapolated?(p), do: Regex.match?(@extrapolated_remark, to_string(p["remarks"]))

  # Actual against plan at the same measured depth, at the last measured
  # station and at the (extrapolated) bottom of the survey.
  defp vs_plan(_survey, []), do: nil

  defp vs_plan(survey, stations) do
    points = survey_points(survey)
    measured = points |> Enum.reject(&extrapolated?/1) |> List.last()
    bottom = List.last(points)

    [{"Last survey", measured}, {"Projected to TD", bottom}]
    |> Enum.uniq_by(fn {_, p} -> p end)
    |> Enum.reject(fn {label, p} ->
      is_nil(p) or (label != "Last survey" and not extrapolated?(p))
    end)
    |> Enum.map(fn {label, p} -> plan_offset(label, p, stations) end)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      rows -> rows
    end
  end

  defp plan_offset(label, p, stations) do
    md = num(p["md"])
    actual = %{tvd: num(p["tvd"]), north: num(p["north_south"]), east: num(p["east_west"])}

    with true <- Enum.all?(Map.values(actual), &is_number/1),
         %{} = planned <- Trajectory.position_at(stations, md) do
      d_tvd = actual.tvd - planned.tvd
      d_n = actual.north - planned.north
      d_e = actual.east - planned.east
      horizontal = :math.sqrt(d_n * d_n + d_e * d_e)
      bearing = :math.atan2(d_e, d_n) * 180 / :math.pi()
      bearing = if bearing < 0, do: bearing + 360, else: bearing

      %{
        label: label,
        md: dist(md),
        beyond_plan: md > List.last(stations).md,
        d_tvd: signed(d_tvd),
        vertical_call: if(d_tvd > 0, do: :low, else: :high),
        d_north: signed(d_n),
        d_east: signed(d_e),
        horizontal: dist(horizontal),
        bearing: fmt(bearing, 0),
        compass: Enum.at(@compass, rem(round(bearing / 45), 8)),
        distance: dist(:math.sqrt(horizontal * horizontal + d_tvd * d_tvd))
      }
    else
      _ -> nil
    end
  end

  # ── Drilling timeline (Fig 03) ────────────────────────────────────────────

  defp timeline(well) do
    timing = well["well_timing"] || %{}

    @timeline_keys
    |> Enum.map(fn {label, key} ->
      e = timing[key] || %{}
      %{label: label, depth: num(e["depth"]), date: e["date"]}
    end)
    |> Enum.filter(&is_number(&1.depth))
    |> Enum.sort_by(& &1.depth)
  end

  # ── Synopsis ──────────────────────────────────────────────────────────────

  defp synopsis(import_data, well) do
    paragraphs = get_in(import_data, ["synopsis", "well_summary"]) || []

    %{
      short: Enum.take(paragraphs, 2),
      full_count: length(paragraphs),
      final_status: present(well["final_well_status"])
    }
  end

  # ── Formatting helpers ────────────────────────────────────────────────────

  defp present(nil), do: nil
  defp present(""), do: nil
  defp present("-"), do: nil
  defp present(v), do: to_string(v)

  defp num(v) when is_number(v), do: v
  defp num(%Decimal{} = v), do: Decimal.to_float(v)

  defp num(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp num(_), do: nil

  defp round_num(v) when is_number(v), do: round(v)
  defp round_num(_), do: 0

  # Depths, lengths and distances: at most two decimals, without padding
  # (1128.734 → "1128.73", 1979.0 → "1979") — the same rule as the report
  # page's ChinookReportsWeb.NumberFormat.up_to_2/1.
  defp dist(v), do: up_to(v, 2)

  # Directional-survey values: up to 5 decimals (NumberFormat.survey/1).
  defp survey(v), do: up_to(v, 5)

  defp up_to(nil, _), do: "—"
  defp up_to(v, _places) when is_integer(v), do: Integer.to_string(v)

  defp up_to(v, places) when is_float(v) do
    (Float.round(v, places) + 0.0)
    |> :erlang.float_to_binary([:compact, decimals: places])
    |> String.trim_trailing(".0")
  end

  defp up_to(v, places) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> up_to(f, places)
      :error -> v
    end
  end

  defp fmt(nil, _), do: "—"

  defp fmt(v, decimals) when is_number(v) do
    :erlang.float_to_binary(v / 1, decimals: decimals)
  end

  defp fmt(v, decimals) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> fmt(f, decimals)
      :error -> v
    end
  end
end
