defmodule ChinookReportsWeb.CreateReportLive do
  use ChinookReportsWeb, :live_view

  import ChinookReportsWeb.ReportFormComponents
  import ChinookReportsWeb.Stepper

  alias ChinookReports.Countries
  alias ChinookReports.DirectionalPlan
  alias ChinookReports.Reports
  alias ChinookReports.Reports.Editing
  alias ChinookReports.Reports.Report
  alias ChinookReportsWeb.PlanUpload

  # entry type: manual vs file upload
  # @entry_types [
  #   %{id: :manual, label: "Manual Entry"},
  #   %{id: :file, label: "File Upload"}
  # ]

  # The whole step list lives here so the stepper, the navigation handlers,
  # and any future "which fields belong to which step" logic all read from
  # one source.
  @steps [
    %{id: 1, label: "Identity", optional: false},
    %{id: 2, label: "Elevations & Location", optional: false},
    %{id: 3, label: "Configuration", optional: false},
    %{id: 4, label: "Well Profile", optional: false},
    %{id: 5, label: "Formation Tops", optional: true},
    %{id: 6, label: "Directional Program", optional: true},
    %{id: 7, label: "Review", optional: false}
  ]

  @identity_fields [
    %{field: :well_name, label: "Well Name", placeholder: "GEAR SODA LAKE 103 HZ…", wide: true},
    %{field: :spud_date, label: "Spud Date", type: :datetime},
    %{
      field: :unique_well_id,
      label: "Unique Well I.D.",
      placeholder: "XXX/XX-XX-XXX-XXWX/XX",
      mask: :uwi
    },
    %{field: :operator, label: "Operator", placeholder: "Operator name"},
    %{field: :country, label: "Country", input: :select, options: &Countries.all/0},
    %{field: :province, label: "Province", placeholder: "Alberta"},
    %{field: :geometry, label: "Well Geometry", input: :select, options: &Report.geometries/0},
    %{
      field: :target_formation,
      label: "Primary Target",
      placeholder: "Enter the target formation"
    },
    %{field: :secondary_target, label: "Secondary target if applicable"},
    %{field: :units, label: "Unit System", input: :select, options: &Report.units/0}
  ]

  @elevation_fields [
    %{field: :gl_elevation, label: "Ground Level", unit: :depth},
    %{field: :kb_elevation, label: "Kelly Bushing", unit: :depth}
    # %{field: :kb_to_ground, label: "KB to Ground", unit: :depth}
  ]

  # latitude/longitude are top-level Report columns; the rest of the
  # Location section lives in the report_data embed, so they're rendered
  # against different form scopes (see step_content/1, step 2).
  @coordinate_fields [
    %{field: :latitude, label: "Latitude", unit: "°N"},
    %{field: :longitude, label: "Longitude", unit: "°W"}
  ]

  @location_fields [
    %{field: :datum, label: "Datum", input: :select, options: &Report.datums/0},
    %{field: :surface_coordinates, label: "Surface Coordinates", wide: true}
  ]

  @configuration_fields [
    %{
      field: :classification,
      label: "Well Classification",
      input: :select,
      options: &Report.classifications/0
    },
    %{field: :license, label: "Well License", placeholder: "Enter well license or permit number"},
    %{field: :purpose, label: "Well Purpose", placeholder: "Enter well purpose"},
    %{field: :substance, label: "Substance", placeholder: "Enter substance"},
    %{field: :terminating_zone, label: "Terminating Zone", placeholder: "Enter terminating zone"}
  ]

  @profile_columns [
    %{key: :section, label: "Section", placeholder: "Lateral"},
    %{key: :start_depth, label: "Start", unit: :depth},
    %{key: :end_depth, label: "End", unit: :depth},
    %{key: :start_date, label: "Start Date", type: :datetime}
  ]

  @formation_top_columns [
    %{key: :formation, label: "Formation", placeholder: "McLaren"},
    %{key: :md, label: "MD", unit: :depth},
    %{key: :tvd, label: "TVD", unit: :depth},
    %{key: :isopach, label: "Isopach", unit: :depth, computed: true},
    %{key: :subsea, label: "Subsea", unit: :depth}
  ]

  @survey_columns [
    %{key: :md, label: "MD", unit: :depth},
    %{key: :inclination, label: "Inclination", unit: "°"},
    %{key: :azimuth, label: "Azimuth", unit: "°"}
  ]

  # Mandatory fields per step: `{top_level_columns, report_data_columns}`.
  # Every one of these must have a value before Next will leave the step,
  # and a step with all of them filled is drawn "complete" in the stepper.
  # Steps not listed here (the table steps) have no mandatory fields.
  @mandatory %{
    1 => {[:well_name, :unique_well_id], []},
    2 => {[:latitude, :longitude], []},
    3 => {[], [:classification]}
  }

  @list_steps %{4 => :profile_sections, 5 => :formation_tops, 6 => :surveys}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Create New Well Report")
     |> assign(:steps, @steps)
     |> assign(:current_step, 1)
     |> assign(:identity_fields, @identity_fields)
     |> assign(:elevation_fields, @elevation_fields)
     |> assign(:coordinate_fields, @coordinate_fields)
     |> assign(:location_fields, @location_fields)
     |> assign(:configuration_fields, @configuration_fields)
     |> assign(:profile_columns, @profile_columns)
     |> assign(:formation_top_columns, @formation_top_columns)
     |> assign(:survey_columns, @survey_columns)
     |> PlanUpload.allow()
     |> assign_form(Reports.new_report_changeset())}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    report = id |> Reports.get_report!() |> Reports.ensure_report_data()
    changeset = Reports.change_report(report)
    {:noreply, socket |> assign(:editing_report, report) |> assign_form(changeset)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :editing_report, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col gap-4">
      <.heading>
        <:title>{if @editing_report, do: "Edit Well Report", else: "Create New Well Report"}</:title>
        <:subtitle>
          Fill out the form below to {if @editing_report, do: "update", else: "create"} a well report.
        </:subtitle>
      </.heading>

      <.stepper
        steps={@steps}
        current_step={@current_step}
        unlocked={unlocked_step_ids(@steps, @form.source)}
        completed={completed_step_ids(@steps, @form.source)}
      />

      <div class="border rounded-lg p-4 bg-white shadow">
        <.form for={@form} phx-change="validate" phx-submit="create_report">
          <div class="min-h-48">
            {step_content(assigns)}
          </div>

          <div class="mt-6 flex items-center justify-between border-t border-light pt-4">
            <button
              class="btn-secondary"
              type="button"
              phx-click="back"
              disabled={first_step?(@steps, @current_step)}
            >
              ← Back
            </button>

            <div class="flex gap-2">
              <button
                :if={optional_step?(@steps, @current_step)}
                type="button"
                phx-click="skip"
                class="btn-secondary"
              >
                Skip
              </button>

              <button
                :if={!last_step?(@steps, @current_step)}
                type="button"
                phx-click="next"
                class="btn-primary"
                disabled={not can_advance?(@current_step, @form.source)}
              >
                Next →
              </button>

              <button
                :if={last_step?(@steps, @current_step)}
                type="submit"
                class="btn-primary"
                disabled={not can_advance?(@current_step, @form.source)}
              >
                {if @editing_report, do: "Approve & save", else: "Approve & activate"}
              </button>
            </div>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  # defp select_entry_type(assigns) do
  #   ~H"""
  #   <%= case @entry_type do %>
  #     <% :manual -> %>
  #       <p class="text-sm text-copy-secondary">User will fill out the form fields manually.</p>
  #     <% :file -> %>
  #       <p class="text-sm text-copy-secondary">
  #         User will upload a file to pre-populate the form fields.
  #       </p>
  #   <% end %>
  #   """
  # end

  defp step_content(assigns) do
    ~H"""
    <%= case @current_step do %>
      <% 1 -> %>
        <%!-- Identity --%>
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <.report_field
            :for={spec <- @identity_fields}
            form={@form}
            spec={spec}
          />
        </div>
      <% 2 -> %>
        <%!-- Elevations & Location --%>
        <.inputs_for :let={data} field={@form[:report_data]}>
          <div class="space-y-4">
            <.section_card title="Elevations" subtitle="Reference datums for depth">
              <%!-- no more <:action> with the toggle --%>
              <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
                <.report_field
                  :for={spec <- @elevation_fields}
                  form={data}
                  spec={spec}
                />
              </div>
            </.section_card>

            <.section_card title="Location" subtitle="Geographic coordinates and datum">
              <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
                <.report_field
                  :for={spec <- coordinate_fields(data)}
                  form={@form}
                  spec={spec}
                />
                <.report_field
                  :for={spec <- @location_fields}
                  form={data}
                  spec={spec}
                />
              </div>
            </.section_card>
          </div>
        </.inputs_for>
      <% 3 -> %>
        <%!-- Configuration --%>
        <.inputs_for :let={data} field={@form[:report_data]}>
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <.report_field :for={spec <- @configuration_fields} form={data} spec={spec} />
          </div>
        </.inputs_for>
      <% 4 -> %>
        <%!-- Well Profile --%>
        <.section_card
          title="Well Profile"
          subtitle="Sections are added as the well progresses — start empty and build up over time"
        >
          <.inputs_for :let={data} field={@form[:report_data]}>
            <.editable_table
              form={data}
              list={:profile_sections}
              columns={resolve_columns(@profile_columns)}
              hint="No sections yet. Add Vertical, Build, Lateral or additional legs as drilling reaches them."
            />
          </.inputs_for>
        </.section_card>
      <% 5 -> %>
        <%!-- Formation Tops --%>
        <.section_card
          title="Formation Tops — Prognosis"
          subtitle="Estimated tops; actuals are filled in later as the well progresses"
        >
          <.inputs_for :let={data} field={@form[:report_data]}>
            <.editable_table
              form={data}
              list={:formation_tops}
              columns={resolve_columns(@formation_top_columns)}
            />
          </.inputs_for>
        </.section_card>
      <% 6 -> %>
        <%!-- Directional Program --%>
        <.section_card
          title="Directional Program — Prognosis Survey Points"
          subtitle="Planned survey stations; the actual survey appends to these as drilling proceeds"
        >
          <.plan_drop_zone
            upload={@uploads.plan}
            importing={@plan_importing}
            tops={@plan_tops}
            tops_note="Fills the Formation Tops step, matching formations by name; plan formations not in it are added. Saved with the report."
          />
          <.inputs_for :let={data} field={@form[:report_data]}>
            <.editable_table
              form={data}
              list={:surveys}
              columns={resolve_columns(@survey_columns)}
            />
          </.inputs_for>
          <p class="mt-3 text-xs text-copy-secondary">
            TVD, N/S, E/W and dogleg are computed from MD / Inc / Azi (minimum curvature) — no need to enter them.
          </p>
          <p
            :if={Ecto.Changeset.get_field(@form.source, :geometry) == "Deviated"}
            class="mt-2 text-xs text-copy-secondary"
          >
            Deviated well: the report Summary measures the actual surveys against this path.
            You can skip it for now and add or revise it from the report's Surveys tab while the well is active.
          </p>
        </.section_card>
      <% 7 -> %>
        <%!-- Review --%>
        <div class="space-y-4">
          <.section_card title="Identity" subtitle="Confirm the details below before submitting">
            <dl class="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <div :for={spec <- @identity_fields ++ @coordinate_fields}>
                <dt class="text-xs font-semibold uppercase tracking-wide text-copy-secondary">
                  {spec.label}
                </dt>
                <dd class="text-sm text-copy">{review_value(@form, spec.field)}</dd>
              </div>
            </dl>
          </.section_card>

          <.inputs_for :let={data} field={@form[:report_data]}>
            <.section_card title="Elevations, Location & Configuration">
              <dl class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <div :for={spec <- @elevation_fields ++ @location_fields ++ @configuration_fields}>
                  <dt class="text-xs font-semibold uppercase tracking-wide text-copy-secondary">
                    {spec.label}
                  </dt>
                  <dd class="text-sm text-copy">{review_value(data, spec.field)}</dd>
                </div>
              </dl>
            </.section_card>

            <.section_card title="Tables">
              <ul class="space-y-1 text-sm text-copy">
                <li>
                  Well Profile sections:
                  <strong>{length(data[:profile_sections].value || [])}</strong>
                </li>
                <li>
                  Formation tops entered: <strong>{length(data[:formation_tops].value || [])}</strong>
                </li>
                <li>
                  Survey points entered: <strong>{length(data[:surveys].value || [])}</strong>
                </li>
              </ul>
            </.section_card>
          </.inputs_for>

          <p class="text-xs text-copy-secondary">
            Submitting from here marks this report <strong>Active</strong>.
          </p>
        </div>
      <% _other -> %>
        <p class="text-sm text-copy-secondary">
          Step content for <strong>{step_label(@steps, @current_step)}</strong> coming next.
        </p>
    <% end %>
    """
  end

  # ── events ────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("validate", %{"report" => params}, socket) do
    changeset =
      socket.assigns.form.source
      |> Reports.change_report(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  # A plan file dropped on step 6 while that step has no rows: the upload's
  # phx-change carries no report fields.
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("next", _params, socket) do
    current_step = socket.assigns.current_step

    changeset =
      socket.assigns.form.source
      |> Reports.change_report(socket.assigns.form.params || %{})
      |> Map.put(:action, :validate)

    if optional_step?(@steps, current_step) or mandatory_met?(changeset, current_step) do
      {:noreply, assign(socket, :current_step, next_step(socket.assigns))}
    else
      {:noreply,
       socket
       |> assign_form(changeset)
       |> put_flash(:error, "Fill in the required fields before continuing.")}
    end
  end

  def handle_event("back", _params, socket) do
    {:noreply, assign(socket, :current_step, prev_step(socket.assigns))}
  end

  # Skip is the same as next, but lives as its own event so we can later
  # mark the skipped step as "intentionally empty" in the UI if we want.
  def handle_event("skip", _params, socket) do
    {:noreply, assign(socket, :current_step, next_step(socket.assigns))}
  end

  def handle_event("navigate_to_step", %{"step" => step}, socket) do
    {:noreply, assign(socket, :current_step, String.to_integer(step))}
  end

  def handle_event("create_report", %{"report" => params}, socket) do
    changeset = Map.put(socket.assigns.form.source, :action, nil)
    params = Map.put(params, "status", "active")

    result =
      case socket.assigns.editing_report do
        nil -> Reports.create_report(changeset, params)
        _report -> Reports.update_report(changeset, params)
      end

    case result do
      {:ok, updated} ->
        message = if socket.assigns.editing_report, do: "Report updated.", else: "Report created."

        {:noreply,
         socket
         |> put_flash(:info, message)
         |> push_navigate(to: ~p"/reports/#{updated.id}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("add_row", %{"list" => list}, socket) do
    changeset = Editing.add_row(current_changeset(socket), String.to_existing_atom(list))
    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("remove_row", %{"list" => list, "index" => index}, socket) do
    changeset =
      Editing.remove_row(
        current_changeset(socket),
        String.to_existing_atom(list),
        String.to_integer(index)
      )

    {:noreply, assign_form(socket, changeset)}
  end

  # A read plan's formation tops, offered by the step-6 drop zone, merged into
  # the Formation Tops step (saved with the rest of the wizard).
  def handle_event("import_plan_tops", _params, socket) do
    tops = socket.assigns.plan_tops || []
    changeset = current_changeset(socket)
    existing = Ecto.Changeset.get_field(changeset, :report_data).formation_tops
    rows = DirectionalPlan.merge_formation_tops(existing, tops)

    {:noreply,
     socket
     |> assign_form(Editing.replace_rows(changeset, :formation_tops, rows))
     |> PlanUpload.clear_tops()
     |> put_flash(:info, "Imported #{length(tops)} formation tops into the Formation Tops step.")}
  end

  def handle_event("skip_plan_tops", _params, socket) do
    {:noreply, PlanUpload.clear_tops(socket)}
  end

  # A dropped directional plan replaces the Directional Program rows.
  @impl true
  def handle_async(:plan_import, result, socket) do
    uwi = Ecto.Changeset.get_field(current_changeset(socket), :unique_well_id)

    {:noreply,
     PlanUpload.apply_result(socket, result, uwi, fn socket, rows ->
       assign_form(socket, Editing.replace_rows(current_changeset(socket), :surveys, rows))
     end)}
  end

  # ── helpers ───────────────────────────────────────────────────────────────

  # UTM coordinates are metric Easting/Northing; every other supported datum
  # (ATS/NTS/DLS/Other) is a lat/long-based description, so the unit suffix
  # on the Latitude/Longitude fields follows whichever Datum is selected.
  defp coordinate_fields(data_form) do
    case data_form[:datum].value do
      "UTM" -> Enum.map(@coordinate_fields, &Map.put(&1, :unit, "m"))
      _other -> @coordinate_fields
    end
  end

  defp resolve_columns(columns) do
    Enum.map(columns, fn col ->
      case col[:unit] do
        :depth -> Map.put(col, :unit, "m")
        _ -> col
      end
    end)
  end

  defp next_step(%{steps: steps, current_step: current}) do
    i = Enum.find_index(steps, &(&1.id == current))
    Enum.at(steps, min(i + 1, length(steps) - 1)).id
  end

  defp prev_step(%{steps: steps, current_step: current}) do
    i = Enum.find_index(steps, &(&1.id == current))
    Enum.at(steps, max(i - 1, 0)).id
  end

  defp first_step?(steps, current), do: List.first(steps).id == current
  defp last_step?(steps, current), do: List.last(steps).id == current
  defp optional_step?(steps, current), do: Enum.find(steps, &(&1.id == current)).optional

  defp step_label(steps, current), do: Enum.find(steps, &(&1.id == current)).label

  # Whether Next/Save may leave the current step: an optional step always
  # can, otherwise its mandatory fields must all be filled.
  defp can_advance?(step, changeset) do
    optional_step?(@steps, step) or mandatory_met?(changeset, step)
  end

  # Steps you can click straight to: everything up to and including the first
  # step that still has a mandatory field missing. Steps with no mandatory
  # fields (the table steps) never block the chain, so a draft with the key
  # fields filled ends up entirely navigable.
  defp unlocked_step_ids(steps, changeset) do
    steps
    |> Enum.reduce({[], true}, fn step, {ids, prefix_ok?} ->
      ids = if prefix_ok?, do: [step.id | ids], else: ids
      {ids, prefix_ok? and mandatory_met?(changeset, step.id)}
    end)
    |> elem(0)
  end

  # Steps drawn "complete" in the stepper — solid circle, solid connector
  # leaving them.
  defp completed_step_ids(steps, changeset) do
    for step <- steps, step_complete?(changeset, step.id), do: step.id
  end

  # A table step counts as complete once it has one row with real content in
  # it; every other step, once all its mandatory fields are filled.
  defp step_complete?(changeset, step) when step in [4, 5, 6] do
    report_data_list_present?(changeset, Map.fetch!(@list_steps, step))
  end

  defp step_complete?(changeset, step), do: mandatory_met?(changeset, step)

  # The Next-button gate. Table steps have no mandatory fields, so Next
  # always lets you leave them (Skip covers the optional ones).
  defp mandatory_met?(_changeset, step) when step in [4, 5, 6], do: true

  defp mandatory_met?(changeset, step) do
    {top_fields, data_fields} = Map.get(@mandatory, step, {[], []})
    data = get_field(changeset, :report_data)

    # Present *and* valid: a filled-in field that fails validation (e.g. a
    # UWI in the wrong format for the country) still holds the step.
    Enum.all?(top_fields, &(present?(get_field(changeset, &1)) and not has_error?(changeset, &1))) and
      Enum.all?(data_fields, &present?(data && Map.get(data, &1)))
  end

  defp has_error?(changeset, field), do: Keyword.has_key?(changeset.errors, field)

  defp report_data_list_present?(changeset, key) do
    case get_field(changeset, :report_data) do
      nil -> false
      data -> Enum.any?(Map.get(data, key, []), &row_has_content?/1)
    end
  end

  defp row_has_content?(row) do
    row
    |> Map.from_struct()
    |> Map.drop([:id])
    |> Map.values()
    |> Enum.any?(&present?/1)
  end

  defp get_field(changeset, field), do: Ecto.Changeset.get_field(changeset, field)

  # Read-only display value for the Review step; blank/nil reads as an em dash
  # rather than an empty cell.
  defp review_value(form, field) do
    case form[field].value do
      value when value in [nil, ""] -> "—"
      value -> value
    end
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: :report))
  end

  # Pull the current changeset and re-merge the latest form params so any
  # in-flight typing isn't lost when we add/remove a row.
  defp current_changeset(socket) do
    params = socket.assigns.form.params || %{}
    Reports.change_report(socket.assigns.form.source, params)
  end
end
