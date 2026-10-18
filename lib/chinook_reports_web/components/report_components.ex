defmodule ChinookReportsWeb.ReportComponents do
  use Phoenix.Component
  use Gettext, backend: ChinookReportsWeb.Gettext
  import ChinookReportsWeb.CoreComponents
  import ChinookReportsWeb.ReportFormComponents
  import LiveSvelte

  alias ChinookReportsWeb.NumberFormat

  attr :report, :map, required: true

  def report_details(assigns) do
    ~H"""
    <div class="flex flex-col gap-8">
      <.well_summary_section report={@report} />

      <%= if data = @report.report_data do %>
        <.elevations_location_section report={@report} data={data} />
        <.configuration_section data={data} />
        <.profile_section rows={data.profile_sections} />
        <.formation_tops_section rows={data.formation_tops} />
        <.surveys_section rows={data.surveys} kb={ChinookReports.FormationTops.kb_elevation(@report)} />
      <% end %>

      <%= if @report.import_data not in [nil, %{}] do %>
        <.import_sections import={@report.import_data} />
      <% end %>
    </div>
    """
  end

  # ── Tab dispatch (redesigned report page) ───────────────────────────────

  @doc """
  Renders the body of one non-Summary tab on the redesigned report page,
  reusing the existing section components. The Summary tab is handled by
  `ChinookReportsWeb.ReportSummaryComponents`.
  """
  attr :tab, :string, required: true
  attr :report, :map, required: true
  attr :editable, :boolean, default: false
  attr :editing, :string, default: nil
  attr :form, :any, default: nil

  attr :survey_view, :string,
    default: nil,
    doc: ~s(Surveys tab: "actual" or "planned"; `nil` picks actual when there is one)

  attr :plan_upload, :any,
    default: nil,
    doc: "the `:plan` UploadConfig, for the Directional Program"

  attr :plan_importing, :string, default: nil
  attr :plan_tops, :list, default: nil, doc: "a read plan's formation tops awaiting import"

  def tab_content(assigns) do
    assigns =
      assign(assigns,
        data: assigns.report.report_data,
        import: assigns.report.import_data || %{}
      )

    ~H"""
    <div class="flex flex-col gap-8 pt-6">
      <%= case @tab do %>
        <% "well_data" -> %>
          <.live_component
            :for={card <- ChinookReportsWeb.WellDataCardLive.cards()}
            module={ChinookReportsWeb.WellDataCardLive}
            id={"well-data-#{card}"}
            card={card}
            report={@report}
            editable={@editable}
          />
          <.live_component
            module={ChinookReportsWeb.ImportTableLive}
            id="welldata-well_profile"
            section="well_profile"
            report={@report}
            editable={@editable}
          />
        <% "formation_tops" -> %>
          <%!-- Every report gets the full tops table; one set up in the wizard
               starts it from its typed tops (FormationTops.recompute_for_report/2). --%>
          <.live_component
            module={ChinookReportsWeb.FormationTopsLive}
            id="formation-tops"
            report={@report}
            editable={@editable}
          />
        <% "reservoir" -> %>
          <%= if reservoir = @import["reservoir_data"] do %>
            <.reservoir_section reservoir={reservoir} />
            <.live_component
              module={ChinookReportsWeb.ReservoirQualityLive}
              id="reservoir-quality"
              report={@report}
              editable={@editable}
            />
            <.live_component
              :if={ChinookReports.ReservoirQuality.leg_index(@report)}
              module={ChinookReportsWeb.ImportTableLive}
              id="reservoir-intervals"
              section="intervals"
              leg={ChinookReports.ReservoirQuality.leg_index(@report)}
              report={@report}
              editable={@editable}
            />
          <% end %>
        <% "synopsis" -> %>
          <.live_component
            module={ChinookReportsWeb.SynopsisLive}
            id="synopsis-editor"
            report={@report}
            legs={@import["reservoir_data"] || []}
            editable={@editable}
          />
        <% "surveys" -> %>
          <% legs = @import["reservoir_data"] || []
          planned = (@data && @data.surveys) || []
          view = @survey_view || if(legs != [], do: "actual", else: "planned") %>
          <.survey_view_tabs
            active={view}
            actual_count={
              legs |> Enum.map(&length(get_in(&1, ["survey", "survey_points"]) || [])) |> Enum.sum()
            }
            planned_count={length(planned)}
          />
          <%= if view == "actual" do %>
            <%= for {leg, i} <- Enum.with_index(legs) do %>
              <.live_component
                module={ChinookReportsWeb.ImportTableLive}
                id={"survey-#{i}"}
                section="survey"
                leg={i}
                report={@report}
                editable={@editable}
              />
              <.plan_comparison
                :if={get_in(leg, ["survey", "survey_points"]) not in [nil, []]}
                id={"plan-comparison-#{i}"}
                title={if length(legs) > 1, do: "Position vs Plan — #{leg["leg_name"]}"}
                comparison={ChinookReports.PlanComparison.for_leg(@report, i)}
              />
            <% end %>
            <p :if={legs == []} class="py-4 text-sm text-muted">No actual survey on file.</p>
          <% end %>
          <p
            :if={view == "planned" and planned == [] and not @editable}
            class="py-4 text-sm text-muted"
          >
            No planned survey on file.
          </p>
          <%= if view == "planned" and @data do %>
            <.editable_section key="surveys" editing={@editing} form={@form}>
              <:view>
                <.surveys_section
                  rows={@data.surveys}
                  kb={ChinookReports.FormationTops.kb_elevation(@report)}
                >
                  <:action :if={@editable}>
                    <.edit_button section="surveys" />
                  </:action>
                </.surveys_section>
              </:view>
              <:edit :let={form}>
                <.surveys_form
                  form={form}
                  plan_upload={@plan_upload}
                  plan_importing={@plan_importing}
                  plan_tops={@plan_tops}
                  plan_tops_note={plan_tops_note(@import)}
                />
              </:edit>
            </.editable_section>
          <% end %>
        <% "timing" -> %>
          <%= if @import["welldata"] do %>
            <.live_component
              module={ChinookReportsWeb.ImportTableLive}
              id="well-timing"
              section="well_timing"
              report={@report}
              editable={@editable}
            />
          <% end %>
          <%= if @data do %>
            <.editable_section key="profile_sections" editing={@editing} form={@form}>
              <:view>
                <.profile_section rows={@data.profile_sections}>
                  <:action :if={@editable}>
                    <.edit_button section="profile_sections" />
                  </:action>
                </.profile_section>
              </:view>
              <:edit :let={form}><.profile_sections_form form={form} /></:edit>
            </.editable_section>
          <% end %>
        <% "hole_casing_mud_bits" -> %>
          <%= if @import["welldata"] do %>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-5">
              <.live_component
                :for={section <- ~w(hole_sizes mud casing_data)}
                module={ChinookReportsWeb.ImportTableLive}
                id={"welldata-#{section}"}
                section={section}
                report={@report}
                editable={@editable}
              />
            </div>
          <% end %>
          <.live_component
            module={ChinookReportsWeb.ImportTableLive}
            id="import-bits"
            section="bits"
            report={@report}
            editable={@editable}
          />
        <% "mud_log" -> %>
          <.live_component
            module={ChinookReportsWeb.ImportTableLive}
            id="import-mud_log"
            section="mud_log"
            report={@report}
            editable={@editable}
          />
        <% "daily_reports" -> %>
          <.live_component
            module={ChinookReportsWeb.ImportTableLive}
            id="import-daily"
            section="daily"
            report={@report}
            editable={@editable}
          />
        <% _ -> %>
          <p class="text-sm text-muted">Nothing to show here.</p>
      <% end %>
    </div>
    """
  end

  # ── Per-section editing (active reports) ────────────────────────────────

  @doc """
  Wraps one report section: renders the read-only `:view` slot until the parent
  LiveView marks this `key` as being edited, then swaps in the `:edit` slot,
  wrapped in a form that `phx-change`es to "validate" and `phx-submit`s to
  "save_section". The parent LiveView owns `@form`.

  The "Edit" affordance itself lives in the section header — see `edit_button/1`,
  which the caller drops into the section component's `:action` slot.
  """
  attr :key, :string, required: true
  attr :editing, :string, default: nil
  attr :form, :any, default: nil
  slot :view, required: true
  slot :edit, required: true

  def editable_section(assigns) do
    ~H"""
    <div>
      <%= if @editing == @key do %>
        <.form for={@form} phx-change="validate" phx-submit="save_section">
          {render_slot(@edit, @form)}
          <.edit_actions cancel="cancel_edit" />
        </.form>
      <% else %>
        {render_slot(@view)}
      <% end %>
    </div>
    """
  end

  @doc """
  The "Edit" control shown in a section header — pencil icon plus a text label
  (default "Edit"; pass `label={nil}` for icon-only). `color` sets the
  icon/label colour class: the default suits the light section headers, and the
  dark gradient headers pass `"text-on-primary"`.
  """
  attr :section, :string, required: true, doc: "value for phx-value-section"
  attr :label, :string, default: "Edit", doc: "text beside the icon; nil for icon-only"
  attr :color, :string, default: "text-table-header-label", doc: "colour class for icon + label"
  attr :class, :string, default: nil

  def edit_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="edit_section"
      phx-value-section={@section}
      aria-label={@label || "Edit section"}
      title={@label || "Edit"}
      class={[
        "inline-flex items-center gap-1.5 rounded-md px-2 py-1 text-xs font-medium cursor-pointer",
        "opacity-80 transition-opacity hover:opacity-100",
        @color,
        @class
      ]}
    >
      <.icon name="hero-pencil" class="h-4 w-4" />
      <span :if={@label}>{@label}</span>
    </button>
    """
  end

  @doc """
  The Save / Cancel bar every section editor ends with. It sticks to the bottom
  of the viewport while the editor runs past it, so the buttons are always in
  reach, and settles in place once the editor's end scrolls into view. Pressing
  Escape anywhere fires the cancel event.

  Sticky positioning only works when no ancestor between the bar and the page's
  scroll container clips overflow — so render it *outside* `table_panel` /
  `card_panel` (both set `overflow`), as the last child of the editor's form.

  The inner block holds anything shown left of the buttons (add-row, hints,
  error counts).
  """
  attr :cancel, :string, default: "cancel", doc: "event pushed by Cancel and by Escape"
  attr :target, :any, default: nil, doc: "phx-target (a LiveComponent's @myself)"
  attr :disabled, :boolean, default: false
  attr :label, :string, default: "Save changes"
  slot :inner_block

  def edit_actions(assigns) do
    ~H"""
    <div
      class="sticky bottom-0 z-20 mt-3 flex flex-wrap items-center gap-3 rounded-lg border border-border-light bg-bg-card/95 px-4 py-3 shadow-[0_-4px_12px_rgba(0,0,0,0.08)] backdrop-blur"
      phx-window-keydown={@cancel}
      phx-key="Escape"
      phx-target={@target}
    >
      {render_slot(@inner_block)}
      <div class="ml-auto flex items-center gap-2">
        <span class="hidden text-[11px] text-muted sm:inline">Esc to cancel</span>
        <button type="submit" disabled={@disabled} class="btn-primary disabled:opacity-50">
          {@label}
        </button>
        <button type="button" phx-click={@cancel} phx-target={@target} class="btn-secondary">
          Cancel
        </button>
      </div>
    </div>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true

  def profile_sections_form(assigns) do
    ~H"""
    <.table_panel title="Well Profile">
      <.inputs_for :let={data} field={@form[:report_data]}>
        <.editable_table
          form={data}
          list={:profile_sections}
          columns={profile_columns()}
          hint="No sections yet. Add Vertical, Build, Lateral or additional legs as drilling reaches them."
        />
      </.inputs_for>
    </.table_panel>
    """
  end

  # Report page: imported tops are saved as soon as they're imported (the open
  # Surveys form can't carry another section), into the Formation Tops table.
  defp plan_tops_note(_import),
    do:
      "Fills the Prognosis column, matching formations by name; plan formations not in the table are added. Drilling (MWD / Gamma), Wireline and any imported Samples picks are kept. Saved straight away."

  attr :form, Phoenix.HTML.Form, required: true

  attr :plan_upload, :any,
    default: nil,
    doc: "the `:plan` UploadConfig; shows a plan-file drop zone"

  attr :plan_importing, :string, default: nil
  attr :plan_tops, :list, default: nil
  attr :plan_tops_note, :string, default: nil

  def surveys_form(assigns) do
    ~H"""
    <.table_panel title="Directional Program">
      <.plan_drop_zone
        :if={@plan_upload}
        upload={@plan_upload}
        importing={@plan_importing}
        tops={@plan_tops}
        tops_note={@plan_tops_note}
      />
      <.inputs_for :let={data} field={@form[:report_data]}>
        <.editable_table form={data} list={:surveys} columns={survey_columns()} />
      </.inputs_for>
      <p class="mt-3 text-xs text-copy-secondary">
        The planned path. TVD, N/S, E/W and dogleg are computed from MD / Inc / Azi
        (minimum curvature); a program that starts below surface is tied in vertically at the wellhead.
      </p>
    </.table_panel>
    """
  end

  defp profile_columns do
    [
      %{key: :section, label: "Section", placeholder: "Lateral"},
      %{key: :start_depth, label: "Start", unit: "m"},
      %{key: :end_depth, label: "End", unit: "m"},
      %{key: :start_date, label: "Start Date", type: :datetime}
    ]
  end

  defp survey_columns do
    [
      %{key: :md, label: "MD", unit: "m"},
      %{key: :inclination, label: "Inclination", unit: "°"},
      %{key: :azimuth, label: "Azimuth", unit: "°"}
    ]
  end

  attr :report, :map, required: true

  defp well_timing_section(assigns) do
    ~H"""
    <%= if timing = @report["well_timing"] do %>
      <% timing_rows =
        for(
          {label, key} <- [
            {"Spud Date", "spud_date"},
            {"Surface Casing", "surface_casing"},
            {"Sample Point", "sample_point"},
            {"Kick Off Point", "kick_off_point"},
            {"Intermediate Casing Point", "intermediate_casing_point"},
            {"Heel", "heel"},
            {"Final T.D.", "final_td"}
          ],
          event = timing[key],
          do: %{
            "milestone" => label,
            "date" => event["date"],
            "time" => event["time"],
            "depth" => event["depth"]
          }
        ) ++
          if rr = timing["rig_release_date"],
            do: [%{"milestone" => "Rig Release", "date" => rr, "time" => nil, "depth" => nil}],
            else: [] %>

      <.flat_card_panel title="Well Timing">
        <.table id="well_timing_table" rows={timing_rows}>
          <:col :let={row} label="Milestone">{row["milestone"]}</:col>
          <:col :let={row} label="Date">{row["date"]}</:col>
          <:col :let={row} label="Time">{row["time"]}</:col>
          <:col :let={row} label="Depth (m)">{row["depth"]}</:col>
        </.table>
      </.flat_card_panel>
    <% end %>
    """
  end

  attr :report, :map, required: true

  defp hole_mud_casing_section(assigns) do
    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-3 gap-5">
      <%= if holes = @report["hole_sizes"] do %>
        <.table_panel title="Hole Sizes">
          <.table id="hole_sizes_table" rows={holes}>
            <:col :let={h} label="Section">{String.capitalize(h["section"] || "")}</:col>
            <:col :let={h} label="Ø (mm)">{fmt_num(h["bit_diameter"])}</:col>
            <:col :let={h} label="From">{fmt_num(h["from_depth"])}</:col>
            <:col :let={h} label="To (m)">{fmt_num(h["to_depth"])}</:col>
          </.table>
        </.table_panel>
      <% end %>

      <%= if mud = @report["mud"] do %>
        <.table_panel title="Mud">
          <.table id="welldata_mud_table" rows={mud}>
            <:col :let={m} label="Section">{String.capitalize(m["section"] || "")}</:col>
            <:col :let={m} label="Type">{m["type"]}</:col>
            <:col :let={m} label="From">{fmt_num(m["from_depth"])}</:col>
            <:col :let={m} label="To (m)">{fmt_num(m["to_depth"])}</:col>
          </.table>
        </.table_panel>
      <% end %>

      <%= if casing = @report["casing_data"] do %>
        <.table_panel title="Casing">
          <.table id="casing_table" rows={casing}>
            <:col :let={c} label="Section">{c["section"]}</:col>
            <:col :let={c} label="Size (mm)">{fmt_num(c["size"])}</:col>
            <:col :let={c} label="Set At (m)">{fmt_num(c["set_at"])}</:col>
            <:col :let={c} label="Type">{c["type"]}</:col>
          </.table>
        </.table_panel>
      <% end %>
    </div>
    """
  end

  # ── Imported JSON (Excel extraction / seeded test data) ──────────────────

  attr :import, :map, required: true

  defp import_sections(assigns) do
    ~H"""
    <%= if welldata = @import["welldata"] do %>
      <.welldata_section report={welldata} />
    <% end %>
    <%= if tops = @import["tops"] do %>
      <.tops_section tops={tops} />
    <% end %>
    <%= if reservoir = @import["reservoir_data"] do %>
      <.reservoir_section reservoir={reservoir} />
    <% end %>
    <%= if synopsis = @import["synopsis"] do %>
      <.synopsis_section synopsis={synopsis} legs={@import["reservoir_data"] || []} />
    <% end %>
    <%= if daily = @import["daily"] do %>
      <.daily_section daily={daily} />
    <% end %>
    <%= if mud = @import["mud_log"] do %>
      <.mud_section mud={mud} />
    <% end %>
    <%= if bits = @import["bits"] do %>
      <.bits_section bits={bits} />
    <% end %>
    """
  end

  defp illuminated_box(assigns) do
    ~H"""
    <div class="mt-1 w-fit rounded-md px-3 py-2 border border-muted bg-accent">
      <span class="text-xs font-semibold uppercase tracking-wider mb-0.5 text-chinook-green-dark">
        {@title}
      </span>
      <p class="text-sm text-chinook-green-dark">{@description}</p>
    </div>
    """
  end

  defp bits_section(assigns) do
    ~H"""
    <.section_panel id="bits" title="Bits">
      <div class="py-4 overflow-x-auto">
        <.table id="bits_table" rows={@bits}>
          <:col :let={b} label="No">{b["bit_number"]}</:col>
          <:col :let={b} label="Type">{b["type"]}</:col>
          <:col :let={b} label="Make">{b["make"]}</:col>
          <:col :let={b} label="Size">{b["size"]}</:col>
          <:col :let={b} label="Depth In">{b["depth_in"]}</:col>
          <:col :let={b} label="Depth Out">{b["depth_out"]}</:col>
          <:col :let={b} label="Progress">{b["progress"]}</:col>
          <:col :let={b} label="WOB">{b["wob"]}</:col>
          <:col :let={b} label="ROP">{b["rop"]}</:col>
          <:col :let={b} label="RPM">{b["rpm"]}</:col>
          <:col :let={b} label="Hours">{b["hours"]}</:col>
        </.table>
      </div>
    </.section_panel>
    """
  end

  defp daily_section(assigns) do
    ~H"""
    <.section_panel id="daily" title="Daily Drilling Reports">
      <div class="py-4 flex flex-col gap-4">
        <%= for event <- @daily, event["operations_summary"] != nil do %>
          <div class="w-full flex flex-col gap-2">
            <h4 class="text-sm font-semibold text-text">Operations Summary for {event["date"]}</h4>
            <div class="w-full flex flex-row gap-4 text-sm text-text-secondary">
              <span><strong>Depth:</strong> {event["depth"]} m</span>
              <span><strong>Drilling Hours:</strong> {event["drilling_hours"]} hrs</span>
            </div>
            <span class="block p-2 rounded bg-bg text-sm text-text">
              {event["operations_summary"]}
            </span>
          </div>
        <% end %>
      </div>
    </.section_panel>
    """
  end

  defp mud_section(assigns) do
    ~H"""
    <.section_panel id="mud_log" title="Mud Log">
      <div class="py-4 overflow-x-auto">
        <.table id="mud_table" rows={@mud}>
          <:col :let={m} label="Date">{m["date"]}</:col>
          <:col :let={m} label="Depth (m)">{fmt_num(m["depth"])}</:col>
          <:col :let={m} label="Mud Type">{m["mud_type"]}</:col>
          <:col :let={m} label="Density">{m["density"]}</:col>
          <:col :let={m} label="Viscosity">{m["viscosity"]}</:col>
          <:col :let={m} label="WL">{m["wl"] || "—"}</:col>
          <:col :let={m} label="pH">{m["ph"] || "—"}</:col>
          <:col :let={m} label="Remarks">{m["remarks"] || "—"}</:col>
        </.table>
      </div>
    </.section_panel>
    """
  end

  defp reservoir_section(assigns) do
    ~H"""
    <.section_panel id="reservoir" title="Reservoir Data">
      <div class="py-4 flex flex-col gap-6">
        <.svelte name="ProfileChart" props={%{legs: @reservoir}} />
        <.svelte name="ReservoirChart" props={%{legs: @reservoir}} />
      </div>
    </.section_panel>
    """
  end

  attr :synopsis, :map, required: true
  attr :legs, :list, default: []
  slot :action, doc: "trailing content in the panel header (e.g. an edit button)"

  def synopsis_section(assigns) do
    ~H"""
    <.section_panel id="synopsis" title="Synopsis">
      <:action :if={@action != []}>{render_slot(@action)}</:action>
      <%= if summary = @synopsis["well_summary"] do %>
        <.flat_card_panel title="Well Summary">
          <div class="py-4 flex flex-col gap-3">
            <%= for para <- summary do %>
              <p class="text-sm text-text leading-relaxed">{para}</p>
            <% end %>
          </div>
        </.flat_card_panel>
      <% end %>

      <%= if profile = @synopsis["well_profile"] do %>
        <.flat_card_panel title="Well Profile">
          <div class="py-4 flex flex-col gap-4">
            <%= if @legs != [] do %>
              <div class="rounded-lg border border-border-light bg-bg p-2">
                <.svelte name="ProfileChart" props={%{legs: @legs}} />
              </div>
            <% else %>
              <div class="w-full h-32 rounded-lg bg-bg border border-border-light flex items-center justify-center">
                <p class="text-sm text-muted">No wellpath data available</p>
              </div>
            <% end %>
            <ul class="flex flex-col gap-1.5">
              <%= for item <- profile do %>
                <li class="text-sm text-text flex gap-2">
                  <span class="text-primary">·</span>
                  <span>{item}</span>
                </li>
              <% end %>
            </ul>
          </div>
        </.flat_card_panel>
      <% end %>

      <%= if fe_lines = @synopsis["formation_evaluation"] do %>
        <% {pre_text, reservoir_rows, fe_remaining, conclusion_lines} =
          split_formation_evaluation(fe_lines) %>
        <.flat_card_panel title="Formation Evaluation">
          <div class="py-4 flex flex-col gap-4">
            <div class="flex flex-col gap-3">
              <%= for para <- pre_text do %>
                <p class="text-sm text-text leading-relaxed">{para}</p>
              <% end %>
            </div>
            <%= if reservoir_rows != [] do %>
              <.table id="formation_eval_table" rows={reservoir_rows}>
                <:col :let={r} label="Quality">{r["quality"]}</:col>
                <:col :let={r} label="Interval (m)">{r["depth"]}</:col>
                <:col :let={r} label="%">{r["percent"]}</:col>
              </.table>
            <% end %>
            <%= if fe_remaining != [] do %>
              <div class="flex flex-col gap-3">
                <%= for line <- fe_remaining do %>
                  <p class="text-sm text-text leading-relaxed">{line}</p>
                <% end %>
              </div>
            <% end %>
          </div>
        </.flat_card_panel>
        <%= if conclusion_lines != [] do %>
          <.illuminated_box title="Conclusions" description={Enum.join(conclusion_lines, "\n")} />
        <% end %>
      <% end %>
    </.section_panel>
    """
  end

  defp split_formation_evaluation(lines) do
    {pre, rest} =
      Enum.split_while(lines, fn line ->
        not Regex.match?(~r/^(Very Good|Good|Fair|Poor|Nil|Total) reservoir: /, line)
      end)

    {reservoir, post} =
      Enum.split_while(rest, fn line ->
        Regex.match?(~r/^(Very Good|Good|Fair|Poor|Nil|Total) reservoir: /, line)
      end)

    reservoir_rows =
      reservoir
      |> Enum.map(&parse_reservoir_row/1)
      |> Enum.filter(&(&1 != nil))

    {fe_remaining, conclusion_lines} =
      case Enum.split_while(post, &(String.trim(&1) != "CONCLUSIONS")) do
        {before, [_header | after_header]} -> {before, after_header}
        {before, []} -> {before, []}
      end

    {pre, reservoir_rows, fe_remaining, conclusion_lines}
  end

  defp parse_reservoir_row(line) do
    case Regex.run(~r/^(.+?) reservoir: ([\d,.]+)m \(([\d.]+)%\)/, line) do
      [_, quality, depth, percent] ->
        %{"quality" => quality, "depth" => depth, "percent" => percent}

      _ ->
        nil
    end
  end

  defp tops_section(assigns) do
    ~H"""
    <.section_panel id="tops" title="Formation Tops">
      <div class="py-4 overflow-x-auto">
        <table class="w-full text-sm border-collapse">
          <thead>
            <tr class="border-b border-border-light">
              <th
                class="text-left text-xs font-semibold uppercase tracking-wider text-table-header-label py-2 pr-4"
                rowspan="2"
              >
                Formation
              </th>
              <th
                class="text-center text-xs font-semibold uppercase tracking-wider text-table-header-label py-2 px-2 border-l border-border-light"
                colspan="2"
              >
                Prognosis
              </th>
              <th
                class="text-center text-xs font-semibold uppercase tracking-wider text-table-header-label py-2 px-2 border-l border-border-light"
                colspan="4"
              >
                Samples
              </th>
              <th
                class="text-center text-xs font-semibold uppercase tracking-wider text-table-header-label py-2 px-2 border-l border-border-light"
                colspan="4"
              >
                MWD / Gamma
              </th>
              <th
                class="text-center text-xs font-semibold uppercase tracking-wider text-table-header-label py-2 pl-2 border-l border-border-light"
                rowspan="2"
              >
                Diff (m)
              </th>
            </tr>
            <tr class="border-b-2 border-border-light">
              <%= for label <- ["MD", "Subsea"] do %>
                <th class={"text-right text-xs font-medium text-muted py-1 px-2 #{if label == "MD", do: "border-l border-border-light"}"}>
                  {label}
                </th>
              <% end %>
              <%= for label <- ["MD", "TVD", "Isopach", "Subsea"] do %>
                <th class={"text-right text-xs font-medium text-muted py-1 px-2 #{if label == "MD", do: "border-l border-border-light"}"}>
                  {label}
                </th>
              <% end %>
              <%= for label <- ["MD", "TVD", "Isopach", "Subsea"] do %>
                <th class={"text-right text-xs font-medium text-muted py-1 px-2 #{if label == "MD", do: "border-l border-border-light"}"}>
                  {label}
                </th>
              <% end %>
            </tr>
          </thead>
          <tbody>
            <%= for top <- @tops["formations"] do %>
              <% diff = top["difference_m"] %>
              <tr class="border-b border-border-light hover:bg-bg transition-colors">
                <td class="py-2 pr-4 font-medium text-text">{top["formation"]}</td>
                <%= for val <- [get_in(top, ["prognosis", "md"]), get_in(top, ["prognosis", "subsea"])] do %>
                  <td class="text-right py-2 px-2 text-text-secondary tabular-nums border-l border-border-light first-of-type:border-l">
                    {format_top_val(val)}
                  </td>
                <% end %>
                <%= for val <- [get_in(top, ["samples", "md"]), get_in(top, ["samples", "tvd"]), get_in(top, ["samples", "isopach"]), get_in(top, ["samples", "subsea"])] do %>
                  <td class="text-right py-2 px-2 text-text-secondary tabular-nums border-l border-border-light first-of-type:border-l">
                    {format_top_val(val)}
                  </td>
                <% end %>
                <%= for val <- [get_in(top, ["mwd_gamma", "md"]), get_in(top, ["mwd_gamma", "tvd"]), get_in(top, ["mwd_gamma", "isopach"]), get_in(top, ["mwd_gamma", "subsea"])] do %>
                  <td class="text-right py-2 px-2 text-text-secondary tabular-nums border-l border-border-light first-of-type:border-l">
                    {format_top_val(val)}
                  </td>
                <% end %>
                <td class={[
                  "text-right py-2 pl-2 tabular-nums font-medium border-l border-border-light",
                  if(is_number(diff) && diff > 0, do: "text-amber-500", else: "text-primary")
                ]}>
                  {if is_number(diff),
                    do: "#{if diff > 0, do: "+"}#{:erlang.float_to_binary(diff / 1, decimals: 1)}",
                    else: "—"}
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </.section_panel>
    """
  end

  defp format_top_val(nil), do: "—"
  defp format_top_val(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 1)
  defp format_top_val(v), do: to_string(v)

  defp welldata_section(assigns) do
    ~H"""
    <.section_panel id="welldata" title="Well Data">
      <div class="py-4 flex flex-col gap-4">
        <.subtitle subtitle="Well Identification" />
        <div>
          <.wfield label="Well Name" value={@report["well_name"]} />
          <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-x-6 gap-y-3 pt-3">
            <.wfield label="Unique Well ID" value={@report["unique_well_id"]} />
            <.wfield label="AFE Number" value={@report["afe_number"]} />
            <.wfield label="License" value={@report["well_license"]} />
            <.wfield label="Operator" value={@report["operator"]} />
            <.wfield label="Reported To" value={@report["op_geo"]} />
          </div>
        </div>
        <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-x-6 gap-y-3 pt-3 border-t border-border-light">
          <.wfield label="Surface Location" value={@report["surface_location"]} />
          <.wfield label="Bottom Location" value={@report["bottom_location"]} />
          <.wfield label="Field / Region" value={@report["field_region"]} />
          <.wfield
            label="Province / Country"
            value={"#{@report["province"]}, #{@report["country"]}"}
          />
          <.wfield label="Classification" value={@report["well_classification"]} />
          <.wfield label="Security" value={@report["security"]} />
        </div>
        <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-x-6 gap-y-3 pt-3 border-t border-border-light">
          <.wfield label="Geometry" value={@report["well_geometry"]} />
          <.wfield label="Purpose" value={@report["well_purpose"]} />
          <.wfield label="Substance" value={@report["substance"]} />
        </div>
      </div>

      <%= if td = @report["total_depth_actual"] do %>
        <div class="pt-2 border-t border-border-light">
          <p class="text-xs font-semibold uppercase tracking-wider mb-2 text-muted">
            Total Depth
          </p>
          <div class="grid grid-cols-3 gap-2">
            <%= for {label, val} <- [{"MD", td["md"]}, {"TVD", td["tvd"]}, {"Subsea", td["subsea"]}] do %>
              <div class="rounded-md p-2 text-center bg-bg border border-border-light">
                <p class="text-xs font-semibold mb-0.5 text-muted">{label}</p>
                <p class="text-lg font-semibold text-primary">
                  {val}
                </p>
                <span class="text-xs font-normal text-text-secondary">
                  <%= if td["unit"] == "m" do %>
                    {"meters"}
                  <% end %>
                  <%= if td["unit"] == "ft" do %>
                    {"feet"}
                  <% end %>
                </span>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <%!-- ── Objectives + Well Type + Elevations + Location ───── --%>

      <.flat_card_panel title="Well Objectives and Type">
        <div class="py-4 flex flex-col gap-6">
          <div class="grid grid-cols-3 gap-4">
            <.wfield label="Primary Target" value={@report["primary_target"]} />
            <.wfield label="Secondary Target" value={@report["secondary_target"]} />
            <.wfield label="Terminating Zone" value={@report["terminating_zone"]} />
          </div>
          <div class="grid grid-cols-3 gap-3 pt-2 border-t border-border-light">
            <.wfield label="Geometry" value={@report["well_geometry"]} />
            <.wfield label="Purpose" value={@report["well_purpose"]} />
            <.wfield label="Substance" value={@report["substance"]} />
          </div>

          <%= if status = @report["final_well_status"] do %>
            <.illuminated_box title="Final Well Status" description={status} />
          <% end %>
        </div>
      </.flat_card_panel>

      <%!-- ── Elevations + Location ─────────────────────────── --%>
      <% loc = @report["location_data"] %>
      <% elev = @report["elevations"] %>
      <%= if elev || loc do %>
        <.card_panel title="Surface Location and Elevations">
          <div class="px-5 py-4 flex flex-col gap-4">
            <%= if elev do %>
              <div class="flex flex-col gap-2">
                <div class="grid grid-cols-3 gap-2">
                  <%= for {label, val} <- [
                      {"Ground Level", "#{elev["ground_level"]} m"},
                      {"Kelly Bushing", "#{elev["kelly_bushing"]} m"},
                      {"KB to Ground",
                       elev_m(
                         ChinookReports.FormationTops.kb_to_ground(
                           elev["ground_level"],
                           elev["kelly_bushing"]
                         )
                       ) || "—"},
                      {"Datum", "#{elev["reference"]}"}
                    ] do %>
                    <div class="rounded-md bg-bg p-2">
                      <p class="text-xs mb-0.5 text-muted uppercase font-medium">{label}</p>
                      <p class="text-sm text-text">{val}</p>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

            <%= if loc do %>
              <% coords = loc["geographic_coordinates"] %>
              <% grid = loc["surface_location_grid"] %>
              <div class="flex flex-col gap-2 pt-2 border-t border-border-light">
                <div class="grid grid-cols-3 gap-2">
                  <div class="rounded-md bg-bg p-2">
                    <p class="text-xs mb-0.5 text-muted uppercase font-medium">Surface</p>
                    <p class="text-sm text-text">{@report["surface_location"]}</p>
                  </div>
                  <div class="rounded-md bg-bg p-2">
                    <p class="text-xs mb-0.5 text-muted uppercase font-medium">Bottom</p>
                    <p class="text-sm text-text">{@report["bottom_location"]}</p>
                  </div>
                  <div class="rounded-md bg-bg p-2">
                    <p class="text-xs mb-0.5 text-muted uppercase font-medium">Bottom Offset</p>
                    <p class="text-sm text-text">{loc["bottom_coordinates"]}</p>
                  </div>
                  <%= if coords do %>
                    <div class="rounded-md bg-bg p-2 col-span-2">
                      <p class="text-xs mb-0.5 text-muted uppercase font-medium">
                        Geographic Coordinates
                      </p>
                      <p class="text-sm font-mono text-text">
                        {abs(coords["latitude"])}° {coord_dir(
                          coords["latitude"],
                          coords["latitude_dir"],
                          "N",
                          "S"
                        )}, {abs(coords["longitude"])}° {coord_dir(
                          coords["longitude"],
                          coords["longitude_dir"],
                          "E",
                          "W"
                        )}
                        <span class="text-xs font-sans font-normal text-muted ml-1">
                          {coords["datum"]}
                        </span>
                      </p>
                    </div>
                  <% end %>
                  <%= if grid do %>
                    <div class="rounded-md bg-bg p-2 col-span-3">
                      <p class="text-xs mb-0.5 text-muted uppercase font-medium">Grid Offset</p>
                      <p class="text-sm text-text">
                        {grid["northing"]}m {grid["northing_dir"]}, {grid["easting"]}m {grid[
                          "easting_dir"
                        ]} of Sec {grid["section"]}-Twp {grid["township"]}-Rng {grid["range"]}W{grid[
                          "meridian"
                        ]}
                      </p>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        </.card_panel>
      <% end %>

      <%!-- ── Well Timing ──────────────────────────────────────── --%>
      <.well_timing_section report={@report} />

      <%!-- ── Hole Sizes / Mud / Casing ──────────────────────── --%>
      <.hole_mud_casing_section report={@report} />

      <%!-- ── Services + Geological Services ─────────────────── --%>

      <%= if services = @report["services"] do %>
        <.card_panel title="Services">
          <div class="px-5 py-4 flex flex-col gap-3">
            <%= if geo = services["wellsite_geology"] do %>
              <div class="grid grid-cols-2">
                <.wfield label="Wellsite Geology" value={geo["company"]} />
                <%= if geologists = geo["geologists"] do %>
                  <.wfield label="Wellsite Geologists" value={Enum.join(geologists, ", ")} />
                <% end %>
              </div>
            <% end %>
            <div class="grid grid-cols-2 pt-5 border-t border-border-light">
              <%= if dc = services["drilling_contractor"] do %>
                <.wfield label="Drilling Contractor" value={"#{dc["company"]} · Rig #{dc["rig"]}"} />
              <% end %>
              <.wfield label="Supervision" value={services["drilling_supervision"]} />
              <.wfield label="Directional Drilling" value={services["directional_drilling"]} />
              <.wfield label="MWD / LWD" value={services["mwd_lwd_services"]} />
              <.wfield label="Gas Detection" value={services["gas_detection"]} />
              <.wfield label="Mud" value={services["mud"]} />
            </div>
          </div>
        </.card_panel>
      <% end %>

      <%= if geo_svc = @report["geological_services"] do %>
        <.flat_card_panel title="Geological Services">
          <div class="py-4 grid grid-cols-3 gap-3">
            <.wfield label="Samples (Operator)" value={geo_svc["samples_operator"]} />
            <.wfield label="Samples (Government)" value={geo_svc["samples_government"]} />
            <.wfield label="Cores" value={geo_svc["cores"]} />
            <.wfield label="DST" value={geo_svc["dst"]} />
            <.wfield label="Logging Suite" value={geo_svc["logging_suite"]} />
          </div>
        </.flat_card_panel>
      <% end %>

      <%!-- ── Well Profile ──────────────────────────────────────── --%>
      <%= if profile = @report["well_profile"] do %>
        <.table_panel title="Well Profile">
          <.table id="welldata_profile_table" rows={profile}>
            <:col :let={s} label="Section">{s["section"]}</:col>
            <:col :let={s} label="Start">
              {get_in(s, ["start", "date"])}
              <span class="text-xs ml-1 text-muted">{get_in(s, ["start", "time"])}</span>
            </:col>
            <:col :let={s} label="End">
              {get_in(s, ["end", "date"])}
              <span class="text-xs ml-1 text-muted">{get_in(s, ["end", "time"])}</span>
            </:col>
            <:col :let={s} label="Length (m)">{fmt_num(s["length"])}</:col>
            <:col :let={s} label="Duration (days)">{s["duration_days"]}</:col>
          </.table>
        </.table_panel>
      <% end %>
    </.section_panel>
    """
  end

  # ── Well Summary ─────────────────────────────────────────────────────────

  attr :report, :map, required: true
  slot :action

  defp well_summary_section(assigns) do
    ~H"""
    <.section_panel id="well_summary" title="Well Summary">
      <:action :if={@action != []}>{render_slot(@action)}</:action>
      <div class="py-4 flex flex-col gap-4">
        <.subtitle subtitle="Well Identification" />
        <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-x-6 gap-y-3">
          <.wfield label="Well Name" value={@report.well_name} />
          <.wfield label="Unique Well ID" value={@report.unique_well_id} />
          <.wfield label="Operator" value={@report.operator} />
          <div class="flex flex-col gap-0.5">
            <span class="text-xs font-medium text-muted uppercase">Status</span>
            <.status_badge status={@report.status} />
          </div>
        </div>

        <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-x-6 gap-y-3 pt-3 border-t border-border-light">
          <.wfield label="Spud Date" value={@report.spud_date && fmt_datetime(@report.spud_date)} />
          <.wfield
            label="Final T.D. Date"
            value={@report.final_td_date && fmt_datetime(@report.final_td_date)}
          />
          <.wfield label="Geometry" value={@report.geometry} />
          <.wfield label="Units" value={@report.units} />
        </div>

        <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-x-6 gap-y-3 pt-3 border-t border-border-light">
          <.wfield label="Primary Target" value={@report.target_formation} />
          <.wfield label="Secondary Target" value={@report.secondary_target} />
          <.wfield label="Country" value={@report.country} />
          <.wfield label="Province" value={@report.province} />
        </div>

        <%= if @report.latitude && @report.longitude do %>
          <div class="pt-3 border-t border-border-light">
            <div class="rounded-md bg-bg w-fit px-3 py-2">
              <p class="text-xs mb-0.5 text-muted uppercase font-medium">Coordinates</p>
              <p class="text-sm font-mono text-text">
                <%= if @report.report_data && @report.report_data.datum == "UTM" do %>
                  {fmt_coord(@report.latitude)}m, {fmt_coord(@report.longitude)}m
                <% else %>
                  {fmt_coord(@report.latitude)}° N, {fmt_coord(abs(@report.longitude))}° W
                <% end %>
              </p>
            </div>
          </div>
        <% end %>
      </div>
    </.section_panel>
    """
  end

  # ── Elevations & Location (report_data embed) ───────────────────────────

  attr :report, :map, default: nil
  attr :data, :map, required: true
  slot :action

  defp elevations_location_section(assigns) do
    ~H"""
    <% imported_elev =
      (@report && @report.import_data && get_in(@report.import_data, ["welldata", "elevations"])) ||
        %{} %>
    <%= if @action != [] or imported_elev != %{} or has_any?(@data, [:gl_elevation, :kb_elevation, :kb_to_ground, :surface_coordinates, :surface_location, :bottom_location, :field_region]) do %>
      <.card_panel title="Elevations and Location">
        <:action :if={@action != []}>{render_slot(@action)}</:action>
        <div class="px-5 py-4 flex flex-col gap-4">
          <div class="grid grid-cols-3 gap-2">
            <%= for {label, val} <- [
                {"Ground Level", elev_m(@data.gl_elevation || imported_elev["ground_level"])},
                {"Kelly Bushing", elev_m(@data.kb_elevation || imported_elev["kelly_bushing"])},
                {"KB to Ground",
                 elev_m(
                   ChinookReports.FormationTops.kb_to_ground(
                     @data.gl_elevation || imported_elev["ground_level"],
                     @data.kb_elevation || imported_elev["kelly_bushing"]
                   )
                 )},
                {"Datum", @data.datum || imported_elev["reference"]}
              ] do %>
              <div class="rounded-md bg-bg p-2">
                <p class="text-xs mb-0.5 text-muted uppercase font-medium">{label}</p>
                <p class="text-sm text-text">{val || "—"}</p>
              </div>
            <% end %>
          </div>

          <%= if @data.surface_location || @data.bottom_location || @data.field_region do %>
            <div class="grid grid-cols-3 gap-2 pt-2 border-t border-border-light">
              <div class="rounded-md bg-bg p-2">
                <p class="text-xs mb-0.5 text-muted uppercase font-medium">Surface Location</p>
                <p class="text-sm text-text">{@data.surface_location || "—"}</p>
              </div>
              <div class="rounded-md bg-bg p-2">
                <p class="text-xs mb-0.5 text-muted uppercase font-medium">Bottom Location</p>
                <p class="text-sm text-text">{@data.bottom_location || "—"}</p>
              </div>
              <div class="rounded-md bg-bg p-2">
                <p class="text-xs mb-0.5 text-muted uppercase font-medium">Field / Region</p>
                <p class="text-sm text-text">{@data.field_region || "—"}</p>
              </div>
            </div>
          <% end %>

          <%= if @data.surface_coordinates do %>
            <div class="rounded-md bg-bg p-2">
              <p class="text-xs mb-0.5 text-muted uppercase font-medium">Surface Coordinates</p>
              <p class="text-sm text-text">{@data.surface_coordinates}</p>
            </div>
          <% end %>
        </div>
      </.card_panel>
    <% end %>
    """
  end

  # ── Configuration (report_data embed) ────────────────────────────────────

  attr :data, :map, required: true
  slot :action

  defp configuration_section(assigns) do
    ~H"""
    <%= if @action != [] or has_any?(@data, [:classification, :license, :purpose, :substance, :terminating_zone]) do %>
      <.flat_card_panel title="Configuration">
        <:action :if={@action != []}>{render_slot(@action)}</:action>
        <%= if has_any?(@data, [:classification, :license, :purpose, :substance, :terminating_zone]) do %>
          <div class="py-4 grid grid-cols-2 sm:grid-cols-3 gap-x-6 gap-y-3">
            <.wfield label="Classification" value={@data.classification} />
            <.wfield label="License" value={@data.license} />
            <.wfield label="Purpose" value={@data.purpose} />
            <.wfield label="Substance" value={@data.substance} />
            <.wfield label="Terminating Zone" value={@data.terminating_zone} />
          </div>
        <% else %>
          <p class="py-4 text-sm text-muted">No configuration recorded.</p>
        <% end %>
      </.flat_card_panel>
    <% end %>
    """
  end

  # ── Well Profile (report_data.profile_sections) ─────────────────────────

  attr :rows, :list, required: true
  slot :action

  defp profile_section(assigns) do
    ~H"""
    <%= if @rows != [] or @action != [] do %>
      <.table_panel title="Well Profile">
        <:action :if={@action != []}>{render_slot(@action)}</:action>
        <.table :if={@rows != []} id="profile_sections_table" rows={@rows}>
          <:col :let={s} label="Section">{s.section}</:col>
          <:col :let={s} label="Start (m)">{fmt_decimal(s.start_depth)}</:col>
          <:col :let={s} label="End (m)">{fmt_decimal(s.end_depth)}</:col>
          <:col :let={s} label="Start Date">{fmt_datetime(s.start_date)}</:col>
        </.table>
        <p :if={@rows == []} class="py-4 text-sm text-muted">No well profile sections recorded.</p>
      </.table_panel>
    <% end %>
    """
  end

  # ── Formation Tops (report_data.formation_tops) ─────────────────────────

  attr :rows, :list, required: true
  slot :action

  defp formation_tops_section(assigns) do
    ~H"""
    <%= if @rows != [] or @action != [] do %>
      <.table_panel title="Formation Tops">
        <:action :if={@action != []}>{render_slot(@action)}</:action>
        <.table :if={@rows != []} id="formation_tops_table" rows={@rows}>
          <:col :let={t} label="Formation">{t.formation}</:col>
          <:col :let={t} label="MD (m)">{fmt_decimal(t.md)}</:col>
          <:col :let={t} label="TVD (m)">{fmt_decimal(t.tvd)}</:col>
          <:col :let={t} label="Isopach (m)">{fmt_decimal(t.isopach)}</:col>
          <:col :let={t} label="Subsea (m)">{fmt_decimal(t.subsea)}</:col>
        </.table>
        <p :if={@rows == []} class="py-4 text-sm text-muted">No formation tops recorded.</p>
      </.table_panel>
    <% end %>
    """
  end

  # ── Position vs plan (ChinookReports.PlanComparison) ─────────────────────

  attr :id, :string, required: true
  attr :title, :string, default: nil
  attr :comparison, :map, default: nil

  defp plan_comparison(assigns) do
    ~H"""
    <.table_panel title={@title || "Position vs Plan"}>
      <div id={@id}>
        <p :if={is_nil(@comparison)} class="py-4 text-sm text-muted">
          No planned survey to compare against. Add one under Planned.
        </p>

        <%= if @comparison do %>
          <div
            :if={latest = @comparison.latest}
            class="flex flex-wrap items-baseline gap-x-5 gap-y-1 pb-3"
          >
            <span class="text-xs text-text-secondary">
              Last survey · {fmt_survey(latest.md)} m MD
            </span>
            <span class="text-sm font-semibold">{offset(latest.above, "above", "below")}</span>
            <span class="text-sm font-semibold">{offset(latest.ahead, "ahead", "behind")}</span>
            <span class="text-sm font-semibold">{offset(latest.right, "right", "left")}</span>
            <span class="text-sm text-text-secondary">
              {NumberFormat.up_to_2(latest.distance)} m from plan
            </span>
          </div>

          <details>
            <summary class="cursor-pointer text-xs font-medium text-primary hover:text-primary-hover">
              Every station ({length(@comparison.rows)})
            </summary>
            <.table id={"#{@id}-table"} rows={@comparison.rows}>
              <:col :let={r} label="MD (m)">
                {fmt_survey(r.md)}
                <span :if={r.projected} class="ml-1 text-[10px] text-muted">projected</span>
                <span :if={r.beyond_plan} class="ml-1 text-[10px] text-muted">past plan</span>
              </:col>
              <:col :let={r} label="Above / Below">{offset(r.above, "above", "below")}</:col>
              <:col :let={r} label="Ahead / Behind">{offset(r.ahead, "ahead", "behind")}</:col>
              <:col :let={r} label="Left / Right">{offset(r.right, "right", "left")}</:col>
              <:col :let={r} label="Distance (m)">{NumberFormat.up_to_2(r.distance)}</:col>
            </.table>
          </details>

          <p class="mt-3 text-xs text-copy-secondary">
            Each station against the plan at the same MD. Ahead / behind and left / right are
            along and across the plan's {NumberFormat.up_to(@comparison.vs_azimuth_deg, 1)}° section line;
            past the plan's last station it is projected straight ahead.
          </p>
        <% end %>
      </div>
    </.table_panel>
    """
  end

  # "2.31 m above" / "0.4 m below"; anything that rounds to 0.00 is on plan.
  defp offset(v, positive, negative) do
    if abs(v) < 0.005,
      do: "on plan",
      else: "#{NumberFormat.up_to_2(abs(v))} m #{if v > 0, do: positive, else: negative}"
  end

  # ── Directional Program (report_data.surveys) ────────────────────────────

  attr :active, :string, required: true
  attr :actual_count, :integer, required: true
  attr :planned_count, :integer, required: true

  # Actual / Planned switch on the Surveys tab; the choice is kept in the URL
  # (`?survey=`) by ReportPageLive.
  defp survey_view_tabs(assigns) do
    ~H"""
    <div role="tablist" aria-label="Survey" class="flex w-fit rounded-lg border border-border p-0.5">
      <button
        :for={
          {id, label, count} <- [
            {"actual", "Actual", @actual_count},
            {"planned", "Planned", @planned_count}
          ]
        }
        type="button"
        role="tab"
        aria-selected={to_string(id == @active)}
        phx-click="select_survey_view"
        phx-value-view={id}
        class={[
          "px-3 py-1.5 rounded-md text-xs font-medium cursor-pointer transition-colors",
          id == @active && "bg-primary text-on-primary",
          id != @active && "text-text-secondary hover:text-text"
        ]}
      >
        {label}
        <span :if={count > 0} class={["ml-1 text-[10px]", id != @active && "text-muted"]}>
          {count}
        </span>
      </button>
    </div>
    """
  end

  attr :rows, :list, required: true
  attr :kb, :any, default: nil, doc: "KB elevation, for subsea; `nil` leaves it blank"
  slot :action

  # Only MD / Inc / Azi are stored; the rest is integrated from them by
  # minimum curvature (Trajectory.stations/1) each render, so it can't drift.
  defp surveys_section(assigns) do
    by_md =
      assigns.rows
      |> Enum.map(&%{md: &1.md, inc_deg: &1.inclination, azi_deg: &1.azimuth})
      |> ChinookReports.Trajectory.stations()
      |> Map.new(&{&1.md, &1})

    rows =
      Enum.map(assigns.rows, fn s ->
        {s, s.md && Map.get(by_md, Decimal.to_float(s.md))}
      end)

    assigns = assign(assigns, rows: rows)

    ~H"""
    <%= if @rows != [] or @action != [] do %>
      <.table_panel title="Directional Program">
        <:action :if={@action != []}>{render_slot(@action)}</:action>
        <.table :if={@rows != []} id="surveys_table" rows={@rows}>
          <:col :let={{s, _}} label="MD (m)">{fmt_survey(s.md)}</:col>
          <:col :let={{s, _}} label="Inclination (°)">{fmt_survey(s.inclination)}</:col>
          <:col :let={{s, _}} label="Azimuth (°)">{fmt_survey(s.azimuth)}</:col>
          <:col :let={{_, p}} label="TVD (m)">{fmt_survey(p && p.tvd)}</:col>
          <:col :let={{_, p}} label="N/S (m)">{fmt_survey(p && p.north)}</:col>
          <:col :let={{_, p}} label="E/W (m)">{fmt_survey(p && p.east)}</:col>
          <:col :let={{_, p}} label="VS (m)">{fmt_survey(p && p.vertical_section)}</:col>
          <:col :let={{_, p}} label="DLS">{fmt_survey(p && p.dogleg_severity)}</:col>
          <:col :let={{_, p}} label="Subsea (m)">{fmt_survey(p && @kb && @kb - p.tvd)}</:col>
        </.table>
        <p :if={@rows == []} class="py-4 text-sm text-muted">No directional program recorded.</p>
      </.table_panel>
    <% end %>
    """
  end

  # ── Shared building blocks ────────────────────────────────────────────────

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :inner_block, required: true
  slot :action, doc: "trailing content in the panel header (e.g. an edit button)"

  def card_panel(assigns) do
    ~H"""
    <div class="card overflow-hidden">
      <div class="px-5 py-2.5 flex items-center justify-between gap-3">
        <h4 class="text-sm font-semibold uppercase tracking-wider text-table-header-label">
          {@title}
          <%= if @subtitle do %>
            <span class="font-normal normal-case ml-1.5 text-xs text-chinook-green-light">
              {@subtitle}
            </span>
          <% end %>
        </h4>
        <div :if={@action != []} class="shrink-0">{render_slot(@action)}</div>
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true
  slot :action, doc: "trailing content in the panel header (e.g. an edit button)"

  defp flat_card_panel(assigns) do
    ~H"""
    <div class="overflow-hidden">
      <div class="py-2.5 flex items-center justify-between gap-3">
        <h4 class="text-sm font-semibold uppercase tracking-wider text-table-header-label">
          {@title}
        </h4>
        <div :if={@action != []} class="shrink-0">{render_slot(@action)}</div>
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true
  slot :action, doc: "trailing content in the panel header (e.g. an edit button)"

  def table_panel(assigns) do
    ~H"""
    <div class="data-table-container">
      <div class="py-2.5 w-full flex items-center justify-between gap-3">
        <h4 class="text-sm font-semibold uppercase tracking-wider text-table-header-label">
          {@title}
        </h4>
        <div :if={@action != []} class="shrink-0">{render_slot(@action)}</div>
      </div>
      <div class="w-full overflow-x-auto">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true
  slot :action, doc: "trailing content in the panel header (e.g. an edit button)"

  defp section_panel(assigns) do
    ~H"""
    <div id={"#{@id}"} class="flex flex-col rounded-xl card-shadow">
      <div class="flex flex-col relative rounded-xl overflow-hidden">
        <div class="absolute top-0 left-0 w-1 h-full bg-primary"></div>
        <div class="flex items-center justify-between gap-3 px-5 py-3 bg-linear-to-r from-primary to-secondary rounded-t-xl overflow-hidden">
          <h3 class="text-lg font-semibold text-on-primary">{@title}</h3>
          <div :if={@action != []} class="shrink-0">{render_slot(@action)}</div>
        </div>
        <div class="px-5 space-y-4 pb-4">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  defp wfield(assigns) do
    ~H"""
    <%= if @value not in [nil, "", "-"] do %>
      <div class="flex flex-col gap-0.5">
        <span class="text-xs font-medium text-muted uppercase">{@label}</span>
        <span class="text-sm text-text">{@value}</span>
      </div>
    <% end %>
    """
  end

  defp subtitle(assigns) do
    ~H"""
    <span class="font-semibold uppercase text-md text-table-header-label">{@subtitle}</span>
    """
  end

  attr :status, :string, required: true

  defp status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex w-fit items-center rounded-full px-2 py-0.5 text-xs font-medium",
      @status == "complete" && "bg-green-100 text-green-800",
      @status == "active" && "bg-blue-100 text-blue-800",
      @status == "draft" && "bg-gray-100 text-gray-700"
    ]}>
      {String.capitalize(@status || "draft")}
    </span>
    """
  end

  defp has_any?(data, fields), do: Enum.any?(fields, &(Map.get(data, &1) not in [nil, ""]))

  # Directional-survey values keep their precision (see NumberFormat.survey/1).
  defp fmt_survey(nil), do: "—"
  defp fmt_survey(v), do: ChinookReportsWeb.NumberFormat.survey(v)

  defp fmt_decimal(nil), do: "—"
  defp fmt_decimal(%Decimal{} = d), do: d |> Decimal.round(2) |> Decimal.to_string(:normal)

  # spud_date/final_td_date/start_date are wellsite local wall-clock time
  # (:naive_datetime, no timezone conversion). Drop the seconds and only show
  # a time at all when one was actually entered (pre-migration rows and any
  # date-only entry both land on exact midnight).
  defp fmt_datetime(nil), do: "—"

  defp fmt_datetime(%NaiveDateTime{} = ndt) do
    case NaiveDateTime.to_time(ndt) do
      ~T[00:00:00] -> Calendar.strftime(ndt, "%Y-%m-%d")
      _ -> Calendar.strftime(ndt, "%Y-%m-%d %H:%M")
    end
  end

  # Elevation value that may be a typed Decimal (report_data) or a raw number
  # (import_data welldata elevations).
  defp elev_m(nil), do: nil
  defp elev_m(%Decimal{} = d), do: "#{d |> Decimal.round(2) |> Decimal.to_string(:normal)} m"
  defp elev_m(n) when is_number(n), do: "#{:erlang.float_to_binary(n / 1, decimals: 1)} m"
  defp elev_m(_), do: nil

  # Coordinates/depths in plain positional notation — never "1.2e3". Erlang's
  # default float formatting flips to exponents past a certain magnitude, which
  # is unusable for a lat/long/easting readout. Keeps up to 10 decimals but
  # trims trailing zeros (:compact).
  defp fmt_coord(n) when is_float(n), do: :erlang.float_to_binary(n, [:compact, {:decimals, 10}])
  defp fmt_coord(n) when is_integer(n), do: Integer.to_string(n)
  defp fmt_coord(n), do: n

  defp fmt_num(nil), do: nil
  defp fmt_num(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 2)
  defp fmt_num(n) when is_integer(n), do: Integer.to_string(n)

  defp fmt_num(n) when is_binary(n) do
    case Float.parse(n) do
      {f, _} -> :erlang.float_to_binary(f, decimals: 2)
      :error -> n
    end
  end

  defp fmt_num(n), do: n

  defp coord_dir(_value, dir, _pos, _neg) when is_binary(dir) and dir != "" do
    String.first(dir)
  end

  defp coord_dir(value, _dir, pos, neg) when is_number(value) do
    if value < 0, do: neg, else: pos
  end

  defp coord_dir(_value, _dir, pos, _neg), do: pos
end
