defmodule ChinookReportsWeb.Icons do
  use Phoenix.Component

  @doc """
  Renders a link (chain) icon.

  ## Examples

      <.link_icon />
      <.link_icon class="w-5 h-5 text-blue-500" />
      <.link_icon class="w-8 h-8 text-gray-400 hover:text-gray-600" />
  """
  attr :class, :string, default: "w-5 h-5"
  attr :rest, :global

  def chevron_right_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="2"
      stroke="currentColor"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={@class}
      {@rest}
    >
      <polyline points="9 18 15 12 9 6" />
    </svg>
    """
  end
end
