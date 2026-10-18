defmodule ChinookReportsWeb.CreateReportLiveCancelTest do
  use ChinookReportsWeb.ConnCase

  import Phoenix.LiveViewTest

  alias ChinookReports.Repo
  alias ChinookReports.Reports
  alias ChinookReports.Reports.Report

  @cancel_sel ~s(button[phx-click="cancel"])

  defp report(status) do
    {:ok, report} =
      Reports.create_report(%{
        "well_name" => "Gear Soda Lake 103 HZ",
        "unique_well_id" => "100/16-36-046-23W3/00",
        "country" => "Canada",
        "status" => status
      })

    report
  end

  test "cancelling a draft well deletes it", %{conn: conn} do
    draft = report("draft")
    {:ok, view, _html} = live(conn, ~p"/reports/#{draft.id}/draft")

    assert view |> element(@cancel_sel) |> render() =~ "Cancel well"

    assert {:error, {:live_redirect, %{to: "/reports"}}} =
             view |> element(@cancel_sel) |> render_click()

    refute Repo.get(Report, draft.id)
  end

  test "cancelling an edit of an active report keeps the report", %{conn: conn} do
    active = report("active")
    {:ok, view, _html} = live(conn, ~p"/reports/#{active.id}/draft")

    to = "/reports/#{active.id}"

    assert {:error, {:live_redirect, %{to: ^to}}} =
             view |> element(@cancel_sel) |> render_click()

    assert Repo.get(Report, active.id)
  end

  test "cancelling a new, unsaved report goes back to the list", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/create_report")

    assert {:error, {:live_redirect, %{to: "/reports"}}} =
             view |> element(@cancel_sel) |> render_click()
  end
end
