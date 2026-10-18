defmodule ChinookReportsWeb.CreateReportLiveDatumPlaceholderTest do
  use ChinookReportsWeb.ConnCase

  import Phoenix.LiveViewTest

  @form_sel ~s(form[phx-submit="create_report"])

  # The Location step's example values follow the selected Datum, so each
  # hints at that system's own coordinate format.
  test "Location placeholders change with the selected datum", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/create_report")

    view
    |> form(@form_sel, report: %{"well_name" => "W", "unique_well_id" => "UWI-1"})
    |> render_change()

    view |> element(~s(#{@form_sel} button[phx-click="next"])) |> render_click()

    for {datum, lat, long, surface} <- [
          {"ATS", "54.1234", "115.5678", "06-12-045-05W5"},
          {"DLS", "49.8765", "103.4321", "16-24-012-09W2"},
          {"NTS", "56.9123", "121.4567", "A-034-L/094-B-16"},
          {"UTM", "5967432", "412345", "Zone 11U, 412345 E, 5967432 N"},
          {"Other", "52.5000", "113.5000", "Describe the surface location"}
        ] do
      html =
        view
        |> form(@form_sel, report: %{"report_data" => %{"datum" => datum}})
        |> render_change()

      assert html =~ ~s(placeholder="#{lat}"), datum
      assert html =~ ~s(placeholder="#{long}"), datum
      assert html =~ ~s(placeholder="#{surface}"), datum
    end
  end
end
