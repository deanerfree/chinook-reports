defmodule ChinookReportsWeb.WellDataCardLive do
  @moduledoc """
  One card of label/value fields on the Well Data tab, read from and saved to
  `import_data["welldata"]`, picked by the `card` assign.

  Each field addresses a `path` into welldata. A report built in the create
  wizard has no welldata yet, so a field may name a `fallback` (the typed column
  or `report_data` field holding the same fact) to show and pre-fill from until
  the card is first saved.

  Some facts are also read from typed columns elsewhere (the page header reads
  `well_name` first, the Summary `spud_date`, the reports list filters by
  operator…). A field with `sync` writes its value to that column in the same
  update, so the two never disagree. A field with `typed` and no `path`
  (Status) lives only in the column.

  On save the parent gets `{:import_updated, report, title, card}`. The
  Elevations card's KB feeds Formation Tops, so that card saves the re-derived
  tops in the same update (`FormationTops.with_tops/2`).
  """
  use ChinookReportsWeb, :live_component

  alias ChinookReports.Countries
  alias ChinookReports.FormationTops
  alias ChinookReports.Reports
  alias ChinookReports.Reports.Report
  alias ChinookReportsWeb.NumberFormat

  @cards %{
    "identification" => %{
      title: "Well Identification",
      fields: [
        %{path: ["well_name"], label: "Well Name", sync: :well_name, wide: true},
        %{path: ["unique_well_id"], label: "Unique Well ID", sync: :unique_well_id},
        %{
          typed: :status,
          label: "Status",
          type: :select,
          options: &Report.statuses/0,
          required: true
        },
        %{path: ["operator"], label: "Operator", sync: :operator},
        %{path: ["op_geo"], label: "Reported To"},
        %{path: ["afe_number"], label: "AFE Number"},
        %{path: ["well_license"], label: "License", fallback: {:data, :license}},
        %{
          path: ["well_classification"],
          label: "Classification",
          fallback: {:data, :classification}
        },
        %{path: ["security"], label: "Security"},
        %{
          path: ["surface_location"],
          label: "Surface Location",
          fallback: {:data, :surface_location}
        },
        %{
          path: ["bottom_location"],
          label: "Bottom Location",
          fallback: {:data, :bottom_location}
        },
        %{path: ["field_region"], label: "Field / Region", fallback: {:data, :field_region}},
        %{path: ["province"], label: "Province", sync: :province},
        %{
          path: ["country"],
          label: "Country",
          sync: :country,
          type: :select,
          options: &Countries.all/0
        }
      ]
    },
    "objectives" => %{
      title: "Well Objectives and Type",
      fields: [
        %{path: ["primary_target"], label: "Primary Target", sync: :target_formation},
        %{path: ["secondary_target"], label: "Secondary Target", sync: :secondary_target},
        %{
          path: ["terminating_zone"],
          label: "Terminating Zone",
          fallback: {:data, :terminating_zone}
        },
        %{
          path: ["well_geometry"],
          label: "Geometry",
          sync: :geometry,
          type: :select,
          options: &Report.geometries/0
        },
        %{path: ["well_purpose"], label: "Purpose", fallback: {:data, :purpose}},
        %{path: ["substance"], label: "Substance", fallback: {:data, :substance}},
        %{path: ["final_well_status"], label: "Final Well Status", type: :textarea, wide: true}
      ]
    },
    "total_depth" => %{
      title: "Total Depth",
      fields: [
        %{path: ["total_depth_actual", "md"], label: "MD", type: :number, unit: "m"},
        %{path: ["total_depth_actual", "tvd"], label: "TVD", type: :number, unit: "m"},
        %{
          path: ["total_depth_actual", "subsea"],
          label: "Subsea",
          type: :number,
          unit: "m",
          signed: true
        }
      ]
    },
    "elevations" => %{
      title: "Elevations",
      note: "Changing the Kelly Bushing re-derives every Subsea in Formation Tops.",
      fields: [
        %{
          path: ["elevations", "ground_level"],
          label: "Ground Level",
          type: :number,
          unit: "m",
          fallback: {:data, :gl_elevation}
        },
        %{
          path: ["elevations", "kelly_bushing"],
          label: "Kelly Bushing",
          type: :number,
          unit: "m",
          fallback: {:data, :kb_elevation}
        },
        %{
          path: ["elevations", "kb_to_ground"],
          label: "KB to Ground",
          type: :number,
          unit: "m",
          fallback: {:data, :kb_to_ground}
        },
        %{path: ["elevations", "reference"], label: "Datum", fallback: {:data, :datum}}
      ]
    },
    "location" => %{
      title: "Surface Location",
      fields: [
        %{
          path: ["location_data", "surface_coordinates"],
          label: "Surface Coordinates",
          fallback: {:data, :surface_coordinates},
          wide: true
        },
        %{path: ["location_data", "bottom_coordinates"], label: "Bottom Offset", wide: true},
        %{
          path: ["location_data", "geographic_coordinates", "latitude"],
          label: "Latitude",
          type: :number,
          signed: true,
          precise: true,
          fallback: {:report, :latitude}
        },
        %{
          path: ["location_data", "geographic_coordinates", "longitude"],
          label: "Longitude",
          type: :number,
          signed: true,
          precise: true,
          fallback: {:report, :longitude}
        },
        %{path: ["location_data", "geographic_coordinates", "datum"], label: "Coordinate Datum"},
        %{
          path: ["location_data", "surface_location_grid", "northing"],
          label: "Grid Northing",
          type: :number,
          unit: "m"
        },
        %{
          path: ["location_data", "surface_location_grid", "northing_dir"],
          label: "Northing From"
        },
        %{
          path: ["location_data", "surface_location_grid", "easting"],
          label: "Grid Easting",
          type: :number,
          unit: "m"
        },
        %{path: ["location_data", "surface_location_grid", "easting_dir"], label: "Easting From"},
        %{path: ["location_data", "surface_location_grid", "section"], label: "Section"},
        %{path: ["location_data", "surface_location_grid", "township"], label: "Township"},
        %{path: ["location_data", "surface_location_grid", "range"], label: "Range"},
        %{path: ["location_data", "surface_location_grid", "meridian"], label: "Meridian"}
      ]
    },
    "services" => %{
      title: "Services",
      fields: [
        %{path: ["services", "wellsite_geology", "company"], label: "Wellsite Geology"},
        %{
          path: ["services", "wellsite_geology", "geologists"],
          label: "Wellsite Geologists",
          type: :list,
          placeholder: "Comma-separated"
        },
        %{path: ["services", "drilling_contractor", "company"], label: "Drilling Contractor"},
        %{path: ["services", "drilling_contractor", "rig"], label: "Rig"},
        %{path: ["services", "drilling_supervision"], label: "Supervision"},
        %{path: ["services", "directional_drilling"], label: "Directional Drilling"},
        %{path: ["services", "mwd_lwd_services"], label: "MWD / LWD"},
        %{path: ["services", "gas_detection"], label: "Gas Detection"},
        %{path: ["services", "mud"], label: "Mud"}
      ]
    },
    "geological_services" => %{
      title: "Geological Services",
      fields: [
        %{path: ["geological_services", "samples_operator"], label: "Samples (Operator)"},
        %{path: ["geological_services", "samples_government"], label: "Samples (Government)"},
        %{path: ["geological_services", "cores"], label: "Cores"},
        %{path: ["geological_services", "dst"], label: "DST"},
        %{path: ["geological_services", "logging_suite"], label: "Logging Suite"}
      ]
    }
  }

  @card_order ~w(identification objectives total_depth elevations location services geological_services)

  @doc "The cards in the order the Well Data tab shows them."
  def cards, do: @card_order

  @doc "A card's field labels, in input order (inputs are named `fields[<index>]`)."
  def field_labels(card), do: Enum.map(@cards[card].fields, & &1.label)

  @impl true
  def update(%{report: _, card: card} = assigns, socket) when card in @card_order do
    socket =
      socket
      |> assign(assigns)
      |> assign(:spec, @cards[card])
      |> assign_new(:editing, fn -> false end)

    # Mid-edit, keep what's been typed; the fresh report still lands in assigns.
    {:ok, if(socket.assigns.editing, do: socket, else: load(socket))}
  end

  defp load(socket) do
    report = socket.assigns.report

    values =
      Map.new(Enum.with_index(socket.assigns.spec.fields), fn {f, i} ->
        {Integer.to_string(i), input_value(f, current(report, f))}
      end)

    assign(socket, values: values, errors: %{})
  end

  # ── events ────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("edit", _params, socket) do
    {:noreply, assign(socket, editing: true, errors: %{})}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, load(assign(socket, editing: false))}
  end

  def handle_event("validate", %{"fields" => params}, socket) do
    values = Map.merge(socket.assigns.values, params)
    {:noreply, assign(socket, values: values, errors: parse_errors(socket.assigns.spec, values))}
  end

  def handle_event("save", %{"fields" => params}, socket) do
    %{report: report, spec: spec, card: card} = socket.assigns
    values = Map.merge(socket.assigns.values, params)

    with errors when errors == %{} <- parse_errors(spec, values),
         {welldata, typed} = build(report, spec, values),
         {:ok, updated} <-
           Reports.update_import_sections(report, sections(card, report, welldata), typed) do
      send(self(), {:import_updated, updated, spec.title, card})
      {:noreply, load(assign(socket, report: updated, editing: false))}
    else
      %{} = errors ->
        {:noreply, assign(socket, values: values, errors: errors)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, values: values, errors: changeset_errors(spec, changeset))}
    end
  end

  # ── read / write ─────────────────────────────────────────────────────────

  # The KB feeds every Subsea in Formation Tops; save the re-derived tops with it.
  defp sections("elevations", report, welldata),
    do: FormationTops.with_tops(report, %{"welldata" => welldata})

  defp sections(_card, _report, welldata), do: %{"welldata" => welldata}

  defp welldata(report), do: (report.import_data || %{})["welldata"] || %{}

  # The field's current value: welldata, else the typed fallback.
  defp current(report, %{path: path} = f) do
    case get_in(welldata(report), path) do
      v when v in [nil, ""] -> fallback(report, f)
      v -> v
    end
  end

  defp current(report, %{typed: column}), do: Map.get(report, column)

  defp fallback(report, %{sync: column}), do: Map.get(report, column)
  defp fallback(report, %{fallback: {:report, column}}), do: Map.get(report, column)

  defp fallback(%{report_data: %{} = data}, %{fallback: {:data, field}}),
    do: Map.get(data, field)

  defp fallback(_report, _f), do: nil

  # {new welldata, typed-column attrs} from the submitted values.
  defp build(report, spec, values) do
    spec.fields
    |> Enum.with_index()
    |> Enum.reduce({welldata(report), %{}}, fn {f, i}, {wd, typed} ->
      raw = values[Integer.to_string(i)]
      stored = f[:path] && get_in(welldata(report), f.path)

      # Unchanged text keeps the stored value, so e.g. an integer rig number
      # isn't rewritten as a string just because the form submitted it.
      v =
        if not is_nil(stored) and raw == input_value(f, stored) do
          stored
        else
          {:ok, parsed} = parse(f, raw)
          parsed
        end

      wd = if f[:path], do: put_path(wd, f.path, v), else: wd

      typed =
        case f[:sync] || f[:typed] do
          nil -> typed
          column -> Map.put(typed, Atom.to_string(column), v)
        end

      {wd, typed}
    end)
  end

  # put_in that creates the intermediate maps — but never invents a section
  # just to hold a blank, so readers that assume e.g. `elevations` is a map
  # only see the shapes the extractor produces.
  defp put_path(map, [key], v) do
    if is_nil(v) and not Map.has_key?(map, key), do: map, else: Map.put(map, key, v)
  end

  defp put_path(map, [key | rest], v) do
    case {map[key], v} do
      {nil, nil} -> map
      {%{} = inner, _} -> Map.put(map, key, put_path(inner, rest, v))
      {_, _} -> Map.put(map, key, put_path(%{}, rest, v))
    end
  end

  # ── parse / validate ─────────────────────────────────────────────────────

  defp parse_errors(spec, values) do
    spec.fields
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {f, i}, acc ->
      key = Integer.to_string(i)

      case parse(f, values[key]) do
        {:ok, _} -> acc
        {:error, msg} -> Map.put(acc, key, msg)
      end
    end)
  end

  defp parse(%{required: true}, raw) when raw in [nil, ""], do: {:error, "can't be blank"}
  defp parse(_f, nil), do: {:ok, nil}

  defp parse(f, raw) when is_binary(raw) do
    case {Map.get(f, :type, :text), String.trim(raw)} do
      {_, ""} ->
        {:ok, nil}

      {:number, t} ->
        case Float.parse(t) do
          {n, ""} when n < 0 and not is_map_key(f, :signed) ->
            {:error, "must be ≥ 0"}

          {n, ""} ->
            {:ok, n}

          _ ->
            {:error, "must be a number"}
        end

      {:list, t} ->
        {:ok, t |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))}

      {_, t} ->
        {:ok, t}
    end
  end

  defp changeset_errors(spec, changeset) do
    spec.fields
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {f, i}, acc ->
      with column when not is_nil(column) <- f[:sync] || f[:typed],
           {msg, opts} <- Keyword.get(changeset.errors, column) do
        Map.put(acc, Integer.to_string(i), translate_error({msg, opts}))
      else
        _ -> acc
      end
    end)
  end

  # ── view helpers ─────────────────────────────────────────────────────────

  # At most two decimals (NumberFormat), except coordinates, which need their
  # precision (0.01° of latitude is about 1 km). build/3 keeps the stored value
  # when a field's text comes back unchanged, so the rounding never saves.
  defp input_value(_f, nil), do: ""
  defp input_value(%{type: :list}, v) when is_list(v), do: Enum.join(v, ", ")
  defp input_value(%{precise: true}, %Decimal{} = d), do: Decimal.to_string(d, :normal)

  defp input_value(%{precise: true}, v) when is_float(v),
    do: :erlang.float_to_binary(v, [:compact, decimals: 10])

  defp input_value(_f, v) when is_number(v), do: NumberFormat.up_to_2(v)
  defp input_value(_f, %Decimal{} = d), do: NumberFormat.up_to_2(d)
  defp input_value(_f, v), do: to_string(v)

  defp display(_f, ""), do: "—"
  defp display(%{unit: unit}, v), do: "#{v} #{unit}"
  defp display(_f, v), do: v

  defp options(%{options: fun}), do: fun.()

  # ── render ───────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <%!-- Editing, the form wraps the card so the Save bar sits outside the
           card's overflow clip and can stick to the bottom of the viewport. --%>
      <.form
        :if={@editing}
        for={%{}}
        as={:fields}
        id={"#{@id}-form"}
        phx-change="validate"
        phx-submit="save"
        phx-target={@myself}
      >
        <.card_panel title={@spec.title}>
          <div class="grid grid-cols-1 gap-4 px-5 py-4 sm:grid-cols-2 md:grid-cols-3">
            <label
              :for={{f, i} <- Enum.with_index(@spec.fields)}
              class={["flex flex-col gap-1", f[:wide] && "sm:col-span-2 md:col-span-3"]}
            >
              <span class="text-xs font-semibold uppercase tracking-wide text-copy-secondary">
                {f.label}<span :if={f[:unit]} class="ml-1 normal-case font-normal">({f.unit})</span>
              </span>
              <% name = "fields[#{i}]" %>
              <% value = @values[Integer.to_string(i)] %>
              <% error = @errors[Integer.to_string(i)] %>
              <% input_class = [
                "w-full rounded border bg-white px-3 py-2 text-sm focus:outline-none",
                error && "border-danger",
                !error && "border-border focus:border-primary"
              ] %>
              <%= case Map.get(f, :type, :text) do %>
                <% :select -> %>
                  <select name={name} class={input_class}>
                    <option :if={!f[:required]} value="">—</option>
                    <%= for opt <- options(f) do %>
                      <option value={opt} selected={opt == value}>{opt}</option>
                    <% end %>
                    <option :if={value != "" and value not in options(f)} value={value} selected>
                      {value}
                    </option>
                  </select>
                <% :textarea -> %>
                  <textarea name={name} rows="3" phx-debounce="blur" class={input_class}>{value}</textarea>
                <% type -> %>
                  <input
                    type="text"
                    inputmode={type == :number && "decimal"}
                    name={name}
                    value={value}
                    placeholder={f[:placeholder]}
                    phx-debounce="blur"
                    class={input_class}
                  />
              <% end %>
              <span :if={error} class="text-xs text-danger">{f.label} {error}</span>
            </label>
          </div>
          <p :if={@spec[:note]} class="px-5 text-xs text-copy-secondary">{@spec.note}</p>
        </.card_panel>
        <.edit_actions target={@myself} disabled={@errors != %{}} />
      </.form>

      <.card_panel :if={not @editing} title={@spec.title}>
        <:action :if={@editable}>
          <button
            type="button"
            phx-click="edit"
            phx-target={@myself}
            aria-label={"Edit #{@spec.title}"}
            title={"Edit #{@spec.title}"}
            class="inline-flex items-center gap-1.5 rounded-md px-2 py-1 text-xs font-medium cursor-pointer opacity-80 transition-opacity hover:opacity-100 text-table-header-label"
          >
            <.icon name="hero-pencil" class="h-4 w-4" />
            <span>Edit</span>
          </button>
        </:action>
        <div class="grid grid-cols-2 gap-x-6 gap-y-3 px-5 py-4 sm:grid-cols-3 md:grid-cols-4">
          <div
            :for={{f, i} <- Enum.with_index(@spec.fields)}
            class={["flex flex-col gap-0.5", f[:wide] && "col-span-2 sm:col-span-3 md:col-span-4"]}
          >
            <span class="text-xs font-medium text-muted uppercase">{f.label}</span>
            <span class="text-sm text-text whitespace-pre-line">
              {display(f, @values[Integer.to_string(i)])}
            </span>
          </div>
        </div>
      </.card_panel>
    </div>
    """
  end
end
