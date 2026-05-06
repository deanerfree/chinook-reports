defmodule ChinookReportsWeb.ReportPageLive do
  use ChinookReportsWeb, :live_view

  def mount(%{"id" => id}, _session, socket) do
    case fetch_report(id) do
      {:ok, report} ->
        {:ok, assign(socket, report: report)}

      {:error, :not_found} ->
        report = nil

        {:ok, assign(socket, report: report, error: "Report not found")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="w-full p-6 overflow-y-auto">
      <%= cond do %>
        <% @report -> %>
          <div class="space-y-4">
            <.heading>
              <:title>Report</:title>
              <:subtitle>{@report.well_name}</:subtitle>
            </.heading>
            <.report_details report={@report} />
          </div>
        <% @report == nil -> %>
          <p>Report not found.</p>
          <p if={@error} class="text-red-500">{@error}</p>
      <% end %>

      <button class="cursor-pointer" phx-click="back">&#8592; Back to Reports</button>
    </div>
    <script>
    </script>
    """
  end

  def handle_event("back", _value, socket) do
    {:noreply, push_navigate(socket, to: "/reports")}
  end

  defp fetch_report(id) do
    ChinookReports.GenServer.fetch_report(%{"id" => id})
  end
end
