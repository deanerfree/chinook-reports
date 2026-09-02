defmodule ChinookReportsWeb.ReportPageLive do
  use ChinookReportsWeb, :live_view

  alias ChinookReports.ReportSummary
  alias ChinookReports.Reports
  alias ChinookReports.Reports.Editing
  alias ChinookReports.Reports.Report
  import ChinookReportsWeb.ReportSummaryComponents

  def mount(%{"id" => id}, _session, socket) do
    case fetch_report(id) do
      {:ok, report} ->
        {:ok,
         assign(socket,
           report: report,
           error: nil,
           active_tab: "summary",
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
                report={@report}
                editable={editable?(@report)}
                editing={@editing}
                form={@form}
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

  # Keep the active tab in the URL so a refresh / LiveView remount lands back on
  # the same tab instead of snapping to "summary".
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, active_tab: resolve_tab(socket, params["tab"]))}
  end

  def handle_event("select_tab", %{"tab" => tab}, socket) do
    {:noreply,
     socket
     |> assign(editing: nil, form: nil)
     |> push_patch(to: tab_path(socket.assigns.report, tab))}
  end

  def handle_event("back", _value, socket) do
    {:noreply, push_navigate(socket, to: "/reports")}
  end

  def handle_event("edit_section", %{"section" => section}, socket) do
    {:noreply,
     assign(socket, editing: section, form: as_form(edit_changeset(socket.assigns.report)))}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing: nil, form: nil)}
  end

  def handle_event("validate", %{"report" => params}, socket) do
    changeset =
      socket.assigns.report
      |> edit_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: as_form(changeset))}
  end

  def handle_event("save_section", %{"report" => params}, socket) do
    editing = socket.assigns.editing

    case Reports.update_report(base_report(socket.assigns.report), params) do
      {:ok, report} ->
        # A KB change in the Elevations section ripples into every Subsea in the
        # Formation Tops table, so re-derive those and persist alongside.
        report = if editing == "elevations", do: recompute_tops(report), else: report

        {:noreply,
         socket
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

  def handle_event("add_row", %{"list" => list}, socket) do
    {:noreply, assign(socket, form: as_form(mutate_rows(socket, :add, list)))}
  end

  def handle_event("remove_row", %{"list" => list, "index" => index}, socket) do
    {:noreply,
     assign(socket, form: as_form(mutate_rows(socket, {:remove, String.to_integer(index)}, list)))}
  end

  # The Formation Tops editor (a LiveComponent) persists on its own and tells us
  # to refresh the report + summary it derives.
  def handle_info({:tops_updated, report}, socket) do
    {:noreply,
     socket
     |> assign(report: report, summary: ReportSummary.build(report))
     |> put_flash(:info, "Formation Tops saved.")}
  end

  defp mutate_rows(socket, op, list) do
    changeset = edit_changeset(socket.assigns.report, current_params(socket))
    list_atom = String.to_existing_atom(list)

    case op do
      :add -> Editing.add_row(changeset, list_atom)
      {:remove, index} -> Editing.remove_row(changeset, list_atom, index)
    end
  end

  defp current_params(socket) do
    case socket.assigns.form do
      %Phoenix.HTML.Form{params: params} when is_map(params) -> params
      _ -> %{}
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

  # Re-derive import_data["tops"] from the report's survey + KB and persist it.
  # No-op when the report carries no tops.
  defp recompute_tops(report) do
    case ChinookReports.FormationTops.recompute_for_report(report) do
      nil ->
        report

      tops ->
        case Reports.update_import_section(report, "tops", tops) do
          {:ok, updated} -> updated
          {:error, _} -> report
        end
    end
  end

  # Reports created through the wizard always carry a `report_data` embed; guard
  # against a legacy row where the JSONB column is null so the nested form and
  # its changeset still have something to bind to.
  defp base_report(report),
    do: %{report | report_data: report.report_data || %Report.ReportData{}}

  defp edit_changeset(report, params \\ %{}) do
    Reports.change_report(base_report(report), params)
  end

  defp as_form(changeset), do: Phoenix.Component.to_form(changeset, as: :report)

  defp fetch_report(id) do
    ChinookReports.GenServer.fetch_report(%{"id" => id})
  end
end
