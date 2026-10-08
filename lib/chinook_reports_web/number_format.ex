defmodule ChinookReportsWeb.NumberFormat do
  @moduledoc """
  How the report page prints a number: at most two decimal places, without
  padding (`124.93684` → `"124.94"`, `3.5` → `"3.5"`, `1979.0` → `"1979"`).

  Display only — stored values keep the extractor's full precision. The page's
  editors pre-fill inputs with this text and keep a cell's stored value when
  its text comes back unchanged, so rounding here never rewrites data.

  Tables whose columns read better aligned use a fixed two decimals instead
  (`"375.00"`); either way nothing shows more than two.

  Two kinds of value are exempt, because rounding them to centimetres would
  misstate them: geographic coordinates (0.01° of latitude is ~1 km) are shown
  as stored, and directional-survey values use `survey/1` — up to 5 decimals,
  the extractor's own precision, which hides only the float noise of computed
  stations (`11.15998363474584` → `"11.15998"`).
  """

  @survey_places 5

  @doc "At most two decimals: `124.93684` → `\"124.94\"`, integers as-is."
  @spec up_to_2(number() | Decimal.t()) :: String.t()
  def up_to_2(n), do: up_to(n, 2)

  @doc "A directional-survey value, at the survey's own precision (up to 5 decimals)."
  @spec survey(number() | Decimal.t()) :: String.t()
  def survey(n), do: up_to(n, @survey_places)

  @doc "At most `places` decimals, without padding."
  @spec up_to(number() | Decimal.t(), non_neg_integer()) :: String.t()
  def up_to(n, _places) when is_integer(n), do: Integer.to_string(n)

  # `+ 0.0` turns a rounded -0.0 into 0.0; a whole number drops its ".0"
  # (1979.0 → "1979"), so nothing shows a decimal that carries no information.
  def up_to(n, places) when is_float(n) do
    (Float.round(n, places) + 0.0)
    |> :erlang.float_to_binary([:compact, decimals: places])
    |> String.trim_trailing(".0")
  end

  def up_to(%Decimal{} = d, places),
    do: d |> Decimal.round(places) |> Decimal.normalize() |> Decimal.to_string(:normal)
end
