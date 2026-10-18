defmodule ChinookReportsWeb.HomeLive do
  @moduledoc """
  The Home dashboard: what needs attention now. Wells currently drilling (with
  a digest of where each hole is), drafts still to finish and recently
  completed reports. The full, sortable list lives on `/reports`; every count
  here links into it pre-filtered.
  """
  use ChinookReportsWeb, :live_view

  alias ChinookReports.ReportSummary
  alias ChinookReports.Reports

  @impl true
  def mount(_params, _session, socket) do
    %{counts: counts, active: active, drafts: drafts, complete: complete} = Reports.dashboard()

    {:ok,
     assign(socket,
       page_title: "Dashboard",
       counts: counts,
       drilling: Enum.map(active, &ReportSummary.glance/1),
       drafts: drafts,
       complete: complete
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col gap-6 max-w-300">
      <div class="flex flex-col items-start justify-between gap-4 flex-wrap">
        <.heading>
          <:title>Dashboard</:title>
          <:subtitle>Wells drilling now, drafts to finish and recent final reports.</:subtitle>
        </.heading>
        <div class="flex gap-2">
          <a href={~p"/upload"} class="btn-secondary">Upload workbook</a>
          <button type="button" class="btn-primary" phx-click={show_modal("new-report-modal")}>
            + New Report
          </button>
        </div>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <.count_tile label="Drilling now" status="active" count={@counts["active"]} />
        <.count_tile label="Drafts" status="draft" count={@counts["draft"]} />
        <.count_tile label="Complete" status="complete" count={@counts["complete"]} />
      </div>

      <section class="flex flex-col gap-3">
        <h2 class="m-0 text-xs font-bold uppercase tracking-[0.12em] text-text">Drilling now</h2>
        <div :if={@drilling != []} class="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <.well_card :for={well <- @drilling} well={well} />
        </div>
        <p :if={@drilling == []} class="card m-0 px-5 py-4 text-sm text-text-secondary">
          No wells are drilling. Finish a draft below, or upload a workbook to start one.
        </p>
      </section>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 items-start">
        <.report_list
          title="Drafts to finish"
          reports={@drafts}
          empty="No drafts in progress."
          action="Continue"
          href={&~p"/reports/#{&1.id}/draft"}
          status="draft"
          total={@counts["draft"]}
        />
        <.report_list
          title="Recently completed"
          reports={@complete}
          empty="No completed reports yet."
          action="View"
          href={&~p"/reports/#{&1.id}"}
          status="complete"
          total={@counts["complete"]}
        />
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :status, :string, required: true
  attr :count, :integer, required: true

  defp count_tile(assigns) do
    ~H"""
    <a
      href={status_path(@status)}
      class="card px-5 py-4 no-underline hover:border-primary transition-colors"
    >
      <p class="m-0 text-[10px] font-bold uppercase tracking-[0.12em] text-muted">{@label}</p>
      <p class="m-0 mt-1 text-3xl font-bold tabular-nums text-text">{@count}</p>
    </a>
    """
  end

  attr :well, :map, required: true

  defp well_card(assigns) do
    ~H"""
    <a
      href={~p"/reports/#{@well.id}"}
      class="card flex flex-col no-underline hover:border-primary transition-colors"
    >
      <div class="px-5 pt-4 pb-3 flex items-start justify-between gap-3">
        <div class="min-w-0">
          <p class="m-0 text-[15px] font-bold text-text truncate">{@well.well_name}</p>
          <p class="m-0 mt-0.5 text-xs text-text-secondary truncate">
            {@well.uwi}<span :if={@well.operator}> · {@well.operator}</span>
          </p>
        </div>
        <span
          :if={@well.geometry != ""}
          class="shrink-0 text-[9px] font-bold uppercase tracking-[0.14em] px-1.5 py-0.75 text-secondary border border-muted"
        >
          {@well.geometry}
        </span>
      </div>

      <div class="grid grid-cols-2 sm:grid-cols-4 border-t border-border-light">
        <.glance_cell label="Depth" value={depth_value(@well.depth)} />
        <.glance_cell label="Last formation" value={formation_value(@well.last_formation)} />
        <.glance_cell
          label="On well"
          value={@well.days_on_well && "#{@well.days_on_well} d"}
          note={
            cond do
              @well.td_date -> "TD #{@well.td_date}"
              @well.spud -> "spud #{@well.spud}"
              true -> nil
            end
          }
        />
        <.glance_cell label="Off plan" value={@well.off_plan} />
      </div>
    </a>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, default: nil
  attr :note, :string, default: nil

  defp glance_cell(assigns) do
    ~H"""
    <div class="px-5 py-2.5 border-r border-border-light last:border-r-0 min-w-0">
      <p class="m-0 text-[9px] font-bold uppercase tracking-[0.11em] text-muted">{@label}</p>
      <p class="m-0 text-[13px] font-medium tabular-nums text-text truncate">{@value || "—"}</p>
      <p :if={@note} class="m-0 text-[10px] text-muted tabular-nums">{@note}</p>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :reports, :list, required: true
  attr :empty, :string, required: true
  attr :action, :string, required: true
  attr :href, :any, required: true
  attr :status, :string, required: true
  attr :total, :integer, required: true

  defp report_list(assigns) do
    ~H"""
    <section class="card overflow-hidden">
      <div class="px-5 py-3 flex items-baseline justify-between border-b border-border-light">
        <h2 class="m-0 text-xs font-bold uppercase tracking-[0.12em] text-text">{@title}</h2>
        <a
          :if={@total > length(@reports)}
          href={status_path(@status)}
          class="text-xs font-medium text-primary"
        >
          All {@total} →
        </a>
      </div>
      <ul class="list-none m-0 p-0">
        <li
          :for={report <- @reports}
          class="px-5 py-2.5 flex items-center gap-3 border-t border-border-light first:border-t-0"
        >
          <div class="flex-1 min-w-0">
            <p class="m-0 text-sm font-medium text-text truncate">{report.well_name}</p>
            <p class="m-0 text-xs text-text-secondary truncate">
              {report.unique_well_id} · updated {Calendar.strftime(report.updated_at, "%Y-%m-%d")}
            </p>
          </div>
          <a href={@href.(report)} class="shrink-0 text-xs font-bold text-primary">{@action} →</a>
        </li>
      </ul>
      <p :if={@reports == []} class="m-0 px-5 py-4 text-sm text-text-secondary">{@empty}</p>
    </section>
    """
  end

  defp status_path(status),
    do: ~p"/reports?#{%{"filters" => %{"0" => %{"field" => "status", "value" => status}}}}"

  defp depth_value("—"), do: nil
  defp depth_value(md), do: "#{md} m MD"

  defp formation_value(nil), do: nil

  defp formation_value(%{formation: name, call: call}) when call in [:high, :low],
    do: "#{name} (#{call})"

  defp formation_value(%{formation: name}), do: name
end
