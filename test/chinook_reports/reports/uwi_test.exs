defmodule ChinookReports.Reports.UWITest do
  use ExUnit.Case, async: true

  alias ChinookReports.Reports.UWI

  describe "Canada" do
    for uwi <- [
          "100/16-36-046-23W3/00",
          "103/15-31-046-23W3/00",
          # unpadded LSD, as in the Kerrobert workbook
          "102/2-27-032-23W3/00",
          "100/05-30-049-01W4/00",
          # trailing M on the meridian
          "100/16-36-046-23W3M/00",
          "100/01-01-001-01w1m/02",
          # NTS
          "200/d-096-H/094-A-16/00",
          "200/A-063-H/094-A-15/02",
          "  100/16-36-046-23W3/00  "
        ] do
      test "accepts #{inspect(uwi)}" do
        assert UWI.valid?(unquote(uwi), "Canada")
      end
    end

    for {uwi, why} <- [
          {"101/20-20-20-20W20/00", "LSD 20 and meridian 20 do not exist"},
          {"100/16-37-046-23W3/00", "section 37"},
          {"100/16-36-127-23W3/00", "township 127"},
          {"100/16-36-046-35W3/00", "range 35"},
          {"100/16-36-046-23W7/00", "meridian 7"},
          {"100/16-36-046-23E3/00", "east of meridian"},
          {"300/16-36-046-23W3/00", "unknown survey system"},
          {"200/M-096-H/094-A-16/00", "quarter unit M"},
          {"200/d-096-H/094-Q-16/00", "map area Q"},
          {"100-16-36-046-23W3-00", "wrong separators"},
          {"XXX/XX-XX-XXX-XXWX/XX", "placeholder"},
          {"", "blank"}
        ] do
      test "rejects #{inspect(uwi)} (#{why})" do
        refute UWI.valid?(unquote(uwi), "Canada")
      end
    end

    test "rejects nil" do
      refute UWI.valid?(nil, "Canada")
    end
  end

  test "other countries and a blank country are not format-checked" do
    assert UWI.valid?("42-501-20130", "United States")
    assert UWI.valid?("anything", "Algeria")
    assert UWI.valid?("DRAFT-1", nil)
  end

  describe "html_pattern/1" do
    # The browser anchors `pattern` as ^(?:...)$; mirror that here.
    defp html_match?(uwi, country) do
      Regex.match?(~r/^(?:#{UWI.html_pattern(country)})$/, uwi)
    end

    test "agrees with valid?/2 for Canada" do
      for uwi <- [
            "100/16-36-046-23W3/00",
            "100/01-01-001-01w1m/02",
            "200/d-096-H/094-A-16/00",
            "  100/16-36-046-23W3/00  ",
            "101/20-20-20-20W20/00",
            "200/M-096-H/094-A-16/00",
            "XXX/XX-XX-XXX-XXWX/XX",
            ""
          ] do
        assert html_match?(uwi, "Canada") == UWI.valid?(uwi, "Canada"), inspect(uwi)
      end
    end

    test "is nil for countries without a format rule" do
      assert UWI.html_pattern("United States") == nil
      assert UWI.html_pattern(nil) == nil
    end
  end
end
