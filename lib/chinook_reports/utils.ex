defmodule ChinookReports.Utils do
  @moduledoc """
  Project-wide utility functions. Group related helpers under headed sections
  as they're added; if a section grows large enough to stand on its own, lift
  it out into a dedicated module.
  """

  # ── Units ────────────────────────────────────────────────────────────────
  # Conversion and display helpers for physical units.
  # Canonical storage units:
  #   * depth — meters
  #   * angle — degrees
  # Add more dimensions here as they're needed.

  @feet_per_meter Decimal.new("3.28084")

  @doc """
  Convert a user-entered value into the canonical storage unit for its dimension.

      iex> ChinookReports.Utils.to_canonical(Decimal.new("2000"), :depth, "imperial")
      #Decimal<609.6000487...>
  """
  def to_canonical(%Decimal{} = value, :depth, "metric"), do: value

  def to_canonical(%Decimal{} = value, :depth, "imperial"),
    do: Decimal.div(value, @feet_per_meter)

  @doc """
  Convert a canonical (stored) value into the user's chosen display unit.

      iex> ChinookReports.Utils.from_canonical(Decimal.new("609.6"), :depth, "imperial")
      #Decimal<2000.0000...>
  """
  def from_canonical(%Decimal{} = value, :depth, "metric"), do: value

  def from_canonical(%Decimal{} = value, :depth, "imperial"),
    do: Decimal.mult(value, @feet_per_meter)

  @doc """
  The display suffix for a dimension under the given unit system.

      iex> ChinookReports.Utils.suffix(:depth, "imperial")
      "ft"
  """
  def suffix(:depth, "metric"), do: "m"
  def suffix(:depth, "imperial"), do: "ft"
end
