defmodule ChinookReports.ReservoirQualityTest do
  use ExUnit.Case, async: true

  alias ChinookReports.ReservoirQuality

  defp interval(from, to, quality, opts \\ []) do
    %{
      "from_depth" => from,
      "to_depth" => to,
      "interval" => to - from,
      "quality" => quality,
      "gas" => Keyword.get(opts, :gas),
      "lithology" => Keyword.get(opts, :lithology),
      "porosity" => Keyword.get(opts, :porosity),
      "remarks" => Keyword.get(opts, :remarks)
    }
  end

  describe "leg_index/1" do
    test "picks the first leg carrying a log_data map" do
      report = %{
        import_data: %{
          "reservoir_data" => [
            %{"leg_name" => "Vertical", "log_data" => nil},
            %{"leg_name" => "Lateral", "log_data" => %{"intervals" => []}}
          ]
        }
      }

      assert ReservoirQuality.leg_index(report) == 1
    end

    test "falls back to 0 when no leg carries log_data" do
      report = %{import_data: %{"reservoir_data" => [%{"leg_name" => "Lateral"}]}}
      assert ReservoirQuality.leg_index(report) == 0
    end

    test "is nil when the report carries no legs" do
      assert ReservoirQuality.leg_index(%{import_data: %{}}) == nil
      assert ReservoirQuality.leg_index(%{import_data: %{"reservoir_data" => []}}) == nil
    end
  end

  describe "intervals_for_report/1" do
    test "returns the edited leg's intervals" do
      report = %{
        import_data: %{
          "reservoir_data" => [
            %{"log_data" => %{"intervals" => [interval(100.0, 150.0, "Good")]}}
          ]
        }
      }

      assert [%{"quality" => "Good"}] = ReservoirQuality.intervals_for_report(report)
    end

    test "is empty when the report carries no legs" do
      assert ReservoirQuality.intervals_for_report(%{import_data: %{}}) == []
    end
  end

  describe "quality_summary/1" do
    test "sums interval width per quality band and computes percent of total" do
      intervals = [
        interval(0.0, 30.0, "Very Good"),
        interval(30.0, 70.0, "Nil"),
        interval(70.0, 100.0, "Very Good")
      ]

      summary = ReservoirQuality.quality_summary(intervals)
      by_quality = Map.new(summary, &{&1["quality"], &1})

      assert by_quality["Very Good"]["metres"] == 60.0
      assert by_quality["Very Good"]["percent"] == 60.0
      assert by_quality["Nil"]["metres"] == 40.0
      assert by_quality["Good"]["metres"] == 0.0
      assert by_quality["Total"]["metres"] == 100.0
      assert by_quality["Total"]["percent"] == 100.0
    end

    test "handles no intervals without dividing by zero" do
      summary = ReservoirQuality.quality_summary([])

      assert Enum.all?(
               summary,
               &((&1["metres"] == 0.0 and &1["percent"] == 0.0) or &1["quality"] == "Total")
             )
    end
  end

  describe "recompute_for_report/2" do
    test "replaces the leg's intervals and rebuilds quality_summary" do
      report = %{
        import_data: %{
          "reservoir_data" => [
            %{
              "leg_name" => "Lateral",
              "log_data" => %{
                "intervals" => [interval(0.0, 10.0, "Nil")],
                "sheet_name" => "Reservoir1"
              }
            }
          ]
        }
      }

      new_intervals = [interval(0.0, 40.0, "Very Good")]
      [leg] = ReservoirQuality.recompute_for_report(report, new_intervals)

      assert leg["log_data"]["intervals"] == new_intervals
      assert leg["log_data"]["sheet_name"] == "Reservoir1"

      total = Enum.find(leg["log_data"]["quality_summary"], &(&1["quality"] == "Total"))
      assert total["metres"] == 40.0
    end

    test "is nil when the report carries no legs" do
      assert ReservoirQuality.recompute_for_report(%{import_data: %{}}, []) == nil
    end
  end

  describe "interval_rows_for_report/1" do
    test "tags each row with its stored position as a string id" do
      report = %{
        import_data: %{
          "reservoir_data" => [
            %{
              "leg_name" => "Lateral",
              "log_data" => %{
                "intervals" => [interval(0.0, 10.0, "Nil"), interval(10.0, 30.0, "Good")]
              }
            }
          ]
        }
      }

      assert [%{"id" => "0", "quality" => "Nil"}, %{"id" => "1", "quality" => "Good"}] =
               ReservoirQuality.interval_rows_for_report(report)
    end

    test "is empty when the report carries no legs" do
      assert ReservoirQuality.interval_rows_for_report(%{import_data: %{}}) == []
    end
  end

  describe "well_type_for_report/1" do
    defp leg(name, extra \\ %{}),
      do: %{
        import_data: %{
          "reservoir_data" => [
            Map.merge(%{"leg_name" => name, "log_data" => %{"intervals" => []}}, extra)
          ]
        }
      }

    test "is vertical when the leg name mentions vertical" do
      assert ReservoirQuality.well_type_for_report(leg("Vertical")) == :vertical
      assert ReservoirQuality.well_type_for_report(leg("Vertical Pilot Hole")) == :vertical
    end

    test "is horizontal otherwise, including when there are no legs" do
      assert ReservoirQuality.well_type_for_report(leg("Lateral")) == :horizontal
      assert ReservoirQuality.well_type_for_report(%{import_data: %{}}) == :horizontal
    end

    test "prefers the log_data metadata leg name" do
      report =
        leg("Lateral", %{
          "log_data" => %{"metadata" => %{"leg_name" => "Vertical"}, "intervals" => []}
        })

      assert ReservoirQuality.well_type_for_report(report) == :vertical
    end
  end

  describe "curve_data_for_report/1" do
    defp curve_report(points, meta) do
      %{
        import_data: %{
          "reservoir_data" => [
            %{
              "leg_name" => "Lateral",
              "log_data" => %{
                "intervals" => [],
                "curve_data_cleaned" => points,
                "curve_metadata" => meta
              }
            }
          ]
        }
      }
    end

    test "downsamples every fourth point, drops nulls, and derives rop_max" do
      points =
        for md <- 0..40 do
          %{"md" => md * 1.0, "gamma" => 50.0, "rop" => 123.0, "gas" => 200.0}
        end

      out =
        ReservoirQuality.curve_data_for_report(
          curve_report(points, %{"rop" => %{"max" => 300.0}})
        )

      assert length(out.points) == 11

      assert Enum.map(out.points, & &1["md"]) == [
               0.0,
               4.0,
               8.0,
               12.0,
               16.0,
               20.0,
               24.0,
               28.0,
               32.0,
               36.0,
               40.0
             ]

      assert out.md_min == 0.0
      assert out.md_max == 40.0
      # ceil(123/10)*10
      assert out.rop_max == 130
    end

    test "maps the null_value to nil" do
      points =
        for md <- 0..8 do
          gamma = if md == 0, do: -999.25, else: 45.0
          %{"md" => md * 1.0, "gamma" => gamma, "rop" => 30.0, "gas" => 10.0}
        end

      out =
        ReservoirQuality.curve_data_for_report(curve_report(points, %{"null_value" => -999.25}))

      assert [%{"gamma" => nil}, %{"md" => 4.0, "gamma" => 45.0}, %{"md" => 8.0}] = out.points
    end

    test "returns an empty trace when the leg has no log data" do
      report = %{
        import_data: %{"reservoir_data" => [%{"leg_name" => "Lateral", "log_data" => nil}]}
      }

      assert %{points: [], md_min: nil, md_max: nil, rop_max: 300} =
               ReservoirQuality.curve_data_for_report(report)
    end
  end
end
