defmodule ChinookReportsWeb.Stepper do
  @moduledoc """
  Horizontal progress bar for a multi-step form. Pure display — no events.

  Steps are passed in as a list of maps:
    [%{id: :identity, label: "Identity", optional: false}, ...]

  `current_step` is the atom id of the active step. A step listed in
  `completed` has all its mandatory fields filled: its circle and the
  connector leaving it are drawn solid. Everything else is muted grey.
  """
  use Phoenix.Component

  attr :steps, :list, required: true
  attr :current_step, :atom, required: true
  attr :unlocked, :list, default: [], doc: "step ids reachable by clicking ahead of current_step"

  attr :completed, :list,
    default: [],
    doc: "step ids whose mandatory fields are all filled"

  def stepper(assigns) do
    current_index = current_index(assigns.steps, assigns.current_step)

    rows =
      assigns.steps
      |> Enum.with_index()
      |> Enum.map(fn {step, index} ->
        %{
          step: step,
          index: index,
          clickable: clickable?(index, current_index, step.id, assigns.unlocked),
          completed: step.id in assigns.completed
        }
      end)
      |> Enum.map_reduce(false, fn row, prev_completed ->
        {Map.put(row, :prev_completed, prev_completed), row.completed}
      end)
      |> elem(0)

    assigns = assign(assigns, current_index: current_index, rows: rows)

    ~H"""
    <ol class="flex w-full items-start">
      <li
        :for={
          %{
            step: step,
            index: index,
            clickable: clickable,
            completed: completed,
            prev_completed: prev_completed
          } <- @rows
        }
        class="flex flex-1 flex-col items-center"
      >
        <%!-- Circle row: connectors hug flush against the circle so the line never breaks --%>
        <div class="flex w-full items-center">
          <div
            :if={index > 0}
            class={["flex-1 h-0 border-t-2", line_classes(prev_completed)]}
          />
          <div
            :if={index == 0}
            class={[
              "flex-1 h-1 rounded-l",
              "bg-none"
            ]}
          />
          <button
            :if={clickable}
            type="button"
            class={[
              "flex h-9 w-9 shrink-0 cursor-pointer items-center justify-center rounded-full text-xs font-semibold",
              circle_classes(completed, index == @current_index, clickable)
            ]}
            phx-click="navigate_to_step"
            phx-value-step={step.id}
          >
            {index + 1}
          </button>
          <div
            :if={!clickable}
            class={[
              "flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-xs font-semibold",
              circle_classes(completed, index == @current_index, clickable)
            ]}
          >
            {index + 1}
          </div>
          <div
            :if={index < length(@steps) - 1}
            class={["flex-1 h-0 border-t-2", line_classes(completed)]}
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
            if(completed or index == @current_index, do: "text-primary", else: "text-text-secondary")
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

  defp clickable?(index, current_index, step_id, unlocked) do
    index != current_index and (index < current_index or step_id in unlocked)
  end

  # The connector leaving a step is solid once that step is complete, and
  # plain muted grey until then. Nothing in between.
  defp line_classes(true), do: "border-primary"
  defp line_classes(false), do: "border-border-light"

  defp circle_classes(completed, active, clickable) do
    cond do
      # Active: outlined primary ring so "you are here" always reads, even
      # once the step is complete.
      active ->
        "border-2 border-primary bg-[color:var(--color-bg-white)] text-primary"

      # Completed: filled primary, symbol in white
      completed ->
        "bg-primary text-white"

      # Reachable but not yet complete: primary ring on the muted background —
      # "you can jump here", distinct from "done" (solid fill) and "locked".
      clickable ->
        "border-2 cursor-pointer border-primary text-primary bg-[color:var(--color-border-light)] hover:bg-[color:var(--color-bg-card)]"

      # Locked: muted, no affordance
      true ->
        "bg-[color:var(--color-border-light)] text-[color:var(--color-text-secondary)]"
    end
  end
end
