defmodule ChinookReportsWeb.CreateReportLive do
  use ChinookReportsWeb, :live_view

  import ChinookReportsWeb.ReportFormComponents
  import ChinookReportsWeb.Stepper

  alias ChinookReports.Reports
  alias ChinookReports.Reports.Report
  alias ChinookReports.Reports.Report.ReportData.{ProfileSection, FormationTop, SurveyPoint}

  # entry type: manual vs file upload
  @entry_types [
    %{id: :manual, label: "Manual Entry"},
    %{id: :file, label: "File Upload"}
  ]

  # The whole step list lives here so the stepper, the navigation handlers,
  # and any future "which fields belong to which step" logic all read from
  # one source.
  @steps [
    %{id: 1, label: "Identity", optional: false},
    %{id: 2, label: "Elevations & Location", optional: false},
    %{id: 3, label: "Configuration", optional: false},
    %{id: 4, label: "Well Profile", optional: false},
    %{id: 5, label: "Formation Tops", optional: true},
    %{id: 6, label: "Directional Program", optional: true}
  ]

  @identity_fields [
    %{field: :well_name, label: "Well Name", placeholder: "GEAR SODA LAKE 103 HZ…", wide: true},
    %{field: :spud_date, label: "Spud Date", placeholder: "YYYY-MM-DD"},
    %{field: :unique_well_id, label: "Unique Well I.D.", placeholder: "XXX/XX-XX-XXX-XXWX/XX"},
    %{field: :operator, label: "Operator", placeholder: "Operator name"},
    %{field: :country, label: "Country", placeholder: "Canada"},
    %{field: :province, label: "Province", placeholder: "Alberta"},
    %{field: :geometry, label: "Well Geometry", input: :select, options: &Report.geometries/0},
    %{field: :target_formation, label: "Primary Target", placeholder: "Enter the target formation"},
    %{field: :secondary_target, label: "Secondary target if applicable"},
    %{field: :units, label: "Unit System", input: :select, options: &Report.units/0}
  ]

  @elevation_fields [
    %{field: :gl_elevation, label: "Ground Level", unit: :depth},
    %{field: :kb_elevation, label: "Kelly Bushing", unit: :depth},
    %{field: :kb_to_ground, label: "KB to Ground", unit: :depth}
  ]

  @location_fields [
    %{field: :latitude, label: "Latitude", unit: "°N"},
    %{field: :longitude, label: "Longitude", unit: "°W"},
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
    %{key: :start_date, label: "Start Date", placeholder: "YYYY-MM-DD"}
  ]

  @formation_top_columns [
    %{key: :formation, label: "Formation", placeholder: "McLaren"},
    %{key: :md, label: "MD", unit: :depth},
    %{key: :tvd, label: "TVD", unit: :depth},
    %{key: :isopach, label: "Isopach", unit: :depth},
    %{key: :subsea, label: "Subsea", unit: :depth}
  ]

  @survey_columns [
    %{key: :md, label: "MD", unit: :depth},
    %{key: :inclination, label: "Inclination", unit: "°"},
    %{key: :azimuth, label: "Azimuth", unit: "°"}
  ]

  # Fields that must be valid before leaving a given step.
  @step_guards %{
    1 => [:well_name, :unique_well_id]
  }
  IO.inspect(@current_step, label: "<<<<< Current step in CreateReportLive >>>>>")
  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Create New Well Report")
     |> assign(:steps, @steps)
     |> assign(:current_step, 1)
     |> assign(:identity_fields, @identity_fields)
     |> assign(:elevation_fields, @elevation_fields)
     |> assign(:location_fields, @location_fields)
     |> assign(:configuration_fields, @configuration_fields)
     |> assign(:profile_columns, @profile_columns)
     |> assign(:formation_top_columns, @formation_top_columns)
     |> assign(:survey_columns, @survey_columns)
     |> assign_form(Reports.new_report_changeset())}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    report = Reports.get_report!(id)
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

      <.stepper steps={@steps} current_step={@current_step} />

      <div class="border rounded-lg p-4 bg-white shadow">
        <.form for={@form} phx-change="validate" phx-submit="update">
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
              >
                Next →
              </button>

              <button
                :if={last_step?(@steps, @current_step)}
                type="submit"
                class="btn-primary"
              >
                {if @editing_report, do: "Save report", else: "Create report"}
              </button>
            </div>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  defp select_entry_type(assigns) do
    ~H"""
    <%= case @entry_type do %>
      <% :manual -> %>
        <p class="text-sm text-copy-secondary">User will fill out the form fields manually.</p>
      <% :file -> %>
        <p class="text-sm text-copy-secondary">
          User will upload a file to pre-populate the form fields.
        </p>
    <% end %>
    """
  end

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
        </.section_card>
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

  def handle_event("next", _params, socket) do
    required = Map.get(@step_guards, socket.assigns.current_step, [])

    changeset =
      socket.assigns.form.source
      |> Reports.change_report(socket.assigns.form.params || %{})
      |> Map.put(:action, :validate)

    if Enum.any?(required, &Keyword.has_key?(changeset.errors, &1)) do
      {:noreply, assign_form(socket, changeset)}
    else
      {:noreply, assign(socket, :current_step, next_step(socket.assigns))}
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
    {:noreply, assign(socket, :current_step, step)}
  end

  def handle_event("update", %{"report" => params}, socket) do
    changeset = Map.put(socket.assigns.form.source, :action, nil)

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
    list_atom = String.to_existing_atom(list)
    changeset = current_changeset(socket)
    existing = Ecto.Changeset.get_field(changeset, :report_data) |> Map.get(list_atom, [])
    new_list = existing ++ [blank_row(list_atom)]

    changeset = put_in_report_data(changeset, list_atom, new_list)
    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("remove_row", %{"list" => list, "index" => index}, socket) do
    list_atom = String.to_existing_atom(list)
    index = String.to_integer(index)

    changeset = current_changeset(socket)
    existing = Ecto.Changeset.get_field(changeset, :report_data) |> Map.get(list_atom, [])
    new_list = List.delete_at(existing, index)

    changeset = put_in_report_data(changeset, list_atom, new_list)
    {:noreply, assign_form(socket, changeset)}
  end

  # ── helpers ───────────────────────────────────────────────────────────────

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

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: :report))
  end

  # Pull the current changeset and re-merge the latest form params so any
  # in-flight typing isn't lost when we add/remove a row.
  defp current_changeset(socket) do
    params = socket.assigns.form.params || %{}
    Reports.change_report(socket.assigns.form.source, params)
  end

  # Update one nested list inside report_data and rebuild that embed.
  #
  # Ecto.Changeset.put_embed/3 on report_data with a plain, already-modified
  # struct doesn't reliably register nested embeds_many changes (it diffs the
  # embeds_one as a whole against the original, and that diff can come back
  # empty even though a nested list clearly differs). Putting the list at its
  # own nesting level, via a proper changeset for report_data, is what
  # actually gets tracked.
  defp put_in_report_data(changeset, list_atom, new_list) do
    report_data_changeset =
      changeset
      |> Ecto.Changeset.get_field(:report_data)
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_embed(list_atom, new_list)

    Ecto.Changeset.put_embed(changeset, :report_data, report_data_changeset)
  end

  defp blank_row(:profile_sections), do: %ProfileSection{}
  defp blank_row(:formation_tops), do: %FormationTop{}
  defp blank_row(:surveys), do: %SurveyPoint{}
end
