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

  alias ChinookReports.Trajectory

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
          timeline: [map()],
          synopsis: map(),
          chart_props: map()
        }

  @spec build(struct()) :: t()
  def build(report) do
    import_data = report.import_data || %{}
    well = import_data["welldata"] || %{}
    legs = import_data["reservoir_data"] || []
    leg = List.first(legs) || %{}
    survey = leg["survey"] || %{}
    log = leg["log_data"] || %{}

    geometry = well["well_geometry"] || report.geometry || ""
    layout = if String.downcase(to_string(geometry)) == "vertical", do: :vertical, else: :lateral

    plan = plan_curve(survey)

    %{
      geometry: geometry,
      layout: layout,
      header: header(report, well, geometry),
      tabs: tabs(layout, import_data, legs),
      facts: facts(well, layout),
      reservoir_quality: reservoir_quality(log),
      depths: depths(well, survey, plan),
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
        md: fmt(td["md"], 0),
        tvd: fmt(td["tvd"], 1),
        subsea: fmt(td["subsea"], 1)
      }
    }
  end

  defp geometry_label(nil), do: ""
  defp geometry_label(""), do: ""
  defp geometry_label(g), do: g |> to_string() |> String.capitalize()

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
      md: fmt(row[:md], 1),
      tvd: fmt(row[:tvd], 1),
      vs: fmt(row[:vs], 1),
      subsea: fmt(row[:subsea], 1)
    }
  end

  defp delta(a, b) when is_number(a) and is_number(b), do: a - b
  defp delta(_, _), do: nil

  defp signed(nil), do: "—"
  defp signed(v) when v > 0, do: "+" <> fmt(v, 1)
  defp signed(v), do: fmt(v, 1)

  defp depth_note(nil, _), do: "No planned survey on file."

  defp depth_note(d_tvd, d_md) do
    md_part =
      if is_number(d_md) do
        " and #{fmt(abs(d_md), 1)} m #{if d_md < 0, do: "short", else: "long"} in measured depth"
      else
        ""
      end

    "TD landed #{fmt(abs(d_tvd), 1)} m #{if d_tvd < 0, do: "high", else: "low"} to plan" <>
      md_part <> "."
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

  # ── Plan trajectory ───────────────────────────────────────────────────────

  defp plan_curve(%{"prognosed_survey" => stations}) when is_list(stations) do
    Trajectory.integrate(stations)
  end

  defp plan_curve(_), do: []

  # ── Formatting helpers ────────────────────────────────────────────────────

  defp present(nil), do: nil
  defp present(""), do: nil
  defp present("-"), do: nil
  defp present(v), do: to_string(v)

  defp num(v) when is_number(v), do: v

  defp num(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp num(_), do: nil

  defp round_num(v) when is_number(v), do: round(v)
  defp round_num(_), do: 0

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
