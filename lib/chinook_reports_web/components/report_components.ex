defmodule ChinookReportsWeb.ReportComponents do
  use Phoenix.Component
  use Gettext, backend: ChinookReportsWeb.Gettext
  import ChinookReportsWeb.CoreComponents

  def report_details(assigns) do
    IO.inspect(assigns.report, label: "Report in report_details component")

    ~H"""
    <div class="flex flex-col gap-2 mb-6">
      <p><strong>Well Name:</strong> <%= @report.well_name %></p>
      <p><strong>Unique Well ID:</strong> <%= @report.unique_well_id %></p>
      <p><strong>Operator:</strong> <%= @report.operator %></p>
      <p><strong>Spud Date:</strong> <%= format_date(@report.spud_date) %></p>
      <p><strong>Final TD Date:</strong> <%= format_date(@report.final_td_date) %></p>
      <p><strong>Target Formation:</strong> <%= @report.target_formation %></p>
      <p><strong>Country:</strong> <%= @report.country %></p>
    </div>
    <.render_component report={@report}  />
    """
  end

  defp format_date(date) do
    # TODO: format date as needed
    date
  end

  @sections [
    {"welldata", &__MODULE__.welldata_section/1},
    {"bits", &__MODULE__.bits_section/1},
    {"daily", &__MODULE__.daily_section/1},
    {"mud_log", &__MODULE__.mud_section/1},
    {"reservoir_data", &__MODULE__.reservoir_section/1},
    {"synopsis", &__MODULE__.synopsis_section/1},
    {"tops", &__MODULE__.tops_section/1}
  ]

  attr :report, :map, required: true

  @section_order Enum.map(@sections, fn {key, _} -> key end)

  def render_component(assigns) do
    assigns = assign(assigns, :section_order, @section_order)

    ~H"""
    <div class="flex flex-col gap-8 overflow-y-auto">
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

  defp any_section?(report) do
    Enum.any?(
      ["bits", "casing", "daily", "mud_log", "reservoir_data", "synopsis", "tops", "welldata"],
      &has_section?(report, &1)
    )
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
        <.synopsis_section synopsis={@report.report_data["synopsis"]} />
      <% "tops" -> %>
        <.tops_section tops={@report.report_data["tops"]} />
      <% "welldata" -> %>
        <.welldata_section report={@report} />
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
            <p><strong>No:</strong> <%= bit["bit_number"] %></p>
            <p><strong>Type:</strong> <%= bit["type"] %></p>
            <p><strong>Make:</strong> <%= bit["make"] %></p>
            <p><strong>Size:</strong> <%= bit["size"] %></p>
          </div>
          <div class="w-full flex flex-row gap-4">
            <p><strong>Depth in:</strong> <%= bit["depth_in"] %></p>
            <p><strong>Depth out:</strong> <%= bit["depth_out"] %></p>
            <p><strong>Progress:</strong> <%= bit["progress"] %></p>
          </div>
          <div class="w-full flex flex-row gap-4">
            <p><strong>WOB:</strong> <%= bit["wob"] %></p>
            <p><strong>ROP:</strong> <%= bit["rop"] %></p>
            <p><strong>RPM:</strong> <%= bit["rpm"] %></p>
            <p><strong>Hours:</strong> <%= bit["hours"] %></p>
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
            <h4><strong>Operations Summary for <%= event["date"] %>:</strong></h4>
            <div class="w-full flex flex-row gap-2">
              <span><strong>Depth:</strong> <%= event["depth"] %></span>
              <span><strong>Drilling Hours:</strong> <%= event["drilling_hours"] %>hrs</span>
            </div>
            <span class="block bg-gray-100 p-2 rounded"><%= event["operations_summary"] %></span>
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
    grouped =
      assigns.mud
      |> Enum.group_by(& &1["date"])
      |> Enum.sort_by(fn {date, _entries} -> date end)

    assigns = assign(assigns, :grouped, grouped)

    ~H"""
    <div id="mud-container">
      <h3 class="text-lg font-semibold">Mud Log</h3>
      <div class="w-full flex flex-col gap-6">
        <%= for {date, entries} <- @grouped do %>
          <div class="w-full flex flex-col gap-2">
            <h4 class="font-semibold"><%= date %></h4>
            <.table id={"mud_table_#{date}"} rows={entries}>
              <:col :let={entry} label="Depth">{entry["depth"]}</:col>
              <:col :let={entry} label="Density">{entry["density"]}</:col>
              <:col :let={entry} label="Mud Type">{entry["mud_type"]}</:col>
              <:col :let={entry} label="pH">{entry["pH"]}</:col>
              <:col :let={entry} label="WL">{entry["wl"]}</:col>
              <:col :let={entry} label="Viscosity">{entry["viscosity"]}</:col>
              <:col :let={entry} label="Remarks">{entry["remarks"]}</:col>
            </.table>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp reservoir_section(assigns) do
    ~H"""
    <div id="reservoir-container">
      <h3>Reservoir Data</h3>
      <pre><%= inspect(@reservoir) %></pre>
    </div>
    """
  end

  defp synopsis_section(assigns) do
    ~H"""
    <div id="synopsis-container">
      <h3 class="text-lg font-semibold">Synopsis</h3>
      <div class="w-full bg-gray-100 p-4 rounded">
      <%!-- <pre><%= inspect(@synopsis) %></pre> --%>
        <%= for {key, value} <- @synopsis do %>
          <div class="w-full flex flex-row gap-2">
            <%= if key == "formation_evaluation" do %>
              <div class="w-full flex flex-col gap-2">
                <h4><strong>Formation Evaluation:</strong></h4>
                <%= for val <- value do %>
                  <span><%= val %></span>
                <% end %>
              </div>
            <% end %>
            <%= if key == "well_profile" do %>
              <span><strong>Well Profile:</strong> <%= value %></span>
            <% end %>
            <%= if key == "well_summary" do %>
              <span><strong>Well Summary:</strong> <%= value %></span>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp tops_section(assigns) do
    ~H"""
    <div id="tops-container">
      <h3>Tops</h3>
      <pre><%= inspect(@tops) %></pre>
    </div>
    """
  end

  defp welldata_section(assigns) do
    ~H"""
    <div id="welldata-container">
      <h3>Welldata</h3>
      <pre><%= inspect(@report.report_data["welldata"]) %></pre>
    </div>
    """
  end

  defp field(assigns) do
    ~H"""
    <%= if @value != nil do %>
      <span><%= @label %>: <%= @value %></span>
    <% end %>
    """
  end
end
