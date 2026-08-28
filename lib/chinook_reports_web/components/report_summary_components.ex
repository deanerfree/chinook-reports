defmodule ChinookReportsWeb.ReportSummaryComponents do
  @moduledoc """
  The redesigned report page: identity header, tab bar and the Summary tab.

  Layout follows the "Report page redesign" design project — artboard 2a for
  lateral (horizontal / directional) wells and artboard 1b for vertical wells.
  The data-heavy figures are delegated to the `ProfileChart` Svelte component;
  the small static figures (reservoir-quality stack, drilling timeline) are
  server-rendered SVG here.
  """
  use Phoenix.Component
  use Gettext, backend: ChinookReportsWeb.Gettext
  import LiveSvelte

  # ── Identity header ───────────────────────────────────────────────────────

  attr :header, :map, required: true

  def report_header(assigns) do
    ~H"""
    <div class="flex items-start justify-between gap-7 flex-wrap">
      <div class="flex flex-col gap-1.5 min-w-0">
        <div class="flex items-center gap-2">
          <span
            :for={{badge, i} <- Enum.with_index(@header.badges)}
            class={[
              "text-[9px] font-bold uppercase tracking-[0.14em] px-1.5 py-[3px]",
              i == 0 && "text-white bg-primary",
              i != 0 && "text-secondary border border-muted"
            ]}
          >
            {badge}
          </span>
        </div>
        <h1 class="m-0 text-[26px] font-bold tracking-tight leading-tight text-text">
          {@header.well_name}
        </h1>
        <p class="m-0 text-xs text-text-secondary tracking-wide">
          {@header.uwi} &nbsp;·&nbsp; {@header.operator}
          <%= if @header.field not in [nil, ""] do %>
            &nbsp;·&nbsp; {@header.field}
          <% end %>
        </p>
      </div>

      <div class="flex border border-border bg-white shrink-0">
        <div
          :for={
            {label, value} <- [
              {"MD", @header.td.md},
              {"TVD", @header.td.tvd},
              {"Subsea", @header.td.subsea}
            ]
          }
          class="px-4.5 py-2.5 border-l border-border-light first:border-l-0 text-right min-w-24"
        >
          <p class="m-0 mb-0.5 text-[9px] font-bold uppercase tracking-[0.12em] text-muted">
            {label}
          </p>
          <p class="m-0 text-[19px] font-bold text-secondary tabular-nums">
            {value}<span class="text-[10px] font-medium text-muted ml-0.5">m</span>
          </p>
        </div>
      </div>
    </div>
    """
  end

  # ── Tab bar ───────────────────────────────────────────────────────────────

  attr :tabs, :list, required: true
  attr :active, :string, required: true

  def report_tabs(assigns) do
    ~H"""
    <div class="border-b border-border overflow-x-auto">
      <div class="flex gap-0.5 min-w-max">
        <button
          :for={tab <- @tabs}
          type="button"
          phx-click="select_tab"
          phx-value-tab={tab.id}
          class={[
            "px-2.5 py-2.5 text-[10.5px] font-medium uppercase tracking-[0.05em] whitespace-nowrap cursor-pointer -mb-px border-b-2 transition-colors",
            tab.id == @active && "text-text font-bold border-primary",
            tab.id != @active && "text-text-secondary border-transparent hover:text-text"
          ]}
        >
          {tab.label}
          <span :if={tab.count} class="text-[9px] text-muted ml-1 font-medium">{tab.count}</span>
        </button>
      </div>
    </div>
    """
  end

  # ── Summary tab ───────────────────────────────────────────────────────────

  attr :summary, :map, required: true

  def summary_tab(%{summary: %{layout: :vertical}} = assigns) do
    ~H"""
    <div class="grid grid-cols-1 xl:grid-cols-[minmax(0,520px)_1fr] gap-6 items-start pt-6">
      <.blueprint_card>
        <.card_head>Fig. 01&nbsp;&nbsp;Depth column — profile, casing, tops</.card_head>
        <div class="p-2">
          <.svelte name="ProfileChart" props={@summary.chart_props} />
        </div>
      </.blueprint_card>

      <div class="flex flex-col gap-5.5">
        <.key_facts facts={@summary.facts} />
        <.formation_tops_preview summary={@summary} />
        <.synopsis_block synopsis={@summary.synopsis} />
      </div>
    </div>
    """
  end

  def summary_tab(assigns) do
    ~H"""
    <div class="flex flex-col gap-5.5 pt-6">
      <div class="grid grid-cols-1 lg:grid-cols-[1fr_minmax(0,380px)] gap-5.5 items-start">
        <.key_facts facts={@summary.facts} />
        <.reservoir_quality quality={@summary.reservoir_quality} />
      </div>

      <.blueprint_card>
        <.card_head>Fig. 01&nbsp;&nbsp;Wellbore profile &amp; drilling curves</.card_head>
        <div class="p-2">
          <.svelte name="ProfileChart" props={@summary.chart_props} />
        </div>
      </.blueprint_card>

      <.depths_table depths={@summary.depths} />
      <.drilling_timeline rows={@summary.timeline} />
      <.synopsis_block synopsis={@summary.synopsis} wide />
    </div>
    """
  end

  # ── Key facts ─────────────────────────────────────────────────────────────

  attr :facts, :list, required: true

  defp key_facts(assigns) do
    ~H"""
    <.blueprint_card>
      <div class="flex items-baseline justify-between px-4 py-2.5 border-b border-border-light">
        <.card_head bare>Key facts</.card_head>
        <span class="text-[10px] text-muted">Times local to rig</span>
      </div>
      <div class="grid grid-cols-2 sm:grid-cols-3">
        <div
          :for={fact <- @facts}
          class="px-4 py-2.5 border-t border-r border-border-light"
        >
          <p class="m-0 mb-0.5 text-[9px] font-bold uppercase tracking-[0.11em] text-muted">
            {fact.label}
          </p>
          <p class="m-0 text-[13px] font-medium tabular-nums text-text">{fact.value}</p>
        </div>
      </div>
    </.blueprint_card>
    """
  end

  # ── Reservoir quality ─────────────────────────────────────────────────────

  attr :quality, :map, default: nil

  defp reservoir_quality(assigns) do
    ~H"""
    <.blueprint_card :if={@quality}>
      <div class="flex items-baseline justify-between px-4 py-2.5 border-b border-border-light">
        <.card_head bare>Reservoir quality</.card_head>
        <span class="text-[10px] text-muted">{@quality.total_m} m of reservoir</span>
      </div>
      <div class="px-4 py-3.5">
        <svg viewBox="0 0 100 6" preserveAspectRatio="none" class="w-full h-6 block">
          <% offsets = quality_offsets(@quality.rows) %>
          <rect
            :for={{row, x} <- offsets}
            x={x}
            y="0"
            width={row.pct}
            height="6"
            fill={row.colour}
          />
          <rect
            x="0"
            y="0"
            width="100"
            height="6"
            fill="none"
            stroke="rgba(0,0,0,.15)"
            stroke-width="0.5"
          />
        </svg>

        <div class="mt-3.5 flex flex-col">
          <div
            :for={row <- @quality.rows}
            class="flex items-center gap-2.5 py-1.5 border-t border-border-light first:border-t-0"
          >
            <span class="w-2.5 h-2.5 shrink-0" style={"background:#{row.colour}"} />
            <span class="flex-1 text-xs font-medium text-text">{row.quality}</span>
            <span class="text-xs text-text-secondary tabular-nums">{row.metres} m</span>
            <span class="w-12 text-right text-xs font-bold text-secondary tabular-nums">
              {row.pct}%
            </span>
          </div>
        </div>
      </div>
    </.blueprint_card>
    """
  end

  # ── Final depths vs plan ──────────────────────────────────────────────────

  attr :depths, :map, default: nil

  defp depths_table(assigns) do
    ~H"""
    <.blueprint_card :if={@depths}>
      <.card_head>Final depths&nbsp;&nbsp;·&nbsp;&nbsp;against original drill plan</.card_head>
      <div class="grid grid-cols-[110px_repeat(4,1fr)]">
        <div class="px-4 py-2 border-b border-border-light" />
        <div
          :for={h <- ~w(MD TVD Vert.section Subsea)}
          class="px-4 py-2 border-b border-l border-border-light text-right text-[9px] font-bold uppercase tracking-[0.11em] text-muted"
        >
          {h}
        </div>

        <.depths_row label="Actual" row={@depths.actual} />
        <.depths_row label="Planned" row={@depths.planned} />

        <div class="px-4 py-2.5 bg-accent-subtle/40 text-[10px] font-bold uppercase tracking-[0.09em] text-secondary">
          Δ to plan
        </div>
        <div
          class="px-4 py-2.5 border-l border-border-light bg-accent-subtle/40 text-right text-[15px] font-bold tabular-nums"
          style={"color:#{@depths.diff_colour}"}
        >
          {@depths.diff.md}
        </div>
        <div
          class="px-4 py-2.5 border-l border-border-light bg-accent-subtle/40 text-right text-[15px] font-bold tabular-nums"
          style={"color:#{@depths.diff_colour}"}
        >
          {@depths.diff.tvd}
        </div>
        <div
          class="px-4 py-2.5 border-l border-border-light bg-accent-subtle/40 text-right text-[15px] font-bold tabular-nums"
          style={"color:#{@depths.diff_colour}"}
        >
          {@depths.diff.vs}
        </div>
        <div class="px-4 py-2.5 border-l border-border-light bg-accent-subtle/40 text-right text-[13px] text-muted">
          —
        </div>
      </div>
      <p class="m-0 px-4 py-2.5 border-t border-border-light text-xs text-text-secondary">
        {@depths.note}
      </p>
    </.blueprint_card>
    """
  end

  attr :label, :string, required: true
  attr :row, :map, required: true

  defp depths_row(assigns) do
    ~H"""
    <div class="px-4 py-2.5 border-b border-border-light text-[10px] font-bold uppercase tracking-[0.09em] text-text-secondary">
      {@label}
    </div>
    <div
      :for={v <- [@row.md, @row.tvd, @row.vs, @row.subsea]}
      class="px-4 py-2.5 border-b border-l border-border-light text-right text-[15px] font-bold text-text tabular-nums"
    >
      {v}
    </div>
    """
  end

  # ── Drilling timeline (Fig 03) ────────────────────────────────────────────

  attr :rows, :list, required: true

  defp drilling_timeline(assigns) do
    ~H"""
    <.blueprint_card :if={@rows != []}>
      <.card_head>Fig. 03&nbsp;&nbsp;Drilling timeline</.card_head>
      <div class="px-4 py-3.5">
        <% max_d = @rows |> Enum.map(& &1.depth) |> Enum.max() %>
        <svg viewBox="0 0 1000 92" class="w-full h-auto block" font-family="Roboto, sans-serif">
          <line x1="8" x2="992" y1="60" y2="60" stroke="#dcdcdc" />
          <rect
            x="8"
            y="55"
            width={timeline_x(max_d, max_d) - 8}
            height="10"
            fill="rgba(23,105,53,.10)"
          />
          <g :for={{row, i} <- Enum.with_index(@rows)}>
            <% x = timeline_x(row.depth, max_d) %>
            <% up = rem(i, 2) == 0 %>
            <line
              x1={x}
              x2={x}
              y1={if up, do: 34, else: 60}
              y2={if up, do: 60, else: 72}
              stroke="#b9c4bc"
            />
            <circle cx={x} cy="60" r="3" fill="#114a26" />
            <text
              x={x}
              y={if up, do: 26, else: 84}
              font-size="11"
              font-weight="700"
              fill="#1b1b1b"
              text-anchor={timeline_anchor(i, length(@rows))}
            >
              {row.label}
            </text>
            <text
              x={x}
              y={if up, do: 38, else: 96}
              font-size="10"
              fill="#8d998f"
              text-anchor={timeline_anchor(i, length(@rows))}
            >
              {round(row.depth)} m
            </text>
          </g>
        </svg>
      </div>
    </.blueprint_card>
    """
  end

  # ── Formation tops preview (vertical layout) ──────────────────────────────

  attr :summary, :map, required: true

  defp formation_tops_preview(assigns) do
    assigns = assign(assigns, :tops, formation_tops_rows(assigns.summary))

    ~H"""
    <.blueprint_card :if={@tops != []}>
      <div class="flex items-baseline justify-between px-4 py-2.5 border-b border-border-light">
        <.card_head bare>Formation tops</.card_head>
        <span class="text-[10px] text-muted">prognosis vs actual</span>
      </div>
      <div>
        <div
          :for={t <- @tops}
          class="flex items-center gap-3 px-4 py-1.5 border-t border-border-light first:border-t-0"
        >
          <span class="flex-1 text-xs font-medium truncate text-text">{t.formation}</span>
          <span class="text-xs text-text-secondary tabular-nums w-16 text-right">{t.md}</span>
          <span class="text-xs text-muted tabular-nums w-16 text-right">{t.subsea}</span>
          <span
            class="text-[11px] font-bold tabular-nums w-13 text-right"
            style={"color:#{t.diff_colour}"}
          >
            {t.diff}
          </span>
        </div>
      </div>
    </.blueprint_card>
    """
  end

  # ── Synopsis ──────────────────────────────────────────────────────────────

  attr :synopsis, :map, required: true
  attr :wide, :boolean, default: false

  defp synopsis_block(assigns) do
    ~H"""
    <div class={[@wide && "grid grid-cols-1 lg:grid-cols-[1fr_minmax(0,300px)] gap-5.5 items-start"]}>
      <div>
        <.card_head bare>Synopsis</.card_head>
        <div class="mt-2.5 flex flex-col gap-2.5 border-l-2 border-accent pl-3.5">
          <p
            :for={para <- @synopsis.short}
            class="m-0 text-[13px] leading-relaxed text-text text-pretty"
          >
            {para}
          </p>
          <p :if={@synopsis.short == []} class="m-0 text-[13px] text-muted">
            No synopsis on file.
          </p>
        </div>
        <p
          :if={@synopsis.full_count > 2}
          class="m-0 mt-2.5 pl-4 text-[11px] font-bold uppercase tracking-[0.08em] text-primary"
        >
          Read full synopsis →
        </p>
      </div>

      <div :if={@synopsis.final_status} class="bg-accent border border-muted px-4 py-3.5">
        <p class="m-0 mb-1.5 text-[9px] font-bold uppercase tracking-[0.12em] text-secondary">
          Final well status
        </p>
        <p class="m-0 text-[12.5px] leading-relaxed text-secondary">{@synopsis.final_status}</p>
      </div>
    </div>
    """
  end

  # ── Shared chrome ─────────────────────────────────────────────────────────

  slot :inner_block, required: true

  defp blueprint_card(assigns) do
    ~H"""
    <div class="relative border border-border bg-white">
      <span class="absolute -top-1.5 -left-1 text-[11px] leading-none text-primary">+</span>
      <span class="absolute -top-1.5 -right-1 text-[11px] leading-none text-primary">+</span>
      <span class="absolute -bottom-1.5 -left-1 text-[11px] leading-none text-primary">+</span>
      <span class="absolute -bottom-1.5 -right-1 text-[11px] leading-none text-primary">+</span>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :bare, :boolean, default: false
  slot :inner_block, required: true

  defp card_head(assigns) do
    ~H"""
    <h2 class={[
      "m-0 text-[11px] font-bold uppercase tracking-[0.13em] text-text",
      not @bare && "px-4 py-2.5 border-b border-border-light"
    ]}>
      {render_slot(@inner_block)}
    </h2>
    """
  end

  # ── Data helpers ──────────────────────────────────────────────────────────

  defp quality_offsets(rows) do
    {acc, _} =
      Enum.reduce(rows, {[], 0.0}, fn row, {acc, x} ->
        width =
          case Float.parse(to_string(row.pct)) do
            {f, _} -> f
            :error -> 0.0
          end

        {[{row, x} | acc], x + width}
      end)

    Enum.reverse(acc)
  end

  defp timeline_x(v, max_d) when is_number(v) and is_number(max_d) and max_d > 0 do
    8 + v / max_d * (1000 - 16)
  end

  defp timeline_x(_, _), do: 8

  defp timeline_anchor(0, _), do: "start"
  defp timeline_anchor(i, n) when i == n - 1, do: "end"
  defp timeline_anchor(_, _), do: "middle"

  defp formation_tops_rows(%{chart_props: %{tops: tops}}) when is_list(tops) do
    tops
    |> Enum.take(9)
    |> Enum.map(fn t ->
      samples = t["samples"] || %{}
      diff = t["difference_m"]

      %{
        formation: t["formation"],
        md: fmt_top(samples["md"]),
        subsea: fmt_top(samples["subsea"]),
        diff:
          if(is_number(diff),
            do: "#{if(diff > 0, do: "+")}#{:erlang.float_to_binary(diff / 1, decimals: 1)}",
            else: "—"
          ),
        diff_colour: if(is_number(diff) and diff > 0, do: "#e67e22", else: "#176935")
      }
    end)
  end

  defp formation_tops_rows(_), do: []

  defp fmt_top(v) when is_number(v), do: :erlang.float_to_binary(v / 1, decimals: 1)
  defp fmt_top(_), do: "—"
end
