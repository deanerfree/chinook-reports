defmodule ChinookReportsWeb.Stepper do
  @moduledoc """
  Horizontal progress bar for a multi-step form. Pure display — no events.

  Steps are passed in as a list of maps:
    [%{id: :identity, label: "Identity", optional: false}, ...]

  `current_step` is the atom id of the active step.
  """
  use Phoenix.Component

  attr :steps, :list, required: true
  attr :current_step, :atom, required: true

  def stepper(assigns) do
    assigns = assign(assigns, :current_index, current_index(assigns.steps, assigns.current_step))

    ~H"""
    <ol class="flex w-full items-start">
      <li
        :for={{step, index} <- Enum.with_index(@steps)}
        class="flex flex-1 flex-col items-center"
      >
        <%!-- Circle row: connectors hug flush against the circle so the line never breaks --%>
        <div class="flex w-full items-center">
          <div
            :if={index > 0}
            class={[
              "flex-1 h-1",
              index <= @current_index && "bg-primary",
              index > @current_index && "bg-border-light"
            ]}
          />
          <div
            :if={index == 0}
            class={[
              "flex-1 h-1 rounded-l",
              "bg-none"
            ]}
          />
          <div class={[
            "flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-xs font-semibold",
            circle_classes(index, @current_index)
          ]}>
            <button
              :if={index < @current_index}
              class="text-white cursor-pointer"
              phx-click="navigate_to_step"
              phx-value-step={step.id}
            >
              {index + 1}
            </button>
            <span :if={index >= @current_index}>{index + 1}</span>
          </div>
          <div
            :if={index < length(@steps) - 1}
            class={[
              "flex-1 h-1",
              index < @current_index && "bg-primary",
              index >= @current_index && "bg-border-light"
            ]}
          />
          <div
            :if={index == length(@steps) - 1}
            class={[
              "flex-1 h-1",
              "bg-none"
            ]}
          />
        </div>
        <%!-- Label row: drops below, can wrap freely --%>
        <div class="mt-2 flex flex-col items-center text-center px-1">
          <span class={[
            "text-xs font-medium leading-tight",
            index == @current_index && "text-primary",
            index < @current_index && "text-text-secondary",
            index > @current_index && "text-text-secondary"
          ]}>
            {step.label}
          </span>
          <span :if={step.optional} class="text-[10px] uppercase tracking-wide text-(--color-muted)">
            optional
          </span>
        </div>
      </li>
    </ol>
    """
  end

  defp current_index(steps, current_step) do
    Enum.find_index(steps, &(&1.id == current_step)) || 0
  end

  defp circle_classes(index, current_index) do
    cond do
      # Completed: filled primary, symbol in page-background color
      index < current_index ->
        "bg-primary text-text-secondary"

      # Active: outlined primary ring, primary text
      index == current_index ->
        "border-2 border-primary bg-[color:var(--color-bg-card)] text-primary"

      # Future: muted
      true ->
        "bg-[color:var(--color-border-light)] text-[color:var(--color-text-secondary)]"
    end
  end
end
