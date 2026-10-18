defmodule ChinookReports.DirectionalReferenceTest do
  @moduledoc """
  Checks our minimum-curvature maths against surveys computed by the
  directional companies' own software, in `test/test_data/directional/`:

    * `wapiti_plan.json` — CNRL Hz Wapiti 4-31-64-8W6M, Proposal 4 (COMPASS)
    * `paradise_hill_plan.json` — CVE Paradise Hill OBS DD, Plan #2 (COMPASS)
    * `wapiti_actual.json` — the Wapiti driller's final survey (WINSERVE)

  Each holds every station as printed: MD / Inc / Azi plus that software's
  TVD, N/S, E/W, VS and DLS. Values are printed to 2 decimals, so every
  tolerance below is what that rounding can explain and no more:

    * a printed coordinate is off by up to 0.005 m, so an interval's change
      by up to 0.01 m;
    * a printed angle is off by up to 0.005°, which moves the hole by up to
      `interval × 0.005°` (in radians) and its dogleg by up to ~0.0071°
      (inclination and azimuth both off, at worst near horizontal).

  The per-interval check is the strict one: on the Wapiti files it rejects
  balanced-tangential (minimum curvature without the ratio factor), which
  is off by only a few centimetres per 30 m. Cumulative positions drift
  further, because the companies integrate unrounded angles, so they get a
  looser bound that still catches tie-in and unit mistakes.
  """
  use ExUnit.Case, async: true

  alias ChinookReports.{Survey, Trajectory}

  @dir Path.expand("../test_data/directional", __DIR__)
  @files ~w(wapiti_plan paradise_hill_plan wapiti_actual)

  @coord_rounding 0.01
  @angle_rounding_rad 0.005 * :math.pi() / 180
  @dogleg_rounding_deg 0.0071
  @dls_rounding 0.005

  @cumulative_tolerance 0.25
  @vs_tolerance 0.05

  @xyz [{"tvd", :tvd}, {"north_south", :north}, {"east_west", :east}]

  defp reference(name), do: @dir |> Path.join("#{name}.json") |> File.read!() |> Jason.decode!()

  defp station(r), do: %{md: r["md"], inc_deg: r["inclination_deg"], azi_deg: r["azimuth_deg"]}

  # Pairs of consecutive reference stations with a real interval between them.
  defp intervals(stations) do
    stations
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.filter(fn [a, b] -> b["md"] > a["md"] end)
  end

  for name <- @files do
    describe name do
      setup do
        %{stations: reference(unquote(name))["stations"]}
      end

      test "each interval's ΔTVD / ΔN / ΔE is within rounding", %{stations: stations} do
        for [a, b] <- intervals(stations), {key, ours} <- @xyz do
          d = Trajectory.interval(station(a), station(b))
          allowed = @coord_rounding + 2 * (b["md"] - a["md"]) * @angle_rounding_rad
          off = abs(b[key] - a[key] - d[ours])

          assert off <= allowed,
                 "#{key} over #{a["md"]}–#{b["md"]} m is off by #{off} m (allowed #{allowed})"
        end
      end

      test "each station's dogleg severity is within rounding", %{stations: stations} do
        for [a, b] <- intervals(stations) do
          d_md = b["md"] - a["md"]
          dls = Trajectory.interval(station(a), station(b)).dogleg_deg / d_md * 30.0
          allowed = @dls_rounding + 2 * @dogleg_rounding_deg * 30.0 / d_md
          off = abs(b["dogleg_severity"] - dls)

          assert off <= allowed,
                 "DLS at #{b["md"]} m is #{dls}, printed #{b["dogleg_severity"]} (allowed ±#{allowed})"
        end
      end

      test "Trajectory.stations/1 reproduces every printed station", %{stations: stations} do
        ours = stations |> Enum.map(&station/1) |> Trajectory.stations()
        assert length(ours) == length(stations)

        for {r, p} <- Enum.zip(stations, ours) do
          assert_in_delta p.md, r["md"], 1.0e-9

          for {key, k} <- @xyz do
            assert_in_delta p[k], r[key], @cumulative_tolerance, "#{key} at #{r["md"]} m"
          end

          assert_in_delta p.vertical_section,
                          r["vertical_section"],
                          @vs_tolerance,
                          "VS at #{r["md"]} m"
        end
      end

      test "Survey.recompute/3 from scratch reproduces every printed station",
           %{stations: stations} do
        input = Enum.map(stations, &Map.take(&1, ~w(md inclination_deg azimuth_deg)))
        {points, _} = Survey.recompute([], input, nil)
        assert length(points) == length(stations)

        for {r, p} <- Enum.zip(stations, points) do
          for {key, _} <- @xyz do
            assert_in_delta p[key], r[key], @cumulative_tolerance, "#{key} at #{r["md"]} m"
          end

          assert_in_delta p["vertical_section"],
                          r["vertical_section"],
                          @vs_tolerance,
                          "VS at #{r["md"]} m"
        end
      end
    end
  end
end
