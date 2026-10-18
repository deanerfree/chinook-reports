defmodule ChinookReports.FormationTopsTest do
  use ChinookReports.DataCase, async: true

  alias ChinookReports.FormationTops

  # A straight, near-vertical survey: tvd tracks md, station every 100 m to 500 m.
  @survey for md <- 0..500//100, do: %{"md" => md * 1.0, "tvd" => md * 1.0}
  @kb 600.0

  defp row(name, prog \\ %{}, samp \\ %{}, mwd \\ %{}) do
    %{"formation" => name, "prognosis" => prog, "samples" => samp, "mwd_gamma" => mwd}
  end

  defp recompute(rows),
    do: FormationTops.recompute(rows, survey_points: @survey, kb_elevation: @kb)

  describe "prognosis" do
    test "keeps its given subsea (the geologic pick) and derives TVD from KB" do
      [r] = recompute([row("A", %{"md" => 100.0, "subsea" => 502.0})])

      assert r["prognosis"]["subsea"] == 502.0
      assert r["prognosis"]["tvd"] == 98.0
      refute Map.has_key?(r["prognosis"], "method")
    end

    test "TVD tracks a KB change while subsea stays put" do
      [r] =
        FormationTops.recompute([row("A", %{"md" => 100.0, "subsea" => 502.0})],
          survey_points: @survey,
          kb_elevation: 610.0
        )

      assert r["prognosis"]["subsea"] == 502.0
      assert r["prognosis"]["tvd"] == 108.0
    end

    test "falls back to a given TVD when the sheet carries no subsea" do
      [r] = recompute([row("A", %{"md" => 100.0, "tvd" => 98.0})])

      assert r["prognosis"]["tvd"] == 98.0
      assert r["prognosis"]["subsea"] == 502.0
    end
  end

  describe "samples / mwd TVD from the survey" do
    test "interpolates between stations when the pick is within the survey" do
      [r] = recompute([row("A", %{}, %{"md" => 250.0})])

      assert r["samples"]["tvd"] == 250.0
      assert r["samples"]["subsea"] == 350.0
      assert r["samples"]["method"] == "interpolated"
    end

    test "extrapolates from the last station when the pick is beyond the survey" do
      [r] = recompute([row("A", %{}, %{"md" => 700.0})])

      # slope of the last interval is 1.0, so tvd continues 1:1
      assert r["samples"]["tvd"] == 700.0
      assert r["samples"]["method"] == "extrapolated"
      assert FormationTops.provisional?(r)
    end

    test "leaves tvd nil when there is no MD" do
      [r] = recompute([row("A")])
      assert r["samples"]["tvd"] == nil
      assert r["samples"]["subsea"] == nil
      refute FormationTops.provisional?(r)
    end
  end

  describe "isopach" do
    test "is the next formation's TVD minus this one's, in depth order" do
      [a, b, c] =
        recompute([
          row("A", %{"md" => 100.0, "tvd" => 100.0}),
          row("B", %{"md" => 250.0, "tvd" => 250.0}),
          row("C", %{"md" => 400.0, "tvd" => 400.0})
        ])

      assert a["prognosis"]["isopach"] == 150.0
      assert b["prognosis"]["isopach"] == 150.0
      assert c["prognosis"]["isopach"] == nil
    end

    test "handles rows given out of depth order" do
      [deep, shallow] =
        recompute([
          row("Deep", %{"md" => 400.0, "tvd" => 400.0}),
          row("Shallow", %{"md" => 100.0, "tvd" => 100.0})
        ])

      assert shallow["prognosis"]["isopach"] == 300.0
      assert deep["prognosis"]["isopach"] == nil
    end
  end

  describe "isopach fallbacks" do
    test "a prognosis with no KB drops a TVD from another KB; isopach comes from subsea" do
      [a, b] =
        FormationTops.recompute(
          [
            row("A", %{"md" => 100.0, "tvd" => 98.0, "subsea" => 502.0}),
            row("B", %{"md" => 200.0, "tvd" => 190.0, "subsea" => 410.0})
          ],
          survey_points: [],
          kb_elevation: nil
        )

      assert a["prognosis"]["tvd"] == nil
      assert a["prognosis"]["isopach"] == 92.0
      assert b["prognosis"]["isopach"] == nil
    end

    test "with no TVD and no KB, the subsea difference is the thickness" do
      [a, _] =
        FormationTops.recompute(
          [row("A", %{"subsea" => 502.0}), row("B", %{"subsea" => 410.0})],
          survey_points: [],
          kb_elevation: nil
        )

      assert a["prognosis"]["isopach"] == 92.0
    end

    test "an MD-only prognosis reads its TVD off the survey" do
      deviated = [
        %{"md" => 0.0, "tvd" => 0.0},
        %{"md" => 100.0, "tvd" => 100.0},
        %{"md" => 300.0, "tvd" => 200.0}
      ]

      [a, _] =
        FormationTops.recompute([row("A", %{"md" => 100.0}), row("B", %{"md" => 300.0})],
          survey_points: deviated,
          kb_elevation: nil
        )

      assert a["prognosis"]["isopach"] == 100.0
    end

    test "with no survey, an MD-only top is taken as vertical" do
      [a, _] =
        FormationTops.recompute(
          [row("A", %{}, %{"md" => 120.0}), row("B", %{}, %{"md" => 175.5})],
          survey_points: [],
          kb_elevation: @kb
        )

      assert a["samples"]["isopach"] == 55.5
    end

    test "a row with no depth is skipped over" do
      [a, blank, c] =
        recompute([
          row("A", %{"md" => 100.0, "tvd" => 100.0}),
          row("New"),
          row("C", %{"md" => 250.0, "tvd" => 250.0})
        ])

      assert a["prognosis"]["isopach"] == 150.0
      assert blank["prognosis"]["isopach"] == nil
      assert c["prognosis"]["isopach"] == nil
    end
  end

  describe "typed formation tops (report_data)" do
    alias ChinookReports.Reports.Report

    defp typed(tops, extra \\ %{}) do
      %Report{report_data: %Report.ReportData{}}
      |> Report.changeset(%{
        "well_name" => "W",
        "unique_well_id" => "100/01-01-001-01W1/00",
        "report_data" => Map.merge(%{"formation_tops" => tops}, extra)
      })
      |> Ecto.Changeset.get_field(:report_data)
      |> Map.fetch!(:formation_tops)
      |> Enum.map(&(&1.isopach && Decimal.to_float(&1.isopach)))
    end

    test "isopach is derived from TVD as tops are added" do
      assert typed(%{"0" => %{"formation" => "A", "md" => "100", "tvd" => "100"}}) == [nil]

      assert typed(%{
               "0" => %{"formation" => "A", "md" => "100", "tvd" => "100"},
               "1" => %{"formation" => "B", "md" => "260", "tvd" => "240"}
             }) == [140.0, nil]
    end

    test "a typed isopach is overwritten by the calculation" do
      assert typed(%{
               "0" => %{"formation" => "A", "md" => "100", "tvd" => "100", "isopach" => "7"},
               "1" => %{"formation" => "B", "md" => "260", "tvd" => "240"}
             }) == [140.0, nil]
    end

    test "TVD is our KB − subsea, replacing a TVD typed against another KB" do
      %{formation_tops: [top]} =
        %Report{report_data: %Report.ReportData{}}
        |> Report.changeset(%{
          "well_name" => "W",
          "unique_well_id" => "100/01-01-001-01W1/00",
          "report_data" => %{
            "kb_elevation" => "600",
            "formation_tops" => %{"0" => %{"formation" => "A", "tvd" => "97", "subsea" => "500"}}
          }
        })
        |> Ecto.Changeset.apply_changes()
        |> Map.fetch!(:report_data)

      assert Decimal.equal?(top.tvd, "100")
    end

    test "Well Data's KB wins over the typed one, and a change to it moves TVD" do
      {:ok, report} =
        ChinookReports.Reports.create_report(%{
          "well_name" => "W",
          "unique_well_id" => "100/01-01-001-01W1/00",
          "import_data" => %{"welldata" => %{"elevations" => %{"kelly_bushing" => 610.0}}},
          "report_data" => %{
            "kb_elevation" => "600",
            "formation_tops" => %{"0" => %{"formation" => "A", "subsea" => "500"}}
          }
        })

      assert Decimal.equal?(hd(report.report_data.formation_tops).tvd, "110")

      {:ok, report} =
        ChinookReports.Reports.update_import_section(report, "welldata", %{
          "elevations" => %{"kelly_bushing" => 615.0}
        })

      assert Decimal.equal?(hd(report.report_data.formation_tops).tvd, "115")
    end

    test "uses KB − subsea when there's no TVD" do
      assert typed(
               %{
                 "0" => %{"formation" => "A", "subsea" => "500"},
                 "1" => %{"formation" => "B", "subsea" => "450"}
               },
               %{"kb_elevation" => "600"}
             ) == [50.0, nil]
    end

    test "an MD-only top reads its TVD off the directional program" do
      # vertical to 100 m, then 60° inclination: 100 m of hole drops 50 m TVD
      program = %{
        "0" => %{"md" => "0", "inclination" => "0", "azimuth" => "0"},
        "1" => %{"md" => "100", "inclination" => "0", "azimuth" => "0"},
        "2" => %{"md" => "101", "inclination" => "60", "azimuth" => "0"},
        "3" => %{"md" => "400", "inclination" => "60", "azimuth" => "0"}
      }

      [a, nil] =
        typed(
          %{
            "0" => %{"formation" => "A", "md" => "101"},
            "1" => %{"formation" => "B", "md" => "201"}
          },
          %{"surveys" => program}
        )

      assert_in_delta a, 50.0, 0.1
    end
  end

  describe "difference_m" do
    test "is samples.subsea minus prognosis.subsea" do
      [r] =
        recompute([
          row("A", %{"md" => 200.0, "tvd" => 205.0}, %{"md" => 200.0})
        ])

      # prognosis subsea = 600 - 205 = 395 ; samples subsea = 600 - 200 = 400
      assert r["difference_m"] == 5.0
    end

    test "is nil when either subsea is missing" do
      [r] = recompute([row("A", %{"md" => 200.0, "tvd" => 205.0})])
      assert r["difference_m"] == nil
    end
  end

  describe "kb_elevation/1" do
    test "takes the Kelly Bushing from import_data welldata elevations" do
      report = %{
        import_data: %{"welldata" => %{"elevations" => %{"kelly_bushing" => 628.3}}},
        report_data: nil
      }

      assert FormationTops.kb_elevation(report) == 628.3
    end

    test "prefers the imported welldata value over the typed embed" do
      report = %{
        import_data: %{"welldata" => %{"elevations" => %{"kelly_bushing" => 628.3}}},
        report_data: %{kb_elevation: Decimal.new("999.9")}
      }

      assert FormationTops.kb_elevation(report) == 628.3
    end

    test "falls back to the typed embed when there is no imported well data" do
      report = %{import_data: %{}, report_data: %{kb_elevation: Decimal.new("705.2")}}
      assert FormationTops.kb_elevation(report) == 705.2
    end
  end

  describe "kb_to_ground/2" do
    test "is Kelly Bushing minus Ground Level, without float noise" do
      assert FormationTops.kb_to_ground(1047.8, 1052.3) == 4.5
      assert FormationTops.kb_to_ground(Decimal.new("700.0"), "705.5") == 5.5
    end

    test "is nil unless both elevations are present" do
      assert FormationTops.kb_to_ground(nil, 1052.3) == nil
      assert FormationTops.kb_to_ground(1047.8, "") == nil
    end
  end

  describe "recompute/2 input shapes" do
    test "accepts the wrapped %{\"formations\" => [...]} map" do
      out = recompute(%{"formations" => [row("A", %{"md" => 100.0, "tvd" => 100.0})]})
      assert %{"formations" => [%{"prognosis" => %{"subsea" => 500.0}}]} = out
    end

    test "with fewer than two survey points, samples tvd stays nil" do
      out =
        FormationTops.recompute([row("A", %{}, %{"md" => 100.0})],
          survey_points: [%{"md" => 0.0, "tvd" => 0.0}],
          kb_elevation: @kb
        )

      assert [%{"samples" => %{"tvd" => nil}}] = out
    end

    test "with nil KB, subsea stays nil but tvd still computes" do
      out =
        FormationTops.recompute([row("A", %{}, %{"md" => 250.0})],
          survey_points: @survey,
          kb_elevation: nil
        )

      assert [%{"samples" => %{"tvd" => 250.0, "subsea" => nil}}] = out
    end

    test "coerces string numbers from raw import data" do
      [r] = recompute([row("A", %{"md" => "100", "tvd" => "98.5"})])
      assert r["prognosis"]["subsea"] == 501.5
    end
  end
end
