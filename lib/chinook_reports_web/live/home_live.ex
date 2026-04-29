defmodule ChinookReportsWeb.HomeLive do
  use ChinookReportsWeb, :live_view

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
end
