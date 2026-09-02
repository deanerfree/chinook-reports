defmodule ChinookReports.FormationTopsTest do
  use ExUnit.Case, async: true

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
