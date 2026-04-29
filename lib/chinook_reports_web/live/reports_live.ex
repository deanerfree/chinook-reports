defmodule ChinookReportsWeb.ReportsLive do
  use ChinookReportsWeb, :live_view

  alias ChinookReports.GenServer

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case GenServer.fetch_report_data(params) do
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
  def render(assigns) do
    ~H"""
    <div class="flex flex-col gap-4">
      <.heading>
        <:title>Reports</:title>
        <:subtitle>View and manage well reports</:subtitle>
      </.heading>

      <div>
        <.my_table id="reports" items={@reports} meta={@meta} path={~p"/reports"}>
          <:col :let={report} label="Well Name" field={:well_name}>{report.well_name}</:col>
          <:col :let={report} label="Unique Well ID">{report.unique_well_id}</:col>
          <:col :let={report} label="Operator" field={:operator}>{report.operator}</:col>
          <:col :let={report} label="Spud Date" field={:spud_date}>{report.spud_date}</:col>
          <:col :let={report} label="Final TD Date" field={:final_td_date}>{report.final_td_date}</:col>
          <:col :let={report} label="Target Formation">{report.target_formation}</:col>
          <:col :let={report} label="Country">{report.country}</:col>
        </.my_table>

        <Flop.Phoenix.pagination meta={@meta} path={~p"/reports"} />
      </div>
    </div>
    """
  end
end
