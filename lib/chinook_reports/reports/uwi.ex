defmodule ChinookReports.Reports.UWI do
  @moduledoc """
  Format check for a well's Unique Well Identifier.

  Only Canadian UWIs are checked so far, in their two main survey systems:

    * DLS (Dominion Land Survey, survey code `1`), e.g. `100/16-36-046-23W3/00`:
      location exception / LSD 1–16 - section 1–36 - township 1–126 -
      range 1–34 W meridian 1–6 (optional trailing `M`) / event
    * NTS (National Topographic System, survey code `2`, NE BC and the
      territories), e.g. `200/d-096-H/094-A-16/00`: location exception /
      quarter unit A–L - unit 1–100 - block A–L / map sheet / event

  Leading zeros are optional and case is ignored. Wells in every other country
  are not format-checked yet.
  """

  # Written without the /i flag (letters spelled out in both cases) and without
  # anchors so the same source also works as an HTML `pattern` attribute, which
  # takes no flags and is implicitly anchored. See `html_pattern/1`.
  @dls_source "1[0-9A-Za-z]{2}/(0?[1-9]|1[0-6])-(0?[1-9]|[12][0-9]|3[0-6])-(0{0,2}[1-9]|0?[1-9][0-9]|1[01][0-9]|12[0-6])-(0?[1-9]|[12][0-9]|3[0-4])[Ww][1-6][Mm]?/[0-9A-Za-z]{2}"
  @nts_source "2[0-9A-Za-z]{2}/[A-La-l]-(0{0,2}[1-9]|0?[1-9][0-9]|100)-[A-La-l]/[0-9]{3}-[A-Pa-p]-(0?[1-9]|1[0-6])/[0-9A-Za-z]{2}"

  @dls Regex.compile!("^" <> @dls_source <> "$")
  @nts Regex.compile!("^" <> @nts_source <> "$")

  @doc """
  The UWI format for `country` as an HTML `pattern` attribute value, or nil
  for a country with no format rule. Built from the same source as `valid?/2`
  so the browser and the changeset can't disagree. Surrounding whitespace is
  allowed because `valid?/2` trims it.
  """
  @spec html_pattern(String.t() | nil) :: String.t() | nil
  def html_pattern("Canada"), do: "\\s*(?:#{@dls_source}|#{@nts_source})\\s*"
  def html_pattern(_), do: nil

  @doc "An example of a valid UWI for `country`, for placeholders and error messages."
  @spec example(String.t() | nil) :: String.t() | nil
  def example("Canada"), do: "100/16-36-046-23W3/00"
  def example(_), do: nil

  @doc """
  True when `uwi` is a valid identifier for `country`. Always true for a
  country with no format rule.
  """
  @spec valid?(String.t() | nil, String.t() | nil) :: boolean()
  def valid?(uwi, "Canada") when is_binary(uwi) do
    uwi = String.trim(uwi)
    Regex.match?(@dls, uwi) or Regex.match?(@nts, uwi)
  end

  def valid?(_uwi, "Canada"), do: false
  def valid?(_uwi, _country), do: true
end
