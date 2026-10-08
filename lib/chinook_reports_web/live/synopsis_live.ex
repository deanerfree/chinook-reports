defmodule ChinookReportsWeb.SynopsisLive do
  @moduledoc """
  The Synopsis tab (`import_data["synopsis"]`), editable while the report is
  active.

  The three parts are lists of strings in the JSON, edited as plain text:

    * `well_summary` — paragraphs, separated by a blank line
    * `well_profile` — bullet points, one per line
    * `formation_evaluation` — one line per line, as extracted: the
      "<Quality> reservoir: <n>m (<p>%)" lines render as the evaluation table
      and anything after a `CONCLUSIONS` line as the Conclusions box

  Saves through `Reports.update_import_section/3` and notifies the parent with
  `{:import_updated, report, "Synopsis", "synopsis"}`.
  """
  use ChinookReportsWeb, :live_component

  alias ChinookReports.Reports

  @parts [
    {"well_summary", "Well Summary", :paragraphs, "Separate paragraphs with a blank line."},
    {"well_profile", "Well Profile", :lines, "One bullet point per line."},
    {"formation_evaluation", "Formation Evaluation", :lines,
     "One line per line. Lines like “Good reservoir: 198m (14.47%)” form the table; " <>
       "lines after a line reading CONCLUSIONS form the Conclusions box."}
  ]

  @impl true
  def update(%{report: _} = assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(:parts, @parts)
      |> assign_new(:editing, fn -> false end)

    {:ok, if(socket.assigns.editing, do: socket, else: load(socket))}
  end

  defp load(socket) do
    synopsis = synopsis(socket.assigns.report)

    values =
      Map.new(@parts, fn {key, _label, kind, _hint} -> {key, to_text(kind, synopsis[key])} end)

    assign(socket, synopsis: synopsis, values: values)
  end

  defp synopsis(report), do: (report.import_data || %{})["synopsis"] || %{}

  @impl true
  def handle_event("edit", _params, socket), do: {:noreply, assign(socket, editing: true)}

  def handle_event("cancel", _params, socket) do
    {:noreply, load(assign(socket, editing: false))}
  end

  def handle_event("validate", %{"synopsis" => params}, socket) do
    {:noreply, assign(socket, values: Map.merge(socket.assigns.values, params))}
  end

  def handle_event("save", %{"synopsis" => params}, socket) do
    report = socket.assigns.report
    values = Map.merge(socket.assigns.values, params)

    synopsis =
      Enum.reduce(@parts, synopsis(report), fn {key, _label, kind, _hint}, acc ->
        Map.put(acc, key, from_text(kind, values[key]))
      end)

    case Reports.update_import_section(report, "synopsis", synopsis) do
      {:ok, updated} ->
        send(self(), {:import_updated, updated, "Synopsis", "synopsis"})
        {:noreply, load(assign(socket, report: updated, editing: false))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not save Synopsis.")}
    end
  end

  defp to_text(_kind, nil), do: ""
  defp to_text(:paragraphs, list) when is_list(list), do: Enum.join(list, "\n\n")
  defp to_text(:lines, list) when is_list(list), do: Enum.join(list, "\n")
  defp to_text(_kind, s) when is_binary(s), do: s

  defp from_text(:paragraphs, text) do
    (text || "")
    |> String.split(~r/\R\s*\R/)
    |> Enum.map(&(&1 |> String.split(~r/\R/) |> Enum.map_join(" ", fn l -> String.trim(l) end)))
    |> Enum.reject(&(&1 == ""))
  end

  defp from_text(:lines, text) do
    (text || "")
    |> String.split(~r/\R/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <%= if @editing do %>
        <.form
          for={%{}}
          as={:synopsis}
          id={"#{@id}-form"}
          phx-change="validate"
          phx-submit="save"
          phx-target={@myself}
        >
          <.card_panel title="Synopsis">
            <div class="flex flex-col gap-5 px-5 py-4">
              <label :for={{key, label, kind, hint} <- @parts} class="flex flex-col gap-1">
                <span class="text-xs font-semibold uppercase tracking-wide text-copy-secondary">
                  {label}
                </span>
                <textarea
                  name={"synopsis[#{key}]"}
                  rows={if kind == :paragraphs, do: "12", else: "8"}
                  phx-debounce="blur"
                  class="w-full rounded border border-border bg-white px-3 py-2 text-sm leading-relaxed focus:border-primary focus:outline-none"
                >{@values[key]}</textarea>
                <span class="text-xs text-copy-secondary">{hint}</span>
              </label>
            </div>
          </.card_panel>
          <.edit_actions target={@myself} />
        </.form>
      <% else %>
        <%= if @synopsis == %{} and not @editable do %>
          <p class="text-sm text-muted">No synopsis recorded.</p>
        <% else %>
          <.synopsis_section synopsis={@synopsis} legs={@legs}>
            <:action :if={@editable}>
              <button
                type="button"
                phx-click="edit"
                phx-target={@myself}
                aria-label="Edit Synopsis"
                title="Edit Synopsis"
                class="inline-flex items-center gap-1.5 rounded-md px-2 py-1 text-xs font-medium cursor-pointer opacity-80 transition-opacity hover:opacity-100 text-on-primary"
              >
                <.icon name="hero-pencil" class="h-4 w-4" />
                <span>Edit</span>
              </button>
            </:action>
          </.synopsis_section>
        <% end %>
      <% end %>
    </div>
    """
  end
end
