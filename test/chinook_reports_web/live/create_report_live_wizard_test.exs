defmodule ChinookReportsWeb.CreateReportLiveWizardTest do
  @moduledoc """
  End-to-end coverage for the report wizard (CreateReportLive): every field on
  every step, for both the create and the edit flow, driven exactly the way a
  browser would drive it (step-by-step, only touching what's on-screen for the
  current step) and asserted against the row actually written to the DB.

  This exists because the wizard has repeatedly lost data silently: a field
  looks fine in the form but never reaches the database, because either (a) a
  later step's `phx-change`/submit only carries the fields visible on that
  step, and the changeset-accumulation logic dropped earlier steps' edits, or
  (b) a field's name didn't match anything in the schema/changeset at all. Any
  regression of either kind should fail one of these tests.
  """

  use ChinookReportsWeb.ConnCase

  import Phoenix.LiveViewTest

  alias ChinookReports.Repo
  alias ChinookReports.Reports.Report

  @form_sel ~s(form[phx-submit="update"])

  # Values for every field across every step, keyed the same way the wizard's
  # own `phx-change`/submit params are shaped. Reused by both the create and
  # the edit test so the two flows are asserted against the same expectations.
  @step1 %{
    "well_name" => "Gear Soda Lake 103 HZ",
    "unique_well_id" => "100/16-36-046-23W3M/00",
    "operator" => "Chinook Petroleum Ltd.",
    "country" => "Canada",
    "province" => "Alberta",
    "geometry" => "Horizontal",
    "target_formation" => "Cardium",
    "secondary_target" => "Viking",
    "units" => "imperial"
  }

  @step2 %{
    "latitude" => "51.05",
    "longitude" => "-114.07",
    "report_data" => %{
      "gl_elevation" => "884.5",
      "kb_elevation" => "891.2",
      "kb_to_ground" => "6.7",
      "datum" => "NTS",
      "surface_coordinates" => "15-31-46-23W3M"
    }
  }

  @step3 %{
    "report_data" => %{
      "classification" => "DEV",
      "license" => "0123456",
      "purpose" => "Production",
      "substance" => "Oil",
      "terminating_zone" => "Cardium"
    }
  }

  @profile_row %{"section" => "Lateral", "start_depth" => "1200", "end_depth" => "2400"}
  @formation_top_row %{"formation" => "McLaren", "md" => "1500", "tvd" => "1490", "subsea" => "-800"}
  @survey_row %{"md" => "1000", "inclination" => "45", "azimuth" => "180"}

  describe "creating a report" do
    test "every field entered across every step reaches the database", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/create_report")

      fill_step1(view, @step1)
      next(view)

      fill_step2(view, @step2)
      next(view)

      fill_step3(view, @step3)
      next(view)

      add_row_and_fill(view, "profile_sections", @profile_row)
      next(view)

      add_row_and_fill(view, "formation_tops", @formation_top_row)
      next(view)

      add_row_and_fill(view, "surveys", @survey_row)

      {:error, {:live_redirect, %{to: to}}} = submit(view)

      created = Repo.get_by!(Report, unique_well_id: @step1["unique_well_id"])
      assert to == "/reports/#{created.id}"

      assert_step1(created, @step1)
      assert_step2(created, @step2)
      assert_step3(created, @step3)
      assert_row(hd(created.report_data.profile_sections), @profile_row)
      assert_row(hd(created.report_data.formation_tops), @formation_top_row)
      assert_row(hd(created.report_data.surveys), @survey_row)
    end
  end

  describe "editing a report" do
    setup do
      {:ok, report} =
        %Report{report_data: %Report.ReportData{}}
        |> Report.changeset(%{
          "well_name" => "Original Well",
          "unique_well_id" => "ORIG-001",
          "operator" => "Original Operator"
        })
        |> Repo.insert()

      %{report: report}
    end

    test "every field edited across every step reaches the database", %{
      conn: conn,
      report: report
    } do
      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}/edit")

      fill_step1(view, @step1)
      next(view)

      fill_step2(view, @step2)
      next(view)

      fill_step3(view, @step3)
      next(view)

      add_row_and_fill(view, "profile_sections", @profile_row)
      next(view)

      add_row_and_fill(view, "formation_tops", @formation_top_row)
      next(view)

      add_row_and_fill(view, "surveys", @survey_row)

      {:error, {:live_redirect, %{to: to}}} = submit(view)

      updated = Repo.get!(Report, report.id)
      assert to == "/reports/#{updated.id}"

      assert_step1(updated, @step1)
      assert_step2(updated, @step2)
      assert_step3(updated, @step3)
      assert_row(hd(updated.report_data.profile_sections), @profile_row)
      assert_row(hd(updated.report_data.formation_tops), @formation_top_row)
      assert_row(hd(updated.report_data.surveys), @survey_row)
    end

    test "fields left untouched on earlier steps survive edits made on later steps", %{
      conn: conn,
      report: report
    } do
      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}/edit")

      # Only step 1 is touched; every later step is just "Next" through
      # without changing anything, including report_data-owning steps 2/3/4.
      view
      |> form(@form_sel, report: %{"well_name" => "Renamed Well"})
      |> render_change()

      for _ <- 1..5, do: next(view)

      {:error, {:live_redirect, _}} = submit(view)

      updated = Repo.get!(Report, report.id)
      assert updated.well_name == "Renamed Well"
      # untouched field from the original record must survive
      assert updated.operator == "Original Operator"
    end
  end

  # ── step fillers ─────────────────────────────────────────────────────────

  defp fill_step1(view, attrs) do
    view |> form(@form_sel, report: attrs) |> render_change()
  end

  defp fill_step2(view, attrs) do
    view |> form(@form_sel, report: attrs) |> render_change()
  end

  defp fill_step3(view, attrs) do
    view |> form(@form_sel, report: attrs) |> render_change()
  end

  defp add_row_and_fill(view, list, row_attrs) do
    view
    |> element(~s(#{@form_sel} button[phx-click="add_row"][phx-value-list="#{list}"]))
    |> render_click()

    view
    |> form(@form_sel, report: %{"report_data" => %{list => %{"0" => row_attrs}}})
    |> render_change()
  end

  defp next(view) do
    view |> element(~s(#{@form_sel} button[phx-click="next"])) |> render_click()
  end

  defp submit(view) do
    view |> form(@form_sel, report: %{}) |> render_submit()
  end

  # ── assertions ───────────────────────────────────────────────────────────

  defp assert_step1(report, expected) do
    assert report.well_name == expected["well_name"]
    assert report.unique_well_id == expected["unique_well_id"]
    assert report.operator == expected["operator"]
    assert report.country == expected["country"]
    assert report.province == expected["province"]
    assert report.geometry == expected["geometry"]
    assert report.target_formation == expected["target_formation"]
    assert report.secondary_target == expected["secondary_target"]
    assert report.units == expected["units"]
  end

  defp assert_step2(report, expected) do
    assert report.latitude == String.to_float(expected["latitude"])
    assert report.longitude == String.to_float(expected["longitude"])
    data = expected["report_data"]
    assert Decimal.equal?(report.report_data.gl_elevation, Decimal.new(data["gl_elevation"]))
    assert Decimal.equal?(report.report_data.kb_elevation, Decimal.new(data["kb_elevation"]))
    assert Decimal.equal?(report.report_data.kb_to_ground, Decimal.new(data["kb_to_ground"]))
    assert report.report_data.datum == data["datum"]
    assert report.report_data.surface_coordinates == data["surface_coordinates"]
  end

  defp assert_step3(report, expected) do
    data = expected["report_data"]
    assert report.report_data.classification == data["classification"]
    assert report.report_data.license == data["license"]
    assert report.report_data.purpose == data["purpose"]
    assert report.report_data.substance == data["substance"]
    assert report.report_data.terminating_zone == data["terminating_zone"]
  end

  defp assert_row(row, expected) do
    for {key, value} <- expected do
      actual = Map.fetch!(row, String.to_existing_atom(key))

      matches? =
        case actual do
          %Decimal{} -> Decimal.equal?(actual, Decimal.new(value))
          _ -> actual == value
        end

      assert matches?, "expected #{key} to be #{value}, got #{inspect(actual)}"
    end
  end
end
