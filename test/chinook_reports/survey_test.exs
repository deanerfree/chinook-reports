defmodule ChinookReports.SurveyTest do
  use ExUnit.Case, async: true

  alias ChinookReports.Survey

  @gear "GEAR SODA LAKE 103 HZ 15-31-46-23W3M (16-36) Final Report.json"

  # The Gear horizontal's extracted survey and KB — real extractor output to
  # check the recompute against.
  defp gear do
    data =
      [File.cwd!(), "test", "test_data", @gear] |> Path.join() |> File.read!() |> Jason.decode!()

    [leg | _] = data["reservoir_data"]
    {leg["survey"], data["welldata"]["elevations"]["kelly_bushing"]}
  end

  defp inputs_only(points), do: Enum.map(points, &Map.drop(&1, Survey.derived_keys()))

  describe "recompute/3" do
    test "an untouched survey comes back exactly as stored" do
      {survey, kb} = gear()
      points = survey["survey_points"]

      assert Survey.recompute(points, points, kb) == {points, nil}
    end

    test "recomputing from scratch reproduces the extractor's TVD, N/S, E/W and Subsea" do
      {survey, kb} = gear()
      stored = survey["survey_points"]

      # no stored survey to keep → every station is recomputed
      {points, from_md} = Survey.recompute([], inputs_only(stored), kb)

      assert from_md == hd(stored)["md"]

      for {p, s} <- Enum.zip(points, stored), key <- ~w(tvd north_south east_west subsea) do
        assert_in_delta p[key], s[key], 1.0e-3, "#{key} at MD #{s["md"]}"
      end

      for {p, s} <- Enum.zip(points, stored) do
        assert_in_delta p["vertical_section"], s["vertical_section"], 0.05
      end
    end

    test "editing a station keeps every station above it as stored" do
      {survey, kb} = gear()
      stored = survey["survey_points"]
      k = 100

      edited =
        List.update_at(stored, k, &Map.put(&1, "inclination_deg", &1["inclination_deg"] + 2))

      {points, from_md} = Survey.recompute(stored, edited, kb)

      assert from_md == Enum.at(stored, k)["md"]
      assert Enum.take(points, k) == Enum.take(stored, k)
      refute Enum.at(points, k + 1)["tvd"] == Enum.at(stored, k + 1)["tvd"]
    end

    test "an appended station is integrated from the last stored one" do
      survey = [
        %{
          "md" => 0.0,
          "inclination_deg" => 0.0,
          "azimuth_deg" => 0.0,
          "tvd" => 0.0,
          "north_south" => 0.0,
          "east_west" => 0.0,
          "vertical_section" => 0.0,
          "dogleg_severity" => 0.0,
          "subsea" => 600.0
        },
        %{
          "md" => 100.0,
          "inclination_deg" => 0.0,
          "azimuth_deg" => 0.0,
          "tvd" => 100.0,
          "north_south" => 0.0,
          "east_west" => 0.0,
          "vertical_section" => 0.0,
          "dogleg_severity" => 0.0,
          "subsea" => 500.0
        }
      ]

      new = survey ++ [%{"md" => 130.0, "inclination_deg" => 3.0, "azimuth_deg" => 90.0}]
      {points, from_md} = Survey.recompute(survey, new, 600.0)

      assert from_md == 130.0
      assert Enum.take(points, 2) == survey
      last = List.last(points)
      # 3° build over 30 m → DLS 3°/30 m, drifting east
      assert_in_delta last["dogleg_severity"], 3.0, 1.0e-9
      assert last["east_west"] > 0
      assert_in_delta last["north_south"], 0.0, 1.0e-9
      assert_in_delta last["subsea"], 600.0 - last["tvd"], 1.0e-9
    end

    test "stations are returned sorted by MD whatever order they were entered in" do
      new = [
        %{"md" => 50.0, "inclination_deg" => 0.0, "azimuth_deg" => 0.0},
        %{"md" => 0.0, "inclination_deg" => 0.0, "azimuth_deg" => 0.0}
      ]

      {points, _} = Survey.recompute([], new, nil)
      assert Enum.map(points, & &1["md"]) == [0.0, 50.0]
      assert Enum.map(points, & &1["tvd"]) == [0.0, 50.0]
    end
  end

  describe "recompute_markers/4" do
    test "moves Last Survey to the deepest station and re-places markers below the change" do
      points = [
        %{
          "md" => 0.0,
          "inclination_deg" => 0.0,
          "azimuth_deg" => 0.0,
          "tvd" => 0.0,
          "north_south" => 0.0,
          "east_west" => 0.0,
          "vertical_section" => 0.0
        },
        %{
          "md" => 200.0,
          "inclination_deg" => 0.0,
          "azimuth_deg" => 0.0,
          "tvd" => 200.0,
          "north_south" => 0.0,
          "east_west" => 0.0,
          "vertical_section" => 0.0
        }
      ]

      markers = [
        %{"event" => "Kick Off Point", "md" => 50.0, "tvd" => 49.0},
        %{"event" => "Sparky", "md" => 150.0, "tvd" => 1.0},
        %{"event" => "Last Survey", "md" => 100.0, "tvd" => 100.0}
      ]

      [kop, top, last] = Survey.recompute_markers(markers, points, 100.0, 600.0)

      # above the change: untouched
      assert kop == hd(markers)
      assert top["tvd"] == 150.0
      assert top["subsea"] == 450.0
      assert last["md"] == 200.0
      assert last["tvd"] == 200.0
    end

    test "nothing changed means nothing moves" do
      markers = [%{"event" => "Last Survey", "md" => 1.0}]
      assert Survey.recompute_markers(markers, [], nil, nil) == markers
    end
  end
end
