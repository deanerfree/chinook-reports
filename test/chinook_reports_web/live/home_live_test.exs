defmodule ChinookReportsWeb.HomeLiveTest do
  use ChinookReportsWeb.ConnCase

  import Phoenix.LiveViewTest

  alias ChinookReports.Reports

  @prairie "PRAIRIE FALCON CARSLAND 7-14-18-25W4 Report 2026.json"

  defp create_report(attrs) do
    {:ok, report} =
      Reports.create_report(
        Map.merge(
          %{
            "well_name" => "Well #{System.unique_integer([:positive])}",
            "unique_well_id" => "UWI-#{System.unique_integer([:positive])}"
          },
          attrs
        )
      )

    report
  end

  defp prairie_import do
    Path.join([File.cwd!(), "test", "test_data", @prairie])
    |> File.read!()
    |> Jason.decode!()
    |> Map.drop(["metadata"])
  end

  test "an empty system says nothing is drilling", %{conn: conn} do
    # The sandbox rolls this back; it only shields the test from stray rows.
    ChinookReports.Repo.delete_all(ChinookReports.Reports.Report)
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Dashboard"
    assert html =~ "No wells are drilling"
    assert html =~ "No drafts in progress."
  end

  test "lists drilling wells with their digest, drafts and completed reports", %{conn: conn} do
    active =
      create_report(%{
        "well_name" => "Prairie Falcon",
        "status" => "active",
        "geometry" => "Deviated",
        "import_data" => prairie_import()
      })

    draft = create_report(%{"well_name" => "Half Done", "status" => "draft"})
    create_report(%{"well_name" => "All Wrapped Up", "status" => "complete"})

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Prairie Falcon"
    assert html =~ ~s(href="/reports/#{active.id}")
    assert html =~ "1145 m MD"
    assert html =~ "DETRITAL (low)"
    assert html =~ "Deviated"
    assert html =~ ~r/\d+(\.\d{1,2})? m [NESW]/

    assert html =~ "Half Done"
    assert html =~ ~s(href="/reports/#{draft.id}/draft")
    assert html =~ "All Wrapped Up"
  end

  test "count tiles link to the reports list filtered by status", %{conn: conn} do
    create_report(%{"status" => "active"})
    {:ok, view, _html} = live(conn, ~p"/")

    href =
      view
      |> element("a", "Drilling now")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("href")
      |> hd()

    assert URI.decode_query(URI.parse(href).query) == %{
             "filters[0][field]" => "status",
             "filters[0][value]" => "active"
           }

    {:ok, _view, html} = live(conn, href)
    assert html =~ "Reports"
  end
end
