defmodule ChinookReportsWeb.ReportPageLive do
  use ChinookReportsWeb, :live_view

  alias ChinookReports.ReportSummary
  import ChinookReportsWeb.ReportSummaryComponents

  def mount(%{"id" => id}, _session, socket) do
    case fetch_report(id) do
      {:ok, report} ->
        {:ok,
         assign(socket,
           report: report,
           error: nil,
           active_tab: "summary",
           summary: ReportSummary.build(report)
         )}

      {:error, :not_found} ->
        {:ok,
         assign(socket,
           report: nil,
           summary: nil,
           active_tab: "summary",
           error: "Report not found"
         )}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="w-full max-w-[1200px] mx-auto pb-16">
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
              <.tab_content tab={@active_tab} report={@report} />
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

  def handle_event("select_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: tab)}
  end

  def handle_event("back", _value, socket) do
    {:noreply, push_navigate(socket, to: "/reports")}
  end

  defp fetch_report(id) do
    ChinookReports.GenServer.fetch_report(%{"id" => id})
  end
end
