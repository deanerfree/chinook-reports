defmodule ChinookReportsWeb.HomeLive do
  use ChinookReportsWeb, :live_view

  alias ChinookReports.GenServer

  @impl true
  def render(assigns) do
    ~H"""
    <.heading>
      <:title>Report Dashboard</:title>
      <:subtitle>View and manage extracted well report data from uploaded Excel files.</:subtitle>
    </.heading>

    <.svelte name="HomePage" props={%{results: @results, error: @error}} />
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(results: [], error: nil, extraction_status: nil, reports: [])}
  end

  @impl true
  @spec handle_event(<<_::80>>, any(), any()) :: {:noreply, any()}
  def handle_event("fetch_data", _params, socket) do
    case GenServer.fetch_report_data() do
      {:ok, data} ->
        IO.inspect(data, label: "Fetched Report Data")
        {:noreply, assign(socket, results: data, error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, results: [], error: reason)}
    end
  end
end
