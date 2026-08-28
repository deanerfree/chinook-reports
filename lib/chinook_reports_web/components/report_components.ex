defmodule ChinookReportsWeb.ReportComponents do
  use Phoenix.Component
  use Gettext, backend: ChinookReportsWeb.Gettext
  import ChinookReportsWeb.CoreComponents
  import LiveSvelte

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
        <.surveys_section rows={data.surveys} />
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
          <.well_summary_section report={@report} />
          <%= if @data do %>
            <.elevations_location_section report={@report} data={@data} />
            <.configuration_section data={@data} />
          <% end %>
          <%= if wd = @import["welldata"] do %>
            <.welldata_section report={wd} />
          <% end %>
        <% "formation_tops" -> %>
          <%= if tops = @import["tops"] do %>
            <.tops_section tops={tops} />
          <% end %>
          <%= if @data && @data.formation_tops != [] do %>
            <.formation_tops_section rows={@data.formation_tops} />
          <% end %>
        <% "reservoir" -> %>
          <%= if reservoir = @import["reservoir_data"] do %>
            <.reservoir_section reservoir={reservoir} />
          <% end %>
        <% "synopsis" -> %>
          <%= if synopsis = @import["synopsis"] do %>
            <.synopsis_section synopsis={synopsis} legs={@import["reservoir_data"] || []} />
          <% end %>
        <% "surveys" -> %>
          <.surveys_import_section legs={@import["reservoir_data"] || []} />
          <%= if @data && @data.surveys != [] do %>
            <.surveys_section rows={@data.surveys} />
          <% end %>
        <% "timing" -> %>
          <%= if wd = @import["welldata"] do %>
            <.well_timing_section report={wd} />
          <% end %>
        <% "hole_casing_mud_bits" -> %>
          <%= if wd = @import["welldata"] do %>
            <.hole_mud_casing_section report={wd} />
          <% end %>
          <%= if bits = @import["bits"] do %>
            <.bits_section bits={bits} />
          <% end %>
        <% "mud_log" -> %>
          <%= if mud = @import["mud_log"] do %>
            <.mud_section mud={mud} />
          <% end %>
        <% "daily_reports" -> %>
          <%= if daily = @import["daily"] do %>
            <.daily_section daily={daily} />
          <% end %>
        <% _ -> %>
          <p class="text-sm text-muted">Nothing to show here.</p>
      <% end %>
    </div>
    """
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

  attr :legs, :list, required: true

  defp surveys_import_section(assigns) do
    ~H"""
    <%= for leg <- @legs, points = get_in(leg, ["survey", "survey_points"]) || [], points != [] do %>
      <.table_panel title={"Directional Survey — #{leg["leg_name"] || "Leg"}"}>
        <.table id={"survey_points_#{leg["leg_name"]}"} rows={points}>
          <:col :let={p} label="MD (m)">{fmt_num(p["md"])}</:col>
          <:col :let={p} label="Inc (°)">{fmt_num(p["inclination_deg"])}</:col>
          <:col :let={p} label="Azi (°)">{fmt_num(p["azimuth_deg"])}</:col>
          <:col :let={p} label="TVD (m)">{fmt_num(p["tvd"])}</:col>
          <:col :let={p} label="VS (m)">{fmt_num(p["vertical_section"])}</:col>
          <:col :let={p} label="Subsea (m)">{fmt_num(p["subsea"])}</:col>
        </.table>
      </.table_panel>
    <% end %>
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

  defp synopsis_section(assigns) do
    ~H"""
    <.section_panel id="synopsis" title="Synopsis">
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
                      {"KB to Ground", "#{elev["kb_to_ground"]} m"},
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

  defp well_summary_section(assigns) do
    ~H"""
    <.section_panel id="well_summary" title="Well Summary">
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
          <.wfield label="Spud Date" value={@report.spud_date} />
          <.wfield label="Final T.D. Date" value={@report.final_td_date} />
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
                  {@report.latitude}m, {@report.longitude}m
                <% else %>
                  {@report.latitude}° N, {abs(@report.longitude)}° W
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

  defp elevations_location_section(assigns) do
    ~H"""
    <%= if has_any?(@data, [:gl_elevation, :kb_elevation, :kb_to_ground, :surface_coordinates, :surface_location, :bottom_location, :field_region]) do %>
      <.card_panel title="Elevations and Location">
        <div class="px-5 py-4 flex flex-col gap-4">
          <div class="grid grid-cols-3 gap-2">
            <%= for {label, val} <- [
                {"Ground Level", fmt_unit(@data.gl_elevation)},
                {"Kelly Bushing", fmt_unit(@data.kb_elevation)},
                {"KB to Ground", fmt_unit(@data.kb_to_ground)},
                {"Datum", @data.datum}
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

  defp configuration_section(assigns) do
    ~H"""
    <%= if has_any?(@data, [:classification, :license, :purpose, :substance, :terminating_zone]) do %>
      <.flat_card_panel title="Configuration">
        <div class="py-4 grid grid-cols-2 sm:grid-cols-3 gap-x-6 gap-y-3">
          <.wfield label="Classification" value={@data.classification} />
          <.wfield label="License" value={@data.license} />
          <.wfield label="Purpose" value={@data.purpose} />
          <.wfield label="Substance" value={@data.substance} />
          <.wfield label="Terminating Zone" value={@data.terminating_zone} />
        </div>
      </.flat_card_panel>
    <% end %>
    """
  end

  # ── Well Profile (report_data.profile_sections) ─────────────────────────

  defp profile_section(assigns) do
    ~H"""
    <%= if @rows != [] do %>
      <.table_panel title="Well Profile">
        <.table id="profile_sections_table" rows={@rows}>
          <:col :let={s} label="Section">{s.section}</:col>
          <:col :let={s} label="Start (m)">{fmt_decimal(s.start_depth)}</:col>
          <:col :let={s} label="End (m)">{fmt_decimal(s.end_depth)}</:col>
          <:col :let={s} label="Start Date">{s.start_date || "—"}</:col>
        </.table>
      </.table_panel>
    <% end %>
    """
  end

  # ── Formation Tops (report_data.formation_tops) ─────────────────────────

  defp formation_tops_section(assigns) do
    ~H"""
    <%= if @rows != [] do %>
      <.table_panel title="Formation Tops">
        <.table id="formation_tops_table" rows={@rows}>
          <:col :let={t} label="Formation">{t.formation}</:col>
          <:col :let={t} label="MD (m)">{fmt_decimal(t.md)}</:col>
          <:col :let={t} label="TVD (m)">{fmt_decimal(t.tvd)}</:col>
          <:col :let={t} label="Isopach (m)">{fmt_decimal(t.isopach)}</:col>
          <:col :let={t} label="Subsea (m)">{fmt_decimal(t.subsea)}</:col>
        </.table>
      </.table_panel>
    <% end %>
    """
  end

  # ── Directional Program (report_data.surveys) ────────────────────────────

  defp surveys_section(assigns) do
    ~H"""
    <%= if @rows != [] do %>
      <.table_panel title="Directional Surveys">
        <.table id="surveys_table" rows={@rows}>
          <:col :let={s} label="MD (m)">{fmt_decimal(s.md)}</:col>
          <:col :let={s} label="Inclination (°)">{fmt_decimal(s.inclination)}</:col>
          <:col :let={s} label="Azimuth (°)">{fmt_decimal(s.azimuth)}</:col>
        </.table>
      </.table_panel>
    <% end %>
    """
  end

  # ── Shared building blocks ────────────────────────────────────────────────

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :inner_block, required: true

  defp card_panel(assigns) do
    ~H"""
    <div class="card overflow-hidden">
      <div class="px-5 py-2.5">
        <h4 class="text-sm font-semibold uppercase tracking-wider text-table-header-label">
          {@title}
          <%= if @subtitle do %>
            <span class="font-normal normal-case ml-1.5 text-xs text-chinook-green-light">
              {@subtitle}
            </span>
          <% end %>
        </h4>
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp flat_card_panel(assigns) do
    ~H"""
    <div class="overflow-hidden">
      <div class="py-2.5">
        <h4 class="text-sm font-semibold uppercase tracking-wider text-table-header-label">
          {@title}
        </h4>
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp table_panel(assigns) do
    ~H"""
    <div class="data-table-container">
      <div class="py-2.5 w-full">
        <h4 class="text-sm font-semibold uppercase tracking-wider text-table-header-label">
          {@title}
        </h4>
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

  defp section_panel(assigns) do
    ~H"""
    <div id={"#{@id}"} class="flex flex-col rounded-xl card-shadow">
      <div class="flex flex-col relative rounded-xl overflow-hidden">
        <div class="absolute top-0 left-0 w-1 h-full bg-primary"></div>
        <div class="px-5 py-3 bg-linear-to-r from-primary to-secondary rounded-t-xl overflow-hidden">
          <h3 class="text-lg font-semibold text-on-primary">{@title}</h3>
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

  defp fmt_decimal(nil), do: "—"
  defp fmt_decimal(%Decimal{} = d), do: d |> Decimal.round(2) |> Decimal.to_string(:normal)

  defp fmt_unit(nil), do: nil
  defp fmt_unit(%Decimal{} = d), do: "#{d |> Decimal.round(2) |> Decimal.to_string(:normal)} m"

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
