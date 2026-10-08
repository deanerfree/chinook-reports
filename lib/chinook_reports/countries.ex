defmodule ChinookReports.Countries do
  @moduledoc """
  The countries a report can be filed under — the single list behind every
  Country dropdown and the `Report` changeset's inclusion check. Import this
  module wherever the list is needed rather than repeating it.
  """

  @countries [
    "Canada",
    "United States",
    "Mexico",
    "Algeria",
    "Australia",
    "Romania",
    "Colombia"
  ]

  @doc "Every supported country, in dropdown order."
  @spec all() :: [String.t()]
  def all, do: @countries

  @doc "True when `country` is one of the supported countries."
  @spec member?(term()) :: boolean()
  def member?(country), do: country in @countries
end
