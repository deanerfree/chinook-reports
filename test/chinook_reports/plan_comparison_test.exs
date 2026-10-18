defmodule ChinookReports.PlanComparisonTest do
  use ExUnit.Case, async: true

  alias ChinookReports.{PlanComparison, Trajectory}

  # Vertical to 100 m, build to horizontal by 200 m, then 200 m of lateral on
  # `azi`. The section line runs the same way.
  defp plan(azi) do
    [
      %{md: 0, inc_deg: 0, azi_deg: azi},
      %{md: 100, inc_deg: 0, azi_deg: azi},
      %{md: 200, inc_deg: 90, azi_deg: azi},
      %{md: 400, inc_deg: 90, azi_deg: azi}
    ]
  end

  # An actual station at `md`, moved off the plan by the given TVD/N/E.
  defp actual(plan, md, d_tvd, d_n, d_e, remarks \\ nil) do
    p = Trajectory.position_at(plan, md)

    %{
      "md" => md,
      "tvd" => p.tvd + d_tvd,
      "north_south" => p.north + d_n,
      "east_west" => p.east + d_e,
      "remarks" => remarks
    }
  end

  test "reads high/low, ahead/behind and left/right along a northward plan" do
    plan = plan(0)

    %{rows: [row], vs_azimuth_deg: azi} =
      PlanComparison.compare([actual(plan, 300, -2, 3, 1.5)], plan)

    assert_in_delta azi, 0.0, 1.0e-6
    assert_in_delta row.above, 2.0, 1.0e-6
    assert_in_delta row.ahead, 3.0, 1.0e-6
    assert_in_delta row.right, 1.5, 1.0e-6
    assert_in_delta row.distance, :math.sqrt(4 + 9 + 2.25), 1.0e-6
  end

  test "left and right follow the plan's direction, not the compass" do
    # Facing south, east is on the left and south is ahead.
    plan = plan(180)
    %{rows: [row]} = PlanComparison.compare([actual(plan, 300, 4, -2, 1)], plan)

    assert_in_delta row.above, -4.0, 1.0e-6
    assert_in_delta row.ahead, 2.0, 1.0e-6
    assert_in_delta row.right, -1.0, 1.0e-6
  end

  test "a station on the plan is zero in every direction" do
    plan = plan(90)
    %{rows: [row]} = PlanComparison.compare([actual(plan, 250, 0, 0, 0)], plan)

    for k <- [:above, :ahead, :right, :distance], do: assert_in_delta(row[k], 0.0, 1.0e-6)
  end

  test "flags stations past the plan and projected ones; latest is the deepest measured" do
    plan = plan(0)

    points = [
      actual(plan, 450, 0, 0, 0, "Extrapolation to bit"),
      actual(plan, 380, 1, 0, 0),
      actual(plan, 420, 0, 0, 0)
    ]

    %{rows: rows, latest: latest} = PlanComparison.compare(points, plan)

    assert Enum.map(rows, & &1.md) == [380.0, 420.0, 450.0]
    assert Enum.map(rows, & &1.beyond_plan) == [false, true, true]
    assert Enum.map(rows, & &1.projected) == [false, false, true]
    assert latest.md == 420.0
  end

  test "skips incomplete stations and returns nil without a plan or survey" do
    plan = plan(0)
    assert PlanComparison.compare([actual(plan, 300, 0, 0, 0)], []) == nil
    assert PlanComparison.compare([], plan) == nil
    assert PlanComparison.compare([%{"md" => 300, "tvd" => 250}], plan) == nil
  end
end
