defmodule ChinookReportsWeb.ReportFormComponents do
  @moduledoc """
  Form building blocks for the report-setup form. Styled with the Chinook
  design tokens (semantic colors, `.card`, `.btn-*` classes) so dark mode
  and palette changes propagate automatically.
  """
  use Phoenix.Component
  alias ChinookReports.Reports.Report

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :placeholder, :string, default: nil
  attr :unit, :string, default: nil
  attr :wide, :boolean, default: false
  attr :required, :boolean, default: false, doc: "appends a * to the label"

  attr :type, :string,
    default: "text",
    doc: ~s(input type; use "date" for a native calendar picker)

  attr :rest, :global,
    include: ~w(pattern title inputmode autocomplete),
    doc: "extra input attributes, e.g. `pattern` for a browser-side format check"

  def field(assigns) do
    ~H"""
    <label class={["flex flex-col gap-1", @wide && "sm:col-span-2"]}>
      <span class="text-xs font-semibold uppercase tracking-wide text-copy-secondary">
        {@label}{if @required, do: " *"}
      </span>
      <div class="flex items-stretch">
        <input
          type={@type}
          name={@field.name}
          id={@field.id}
          value={format_value(@field.value)}
          placeholder={@placeholder}
          {@rest}
          class={[
            "w-full border bg-surface-card px-3 py-2 text-sm text-copy outline-none",
            "focus:ring-1 scheme-light dark:scheme-dark",
            @unit && "rounded-l",
            !@unit && "rounded",
            @field.errors == [] && "border-border focus:border-primary focus:ring-primary",
            @field.errors != [] && "border-danger focus:border-danger focus:ring-danger"
          ]}
        />
        <span
          :if={@unit}
          class="flex items-center rounded-r border border-l-0 border-border bg-surface px-2 text-xs font-medium text-copy-secondary"
        >
          {@unit}
        </span>
      </div>
      <span :for={msg <- field_errors(@field)} class="text-xs text-danger">
        {msg}
      </span>
    </label>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :options, :list, required: true
  attr :required, :boolean, default: false, doc: "appends a * to the label"

  def select_field(assigns) do
    ~H"""
    <label class="flex flex-col gap-1">
      <span class="text-xs font-semibold uppercase tracking-wide text-copy-secondary">
        {@label}{if @required, do: " *"}
      </span>
      <select
        name={@field.name}
        id={@field.id}
        class={[
          "w-full rounded border bg-surface-card px-3 py-2 text-sm text-copy focus:ring-1 outline-none",
          @field.errors == [] && "border-border focus:border-primary focus:ring-primary",
          @field.errors != [] && "border-danger focus:border-danger focus:ring-danger"
        ]}
      >
        <%!-- Without this, when @field.value matches none of @options (nothing
        chosen yet), the browser silently displays — and later submits — the
        first real option as if it had been picked. --%>
        <option value="" selected={@field.value in [nil, ""]}></option>
        <option
          :for={opt <- @options}
          value={opt}
          selected={to_string(@field.value) == opt}
        >
          {opt}
        </option>
      </select>
      <span :for={msg <- field_errors(@field)} class="text-xs text-danger">
        {msg}
      </span>
    </label>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :wide, :boolean, default: false

  @doc """
  A date input and a time input side by side for a single :naive_datetime
  field, instead of one combined `datetime-local` control. Each writes to its
  own param — "<field>_date" / "<field>_time" — since there's no native input
  that splits a value across two fields; `Report.changeset/2` stitches the
  pair back into one ISO datetime string before casting.
  """
  def datetime_field(assigns) do
    ~H"""
    <div class={["flex flex-col gap-1", @wide && "sm:col-span-2"]}>
      <span class="text-xs font-semibold uppercase tracking-wide text-copy-secondary">
        {@label}
      </span>
      <div class="flex gap-2">
        <input
          type="date"
          name={compound_name(@field.name, "date")}
          id={"#{@field.id}_date"}
          value={date_part(@field.value)}
          class={datetime_input_class(@field)}
        />
        <input
          type="time"
          name={compound_name(@field.name, "time")}
          id={"#{@field.id}_time"}
          value={time_part(@field.value)}
          class={datetime_input_class(@field)}
        />
      </div>
      <span :for={msg <- field_errors(@field)} class="text-xs text-danger">
        {msg}
      </span>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :inner_block, required: true

  def section_card(assigns) do
    ~H"""
    <section class="card mb-6">
      <header class="border-b border-light px-5 py-3">
        <h3 class="text-base! font-semibold! text-copy!">{@title}</h3>
        <span class="accent-bar my-2!"></span>
        <p :if={@subtitle} class="text-xs text-copy-secondary">{@subtitle}</p>
      </header>
      <div class="p-5">{render_slot(@inner_block)}</div>
    </section>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :spec, :map, required: true

  def report_field(assigns) do
    ~H"""
    <%= cond do %>
      <% @spec[:input] == :select -> %>
        <.select_field
          field={@form[@spec.field]}
          label={display_label(@spec)}
          options={resolve_options(@spec[:options])}
        />
      <% @spec[:type] == :datetime -> %>
        <.datetime_field
          field={@form[@spec.field]}
          label={display_label(@spec)}
          wide={@spec[:wide] || false}
        />
      <% true -> %>
        <.field
          field={@form[@spec.field]}
          label={display_label(@spec)}
          type={input_type(@spec[:type])}
          placeholder={@spec[:placeholder]}
          unit={resolve_unit(@spec[:unit], @form)}
          wide={@spec[:wide] || false}
          phx-hook={@spec[:mask] == :uwi && "UWIMaskHook"}
          data-uwi-country={@spec[:mask] == :uwi && @form[:country].value}
        />
    <% end %>
    """
  end

  attr :form, Phoenix.HTML.Form,
    required: true,
    doc: "the parent sub-form scoped to report_data"

  attr :list, :atom,
    required: true,
    doc: "the embeds_many field name, e.g. :formation_tops"

  attr :columns, :list,
    required: true,
    doc:
      "list of column specs: %{key, label, placeholder?, unit?, computed?} — a `computed` column is read-only"

  attr :hint, :string,
    default: nil,
    doc: "shown above an empty table; useful for 'add your first row' prompts"

  def editable_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <p :if={@hint} class="mb-3 text-xs text-copy-secondary">{@hint}</p>

      <table class="w-full border-collapse text-sm">
        <thead>
          <tr>
            <th
              :for={col <- @columns}
              class="border-b border-light px-2 py-2 text-left text-xs font-semibold uppercase tracking-wide text-copy-secondary"
            >
              {col.label}<span :if={col[:unit]} class="text-muted"> ({col.unit})</span>
            </th>
            <th class="border-b border-light px-2 py-2"></th>
          </tr>
        </thead>

        <tbody>
          <.inputs_for :let={row} field={@form[@list]}>
            <tr class="hover:bg-surface">
              <td :for={col <- @columns} class="border-b border-light px-1 py-1">
                <div :if={col[:type] == :datetime} class="flex gap-1">
                  <input
                    type="date"
                    name={compound_name(row[col.key].name, "date")}
                    value={date_part(row[col.key].value)}
                    class={table_cell_input_class()}
                  />
                  <input
                    type="time"
                    name={compound_name(row[col.key].name, "time")}
                    value={time_part(row[col.key].value)}
                    class={table_cell_input_class()}
                  />
                </div>
                <input
                  :if={col[:type] != :datetime}
                  type={input_type(col[:type])}
                  name={row[col.key].name}
                  value={format_value(row[col.key].value)}
                  placeholder={col[:placeholder]}
                  readonly={col[:computed]}
                  tabindex={col[:computed] && "-1"}
                  title={col[:computed] && "Calculated"}
                  class={[table_cell_input_class(), col[:computed] && "text-muted"]}
                />
              </td>
              <td class="border-b border-light px-1 py-1 text-center">
                <button
                  type="button"
                  phx-click="remove_row"
                  phx-value-list={@list}
                  phx-value-index={row.index}
                  class="rounded px-2 py-1 text-xs text-copy-secondary hover:bg-danger/10 hover:text-danger"
                  title="Remove row"
                >
                  ✕
                </button>
              </td>
            </tr>
          </.inputs_for>
        </tbody>
      </table>

      <button
        type="button"
        phx-click="add_row"
        phx-value-list={@list}
        class="mt-3 rounded border border-border px-3 py-1.5 text-xs font-medium text-copy-secondary hover:border-primary hover:text-primary"
      >
        + Add row
      </button>
    </div>
    """
  end

  @doc """
  Drop target for a directional plan file over the Directional Program table.
  Must sit inside the form (the upload rides its `phx-change`); see
  `ChinookReportsWeb.PlanUpload`.
  """
  attr :upload, Phoenix.LiveView.UploadConfig, required: true
  attr :importing, :string, default: nil, doc: "name of the file being read, while it is"

  attr :tops, :list,
    default: nil,
    doc: "the read plan's formation tops (`@plan_tops`), shown as an import prompt"

  attr :tops_note, :string, default: nil, doc: "where imported tops go, under the prompt"

  attr :hint, :string,
    default:
      "COMPASS PDF, CSV or TXT. Replaces the stations below; nothing is saved until you save.",
    doc: "what a dropped plan does, under the prompt"

  attr :id, :string, default: nil

  def plan_drop_zone(assigns) do
    ~H"""
    <div
      id={@id}
      class="mb-4 rounded-lg border-2 border-dashed border-border px-4 py-5 text-center transition-colors hover:border-muted [&.phx-drop-target-active]:border-primary [&.phx-drop-target-active]:bg-primary/5"
      phx-drop-target={@upload.ref}
    >
      <.live_file_input upload={@upload} class="hidden" />
      <%= if @importing do %>
        <div class="flex items-center justify-center gap-2 text-sm text-primary">
          <div class="h-4 w-4 shrink-0 rounded-full border-2 border-primary border-t-transparent animate-spin">
          </div>
          Reading {@importing}…
        </div>
      <% else %>
        <p class="text-sm font-medium text-copy">
          Drop a directional plan here, or
          <label
            for={@upload.ref}
            class="cursor-pointer text-primary hover:text-primary-hover underline"
          >
            browse
          </label>
        </p>
        <p class="mt-1 text-xs text-copy-secondary">{@hint}</p>
      <% end %>

      <div
        :if={@tops && !@importing}
        id="plan-tops-prompt"
        class="mt-4 rounded-md border border-border bg-bg px-4 py-3 text-left"
      >
        <p class="text-sm font-medium text-copy">
          This plan also lists {length(@tops)} formation {if length(@tops) == 1,
            do: "top",
            else: "tops"}. Import them into Formation Tops?
        </p>
        <p :if={@tops_note} class="mt-1 text-xs text-copy-secondary">{@tops_note}</p>
        <div class="mt-3 flex gap-2">
          <button type="button" phx-click="import_plan_tops" class="btn-primary">
            Import tops
          </button>
          <button type="button" phx-click="skip_plan_tops" class="btn-secondary">
            Skip
          </button>
        </div>
      </div>

      <p
        :for={
          err <- upload_errors(@upload) ++ Enum.flat_map(@upload.entries, &upload_errors(@upload, &1))
        }
        class="mt-2 text-xs text-danger"
      >
        {plan_upload_error(err)}
      </p>
    </div>
    """
  end

  defp plan_upload_error(:too_large), do: "That file is too large (max 25 MB)."
  defp plan_upload_error(:not_accepted), do: "Use a .pdf, .csv or .txt plan file."
  defp plan_upload_error(:too_many_files), do: "Drop one plan file at a time."
  defp plan_upload_error(_), do: "Upload failed."

  defp display_label(%{field: field, label: label}) do
    if Report.required?(field), do: label <> " *", else: label
  end

  # Render a form field's value for a text input.
  #
  # Floats are formatted in plain positional notation so stored values like
  # 1200.0 show as "1200.0" and never "1.2e3" — Erlang's default float
  # formatting (and Float.to_string/1) switches to exponents past a certain
  # magnitude, which is useless for coordinates and depths. Strings (the raw
  # text a user is mid-edit on) and nil pass straight through unchanged.
  defp format_value(value) when is_float(value) do
    :erlang.float_to_binary(value, [:compact, {:decimals, 10}])
  end

  # A stored Date must reach a `type="date"` input as an ISO `yyyy-mm-dd`
  # string or the browser drops it and shows an empty picker.
  defp format_value(%Date{} = date), do: Date.to_iso8601(date)

  defp format_value(value), do: Phoenix.HTML.Form.normalize_value("text", value)

  # Field/column specs carry an optional `:type`; `:date` swaps in a native
  # calendar picker with a guaranteed ISO value instead of the default
  # free-text box. `:datetime` fields don't reach this — see report_field/1
  # and editable_table/1, which route them to .datetime_field's split
  # date/time inputs instead.
  defp input_type(:date), do: "date"
  defp input_type(_), do: "text"

  # spud_date/final_td_date/profile_sections.start_date render as a date
  # input and a time input rather than one combined `datetime-local` control
  # (no native input splits a value across two fields). Turn
  # "report[spud_date]" into "report[spud_date_date]" / "report[spud_date_time]"
  # so each half gets its own param; Report.changeset/2 stitches the pair
  # back into one ISO datetime string before casting.
  defp compound_name(field_name, suffix),
    do: String.replace_trailing(field_name, "]", "_#{suffix}]")

  defp date_part(%NaiveDateTime{} = ndt), do: ndt |> NaiveDateTime.to_date() |> Date.to_iso8601()
  defp date_part(%Date{} = date), do: Date.to_iso8601(date)
  defp date_part(_), do: nil

  # A stored midnight is indistinguishable from "no time was ever entered"
  # (see Report.changeset/2's default when the time input is left blank), so
  # leave the time input empty rather than show a misleading 00:00 on every
  # date-only record.
  defp time_part(%NaiveDateTime{} = ndt) do
    case NaiveDateTime.to_time(ndt) do
      ~T[00:00:00] -> nil
      time -> Calendar.strftime(time, "%H:%M")
    end
  end

  defp time_part(_), do: nil

  defp datetime_input_class(%Phoenix.HTML.FormField{errors: errors}) do
    [
      "w-full rounded border bg-surface-card px-3 py-2 text-sm text-copy outline-none",
      "focus:ring-1 [color-scheme:light] dark:[color-scheme:dark]",
      errors == [] && "border-border focus:border-primary focus:ring-primary",
      errors != [] && "border-danger focus:border-danger focus:ring-danger"
    ]
  end

  defp table_cell_input_class do
    "w-full rounded border border-transparent bg-transparent px-2 py-1 outline-none hover:border-border focus:border-primary focus:bg-surface-card [color-scheme:light] dark:[color-scheme:dark]"
  end

  defp field_errors(%Phoenix.HTML.FormField{errors: errors}) do
    Enum.map(errors, fn {msg, _opts} -> msg end)
  end

  # Unit can be:
  #   - a string like "°N"     → pass through
  #   - the atom :depth         → resolve via the form's :units field
  #   - nil                     → no unit suffix
  defp resolve_unit(nil, _form), do: nil
  # static for now; dynamic in 5b-v
  defp resolve_unit(:depth, _form), do: "m"
  defp resolve_unit(unit, _form) when is_binary(unit), do: unit

  # Options can be a literal list, or a 0-arity function we call at render time.
  defp resolve_options(opts) when is_list(opts), do: opts
  defp resolve_options(opts) when is_function(opts, 0), do: opts.()
end
