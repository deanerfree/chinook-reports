defmodule ChinookReportsWeb.CreateReportLiveUWITest do
  use ChinookReportsWeb.ConnCase

  import Phoenix.LiveViewTest

  alias ChinookReports.Countries

  @form_sel ~s(form[phx-submit="create_report"])
  @next_sel ~s(#{@form_sel} button[phx-click="next"])

  defp fill(view, attrs), do: view |> form(@form_sel, report: attrs) |> render_change()

  test "Country is a dropdown of the shared country list", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/create_report")

    options =
      view
      |> element(~s(select[name="report[country]"]))
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("option")
      |> Enum.map(&(&1 |> Floki.text() |> String.trim()))
      |> Enum.reject(&(&1 == ""))

    assert options == Countries.all()
  end

  test "a bad Canadian UWI is flagged and holds the step until fixed", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/create_report")

    html =
      fill(view, %{
        "well_name" => "Test",
        "country" => "Canada",
        "unique_well_id" => "101/20-20-20-20W20/00"
      })

    assert html =~ "must be a Canada UWI"
    assert view |> element(@next_sel) |> render() =~ "disabled"

    fill(view, %{"unique_well_id" => "100/16-36-046-23W3/00"})
    refute view |> element(@next_sel) |> render() =~ "disabled"
  end

  test "outside Canada any UWI is accepted", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/create_report")

    html =
      fill(view, %{
        "well_name" => "Test",
        "country" => "Romania",
        "unique_well_id" => "Bustuchin-1"
      })

    refute html =~ "UWI, e.g."
    refute view |> element(@next_sel) |> render() =~ "disabled"
  end
end
