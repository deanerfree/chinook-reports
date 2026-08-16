defmodule ChinookReportsWeb.ReportComponents do
  use Phoenix.Component
  use Gettext, backend: ChinookReportsWeb.Gettext
  import ChinookReportsWeb.CoreComponents
  import LiveSvelte

  def report_details(assigns) do
    IO.inspect(assigns.report, label: "Report in report_details component")

    ~H"""
    <.render_component report={@report} />
    """
  end

  # defp format_date(date) do
  #   # TODO: format date as needed
  #   date
  # end

  @sections [
    {"welldata", &__MODULE__.welldata_section/1},
    {"synopsis", &__MODULE__.synopsis_section/1},
    {"tops", &__MODULE__.tops_section/1},
    {"daily", &__MODULE__.daily_section/1},
    {"mud_log", &__MODULE__.mud_section/1},
    {"bits", &__MODULE__.bits_section/1},
    {"reservoir_data", &__MODULE__.reservoir_section/1}
  ]

  attr :report, :map, required: true

  @section_order Enum.map(@sections, fn {key, _} -> key end)

  def render_component(assigns) do
    assigns = assign(assigns, :section_order, @section_order)

    ~H"""
    <div class="flex flex-col gap-8">
      <%= for key <- @section_order, has_section?(@report, key) do %>
        <section class={key <> "_section"}>
          <.dynamic_section report={@report} section_key={key} />
        </section>
      <% end %>
    </div>
    """
  end

  defp has_section?(%{report_data: data}, key) when is_map(data) do
    case Map.get(data, key) do
      nil -> false
      [] -> false
      "" -> false
      map when map_size(map) == 0 -> false
      _ -> true
    end
  end

  # Fallback for non-map report_data or missing keys
  defp has_section?(_report, _key), do: false

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

  attr :report, :map, required: true
  attr :section_key, :string, required: true

  def dynamic_section(assigns) do
    ~H"""
    <%= case @section_key do %>
      <% "bits" -> %>
        <.bits_section bits={@report.report_data["bits"]} />
      <% "casing" -> %>
        <.casing_section casing={@report.report_data["casing"]} />
      <% "daily" -> %>
        <.daily_section daily={@report.report_data["daily"]} />
      <% "mud_log" -> %>
        <.mud_section mud={@report.report_data["mud_log"]} />
      <% "reservoir_data" -> %>
        <.reservoir_section reservoir={@report.report_data["reservoir_data"]} />
      <% "synopsis" -> %>
        <.synopsis_section
          synopsis={@report.report_data["synopsis"]}
          legs={@report.report_data["reservoir_data"] || []}
        />
      <% "tops" -> %>
        <.tops_section tops={@report.report_data["tops"]} />
      <% "welldata" -> %>
        <.welldata_section report={@report.report_data["welldata"]} />
    <% end %>
    """
  end

  defp bits_section(assigns) do
    # TODO: Add calculation for cumulative Drill time, average ROP.
    ~H"""
    <div id="bits-container" class="flex flex-col gap-4">
      <h3 class="text-lg font-semibold">Bits</h3>
      <%= for bit <- @bits do %>
        <div class="w-full flex flex-col gap-2">
          <div class="w-full flex flex-row gap-4">
            <p><strong>No:</strong> {bit["bit_number"]}</p>
            <p><strong>Type:</strong> {bit["type"]}</p>
            <p><strong>Make:</strong> {bit["make"]}</p>
            <p><strong>Size:</strong> {bit["size"]}</p>
          </div>
          <div class="w-full flex flex-row gap-4">
            <p><strong>Depth in:</strong> {bit["depth_in"]}</p>
            <p><strong>Depth out:</strong> {bit["depth_out"]}</p>
            <p><strong>Progress:</strong> {bit["progress"]}</p>
          </div>
          <div class="w-full flex flex-row gap-4">
            <p><strong>WOB:</strong> {bit["wob"]}</p>
            <p><strong>ROP:</strong> {bit["rop"]}</p>
            <p><strong>RPM:</strong> {bit["rpm"]}</p>
            <p><strong>Hours:</strong> {bit["hours"]}</p>
          </div>
          
    <!-- Add more fields as needed -->
        </div>
      <% end %>
    </div>
    """
  end

  defp casing_section(assigns) do
    ~H"""
    <div id="casing-container">
      <h3>Casing</h3>
      <pre><%= inspect(@casing) %></pre>
    </div>
    """
  end

  defp daily_section(assigns) do
    ~H"""
    <div id="daily-container">
      <h3 class="text-lg font-semibold">Daily Drilling Events</h3>
      <%= for event <- @daily do %>
        <%= if event["operations_summary"] != nil do %>
          <%!-- Skip entries without operations summary for now --%>
          <div class="w-full flex flex-col gap-4">
            <div class="w-full flex flex-col gap-2">
              <h4><strong>Operations Summary for {event["date"]}:</strong></h4>
              <div class="w-full flex flex-row gap-2">
                <span><strong>Depth:</strong> {event["depth"]}</span>
                <span><strong>Drilling Hours:</strong> {event["drilling_hours"]}hrs</span>
              </div>
              <span class="block p-2 rounded bg-bg">{event["operations_summary"]}</span>
            </div>
          </div>
        <% else %>
          <%!-- Skip entries without operations summary for now --%>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp mud_section(assigns) do
    ~H"""
    <.section_panel id="mud_log" title="Mud Log">
      <div class="py-4 overflow-x-auto">
        <.table id="mud_table" rows={@mud}>
          <:col :let={m} label="Date">{m["date"]}</:col>
          <:col :let={m} label="Depth (m)">{m["depth"]}</:col>
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
      <div class="py-4">
        <.svelte name="ProfileChart" props={%{legs: @reservoir}} />
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

  defp welldata_section(assigns) do
    ~H"""
    <.section_panel id="well_summary" title="Well Summary">
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
                    <%= if td["unit"] == "ft" do %>
                      {"feet"}
                    <% end %>
                  <% end %>
                </span>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <%!-- ── Objectives + Well Type + Elevations + Location ───── --%>

      <%!-- Left: Objectives + Well Type --%>
      <%!-- <div class="py-4 flex flex-col gap-4"> --%>
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
        <%!-- </div> --%>
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
                    <div class="rounded-md bg-bg">
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
                  <div class="rounded-md bg-bg">
                    <p class="text-xs mb-0.5 text-muted uppercase font-medium">Surface</p>
                    <p class="text-sm text-text">{@report["surface_location"]}</p>
                  </div>
                  <div class="rounded-md bg-bg">
                    <p class="text-xs mb-0.5 text-muted uppercase font-medium">Bottom</p>
                    <p class="text-sm text-text">{@report["bottom_location"]}</p>
                  </div>
                  <div class="rounded-md bg-bg">
                    <p class="text-xs mb-0.5 text-muted uppercase font-medium">Bottom Offset</p>
                    <p class="text-sm text-text">{loc["bottom_coordinates"]}</p>
                  </div>
                  <%= if coords do %>
                    <div class="rounded-md bg-bg col-span-2">
                      <p class="text-xs mb-0.5 text-muted uppercase font-medium">
                        Geographic Coordinates
                      </p>
                      <p class="text-sm font-mono text-text">
                        {coords["latitude"]}° N, {abs(coords["longitude"])}° W
                        <span class="text-xs font-sans font-normal text-muted ml-1">
                          {coords["datum"]}
                        </span>
                      </p>
                    </div>
                  <% end %>
                  <%= if grid do %>
                    <div class="rounded-md bg-bg col-span-3">
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

      <%!-- ── Hole Sizes / Mud / Casing ──────────────────────── --%>
      <div class="grid grid-cols-1 md:grid-cols-3 gap-5">
        <%= if holes = @report["hole_sizes"] do %>
          <.table_panel title="Hole Sizes">
            <.table id="hole_sizes_table" rows={holes}>
              <:col :let={h} label="Section">{String.capitalize(h["section"])}</:col>
              <:col :let={h} label="Ø (mm)">{h["bit_diameter"]}</:col>
              <:col :let={h} label="From">{h["from_depth"]}</:col>
              <:col :let={h} label="To (m)">{h["to_depth"]}</:col>
            </.table>
          </.table_panel>
        <% end %>

        <%= if mud = @report["mud"] do %>
          <.table_panel title="Mud">
            <.table id="welldata_mud_table" rows={mud}>
              <:col :let={m} label="Section">{String.capitalize(m["section"])}</:col>
              <:col :let={m} label="Type">{m["type"]}</:col>
              <:col :let={m} label="From">{m["from_depth"]}</:col>
              <:col :let={m} label="To (m)">{m["to_depth"]}</:col>
            </.table>
          </.table_panel>
        <% end %>

        <%= if casing = @report["casing_data"] do %>
          <.table_panel title="Casing">
            <.table id="casing_table" rows={casing}>
              <:col :let={c} label="Section">{c["section"]}</:col>
              <:col :let={c} label="Size (mm)">{c["size"]}</:col>
              <:col :let={c} label="Set At (m)">{c["set_at"]}</:col>
              <:col :let={c} label="Type">{c["type"]}</:col>
            </.table>
          </.table_panel>
        <% end %>
      </div>

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
          <.table id="well_profile_table" rows={profile}>
            <:col :let={s} label="Section">{s["section"]}</:col>
            <:col :let={s} label="Start">
              {get_in(s, ["start", "date"])}
              <span class="text-xs ml-1 text-muted">{get_in(s, ["start", "time"])}</span>
            </:col>
            <:col :let={s} label="End">
              {get_in(s, ["end", "date"])}
              <span class="text-xs ml-1 text-muted">{get_in(s, ["end", "time"])}</span>
            </:col>
            <:col :let={s} label="Length (m)">{s["length"]}</:col>
            <:col :let={s} label="Duration (days)">{s["duration_days"]}</:col>
          </.table>
        </.table_panel>
      <% end %>
    </.section_panel>
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
end
