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

  def field(assigns) do
    ~H"""
    <label class={["flex flex-col gap-1", @wide && "sm:col-span-2"]}>
      <span class="text-xs font-semibold uppercase tracking-wide text-copy-secondary">
        {@label}
      </span>
      <div class="flex items-stretch">
        <input
          type="text"
          name={@field.name}
          id={@field.id}
          value={Phoenix.HTML.Form.normalize_value("text", @field.value)}
          placeholder={@placeholder}
          class={[
            "w-full border bg-surface-card px-3 py-2 text-sm text-copy outline-none",
            "focus:ring-1",
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

  def select_field(assigns) do
    ~H"""
    <label class="flex flex-col gap-1">
      <span class="text-xs font-semibold uppercase tracking-wide text-copy-secondary">
        {@label}
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
    <%= case @spec[:input] do %>
      <% :select -> %>
        <.select_field
          field={@form[@spec.field]}
          label={display_label(@spec)}
          options={resolve_options(@spec[:options])}
        />
      <% _text -> %>
        <.field
          field={@form[@spec.field]}
          label={display_label(@spec)}
          placeholder={@spec[:placeholder]}
          unit={resolve_unit(@spec[:unit], @form)}
          wide={@spec[:wide] || false}
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
    doc: "list of column specs: %{key, label, placeholder?, unit?}"

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
                <input
                  type="text"
                  name={row[col.key].name}
                  value={Phoenix.HTML.Form.normalize_value("text", row[col.key].value)}
                  placeholder={col[:placeholder]}
                  class="w-full rounded border border-transparent bg-transparent px-2 py-1 outline-none hover:border-border focus:border-primary focus:bg-surface-card"
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

  defp display_label(%{field: field, label: label}) do
    if Report.required?(field), do: label <> " *", else: label
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
