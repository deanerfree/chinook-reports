defmodule ChinookReportsWeb.ImportTableLive do
  @moduledoc """
  One editable table out of `import_data`, picked by the `section` assign:

    * welldata tables — Well Timing, Hole Sizes, Mud, Casing, Well Profile
    * top-level lists — Bits, Mud Log, Daily Drilling Reports
    * a reservoir leg's `log_data.intervals` (Interval Details) and its
      directional `survey` — both take the leg's index as `leg`

  Each table is edited on its own (its pencil), persists itself through
  `Reports.update_import_section/4`, replacing only its own slice, then tells
  the parent via `send(self(), {:import_updated, report, title, section})` so
  the report and Summary are refreshed. A survey save also re-derives
  Formation Tops in the same update (`FormationTops.with_tops/2`).

  Keys a table doesn't show (e.g. casing `weight`) are kept on save. Columns of
  type `:derived` are never typed — they're recomputed on every change (a live
  preview) and on save:

    * Hole Sizes `interval`, Well Profile `length` — from the depths
    * Daily `rop` — progress / drilling hours
    * Survey TVD … Subsea — `ChinookReports.Survey` (minimum curvature)
    * Interval Details' From / To / Quality belong to the Reservoir Quality
      picker; saving here recomputes the quality and lithology summaries
      through `ChinookReports.ReservoirQuality`

  Well Timing's Spud and Final T.D. also write the typed `spud_date` /
  `final_td_date` columns (which the Summary reads first), so they can't drift.
  """
  use ChinookReportsWeb, :live_component

  alias ChinookReports.{FormationTops, Reports, ReservoirQuality, Survey}
  alias ChinookReportsWeb.NumberFormat

  @milestones [
    {"Spud Date", "spud_date"},
    {"Surface Casing", "surface_casing"},
    {"Sample Point", "sample_point"},
    {"Kick Off Point", "kick_off_point"},
    {"Intermediate Casing Point", "intermediate_casing_point"},
    {"Heel", "heel"},
    {"Final T.D.", "final_td"}
  ]

  @welldata_sections ~w(well_timing hole_sizes mud casing_data well_profile)
  @list_sections ~w(bits mud_log daily)

  # Column specs per table. `type` drives the input and the parse on save:
  # :text / :textarea are kept as typed, :time must be HH:MM, :number must be
  # ≥ 0 (and ≤ `max`, if set); `required` cells must be filled on any row that
  # isn't entirely blank. `display` controls the read-only cell: :raw as stored,
  # :num to 2 dp, :capitalize for the shouty section names the extractor emits.
  @specs %{
    "well_timing" => %{
      title: "Well Timing",
      fixed_rows: true,
      columns: [
        %{key: "milestone", label: "Milestone", type: :label},
        %{key: "date", label: "Date", type: :text, placeholder: "YYYY-MM-DD", display: :raw},
        %{key: "time", label: "Time", type: :time, placeholder: "HH:MM", display: :raw},
        %{key: "depth", label: "Depth (m)", type: :number, display: :raw}
      ]
    },
    "hole_sizes" => %{
      title: "Hole Sizes",
      fixed_rows: false,
      columns: [
        %{
          key: "section",
          label: "Section",
          type: :text,
          placeholder: "Surface",
          display: :capitalize
        },
        %{key: "bit_diameter", label: "Ø (mm)", type: :number, display: :num},
        %{key: "from_depth", label: "From", type: :number, display: :num},
        %{key: "to_depth", label: "To (m)", type: :number, display: :num}
      ]
    },
    "mud" => %{
      title: "Mud",
      fixed_rows: false,
      columns: [
        %{
          key: "section",
          label: "Section",
          type: :text,
          placeholder: "Surface",
          display: :capitalize
        },
        %{key: "type", label: "Type", type: :text, placeholder: "Gel", display: :raw},
        %{key: "from_depth", label: "From", type: :number, display: :num},
        %{key: "to_depth", label: "To (m)", type: :number, display: :num}
      ]
    },
    "well_profile" => %{
      title: "Well Profile",
      fixed_rows: false,
      columns: [
        %{key: "section", label: "Section", type: :text, placeholder: "Vertical", display: :raw},
        %{
          key: "start_date",
          label: "Start Date",
          type: :text,
          placeholder: "YYYY-MM-DD",
          display: :raw
        },
        %{
          key: "start_time",
          label: "Start Time",
          type: :time,
          placeholder: "HH:MM",
          display: :raw
        },
        %{key: "start_depth", label: "Start (m)", type: :number, display: :num},
        %{
          key: "end_date",
          label: "End Date",
          type: :text,
          placeholder: "YYYY-MM-DD",
          display: :raw
        },
        %{key: "end_time", label: "End Time", type: :time, placeholder: "HH:MM", display: :raw},
        %{key: "end_depth", label: "End (m)", type: :number, display: :num},
        %{key: "length", label: "Length (m)", type: :derived, display: :num},
        %{key: "duration_days", label: "Duration (days)", type: :text, display: :raw}
      ]
    },
    "casing_data" => %{
      title: "Casing",
      fixed_rows: false,
      columns: [
        %{
          key: "section",
          label: "Section",
          type: :text,
          placeholder: "Surface Casing",
          display: :raw
        },
        %{key: "size", label: "Size (mm)", type: :number, display: :num},
        %{key: "set_at", label: "Set At (m)", type: :number, display: :num},
        %{key: "type", label: "Type", type: :text, placeholder: "J-55/LT&C", display: :raw}
      ]
    },
    "bits" => %{
      title: "Bits",
      fixed_rows: false,
      columns: [
        %{key: "bit_number", label: "No", type: :text, placeholder: "1", display: :raw},
        %{key: "type", label: "Type", type: :text, display: :raw},
        %{key: "make", label: "Make", type: :text, display: :raw},
        %{key: "size", label: "Size (mm)", type: :number, display: :raw},
        %{key: "depth_in", label: "Depth In", type: :number, display: :raw},
        %{key: "depth_out", label: "Depth Out", type: :number, display: :raw},
        %{key: "progress", label: "Progress", type: :number, display: :raw},
        %{key: "wob", label: "WOB", type: :number, display: :raw},
        %{key: "rop", label: "ROP", type: :number, display: :raw},
        %{key: "rpm", label: "RPM", type: :number, display: :raw},
        %{key: "hours", label: "Hours", type: :number, display: :raw},
        %{key: "remarks", label: "Remarks", type: :text, display: :raw}
      ]
    },
    "mud_log" => %{
      title: "Mud Log",
      fixed_rows: false,
      columns: [
        %{key: "date", label: "Date", type: :text, placeholder: "YYYY-MM-DD", display: :raw},
        %{key: "depth", label: "Depth (m)", type: :number, display: :num},
        %{key: "mud_type", label: "Mud Type", type: :text, display: :raw},
        %{key: "density", label: "Density", type: :number, display: :raw},
        %{key: "viscosity", label: "Viscosity", type: :number, display: :raw},
        %{key: "wl", label: "WL", type: :number, display: :raw},
        %{key: "ph", label: "pH", type: :number, max: 14, display: :raw},
        %{key: "remarks", label: "Remarks", type: :text, display: :raw}
      ]
    },
    "daily" => %{
      title: "Daily Drilling Reports",
      fixed_rows: false,
      columns: [
        %{key: "date", label: "Date", type: :text, placeholder: "YYYY-MM-DD", display: :raw},
        %{key: "depth", label: "Depth (m)", type: :number, display: :raw},
        %{key: "progress", label: "Progress (m)", type: :number, display: :raw},
        %{key: "drilling_hours", label: "Drilling Hrs", type: :number, display: :raw},
        %{key: "rop", label: "ROP (m/hr)", type: :derived, display: :num},
        %{key: "operations_summary", label: "Operations Summary", type: :textarea, display: :raw}
      ]
    },
    "intervals" => %{
      title: "Interval Details",
      fixed_rows: true,
      note: "From, To and Quality are set by dragging on the Reservoir Quality chart above.",
      columns: [
        %{key: "from_depth", label: "From (m)", type: :derived, display: :num},
        %{key: "to_depth", label: "To (m)", type: :derived, display: :num},
        %{key: "interval", label: "Interval (m)", type: :derived, display: :num},
        %{key: "quality", label: "Quality", type: :derived, display: :raw},
        %{key: "lithology", label: "Lithology", type: :text, display: :raw},
        %{key: "porosity", label: "Porosity", type: :text, placeholder: "12-24%", display: :raw},
        %{key: "gas", label: "Gas (units)", type: :number, display: :raw},
        %{key: "remarks", label: "Remarks", type: :text, display: :raw}
      ]
    },
    "survey" => %{
      title: "Directional Survey",
      fixed_rows: false,
      note:
        "Enter MD, Inc and Azi; TVD, N/S, E/W, VS, DLS (°/30 m) and Subsea are computed by " <>
          "minimum curvature from the first changed station down. Formation Tops follow on save.",
      columns: [
        %{key: "md", label: "MD (m)", type: :number, required: true, display: :survey},
        %{
          key: "inclination_deg",
          label: "Inc (°)",
          type: :number,
          max: 180,
          required: true,
          display: :survey
        },
        %{
          key: "azimuth_deg",
          label: "Azi (°)",
          type: :number,
          max: 360,
          required: true,
          display: :survey
        },
        %{key: "tvd", label: "TVD (m)", type: :derived, display: :survey},
        %{key: "north_south", label: "N/S (m)", type: :derived, display: :survey},
        %{key: "east_west", label: "E/W (m)", type: :derived, display: :survey},
        %{key: "vertical_section", label: "VS (m)", type: :derived, display: :survey},
        %{key: "dogleg_severity", label: "DLS", type: :derived, display: :survey},
        %{key: "subsea", label: "Subsea (m)", type: :derived, display: :survey},
        %{key: "remarks", label: "Remarks", type: :text, display: :raw}
      ]
    }
  }

  @sections Map.keys(@specs)

  @impl true
  def update(%{report: report, section: section} = assigns, socket) when section in @sections do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:leg, fn -> nil end)
      |> assign(:spec, @specs[section])
      |> assign_new(:editing, fn -> false end)
      |> assign_new(:errors, fn -> [] end)

    socket = assign(socket, :title, title(section, report, socket.assigns.leg))

    # Mid-edit, keep the user's rows; the fresh report still lands in assigns
    # so the save merges into the latest import_data.
    {:ok, if(socket.assigns.editing, do: socket, else: load(socket))}
  end

  defp load(socket) do
    %{section: section, report: report, leg: leg} = socket.assigns
    assign(socket, rows: to_rows(section, report, leg), errors: [])
  end

  defp title("survey", report, leg) do
    name = get_in(Enum.at(legs(report), leg) || %{}, ["leg_name"]) || "Leg"
    "Directional Survey — #{name}"
  end

  defp title(section, _report, _leg), do: @specs[section].title

  defp welldata(report), do: (report.import_data || %{})["welldata"] || %{}
  defp legs(report), do: (report.import_data || %{})["reservoir_data"] || []

  # ── events ────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("edit", _params, socket) do
    {:noreply, assign(socket, editing: true, errors: [])}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, load(assign(socket, editing: false))}
  end

  def handle_event("validate", params, socket) do
    rows = merge_params(socket.assigns.rows, params, socket.assigns.spec)
    {:noreply, preview(socket, rows)}
  end

  def handle_event("add_row", _params, socket) do
    {:noreply, assign(socket, rows: socket.assigns.rows ++ [%{}])}
  end

  def handle_event("remove_row", %{"index" => i}, socket) do
    rows = List.delete_at(socket.assigns.rows, String.to_integer(i))
    {:noreply, preview(socket, rows)}
  end

  def handle_event("save", params, socket) do
    %{report: report, section: section, spec: spec, leg: leg} = socket.assigns
    rows = merge_params(socket.assigns.rows, params, socket.assigns.spec)

    case validate(rows, spec) do
      [] ->
        rows =
          rows
          |> Enum.map(&coerce_row(&1, spec))
          |> drop_blank(spec)
          |> then(&derive(section, &1, report, leg))

        case persist(section, report, rows, leg) do
          {:ok, updated} ->
            send(self(), {:import_updated, updated, socket.assigns.title, section})
            {:noreply, load(assign(socket, report: updated, editing: false))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not save #{socket.assigns.title}.")}
        end

      errors ->
        {:noreply, assign(socket, rows: rows, errors: errors)}
    end
  end

  # Validate, and when everything parses refresh the derived cells so the user
  # sees TVD / ROP / length follow their edit before saving.
  defp preview(socket, rows) do
    %{spec: spec, section: section, report: report, leg: leg} = socket.assigns

    case validate(rows, spec) do
      [] ->
        derived_keys = for c <- spec.columns, c.type == :derived, do: c.key

        computed =
          rows
          |> Enum.with_index()
          |> Enum.reject(fn {r, _} -> blank_row?(r, spec) end)
          |> Enum.map(fn {r, i} -> Map.put(coerce_row(r, spec), "__i", i) end)
          |> then(&derive(section, &1, report, leg))
          |> Map.new(&{&1["__i"], Map.take(&1, derived_keys)})

        rows =
          rows
          |> Enum.with_index()
          |> Enum.map(fn {r, i} -> Map.merge(r, Map.get(computed, i, %{})) end)

        assign(socket, rows: rows, errors: [])

      errors ->
        assign(socket, rows: rows, errors: errors)
    end
  end

  # ── JSON ⇄ rows ──────────────────────────────────────────────────────────

  # Well Timing: every milestone gets a row (so missing ones can be filled in),
  # plus Rig Release, which is a bare date string in the JSON.
  defp to_rows("well_timing", report, _leg) do
    timing = welldata(report)["well_timing"] || %{}

    Enum.map(@milestones, fn {label, key} ->
      Map.merge(timing[key] || %{}, %{"key" => key, "milestone" => label})
    end) ++
      [
        %{
          "key" => "rig_release_date",
          "milestone" => "Rig Release",
          "date" => timing["rig_release_date"],
          "date_only" => true
        }
      ]
  end

  # Well Profile nests each end's date/time/depth; flatten for the table.
  defp to_rows("well_profile", report, _leg) do
    Enum.map(welldata(report)["well_profile"] || [], &flatten_ends/1)
  end

  defp to_rows(section, report, _leg) when section in @welldata_sections,
    do: welldata(report)[section] || []

  defp to_rows(section, report, _leg) when section in @list_sections,
    do: (report.import_data || %{})[section] || []

  defp to_rows("intervals", report, _leg), do: ReservoirQuality.intervals_for_report(report)

  defp to_rows("survey", report, leg),
    do: get_in(Enum.at(legs(report), leg) || %{}, ["survey", "survey_points"]) || []

  defp flatten_ends(row) do
    for side <- ~w(start end), {k, v} <- row[side] || %{}, into: Map.drop(row, ~w(start end)) do
      {"#{side}_#{k}", v}
    end
  end

  defp from_rows("well_timing", rows) do
    Map.new(rows, fn
      %{"key" => "rig_release_date"} = row ->
        {"rig_release_date", row["date"]}

      %{"key" => key} = row ->
        {key, Map.drop(row, ~w(key milestone date_only))}
    end)
  end

  defp from_rows("well_profile", rows) do
    flat = for side <- ~w(start end), k <- ~w(date time depth), do: "#{side}_#{k}"

    Enum.map(rows, fn row ->
      nest = fn side -> Map.new(~w(date time depth), &{&1, row["#{side}_#{&1}"]}) end

      row
      |> Map.drop(flat)
      |> Map.merge(%{"start" => nest.("start"), "end" => nest.("end")})
    end)
  end

  defp from_rows(_section, rows), do: rows

  # ── derived columns ──────────────────────────────────────────────────────

  defp derive("hole_sizes", rows, _report, _leg),
    do: Enum.map(rows, &Map.put(&1, "interval", diff(&1["from_depth"], &1["to_depth"])))

  defp derive("well_profile", rows, _report, _leg),
    do: Enum.map(rows, &Map.put(&1, "length", diff(&1["start_depth"], &1["end_depth"])))

  defp derive("daily", rows, _report, _leg) do
    Enum.map(rows, fn row ->
      rop =
        case {row["progress"], row["drilling_hours"]} do
          {p, h} when is_number(p) and is_number(h) and h > 0 -> p / h
          _ -> nil
        end

      Map.put(row, "rop", rop)
    end)
  end

  defp derive("survey", rows, report, leg) do
    {points, _from} =
      Survey.recompute(to_rows("survey", report, leg), rows, FormationTops.kb_elevation(report))

    points
  end

  defp derive(_section, rows, _report, _leg), do: rows

  defp diff(a, b) when is_number(a) and is_number(b), do: b - a
  defp diff(_, _), do: nil

  # ── persist ──────────────────────────────────────────────────────────────

  defp persist(section, report, rows, _leg) when section in @welldata_sections do
    value = from_rows(section, rows)
    welldata = Map.put(welldata(report), section, value)
    Reports.update_import_section(report, "welldata", welldata, typed_attrs(section, value))
  end

  defp persist(section, report, rows, _leg) when section in @list_sections,
    do: Reports.update_import_section(report, section, rows)

  defp persist("intervals", report, rows, _leg) do
    case ReservoirQuality.recompute_for_report(report, rows) do
      nil -> {:error, :no_legs}
      legs -> Reports.update_import_section(report, "reservoir_data", legs)
    end
  end

  defp persist("survey", report, rows, leg) do
    kb = FormationTops.kb_elevation(report)
    stored = to_rows("survey", report, leg)
    {points, from_md} = Survey.recompute(stored, rows, kb)

    legs =
      List.update_at(legs(report), leg, fn l ->
        survey = l["survey"] || %{}

        survey =
          survey
          |> Map.put("survey_points", points)
          |> Map.put(
            "markers",
            Survey.recompute_markers(survey["markers"] || [], points, from_md, kb)
          )

        Map.put(l, "survey", survey)
      end)

    # Formation Tops' TVDs come from this survey; save them with it.
    Reports.update_import_sections(
      report,
      FormationTops.with_tops(report, %{"reservoir_data" => legs})
    )
  end

  # Spud / Final T.D. mirror typed columns; only Well Timing writes them. A date
  # that isn't YYYY-MM-DD (e.g. "Pre-Set") leaves the column as it was.
  defp typed_attrs("well_timing", timing) do
    for {column, key} <- [{"spud_date", "spud_date"}, {"final_td_date", "final_td"}],
        {:ok, value} <- [timing_datetime(timing[key])],
        into: %{},
        do: {column, value}
  end

  defp typed_attrs(_section, _value), do: %{}

  defp timing_datetime(%{"date" => date} = event) when is_binary(date) do
    time = if is_binary(event["time"]), do: event["time"], else: "00:00"

    with {:ok, d} <- Date.from_iso8601(date),
         {:ok, t} <- Time.from_iso8601(String.pad_leading(time, 5, "0") <> ":00") do
      {:ok, NaiveDateTime.new!(d, t)}
    else
      _ -> :skip
    end
  end

  defp timing_datetime(%{"date" => nil}), do: {:ok, nil}
  defp timing_datetime(_), do: :skip

  # Fixed-row tables (milestones, picker intervals) keep every row; free lists
  # drop rows left entirely blank.
  defp drop_blank(rows, %{fixed_rows: true}), do: rows
  defp drop_blank(rows, spec), do: Enum.reject(rows, &blank_row?(&1, spec))

  # A row is blank when every cell the user can type in is empty.
  defp blank_row?(row, spec) do
    spec.columns
    |> Enum.filter(&(&1.type not in [:label, :derived]))
    |> Enum.all?(&(row[&1.key] in [nil, ""]))
  end

  # ── params / validate / coerce ───────────────────────────────────────────

  # The browser submits every input as a string; a cell whose text is unchanged
  # keeps its stored value, so untouched numbers (bit numbers, remarks…) aren't
  # rewritten as strings.
  defp merge_params(rows, %{"rows" => row_params}, spec) do
    Enum.map(Enum.with_index(rows), fn {row, i} ->
      merge_row(row, Map.get(row_params, Integer.to_string(i), %{}), spec)
    end)
  end

  defp merge_params(rows, _params, _spec), do: rows

  defp merge_row(row, params, spec) do
    Enum.reduce(params, row, fn {k, v}, acc ->
      col = Enum.find(spec.columns, %{}, &(&1.key == k))
      if v == input_value(col, acc[k]), do: acc, else: Map.put(acc, k, v)
    end)
  end

  # [{row_index, column_key}] for every cell that won't parse, every required
  # cell left empty, and (for the survey) every repeated MD.
  defp validate(rows, spec) do
    indexed = rows |> Enum.with_index() |> Enum.reject(fn {r, _} -> blank_row?(r, spec) end)

    bad =
      for {row, i} <- indexed,
          col <- spec.columns,
          not valid_cell?(col, row[col.key]),
          do: {i, col.key}

    bad ++ duplicate_mds(indexed, spec)
  end

  defp valid_cell?(%{required: true} = col, v) do
    v not in [nil, ""] and match?({:ok, _}, parse(col, v))
  end

  defp valid_cell?(col, v), do: match?({:ok, _}, parse(col, v))

  defp duplicate_mds(indexed, %{columns: [%{key: "md"} | _]} = spec) do
    md_col = hd(spec.columns)

    indexed
    |> Enum.group_by(fn {r, _} -> parse(md_col, r["md"]) end, fn {_, i} -> i end)
    |> Enum.flat_map(fn
      {{:ok, md}, [_, _ | _] = is} when is_number(md) -> Enum.map(is, &{&1, "md"})
      _ -> []
    end)
  end

  defp duplicate_mds(_indexed, _spec), do: []

  defp coerce_row(row, spec) do
    Enum.reduce(spec.columns, row, fn col, acc ->
      case parse(col, acc[col.key]) do
        {:ok, v} -> Map.put(acc, col.key, v)
        :error -> acc
      end
    end)
  end

  defp parse(%{type: type}, v) when type in [:label, :derived], do: {:ok, v}
  defp parse(_col, nil), do: {:ok, nil}
  defp parse(%{type: :number} = col, n) when is_number(n), do: in_range(col, n / 1)
  # Imported text cells are sometimes numbers (bit numbers, rig numbers…); keep them.
  defp parse(%{type: type}, n) when is_number(n) and type in [:text, :textarea], do: {:ok, n}

  defp parse(%{type: type} = col, s) when is_binary(s) do
    case {type, String.trim(s)} do
      {_, ""} ->
        {:ok, nil}

      {:time, t} ->
        if Regex.match?(~r/^([01]?\d|2[0-3]):[0-5]\d$/, t), do: {:ok, t}, else: :error

      {:number, t} ->
        case Float.parse(t) do
          {f, ""} -> in_range(col, f)
          _ -> :error
        end

      {_text, t} ->
        {:ok, t}
    end
  end

  defp parse(_col, _), do: :error

  defp in_range(col, n) do
    cond do
      n < 0 -> :error
      is_number(col[:max]) and n > col.max -> :error
      true -> {:ok, n}
    end
  end

  # ── view helpers ─────────────────────────────────────────────────────────

  defp display(_col, nil), do: nil
  defp display(%{display: :capitalize}, v) when is_binary(v), do: String.capitalize(v)

  defp display(%{display: :num}, n) when is_number(n),
    do: :erlang.float_to_binary(n / 1, decimals: 2)

  # Survey values keep their own precision — rounding a station to centimetres
  # would misstate the wellpath (see NumberFormat).
  defp display(%{display: :survey}, n) when is_number(n), do: NumberFormat.survey(n)
  defp display(_col, n) when is_number(n), do: NumberFormat.up_to_2(n)
  defp display(_col, v), do: v

  # Inputs show the same text as display/2's rules; merge_row/3 keeps the stored
  # full-precision value for any cell whose text comes back unchanged.
  defp input_value(_col, nil), do: ""
  defp input_value(%{display: :survey}, n) when is_number(n), do: NumberFormat.survey(n)
  defp input_value(_col, n) when is_number(n), do: NumberFormat.up_to_2(n)
  defp input_value(_col, v), do: to_string(v)

  # Rig Release only carries a date.
  defp cell_locked?(%{"date_only" => true}, key), do: key in ~w(time depth)
  defp cell_locked?(_row, _key), do: false

  defp error?(errors, i, key), do: {i, key} in errors

  # Rows the read-only table shows: Well Timing hides milestones never recorded,
  # as before editing existed.
  defp view_rows(rows) do
    Enum.reject(rows, fn row ->
      Map.has_key?(row, "milestone") and
        Enum.all?(~w(date time depth), &(row[&1] in [nil, ""]))
    end)
  end

  defp error_hint(spec) do
    if Enum.any?(spec.columns, & &1[:required]),
      do:
        "Fix the highlighted cells — MD, Inc and Azi are required, MDs must be unique, Inc ≤ 180°, Azi ≤ 360°.",
      else: "Fix the highlighted cells — numbers must be ≥ 0, times HH:MM."
  end

  # ── render ───────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    assigns = assign(assigns, view_rows: view_rows(assigns.rows))

    ~H"""
    <div id={@id} class={[@editing && @spec.fixed_rows == false && "md:col-span-3"]}>
      <%= cond do %>
        <% @editing -> %>
          <%!-- The form wraps the panel so the Save bar sits outside the panel's
               overflow container and can stick to the bottom of the viewport. --%>
          <.form
            for={%{}}
            id={"#{@id}-form"}
            phx-change="validate"
            phx-submit="save"
            phx-target={@myself}
          >
            <.table_panel title={@title}>
              <div class="border-2 border-border-light rounded-lg overflow-x-auto">
                <table class="w-full text-sm">
                  <thead style="background-color: var(--color-accent-subtle)">
                    <tr>
                      <th
                        :for={col <- @spec.columns}
                        class="px-2 py-1 text-left font-semibold text-primary"
                      >
                        {col.label}
                      </th>
                      <th :if={not @spec.fixed_rows} class="w-8"></th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-zinc-100 border-t border-zinc-200">
                    <tr :for={{row, i} <- Enum.with_index(@rows)}>
                      <td :for={col <- @spec.columns} class="px-2 py-1">
                        <%= cond do %>
                          <% col.type == :label -> %>
                            <span class="font-semibold text-text">{row[col.key]}</span>
                          <% col.type == :derived -> %>
                            <span class="text-muted tabular-nums" title="Derived on save">
                              {display(col, row[col.key]) || "—"}
                            </span>
                          <% cell_locked?(row, col.key) -> %>
                          <% col.type == :textarea -> %>
                            <textarea
                              name={"rows[#{i}][#{col.key}]"}
                              rows="4"
                              phx-debounce="blur"
                              class={[
                                "w-full min-w-96 rounded border bg-white px-2 py-1 focus:outline-none",
                                error?(@errors, i, col.key) && "border-danger",
                                !error?(@errors, i, col.key) &&
                                  "border-border-light focus:border-primary"
                              ]}
                            >{input_value(col, row[col.key])}</textarea>
                          <% true -> %>
                            <input
                              type={if col.type == :number, do: "number", else: "text"}
                              step={col.type == :number && "any"}
                              min={col.type == :number && "0"}
                              max={col.type == :number && col[:max]}
                              inputmode={col.type == :number && "decimal"}
                              name={"rows[#{i}][#{col.key}]"}
                              value={input_value(col, row[col.key])}
                              placeholder={Map.get(col, :placeholder, "—")}
                              phx-debounce="blur"
                              class={[
                                "w-full min-w-20 rounded border bg-white px-2 py-1 focus:outline-none",
                                col.type == :number && "text-right tabular-nums",
                                error?(@errors, i, col.key) && "border-danger",
                                !error?(@errors, i, col.key) &&
                                  "border-border-light focus:border-primary"
                              ]}
                            />
                        <% end %>
                      </td>
                      <td :if={not @spec.fixed_rows} class="px-1 text-center">
                        <button
                          type="button"
                          phx-click="remove_row"
                          phx-value-index={i}
                          phx-target={@myself}
                          class="rounded p-1 text-muted hover:bg-danger/10 hover:text-danger cursor-pointer"
                          title="Remove row"
                          aria-label="Remove row"
                        >
                          <.icon name="hero-trash" class="h-4 w-4" />
                        </button>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>

              <p :if={@spec[:note]} class="mt-2 text-xs text-copy-secondary">{@spec.note}</p>
            </.table_panel>
            <.edit_actions target={@myself} disabled={@errors != []}>
              <button
                :if={not @spec.fixed_rows}
                type="button"
                phx-click="add_row"
                phx-target={@myself}
                class="rounded border border-border px-3 py-1.5 text-xs font-medium text-copy-secondary hover:border-primary hover:text-primary cursor-pointer"
              >
                + Add row
              </button>
              <span :if={@errors != []} class="text-xs font-semibold text-danger">
                {error_hint(@spec)}
              </span>
            </.edit_actions>
          </.form>
        <% @rows != [] or @editable -> %>
          <.table_panel title={@title}>
            <:action :if={@editable}>
              <button
                type="button"
                phx-click="edit"
                phx-target={@myself}
                aria-label={"Edit #{@title}"}
                title={"Edit #{@title}"}
                class="inline-flex items-center gap-1.5 rounded-md px-2 py-1 text-xs font-medium cursor-pointer opacity-80 transition-opacity hover:opacity-100 text-table-header-label"
              >
                <.icon name="hero-pencil" class="h-4 w-4" />
                <span>Edit</span>
              </button>
            </:action>

            <%= if @view_rows == [] do %>
              <p class="text-sm text-muted">Nothing recorded yet.</p>
            <% else %>
              <.table id={"#{@id}-table"} rows={@view_rows}>
                <:col :let={row} :for={col <- @spec.columns} label={col.label}>
                  <span class={[
                    col.type == :label && "font-semibold",
                    col.type == :textarea && "block min-w-96 whitespace-pre-line"
                  ]}>
                    {display(col, row[col.key])}
                  </span>
                </:col>
              </.table>
            <% end %>
          </.table_panel>
        <% true -> %>
      <% end %>
    </div>
    """
  end
end
