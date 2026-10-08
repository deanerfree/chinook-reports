defmodule ChinookReportsWeb.CreateReportLiveStepperTest do
  @moduledoc """
  The stepper's rules: a connector is solid only once the step it leaves has
  all its mandatory fields; Next is disabled until the current step's
  mandatory fields are filled; you can only click ahead to a step whose
  predecessors are all complete.
  """

  use ChinookReportsWeb.ConnCase

  import Phoenix.LiveViewTest

  alias ChinookReports.Repo
  alias ChinookReports.Reports.Report

  @form_sel ~s(form[phx-submit="create_report"])

  defp stepper_html(view) do
    view |> render() |> then(&Regex.run(~r{<ol class="flex w-full.*?</ol>}s, &1)) |> hd()
  end

  defp solid_connectors(view),
    do: stepper_html(view) |> then(&Regex.scan(~r/border-primary/, &1)) |> length()

  defp next_disabled?(view) do
    view
    |> element(~s(#{@form_sel} button[phx-click="next"]))
    |> render()
    |> String.contains?("disabled")
  end

  describe "fresh report" do
    test "Next is disabled and no connector is solid until step 1 is complete", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/create_report")

      assert next_disabled?(view)
      # circles can carry border-primary (the active ring), so compare a baseline
      base = solid_connectors(view)

      view
      |> form(@form_sel, report: %{"well_name" => "W", "unique_well_id" => "UWI-1"})
      |> render_change()

      refute next_disabled?(view)
      assert solid_connectors(view) > base
    end

    test "cannot Next past an incomplete later step", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/create_report")

      view
      |> form(@form_sel, report: %{"well_name" => "W", "unique_well_id" => "UWI-1"})
      |> render_change()

      view |> element(~s(#{@form_sel} button[phx-click="next"])) |> render_click()
      # now on step 2 (Elevations & Location) with nothing filled
      assert next_disabled?(view)

      view
      |> form(@form_sel, report: %{"latitude" => "50.1", "longitude" => "-113.2"})
      |> render_change()

      refute next_disabled?(view)
    end
  end

  describe "saved draft" do
    setup do
      {:ok, report} =
        %Report{report_data: %Report.ReportData{}}
        |> Report.changeset(%{
          "well_name" => "Draft Well",
          "unique_well_id" => "DRAFT-1",
          "latitude" => "50.1",
          "longitude" => "-113.2",
          "status" => "draft",
          "report_data" => %{"classification" => "DEV"}
        })
        |> Repo.insert()

      %{report: report}
    end

    test "a complete draft lets you jump straight to any step", %{conn: conn, report: report} do
      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}/draft")

      # steps 1-3 have their mandatory fields; 4-6 have none -> all reachable
      for step <- [3, 5, 6] do
        assert view
               |> element(~s(button[phx-click="navigate_to_step"][phx-value-step="#{step}"]))
               |> has_element?()
      end
    end

    test "an incomplete draft locks the steps past the gap", %{conn: conn} do
      {:ok, report} =
        %Report{report_data: %Report.ReportData{}}
        |> Report.changeset(%{
          "well_name" => "Half Draft",
          "unique_well_id" => "HALF-1",
          "status" => "draft"
        })
        |> Repo.insert()

      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}/draft")

      # step 2's mandatory latitude/longitude are missing, so step 3 is not clickable
      refute view
             |> element(~s(button[phx-click="navigate_to_step"][phx-value-step="3"]))
             |> has_element?()
    end
  end
end
