defmodule ChinookReportsWeb.ReportsLive do
  use ChinookReportsWeb, :live_view

  alias ChinookReports.GenServer
  alias ChinookReports.Reports

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case GenServer.fetch_reports_list(params) do
      {:ok, {reports, meta}} ->
        {:noreply, assign(socket, reports: reports, meta: meta)}

      {:error, reason} ->
        reports = []
        meta = %{}
        IO.inspect("Error fetching reports: #{inspect(reason)}")
        {:noreply, assign(socket, reports: reports, meta: meta, error: reason)}
    end
  end

  @impl true
  def handle_event("delete_draft", %{"id" => id}, socket) do
    report = Reports.get_report!(id)

    if report.status == "draft" do
      {:ok, _} = Reports.delete_draft(report)
    end

    {:noreply, push_patch(socket, to: ~p"/reports")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col gap-4">
      <.heading>
        <:title>Reports</:title>
        <:subtitle>View and manage well reports</:subtitle>
      </.heading>
      {render_table(assigns)}
    </div>
    """
  end

  defp render_table(assigns) do
    case assigns.reports do
      [] ->
        ~H"""
        <div class="p-4 bg-yellow-100 text-yellow-800 rounded border border-text-yellow-800 flex flex-col gap-4">
          <div class="flex flex-col items-center gap-2">
            <p class="font-semibold">No reports found</p>
            <p class="text-sm">You can create a new report by clicking the "New Report" button.</p>
          </div>
          <div class="flex justify-center">
            <button type="button" class="btn-primary" phx-click={show_modal("new-report-modal")}>
              Draft New Report
            </button>
          </div>
        </div>
        """

      _ ->
        ~H"""
        <div>
          <.my_table id="reports" items={@reports} meta={@meta} path={~p"/reports"}>
            <:col :let={report} label="Well Name" field={:well_name}>{report.well_name}</:col>
            <:col :let={report} label="Unique Well ID">{report.unique_well_id}</:col>
            <:col :let={report} label="Operator" field={:operator}>{report.operator}</:col>
            <:col :let={report} label="Spud Date" field={:spud_date}>{report.spud_date}</:col>
            <:col :let={report} label="Final TD Date" field={:final_td_date}>
              {report.final_td_date}
            </:col>
            <:col :let={report} label="Target Formation">{report.target_formation}</:col>
            <:col :let={report} label="Country">{report.country}</:col>
            <:col :let={report} label="Status">
              <span class={[
                "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium",
                report.status == "complete" && "bg-green-100 text-green-800",
                report.status == "active" && "bg-blue-100 text-blue-800",
                report.status == "draft" && "bg-gray-100 text-gray-700"
              ]}>
                {String.capitalize(report.status || "draft")}
              </span>
            </:col>
            <:col :let={report} label="Action">
              <%= case report.status do %>
                <% status when status in ["complete", "active"] -> %>
                  <a href={~p"/reports/#{report.id}"} title="View report">
                    <.eye_icon class="w-5 h-5 text-blue-500 hover:text-gray-700" />
                  </a>
                <% "draft" -> %>
                  <div class="flex items-center gap-2">
                    <a href={~p"/reports/#{report.id}/edit"} title="Edit report">
                      <.pencil_square_icon class="w-5 h-5 text-blue-500 hover:text-blue-700" />
                    </a>
                    <button
                      phx-click="delete_draft"
                      phx-value-id={report.id}
                      data-confirm="Delete this draft? This cannot be undone."
                      title="Delete draft"
                    >
                      <.trash_icon class="w-5 h-5 text-red-400 hover:text-red-600" />
                    </button>
                  </div>
                <% _ -> %>
              <% end %>
            </:col>
          </.my_table>

          <Flop.Phoenix.pagination meta={@meta} path={~p"/reports"} />
        </div>
        """
    end
  end
end
