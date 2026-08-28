defmodule ChinookReports.ReportSummaryTest do
  use ExUnit.Case, async: true

  alias ChinookReports.ReportSummary
  alias ChinookReports.Reports.Report

  @gear "GEAR SODA LAKE 103 HZ 15-31-46-23W3M (16-36) Final Report.json"
  @prairie "PRAIRIE FALCON CARSLAND 7-14-18-25W4 Report 2026.json"

  defp load(file) do
    json =
      Path.join([File.cwd!(), "test", "test_data", file])
      |> File.read!()
      |> Jason.decode!()

    %Report{
      well_name: json["metadata"]["well_name"],
      unique_well_id: json["metadata"]["unique_well_id"],
      operator: json["metadata"]["operator"],
      geometry: json["metadata"]["geometry"],
      import_data: Map.drop(json, ["metadata"])
    }
  end

  describe "horizontal well (GEAR)" do
    setup do
      %{s: ReportSummary.build(load(@gear))}
    end

    test "uses the lateral layout", %{s: s} do
      assert s.layout == :lateral
      assert s.chart_props.layout == "lateral"
      assert s.chart_props.show_curves
      assert s.chart_props.overlay_curves
    end

    test "header carries the TD stat block", %{s: s} do
      assert s.header.well_name =~ "GEAR SODA LAKE"
      assert s.header.td.md == "1979"
      assert "Horizontal" in s.header.badges
    end

    test "tab bar includes Reservoir and real counts", %{s: s} do
      by_id = Map.new(s.tabs, &{&1.id, &1.count})
      assert Map.has_key?(by_id, "reservoir")
      assert by_id["formation_tops"] == 9
      assert by_id["daily_reports"] == 91
      assert by_id["mud_log"] == 20
      assert by_id["surveys"] == 177
    end

    test "key facts are nil-safe and populated", %{s: s} do
      labels = Enum.map(s.facts, & &1.label)
      assert "Primary target" in labels
      assert "Rig" in labels
      refute Enum.any?(s.facts, &is_nil(&1.value))
    end

    test "reservoir quality drops the Total row and keeps five bands", %{s: s} do
      assert length(s.reservoir_quality.rows) == 5
      refute Enum.any?(s.reservoir_quality.rows, &(&1.quality == "Total"))
      assert s.reservoir_quality.total_m > 0
    end

    test "depths compare actual against the integrated plan", %{s: s} do
      assert s.depths.actual.md == "1979.0"
      assert s.depths.planned.md != "—"
      assert s.depths.note =~ "TD landed"
    end

    test "timeline is sorted by depth", %{s: s} do
      depths = Enum.map(s.timeline, & &1.depth)
      assert depths == Enum.sort(depths)
      assert List.first(s.timeline).label == "Spud"
    end
  end

  describe "vertical well (PRAIRIE FALCON)" do
    setup do
      %{s: ReportSummary.build(load(@prairie))}
    end

    test "uses the vertical layout and omits the Reservoir tab", %{s: s} do
      assert s.layout == :vertical
      refute Enum.any?(s.tabs, &(&1.id == "reservoir"))
      refute s.chart_props.show_curves
    end

    test "still exposes formation tops for the depth column", %{s: s} do
      assert length(s.chart_props.tops) == 21
      assert is_list(s.chart_props.casing)
    end
  end

  test "an empty report still builds" do
    s = ReportSummary.build(%Report{well_name: "Blank", import_data: %{}})
    assert s.layout == :lateral
    assert s.facts == []
    assert s.reservoir_quality == nil
    assert s.timeline == []
  end
end
