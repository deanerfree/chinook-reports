defmodule ChinookReportsWeb.ReportPageLive do
  use ChinookReportsWeb, :live_view

  alias ChinookReports.DirectionalPlan
  alias ChinookReports.FormationTops
  alias ChinookReports.ReportSummary
  alias ChinookReports.Reports
  alias ChinookReports.Reports.Editing
  alias ChinookReports.ReservoirQuality
  alias ChinookReportsWeb.PlanUpload
  import ChinookReportsWeb.ReportSummaryComponents

  def mount(%{"id" => id}, _session, socket) do
    case fetch_report(id) do
      {:ok, report} ->
        {:ok,
         socket
         |> PlanUpload.allow()
         |> assign(
           report: report,
           error: nil,
           active_tab: "summary",
           survey_view: nil,
           editing: nil,
           form: nil,
           summary: ReportSummary.build(report)
         )}

      {:error, :not_found} ->
        {:ok,
         assign(socket,
           report: nil,
           summary: nil,
           active_tab: "summary",
           survey_view: nil,
           editing: nil,
           form: nil,
           error: "Report not found"
         )}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="w-full max-w-300 mx-auto pb-16">
      <%= cond do %>
        <% @report && @summary -> %>
          <div class="flex flex-col gap-5">
            <button
              class="w-fit text-xs font-medium text-primary hover:text-primary-hover cursor-pointer"
              phx-click="back"
            >
              &#8592; Back to Reports
            </button>

            <.report_header header={@summary.header} />
            <.report_tabs tabs={@summary.tabs} active={@active_tab} />

            <%= if @active_tab == "summary" do %>
              <.summary_tab summary={@summary} />
            <% else %>
              <.tab_content
                tab={@active_tab}
                survey_view={@survey_view}
                report={@report}
                editable={editable?(@report)}
                editing={@editing}
                form={@form}
                plan_upload={@uploads[:plan]}
                plan_importing={@plan_importing}
                plan_tops={@plan_tops}
              />
            <% end %>
          </div>
        <% true -> %>
          <p>Report not found.</p>
          <p :if={@error} class="text-red-500">{@error}</p>
          <button class="cursor-pointer mt-4" phx-click="back">&#8592; Back to Reports</button>
      <% end %>
    </div>
    """
  end

  # Keep the active tab (and the Surveys tab's Actual / Planned choice) in the
  # URL so a refresh / LiveView remount lands back on the same view instead of
  # snapping to "summary".
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(
       active_tab: resolve_tab(socket, params["tab"]),
       survey_view: if(params["survey"] in ~w(actual planned), do: params["survey"])
     )}
  end

  def handle_event("select_tab", %{"tab" => tab}, socket) do
    {:noreply,
     socket
     |> assign(editing: nil, form: nil)
     |> push_patch(to: tab_path(socket.assigns.report, tab))}
  end

  def handle_event("select_survey_view", %{"view" => view}, socket) do
    {:noreply,
     socket
     |> assign(editing: nil, form: nil)
     |> push_patch(to: tab_path(socket.assigns.report, "surveys") <> "&survey=#{view}")}
  end

  def handle_event("back", _value, socket) do
    {:noreply, push_navigate(socket, to: "/reports")}
  end

  def handle_event("edit_section", %{"section" => section}, socket) do
    {:noreply,
     socket
     |> PlanUpload.clear_tops()
     |> assign(editing: section, form: as_form(edit_changeset(socket.assigns.report)))}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, socket |> PlanUpload.clear_tops() |> assign(editing: nil, form: nil)}
  end

  def handle_event("validate", %{"report" => params}, socket) do
    changeset =
      socket.assigns.report
      |> edit_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: as_form(changeset))}
  end

  # A plan file dropped on an empty Directional Program: the upload's
  # phx-change carries no report fields.
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("save_section", %{"report" => params}, socket) do
    case Reports.update_report(base_report(socket.assigns.report), params) do
      {:ok, report} ->
        {:noreply,
         socket
         |> PlanUpload.clear_tops()
         |> assign(
           report: report,
           summary: ReportSummary.build(report),
           editing: nil,
           form: nil
         )
         |> put_flash(:info, "Changes saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: as_form(Map.put(changeset, :action, :validate)))}
    end
  end

  # A read plan's formation tops (offered by the Surveys editor's drop zone).
  # They're saved now — the open Surveys form can't carry another section —
  # into the table the Formation Tops tab shows.
  def handle_event("import_plan_tops", _params, socket) do
    tops = socket.assigns.plan_tops || []

    case save_plan_tops(socket.assigns.report, tops) do
      {:ok, report} ->
        {:noreply,
         socket
         |> PlanUpload.clear_tops()
         |> assign(report: report, summary: ReportSummary.build(report))
         |> put_flash(:info, "Imported #{length(tops)} formation tops into Formation Tops.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not save the formation tops.")}
    end
  end

  def handle_event("skip_plan_tops", _params, socket) do
    {:noreply, PlanUpload.clear_tops(socket)}
  end

  def handle_event("add_row", %{"list" => list}, socket) do
    {:noreply, assign(socket, form: as_form(mutate_rows(socket, :add, list)))}
  end

  def handle_event("remove_row", %{"list" => list, "index" => index}, socket) do
    {:noreply,
     assign(socket, form: as_form(mutate_rows(socket, {:remove, String.to_integer(index)}, list)))}
  end

  # The Reservoir Quality picker (a Svelte component in ReservoirQualityLive)
  # pushes its full section list here on every commit; we apply it, recompute
  # the derived quality_summary and persist.
  def handle_event("commit_intervals", %{"intervals" => list}, socket) when is_list(list) do
    report = socket.assigns.report

    with {:ok, legs} <- ReservoirQuality.commit_intervals(report, list),
         {:ok, updated} <- Reports.update_import_section(report, "reservoir_data", legs) do
      {:noreply,
       socket
       |> assign(report: updated, summary: ReportSummary.build(updated))
       |> put_flash(:info, "Reservoir Quality saved.")}
    else
      {:error, :invalid} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "That change left a section with a bad depth or quality — not saved."
         )}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not save Reservoir Quality.")}
    end
  end

  # The Formation Tops editor (a LiveComponent) persists on its own and tells us
  # to refresh the report + summary it derives.
  def handle_info({:tops_updated, report}, socket) do
    {:noreply,
     socket
     |> assign(report: report, summary: ReportSummary.build(report))
     |> put_flash(:info, "Formation Tops saved.")}
  end

  # A flash from a LiveComponent (its own only shows on a redirect).
  def handle_info({:put_flash, kind, message}, socket) do
    {:noreply, put_flash(socket, kind, message)}
  end

  # The import_data editors (WellDataCardLive, ImportTableLive, SynopsisLive)
  # persist their own slice — plus any Formation Tops it re-derives — and hand
  # back the updated report.
  def handle_info({:import_updated, report, title, _section}, socket) do
    {:noreply,
     socket
     |> assign(report: report, summary: ReportSummary.build(report))
     |> put_flash(:info, "#{title} saved.")}
  end

  # A dropped directional plan replaces the Directional Program rows in the open
  # Surveys form (dropped if that form was closed while the file was read).
  def handle_async(:plan_import, result, socket) do
    case socket.assigns.editing do
      "surveys" ->
        {:noreply,
         PlanUpload.apply_result(socket, result, socket.assigns.report.unique_well_id, fn socket,
                                                                                          rows ->
           assign(socket,
             form: as_form(Editing.replace_rows(current_changeset(socket), :surveys, rows))
           )
         end)}

      _ ->
        {:noreply, assign(socket, plan_importing: nil)}
    end
  end

  # The plan fills the tops table's Prognosis column (a wizard-made report's
  # table starts from its typed tops), re-derived as any tops edit is.
  defp save_plan_tops(report, plan_tops) do
    rows =
      case FormationTops.recompute_for_report(report) do
        %{"formations" => rows} -> rows
        nil -> []
      end

    formations = DirectionalPlan.merge_prognosis(rows, plan_tops)
    tops = FormationTops.recompute_for_report(report, formations: formations)
    Reports.update_import_section(report, "tops", tops)
  end

  defp mutate_rows(socket, op, list) do
    changeset = current_changeset(socket)
    list_atom = String.to_existing_atom(list)

    case op do
      :add -> Editing.add_row(changeset, list_atom)
      {:remove, index} -> Editing.remove_row(changeset, list_atom, index)
    end
  end

  # Build on the open form's changeset, not its params: rows added since the
  # last phx-change exist only in the changeset, so rebuilding from params would
  # drop them (two "Add row" clicks in a row left you with one row).
  defp current_changeset(socket) do
    case socket.assigns.form do
      %Phoenix.HTML.Form{source: %Ecto.Changeset{} = changeset} -> changeset
      _ -> edit_changeset(socket.assigns.report)
    end
  end

  defp editable?(%{status: "active"}), do: true
  defp editable?(_), do: false

  defp resolve_tab(socket, tab) do
    valid = valid_tab_ids(socket.assigns[:summary])
    if tab in valid, do: tab, else: "summary"
  end

  defp valid_tab_ids(%{tabs: tabs}) when is_list(tabs), do: Enum.map(tabs, & &1.id)
  defp valid_tab_ids(_), do: ["summary"]

  defp tab_path(report, "summary"), do: "/reports/#{report.id}"
  defp tab_path(report, tab), do: "/reports/#{report.id}?tab=#{tab}"

  defp base_report(report), do: Reports.ensure_report_data(report)

  defp edit_changeset(report, params \\ %{}) do
    Reports.change_report(base_report(report), params)
  end

  defp as_form(changeset), do: Phoenix.Component.to_form(changeset, as: :report)

  defp fetch_report(id) do
    ChinookReports.GenServer.fetch_report(%{"id" => id})
  end
end
