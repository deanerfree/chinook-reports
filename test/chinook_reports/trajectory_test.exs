defmodule ChinookReports.TrajectoryTest do
  use ExUnit.Case, async: true

  alias ChinookReports.Trajectory

  test "returns [] for fewer than two usable stations" do
    assert Trajectory.integrate([]) == []
    assert Trajectory.integrate([%{md: 0, inc_deg: 0, azi_deg: 0}]) == []
    assert Trajectory.integrate(nil) == []
  end

  test "a straight vertical hole stays at zero offset, tvd tracks md" do
    stations = [
      %{md: 0, inc_deg: 0, azi_deg: 0},
      %{md: 100, inc_deg: 0, azi_deg: 0},
      %{md: 250, inc_deg: 0, azi_deg: 0}
    ]

    points = Trajectory.integrate(stations)

    assert length(points) == 3
    last = List.last(points)
    assert_in_delta last.tvd, 250.0, 0.001
    assert_in_delta last.north, 0.0, 0.001
    assert_in_delta last.east, 0.0, 0.001
    assert_in_delta last.vertical_section, 0.0, 0.001
  end

  test "a 90-degree build to horizontal east lands the expected TVD and reach" do
    # 0->100 vertical, then build to 90 deg over 100 m MD, then 200 m horizontal east.
    stations = [
      %{md: 0, inc_deg: 0, azi_deg: 90},
      %{md: 100, inc_deg: 0, azi_deg: 90},
      %{md: 200, inc_deg: 90, azi_deg: 90},
      %{md: 400, inc_deg: 90, azi_deg: 90}
    ]

    points = Trajectory.integrate(stations)
    last = List.last(points)

    # Build arc contributes 2/pi * 100 to both TVD gain and easting; then 200 m east.
    assert_in_delta last.tvd, 100.0 + 200.0 / :math.pi(), 0.5
    assert_in_delta last.east, 200.0 / :math.pi() + 200.0, 0.5
    assert_in_delta last.north, 0.0, 0.001
    # VS azimuth is due east, so vertical section equals easting.
    assert_in_delta last.vertical_section, last.east, 0.001
  end

  test "accepts string-keyed stations from raw import data" do
    stations = [
      %{"md" => 0.0, "inclination_deg" => 0.0, "azimuth_deg" => 0.0},
      %{"md" => 500.0, "inclination_deg" => 0.0, "azimuth_deg" => 0.0}
    ]

    assert [%{tvd: _}, %{tvd: tvd}] = Trajectory.integrate(stations)
    assert_in_delta tvd, 500.0, 0.001
  end

  describe "position_at/2" do
    @slant [
      %{md: 0, inc_deg: 0, azi_deg: 0},
      %{md: 100, inc_deg: 0, azi_deg: 0},
      %{md: 200, inc_deg: 0, azi_deg: 0}
    ]

    test "interpolates between stations" do
      p = Trajectory.position_at(@slant, 150)
      assert_in_delta p.tvd, 150.0, 0.001
      assert_in_delta p.north, 0.0, 0.001
    end

    test "projects past the last station on its inclination and azimuth" do
      stations =
        [%{md: 0, inc_deg: 0, azi_deg: 0}, %{md: 100, inc_deg: 0, azi_deg: 0}] ++
          [%{md: 101, inc_deg: 30, azi_deg: 90}]

      last = List.last(Trajectory.integrate(stations))
      p = Trajectory.position_at(stations, 201)

      assert_in_delta p.tvd - last.tvd, 100 * :math.cos(:math.pi() / 6), 0.001
      assert_in_delta p.east - last.east, 50.0, 0.001
      assert_in_delta p.north - last.north, 0.0, 0.001
    end

    test "nil when there is no usable plan or the depth is above it" do
      assert Trajectory.position_at([], 100) == nil

      assert Trajectory.position_at(
               [%{md: 50, inc_deg: 0, azi_deg: 0}, %{md: 60, inc_deg: 0, azi_deg: 0}],
               10
             ) == nil
    end
  end
end
