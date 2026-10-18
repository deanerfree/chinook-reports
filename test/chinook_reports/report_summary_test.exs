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
      assert s.depths.actual.md == "1979"
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

    test "last formation skips the TD row and calls it against prognosis", %{s: s} do
      assert %{formation: "DETRITAL", md: "1128.71", call: :low, diff: "-2.07"} =
               s.vertical.last_formation
    end

    test "primary target top is matched by name", %{s: s} do
      assert %{formation: "VIKING SS", call: :low} = s.vertical.target
    end

    test "depth separates the last measured station from the projection to TD", %{s: s} do
      d = s.vertical.depth
      assert d.md == "1145"
      assert d.extrapolated
      # a survey station keeps the survey's precision
      assert d.last_survey.md == "1118.1286"
      assert d.projected_from == "26.87"
    end

    test "no gas curve on a vertical well yields nil, not a crash", %{s: s} do
      assert s.vertical.max_gas == nil
    end

    test "a plain vertical well gets no plan comparison even with a plan on file", %{s: s} do
      refute s.vertical.deviated
      assert s.vertical.has_plan
      assert s.vertical.vs_plan == nil
    end
  end

  describe "deviated well (PRAIRIE FALCON set to Deviated)" do
    defp deviated(report \\ load(@prairie)), do: %{report | geometry: "Deviated"}

    defp with_program(report, rows) do
      surveys =
        Enum.map(rows, fn {md, inc, azi} ->
          %Report.ReportData.SurveyPoint{
            md: Decimal.new(md),
            inclination: Decimal.new(inc),
            azimuth: Decimal.new(azi)
          }
        end)

      %{report | report_data: %Report.ReportData{surveys: surveys}}
    end

    defp without_imported_plan(report) do
      update_in(report.import_data["reservoir_data"], fn [leg | rest] ->
        [put_in(leg, ["survey", "prognosed_survey"], []) | rest]
      end)
    end

    test "the geometry column overrides the imported welldata and keeps the vertical layout" do
      s = ReportSummary.build(deviated())
      assert s.geometry == "Deviated"
      assert s.layout == :vertical
      assert s.vertical.deviated
    end

    test "compares actual to the imported plan at the same MD" do
      s = ReportSummary.build(deviated())
      assert [%{label: "Last survey"}, %{label: "Projected to TD"} = td] = s.vertical.vs_plan
      assert td.md == "1145"
      assert td.beyond_plan
      {offset, _} = Float.parse(td.horizontal)
      assert offset > 0 and offset < 20
    end

    test "an entered directional program wins over the imported plan" do
      # A straight-down program: the offset is the well's whole drift off vertical.
      s =
        deviated()
        |> with_program([{"0", "0", "0"}, {"1200", "0", "0"}])
        |> ReportSummary.build()

      td = List.last(s.vertical.vs_plan)
      refute td.beyond_plan
      assert td.horizontal == "106.29"
      assert td.compass == "N"
    end

    test "a program entered from the kick-off point is tied in at surface" do
      s =
        deviated()
        |> without_imported_plan()
        |> with_program([{"500", "0", "0"}, {"1200", "0", "0"}])
        |> ReportSummary.build()

      td = List.last(s.vertical.vs_plan)
      assert td.horizontal == "106.29"
      # tvd 1145 straight down vs actual 1139.0: the hole is 6 m high to plan
      assert td.vertical_call == :high
    end

    test "with no plan anywhere the comparison is empty but flagged" do
      s = deviated() |> without_imported_plan() |> ReportSummary.build()
      assert s.vertical.deviated
      refute s.vertical.has_plan
      assert s.vertical.vs_plan == nil
      assert s.vertical.last_formation.formation == "DETRITAL"
    end
  end

  describe "glance/2" do
    test "digests a deviated vertical for the dashboard" do
      g =
        %{load(@prairie) | geometry: "Deviated"}
        |> ReportSummary.glance(~D[2026-06-12])

      assert g.depth == "1145"
      assert g.geometry == "Deviated"
      assert %{formation: "DETRITAL", call: :low} = g.last_formation
      assert g.spud == "2026-06-02"
      # stops at final TD (2026-06-05), not "today"
      assert g.td_date == "2026-06-05"
      assert g.days_on_well == 3
      assert g.off_plan =~ ~r/^\d+(\.\d{1,2})? m S$/
    end

    test "drilling-event rows are not reported as the last formation" do
      report = load(@prairie)

      report =
        update_in(report.import_data["tops"]["formations"], fn tops ->
          tops ++
            [%{"formation" => "ICP/HEEL", "samples" => %{"md" => 1140.0}, "mwd_gamma" => %{}}]
        end)

      assert ReportSummary.glance(report).last_formation.formation == "DETRITAL"
    end

    test "a bare report still digests" do
      g = ReportSummary.glance(%Report{well_name: "Blank", import_data: %{}})
      assert g.well_name == "Blank"
      assert g.days_on_well == nil
      assert g.off_plan == nil
      assert g.last_formation == nil
    end
  end

  test "horizontal wells carry no vertical section" do
    assert ReportSummary.build(load(@gear)).vertical == nil
  end

  test "an empty report still builds" do
    s = ReportSummary.build(%Report{well_name: "Blank", import_data: %{}})
    assert s.layout == :lateral
    assert s.facts == []
    assert s.reservoir_quality == nil
    assert s.timeline == []
  end

  test "a new well with only a directional program charts the plan before any survey" do
    s =
      %Report{well_name: "New", import_data: %{}}
      |> with_program([{"0", "0", "0"}, {"200", "0", "0"}, {"500", "30", "90"}])
      |> ReportSummary.build()

    assert s.chart_props.legs == []
    assert [%{md: +0.0, tvd: +0.0, vertical_section: +0.0} | _] = s.chart_props.plan
    assert %{md: 500.0} = List.last(s.chart_props.plan)
  end
end
