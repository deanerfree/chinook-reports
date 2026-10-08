defmodule ChinookReports.Reports.ReportCountryUWITest do
  use ExUnit.Case, async: true

  alias ChinookReports.Countries
  alias ChinookReports.Reports.Report

  defp changeset(attrs, report \\ %Report{}) do
    Report.changeset(report, Map.merge(%{"well_name" => "W", "unique_well_id" => "U-1"}, attrs))
  end

  test "the country list is the shared one" do
    assert Countries.all() ==
             ["Canada", "United States", "Mexico", "Algeria", "Australia", "Romania", "Colombia"]

    assert Countries.member?("Romania")
    refute Countries.member?("canada")
  end

  test "country must come from the list" do
    assert changeset(%{"country" => "Mexico"}).valid?
    refute changeset(%{"country" => "Narnia"}).valid?
  end

  test "a Canadian report needs a Canadian UWI" do
    assert changeset(%{"country" => "Canada", "unique_well_id" => "100/16-36-046-23W3/00"}).valid?

    cs = changeset(%{"country" => "Canada", "unique_well_id" => "101/20-20-20-20W20/00"})
    refute cs.valid?
    assert {"must be a Canada UWI, e.g. 100/16-36-046-23W3/00", _} = cs.errors[:unique_well_id]
  end

  test "other countries and a blank country accept any UWI" do
    assert changeset(%{"country" => "Australia", "unique_well_id" => "Moomba-191"}).valid?
    assert changeset(%{"unique_well_id" => "DRAFT-1"}).valid?
  end

  test "switching an existing report to Canada re-checks its UWI" do
    existing = %Report{well_name: "W", unique_well_id: "DRAFT-1", country: nil}
    refute Report.changeset(existing, %{"country" => "Canada"}).valid?
  end

  test "an untouched legacy UWI does not block unrelated edits" do
    existing = %Report{well_name: "W", unique_well_id: "101/20-20-20-20W20/00", country: "Canada"}
    assert Report.changeset(existing, %{"operator" => "New Operator"}).valid?
  end
end
