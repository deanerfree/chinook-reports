defmodule ChinookReportsWeb.FormationTopsLive do
  @moduledoc """
  The rich Formation Tops table (`import_data["tops"]`), with per-column-group
  editing while the report is active.

  The user edits one group at a time (its pencil). Prognosis takes an MD and a
  Subsea (the datum-stable geologic pick); Samples and MWD / Gamma take only the
  MD read at the wellsite. Everything else is derived by
  `ChinookReports.FormationTops` on save (and on any KB / survey change
  elsewhere): for Samples / MWD the TVD comes from the directional survey
  (interpolated where it has reached, extrapolated beyond — those rows are
  flagged) and Subsea is `KB − TVD`; for Prognosis the TVD is `KB − Subsea`.
  Isopach and Diff follow.

  `editable_fields/1` is the single source of truth for which columns a group's
  pick lives in.
  """
  use ChinookReportsWeb, :live_component

  alias ChinookReports.{FormationTops, Reports}
  alias ChinookReportsWeb.NumberFormat

  @groups ~w(prognosis samples mwd_gamma)
  @editable_groups ~w(prognosis samples mwd_gamma)
  @labels %{"prognosis" => "Prognosis", "samples" => "Samples", "mwd_gamma" => "MWD / Gamma"}
  @group_notes %{
    "prognosis" => "Enter the prognosed MD and Subsea (TVDSS — negative below sea level).",
    "samples" => "Enter the MD picked from cuttings at the wellsite.",
    "mwd_gamma" => "Enter the MD read from the MWD / gamma log."
  }

  @impl true
  def update(%{report: _report} = assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(:groups, @groups)
      |> assign_new(:editing, fn -> nil end)
      |> assign_new(:errors, fn -> [] end)
      |> assign_new(:pending_delete, fn -> nil end)

    {:ok, if(socket.assigns.editing, do: socket, else: load(socket))}
  end

  defp load(socket) do
    report = socket.assigns.report

    rows =
      case FormationTops.recompute_for_report(report) do
        %{"formations" => formations} -> formations
        _ -> []
      end

    socket
    |> assign(:rows, rows)
    |> assign(:survey_reach, FormationTops.survey_reach(report))
    |> assign(:kb, FormationTops.kb_elevation(report))
    |> assign(:errors, [])
    |> assign(:pending_delete, nil)
  end

  # ── events ────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("edit_group", %{"group" => g}, socket) when g in @editable_groups do
    {:noreply, assign(socket, editing: g, errors: [])}
  end

  # Escape fires "cancel" too; with the delete confirmation open it only
  # dismisses that, rather than throwing away the whole edit.
  def handle_event("cancel", _params, %{assigns: %{pending_delete: i}} = socket)
      when not is_nil(i) do
    {:noreply, assign(socket, pending_delete: nil)}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, load(assign(socket, editing: nil))}
  end

  def handle_event("validate", %{"tops" => params}, socket) do
    rows = merge_params(socket.assigns.rows, params)

    {:noreply,
     assign(socket, rows: preview(socket, rows), errors: validate(rows, socket.assigns.editing))}
  end

  def handle_event("add_row", _params, socket) do
    {:noreply, assign(socket, rows: socket.assigns.rows ++ [blank_row()])}
  end

  # The row menu sends the index via `JS.push(value: %{index: i})`, which arrives
  # as an integer; accept a string too (phx-value-* attributes are strings).
  def handle_event("ask_delete", %{"index" => i}, socket) when is_integer(i) do
    {:noreply, assign(socket, pending_delete: i)}
  end

  def handle_event("ask_delete", %{"index" => i}, socket) when is_binary(i) do
    {:noreply, assign(socket, pending_delete: String.to_integer(i))}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, pending_delete: nil)}
  end

  def handle_event("confirm_delete", _params, socket) do
    rows = List.delete_at(socket.assigns.rows, socket.assigns.pending_delete)

    {:noreply,
     assign(socket,
       rows: preview(socket, rows),
       pending_delete: nil,
       errors: validate(rows, socket.assigns.editing)
     )}
  end

  def handle_event("save", %{"tops" => params}, socket) do
    rows = merge_params(socket.assigns.rows, params)
    errors = validate(rows, socket.assigns.editing)

    if errors == [] do
      report = socket.assigns.report
      formations = rows |> Enum.map(&coerce_row/1) |> Enum.reject(&blank?/1)
      tops = FormationTops.recompute_for_report(report, formations: formations)

      case Reports.update_import_section(report, "tops", tops) do
        {:ok, updated} ->
          send(self(), {:tops_updated, updated})
          {:noreply, load(assign(socket, report: updated, editing: nil))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not save Formation Tops.")}
      end
    else
      {:noreply, assign(socket, rows: preview(socket, rows), errors: errors)}
    end
  end

  # ── build / validate rows ────────────────────────────────────────────────

  defp merge_params(rows, %{"rows" => row_params}) do
    row_params
    |> Enum.sort_by(fn {k, _} -> String.to_integer(k) end)
    |> Enum.map(fn {k, rp} ->
      base = Enum.at(rows, String.to_integer(k)) || blank_row()

      base = Map.put(base, "formation", Map.get(rp, "formation", base["formation"]))
      Enum.reduce(@editable_groups, base, &put_pick(&2, &1, rp))
    end)
  end

  defp merge_params(rows, _), do: rows

  # Pull the group's editable cells (MD, and Subsea for Prognosis) out of the submitted params.
  # A pick whose text comes back unchanged keeps its stored value, so the
  # at-most-2-decimals input text never rounds a saved pick.
  defp put_pick(row, group, rp) do
    Enum.reduce(editable_fields(group), row, fn field, acc ->
      put_cell(acc, group, field, get_in(rp, [group, field]))
    end)
  end

  defp put_cell(row, _group, _field, nil), do: row

  defp put_cell(row, group, field, raw) do
    if raw == pick_value(row, group, field), do: row, else: put_in(row, [group, field], raw)
  end

  # Recompute derived cells for a live preview (bad numbers just read "—").
  defp preview(socket, rows) do
    formations = Enum.map(rows, &coerce_row/1)

    case FormationTops.recompute_for_report(socket.assigns.report, formations: formations) do
      %{"formations" => fs} -> fs
      _ -> rows
    end
  end

  # errors: list of {row_index, group} for a bad pick in the group being edited
  defp validate(rows, group) when group in @editable_groups do
    rows
    |> Enum.with_index()
    |> Enum.flat_map(fn {row, i} ->
      bad? =
        Enum.any?(editable_fields(group), fn field ->
          parse_pick(field, get_in(row, [group, field])) == :error
        end)

      if bad?, do: [{i, group}], else: []
    end)
  end

  defp validate(_rows, _), do: []

  defp coerce_row(row) do
    row = Map.put(row, "formation", trim(row["formation"]))

    Enum.reduce(@editable_groups, row, fn g, acc ->
      Enum.reduce(editable_fields(g), acc, fn field, row ->
        case parse_pick(field, get_in(row, [g, field])) do
          {:ok, v} -> put_in(row, [g, field], v)
          :error -> row
        end
      end)
    end)
  end

  defp blank_row do
    %{"formation" => nil, "prognosis" => %{}, "samples" => %{}, "mwd_gamma" => %{}}
  end

  defp blank?(row) do
    is_nil(row["formation"]) and
      Enum.all?(@groups, fn g ->
        Enum.all?(editable_fields(g), fn f -> get_in(row, [g, f]) in [nil, ""] end)
      end)
  end

  # Parse a group's pick. MD must be a non-negative number; Subsea is a signed datum.
  defp parse_pick(field, raw) do
    case parse_number(raw) do
      {:ok, n} when is_number(n) and field == "md" and n < 0 -> :error
      other -> other
    end
  end

  defp parse_number(nil), do: {:ok, nil}
  defp parse_number(n) when is_number(n), do: {:ok, n / 1}

  defp parse_number(s) when is_binary(s) do
    case String.trim(s) do
      "" ->
        {:ok, nil}

      t ->
        case Float.parse(t) do
          {f, ""} -> {:ok, f}
          _ -> :error
        end
    end
  end

  defp parse_number(_), do: :error

  defp trim(nil), do: nil
  defp trim(s) when is_binary(s), do: ((t = String.trim(s)) != "" && t) || nil
  defp trim(other), do: other

  # ── view helpers ─────────────────────────────────────────────────────────

  defp group_label(g), do: @labels[g]
  defp group_note(g), do: Map.get(@group_notes, g, "")
  defp editable_group?(g), do: g in @editable_groups

  # The columns a group's pick is entered and stored in; every other cell is derived.
  # Prognosis carries an MD and a Subsea (the datum-stable pick TVD is `KB − Subsea`
  # from); Samples / MWD carry only the MD read at the wellsite.
  defp editable_fields("prognosis"), do: ~w(md subsea)
  defp editable_fields(_group), do: ~w(md)

  defp provisional_row?(row), do: FormationTops.provisional?(row)

  defp cell_editable?(_group, editing) when is_nil(editing), do: false
  defp cell_editable?(group, editing), do: group == editing

  # Is `field` one of `group`'s editable cells while it's being edited?
  defp cell_editable?(group, field, editing),
    do: cell_editable?(group, editing) and field in editable_fields(group)

  # Depths show at most two decimals (NumberFormat.up_to_2/1).
  defp fmt(nil), do: "—"
  defp fmt(""), do: "—"
  defp fmt(n) when is_number(n), do: NumberFormat.up_to_2(n)

  defp fmt(s) when is_binary(s) do
    case Float.parse(s) do
      {f, ""} -> NumberFormat.up_to_2(f)
      _ -> s
    end
  end

  # Current value of an editable cell, as an input-ready string.
  defp pick_value(row, group, field) do
    case get_in(row, [group, field]) do
      nil -> ""
      "" -> ""
      n when is_number(n) -> NumberFormat.up_to_2(n)
      s -> s
    end
  end

  defp diff_display(row) do
    case row["difference_m"] do
      d when is_number(d) -> "#{if d > 0, do: "+"}#{NumberFormat.up_to_2(d)}"
      _ -> "—"
    end
  end

  defp diff_class(row) do
    case row["difference_m"] do
      d when is_number(d) and d > 0 -> "text-amber-500"
      d when is_number(d) -> "text-primary"
      _ -> "text-muted"
    end
  end

  defp error?(errors, i, group), do: {i, group} in errors

  # ── render ───────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col">
      <%!-- The form wraps the clipped card so the Save bar can sit outside its
           overflow and stick to the bottom of the viewport. --%>
      <.form
        :let={_f}
        for={%{}}
        as={:tops}
        id={"tops-form-#{@id}"}
        phx-change="validate"
        phx-submit="save"
        phx-target={@myself}
      >
        <div class="relative flex flex-col overflow-hidden rounded-xl card-shadow">
          <div class="absolute left-0 top-0 h-full w-1 bg-primary"></div>

          <div class="flex flex-wrap items-center justify-between gap-x-3 gap-y-2 rounded-t-xl bg-linear-to-r from-primary to-secondary px-5 py-3">
            <h3 class="m-0 text-lg font-semibold text-on-primary">Formation Tops</h3>
            <div class="flex flex-wrap items-center gap-3 text-on-primary/90">
              <span :if={@survey_reach} class="text-[11px]">
                Last survey
                <span class="font-semibold">
                  {@survey_reach && NumberFormat.survey(@survey_reach)} m
                </span>
                MD
                <span
                  :if={Enum.count(@rows, &provisional_row?/1) > 0}
                  class="ml-1.5 rounded-full bg-amber-400/25 px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wide text-amber-100"
                >
                  {Enum.count(@rows, &provisional_row?/1)} extrapolated
                </span>
              </span>
              <button
                type="button"
                phx-click={JS.toggle(to: "#tops-info-#{@id}")}
                class="inline-flex items-center gap-1 rounded-md px-2 py-1 text-[11px] font-medium text-on-primary/90 cursor-pointer transition-opacity hover:opacity-100"
              >
                <.icon name="hero-information-circle" class="h-4 w-4" />Editing
              </button>
            </div>
          </div>

          <div
            id={"tops-info-#{@id}"}
            class="hidden border-b border-border-light bg-bg px-5 py-3.5 text-[12px] leading-relaxed text-text-secondary"
            phx-click-away={JS.hide()}
          >
            <p class="m-0 mb-1.5">
              Each group is edited one at a time — click its pencil.
              <span class="font-semibold text-text">Prognosis</span>
              takes an <span class="font-semibold text-text">MD</span>
              and a <span class="font-semibold text-text">Subsea</span>
              (TVDSS, negative below sea level); its TVD is KB elevation − Subsea.
            </p>
            <p class="m-0 mb-1.5">
              <span class="font-semibold text-text">Samples</span>
              and <span class="font-semibold text-text">MWD / Gamma</span>
              take the <span class="font-semibold text-text">MD</span>
              you picked (≥ 0); their TVD comes from the directional survey — interpolated where the
              survey has reached, extrapolated beyond it (those rows are highlighted and finalise once
              the survey passes that depth) — and Subsea = KB elevation − TVD.
            </p>
            <p class="m-0 mb-1.5">
              <span class="font-semibold text-text">Isopach</span>
              and <span class="font-semibold text-text">Diff</span>
              are always derived.
            </p>
            <p class="m-0">
              <span class="font-semibold text-text">KB elevation</span>
              ({fmt(@kb)} m) is edited in Well Data · Elevations.
            </p>
          </div>

          <div class="overflow-x-auto px-5 py-4">
            <table class="w-full border-collapse text-sm">
              <thead>
                <tr class="border-b border-border-light">
                  <th
                    rowspan="2"
                    class="py-2 pr-4 text-left text-xs font-semibold uppercase tracking-wider text-table-header-label"
                  >
                    Formation
                  </th>
                  <th
                    :for={g <- @groups}
                    colspan="4"
                    class="border-l border-border-light px-2 py-2 text-center text-xs font-semibold uppercase tracking-wider text-table-header-label"
                  >
                    <div class="inline-flex items-center gap-1.5">
                      {group_label(g)}
                      <button
                        :if={@editable and editable_group?(g)}
                        type="button"
                        phx-click="edit_group"
                        phx-value-group={g}
                        phx-target={@myself}
                        disabled={@editing not in [nil, g]}
                        aria-label={"Edit #{group_label(g)}"}
                        title={"Edit #{group_label(g)}"}
                        class={[
                          "inline-flex items-center gap-1 rounded-md border border-primary/40 bg-white",
                          "px-1.5 py-1 text-primary cursor-pointer transition-colors",
                          "hover:bg-primary hover:text-white hover:border-primary",
                          "disabled:cursor-default disabled:border-border disabled:bg-white disabled:text-muted disabled:opacity-40"
                        ]}
                      >
                        <.icon name="hero-pencil" class="h-3.5 w-3.5" />
                      </button>
                      <div :if={@editable and not editable_group?(g)} title="Set in the draft phase">
                        <.icon name="hero-lock-closed" class="h-3.5 w-3.5 text-white" />
                      </div>
                    </div>
                  </th>
                  <th
                    rowspan="2"
                    class="border-l border-border-light pl-2 py-2 text-center text-xs font-semibold uppercase tracking-wider text-table-header-label"
                  >
                    Diff (m)
                  </th>
                  <th :if={@editing} rowspan="2" class="w-8"></th>
                </tr>
                <tr class="border-b-2 border-border-light">
                  <%= for _g <- @groups do %>
                    <th
                      :for={l <- ~w(MD TVD Isopach Subsea)}
                      class={[
                        "px-2 py-1 text-right text-xs font-medium text-muted",
                        l == "MD" && "border-l border-border-light"
                      ]}
                    >
                      {l}
                    </th>
                  <% end %>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={{row, i} <- Enum.with_index(@rows)}
                  class={[
                    "border-b border-border-light transition-colors",
                    provisional_row?(row) && "bg-amber-50",
                    !provisional_row?(row) && "hover:bg-bg"
                  ]}
                >
                  <td class={[
                    "py-1.5 pr-4 font-medium text-text",
                    provisional_row?(row) && "border-l-2 border-amber-400"
                  ]}>
                    <%= if @editing do %>
                      <input
                        type="text"
                        name={"tops[rows][#{i}][formation]"}
                        value={row["formation"]}
                        placeholder="Formation"
                        phx-debounce="blur"
                        class="w-40 rounded border border-transparent bg-transparent px-2 py-1 hover:border-border-light focus:border-primary focus:bg-white focus:outline-none"
                      />
                    <% else %>
                      {row["formation"]}
                    <% end %>
                  </td>

                  <%= for g <- @groups do %>
                    <%= for f <- ~w(md tvd isopach subsea) do %>
                      <td class={[
                        "px-2 py-1.5 text-right tabular-nums text-text-secondary",
                        f == "md" && "border-l border-border-light"
                      ]}>
                        <%= if cell_editable?(g, f, @editing) do %>
                          <input
                            type="number"
                            step="any"
                            min={f == "md" && "0"}
                            inputmode="decimal"
                            phx-debounce="blur"
                            name={"tops[rows][#{i}][#{g}][#{f}]"}
                            value={pick_value(row, g, f)}
                            placeholder="—"
                            class={[
                              "w-20 rounded border bg-white px-2 py-1 text-right tabular-nums focus:outline-none",
                              error?(@errors, i, g) && "border-danger",
                              !error?(@errors, i, g) && "border-border-light focus:border-primary"
                            ]}
                          />
                        <% else %>
                          <span class={[f != "md" && "text-muted"]}>{fmt(get_in(row, [g, f]))}</span>
                        <% end %>
                      </td>
                    <% end %>
                  <% end %>

                  <td class={[
                    "border-l border-border-light pl-2 py-1.5 text-right font-medium tabular-nums",
                    diff_class(row)
                  ]}>
                    {diff_display(row)}
                  </td>

                  <td :if={@editing} class="px-1 text-center">
                    <div class="relative inline-block">
                      <button
                        type="button"
                        phx-click={JS.toggle(to: "#row-menu-#{@id}-#{i}")}
                        class="rounded p-1 text-muted hover:bg-bg hover:text-text"
                        title="Row actions"
                      >
                        <.icon name="hero-ellipsis-vertical" class="h-4 w-4" />
                      </button>
                      <div
                        id={"row-menu-#{@id}-#{i}"}
                        class="absolute right-0 z-10 mt-1 hidden w-44 rounded-lg border border-border bg-white p-1 shadow-lg"
                        phx-click-away={JS.hide()}
                      >
                        <button
                          type="button"
                          phx-click={
                            JS.hide(to: "#row-menu-#{@id}-#{i}")
                            |> JS.push("ask_delete", value: %{index: i}, target: @myself)
                          }
                          class="flex w-full items-center gap-2 rounded-md px-2.5 py-2 text-left text-[13px] text-danger hover:bg-danger/10"
                        >
                          <.icon name="hero-trash" class="h-4 w-4" /> Delete formation
                        </button>
                      </div>
                    </div>
                  </td>
                </tr>
                <tr :if={@rows == []}>
                  <td colspan="14" class="py-4 text-sm text-muted">No formation tops recorded.</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <.edit_actions
          :if={@editing}
          target={@myself}
          disabled={@errors != []}
          label={"Save #{group_label(@editing)}"}
        >
          <span class="rounded-full bg-primary px-2.5 py-1 text-[11px] font-bold uppercase tracking-wide text-on-primary">
            {group_label(@editing)}
          </span>
          <span class="text-xs text-text-secondary">{group_note(@editing)}</span>
          <button
            type="button"
            phx-click="add_row"
            phx-target={@myself}
            class="rounded border border-border px-3 py-1.5 text-xs font-medium text-copy-secondary hover:border-primary hover:text-primary"
          >
            + Add formation
          </button>
          <span :if={@errors != []} class="text-xs font-semibold text-danger">
            {length(@errors)} {if length(@errors) == 1, do: "row needs", else: "rows need"} a fix
            — every value must be a number, and MD ≥ 0
          </span>
        </.edit_actions>
      </.form>

      <div
        :if={@pending_delete != nil}
        class="fixed inset-0 z-50 flex items-center justify-center bg-zinc-900/50 p-4"
      >
        <div class="w-full max-w-md rounded-2xl bg-white p-6 shadow-xl">
          <div class="flex gap-3">
            <span class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-danger/15 text-danger">
              <.icon name="hero-exclamation-triangle" class="h-5 w-5" />
            </span>
            <div>
              <h4 class="m-0 mb-1 text-[15px] font-bold text-text">Delete this formation?</h4>
              <p class="m-0 text-[13px] leading-relaxed text-text-secondary">
                <%= if name = Enum.at(@rows, @pending_delete)["formation"] do %>
                  “{name}”
                <% else %>
                  This formation
                <% end %>
                and its Prognosis, Samples and MWD / Gamma values will be removed from the report.
                You can still cancel before saving.
              </p>
            </div>
          </div>
          <div class="mt-5 flex justify-end gap-2">
            <button type="button" phx-click="cancel_delete" phx-target={@myself} class="btn-secondary">
              Cancel
            </button>
            <button
              type="button"
              phx-click="confirm_delete"
              phx-target={@myself}
              class="rounded-full bg-danger px-5 py-2 text-sm font-bold text-white hover:brightness-95"
            >
              Delete formation
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
