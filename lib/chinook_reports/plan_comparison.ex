defmodule ChinookReports.PlanComparison do
  @moduledoc """
  Where an actual directional survey sits against the planned path, station by
  station.

  Each actual station is compared to the plan at the same measured depth
  (interpolated between plan stations; past the plan's last station the plan
  is projected straight ahead and the row is flagged `beyond_plan`). The
  offset is read in the plan's vertical-section frame — the azimuth from the
  wellhead to the plan's final point:

    * `above` — plan TVD − actual TVD: positive is above (high to) the plan,
      negative below (low)
    * `ahead` — actual VS − plan VS, both projected onto the plan's
      VS azimuth: positive is ahead of the plan, negative behind
    * `right` — horizontal offset square to that azimuth, looking along it:
      positive is right of the plan, negative left
    * `distance` — straight-line distance between the two points

  The planned path is the Directional Program (`report_data.surveys`) when one
  is entered, otherwise the leg's imported prognosed survey; a program that
  starts below surface is tied in vertically at the wellhead.
  """

  alias ChinookReports.Trajectory

  # Survey remarks that mark a projected (not measured) station.
  @projected_remark ~r/extrapolat|^\s*td\s*$/i

  @type row :: %{
          md: float(),
          above: float(),
          ahead: float(),
          right: float(),
          distance: float(),
          beyond_plan: boolean(),
          projected: boolean()
        }

  @type t :: %{vs_azimuth_deg: float(), rows: [row()], latest: row() | nil}

  @doc """
  Compare leg `leg`'s actual survey against the report's planned path.
  `nil` when there is no plan or no actual station to compare.
  """
  @spec for_leg(struct(), non_neg_integer()) :: t() | nil
  def for_leg(report, leg) do
    survey =
      get_in(report.import_data || %{}, ["reservoir_data", Access.at(leg), "survey"]) || %{}

    compare(survey["survey_points"] || [], plan_stations(report, survey))
  end

  @doc """
  Compare actual `points` (string-keyed `md` / `tvd` / `north_south` /
  `east_west`) against plan `stations` (`%{md, inc_deg, azi_deg}`). Points
  missing a coordinate are skipped. `latest` is the deepest measured
  (not projected) row.
  """
  @spec compare([map()], [Trajectory.station()]) :: t() | nil
  def compare(points, stations) do
    with [_ | _] = actual <-
           points |> Enum.map(&actual/1) |> Enum.reject(&is_nil/1) |> Enum.sort_by(& &1.md),
         [_, _ | _] = curve <- Trajectory.integrate(stations) do
      last_plan = List.last(curve)
      vs_azi = :math.atan2(last_plan.east, last_plan.north)

      rows =
        actual
        |> Enum.zip(Trajectory.positions_at(stations, Enum.map(actual, & &1.md)))
        |> Enum.flat_map(fn
          {_, nil} -> []
          {a, p} -> [row(a, p, vs_azi, last_plan.md)]
        end)

      %{
        vs_azimuth_deg: bearing(vs_azi),
        rows: rows,
        latest: rows |> Enum.reject(& &1.projected) |> List.last()
      }
    else
      _ -> nil
    end
  end

  @doc """
  The planned path for a leg whose survey section is `survey`: the Directional
  Program when one is entered, otherwise the leg's imported prognosed survey.
  Stations sorted by MD, unusable rows dropped, tied in at surface.
  """
  @spec plan_stations(struct(), map()) :: [Trajectory.station()]
  def plan_stations(report, survey) do
    entered =
      case report.report_data do
        %{surveys: [_ | _] = rows} ->
          Enum.map(
            rows,
            &%{md: num(&1.md), inc_deg: num(&1.inclination), azi_deg: num(&1.azimuth)}
          )

        _ ->
          []
      end

    imported =
      Enum.map(survey["prognosed_survey"] || [], fn s ->
        %{md: num(s["md"]), inc_deg: num(s["inclination_deg"]), azi_deg: num(s["azimuth_deg"])}
      end)

    [entered, imported]
    |> Enum.map(fn rows ->
      rows
      |> Enum.filter(&(is_number(&1.md) and is_number(&1.inc_deg) and is_number(&1.azi_deg)))
      |> Enum.sort_by(& &1.md)
    end)
    |> Enum.find([], &(&1 != []))
    |> Trajectory.tie_in_at_surface()
  end

  defp actual(p) do
    a = %{
      md: num(p["md"]),
      tvd: num(p["tvd"]),
      north: num(p["north_south"]),
      east: num(p["east_west"])
    }

    if Enum.all?(Map.values(a), &is_number/1),
      do: Map.put(a, :projected, Regex.match?(@projected_remark, to_string(p["remarks"])))
  end

  defp row(a, p, vs_azi, plan_end_md) do
    d_n = a.north - p.north
    d_e = a.east - p.east
    d_tvd = a.tvd - p.tvd

    %{
      md: a.md,
      above: -d_tvd,
      ahead: d_n * :math.cos(vs_azi) + d_e * :math.sin(vs_azi),
      right: -d_n * :math.sin(vs_azi) + d_e * :math.cos(vs_azi),
      distance: :math.sqrt(d_n * d_n + d_e * d_e + d_tvd * d_tvd),
      beyond_plan: a.md > plan_end_md,
      projected: a.projected
    }
  end

  defp bearing(rad) do
    deg = rad * 180 / :math.pi()
    if deg < 0, do: deg + 360, else: deg
  end

  defp num(v) when is_number(v), do: v * 1.0
  defp num(%Decimal{} = v), do: Decimal.to_float(v)

  defp num(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp num(_), do: nil
end
