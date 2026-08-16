defmodule ChinookReportsWeb.HomeLive do
  use ChinookReportsWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col gap-4">
      <.heading>
        <:title>Report Dashboard</:title>
        <:subtitle>View and manage extracted well report data from uploaded Excel files.</:subtitle>
      </.heading>

      <div class="border rounded-lg p-4 bg-white shadow">
        <p class="text-gray-700">
          Welcome to the Chinook Reports Dashboard! Use the navigation above to view and manage well reports extracted from Excel files.
        </p>
        <p class="text-gray-700 mt-2">
          You can upload new Excel files to extract data, view existing reports, and see details for each report.
        </p>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(results: [], error: nil, extraction_status: nil, reports: [])}
  end
end
