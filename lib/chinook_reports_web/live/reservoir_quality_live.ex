defmodule ChinookReportsWeb.ReservoirQualityLive do
  @moduledoc """
  The Reservoir Quality picker (`import_data["reservoir_data"]`'s leg
  `log_data.intervals`), shown under the Reservoir tab beneath the wellpath /
  quality charts.

  Sections are authored by dragging on the well-log chart (the
  `ReservoirQualityPicker` Svelte component) rather than typed into a grid:
  drag across an unclassified span to mark a section, pick its reservoir
  quality, drag a band's edges to resize it. Each change persists immediately —
  there is no Edit toggle. The component only renders; it pushes a
  `"commit_intervals"` event that `ReportPageLive` applies via
  `ChinookReports.ReservoirQuality.commit_intervals/2`, which also recomputes
  the leg's `quality_summary` so the Summary tab's quality chart stays in step.

  `From`, `To`, `Quality` and `Lithology` are editable here; `Interval` is
  derived (`To - From`). `Porosity`, `Remarks` and the operator-entered `Gas`
  reading are preserved on the stored rows but are not surfaced in the picker.
  """
  use ChinookReportsWeb, :live_component

  alias ChinookReports.ReservoirQuality

  @quality_options ["Very Good", "Good", "Fair", "Poor", "Nil"]

  @impl true
  def update(%{report: report} = assigns, socket) do
    curves = ReservoirQuality.curve_data_for_report(report)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:quality_options, @quality_options)
     |> assign(:rows, ReservoirQuality.interval_rows_for_report(report))
     |> assign(:curves, curves.points)
     |> assign(:curve_metadata, Map.put(curves.metadata, "rop_max", curves.rop_max))
     |> assign(:md_min, curves.md_min)
     |> assign(:md_max, curves.md_max)
     |> assign(:well_type, to_string(ReservoirQuality.well_type_for_report(report)))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"reservoir-quality-card-#{@id}"} class="flex flex-col rounded-xl card-shadow">
      <div class="relative flex flex-col overflow-hidden rounded-xl">
        <div class="absolute left-0 top-0 h-full w-1 bg-primary"></div>

        <div class="flex flex-wrap items-center justify-between gap-x-3 gap-y-2 rounded-t-xl bg-linear-to-r from-primary to-secondary px-5 py-3">
          <h3 class="m-0 text-lg font-semibold text-on-primary">Reservoir Quality</h3>
          <button
            type="button"
            phx-click={JS.toggle(to: "#reservoir-quality-info-#{@id}")}
            class="inline-flex items-center gap-1 rounded-md px-2 py-1 text-[11px] font-medium text-on-primary/90 cursor-pointer transition-opacity hover:opacity-100"
          >
            <.icon name="hero-information-circle" class="h-4 w-4" /> How this works
          </button>
        </div>

        <div
          id={"reservoir-quality-info-#{@id}"}
          class="hidden border-b border-border-light bg-bg px-5 py-3.5 text-[12px] leading-relaxed text-text-secondary"
          phx-click-away={JS.hide()}
        >
          <p class="m-0 mb-1.5">
            Drag across an <span class="font-semibold text-text">unclassified</span>
            span of the log to mark a reservoir section, then pick its
            <span class="font-semibold text-text">Quality</span>
            (Very Good, Good, Fair, Poor or Nil). Drag a band's edges to resize it;
            click a band or a table row to re-classify or delete it.
          </p>
          <p :if={@editable} class="m-0 mb-1.5">
            The <span class="font-semibold text-text">Horizontal / Vertical</span>
            switch changes the layout;
            <span class="font-semibold text-text">Combined / Separate</span>
            switches the GR / ROP / Gas curves between one normalised track and three.
          </p>
          <p class="m-0">
            <span class="font-semibold text-text">Interval</span>
            = To − From. Every change saves straight away and recomputes the
            reservoir-quality distribution on the Summary tab.
          </p>
        </div>

        <div :if={@rows == [] and @curves == []} class="px-5 py-6">
          <p class="m-0 text-sm text-muted">
            No reservoir log data on this report — nothing to pick against yet.
          </p>
        </div>

        <div :if={@rows != [] or @curves != []} class="px-5 py-4">
          <.svelte
            name="ReservoirQualityPicker"
            ssr={false}
            diff={false}
            socket={@socket}
            props={
              %{
                intervals: @rows,
                curves: @curves,
                curve_metadata: @curve_metadata,
                md_min: @md_min,
                md_max: @md_max,
                quality_options: @quality_options,
                well_type: @well_type,
                editable: @editable
              }
            }
          />
        </div>
      </div>
    </div>
    """
  end
end
