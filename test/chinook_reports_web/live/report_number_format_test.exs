defmodule ChinookReportsWeb.ReportNumberFormatTest do
  @moduledoc """
  Every number the report page shows — on every tab, read-only and in edit
  mode — carries at most two decimal places, for each real extracted report
  under `test/test_data`. (The extractor writes full-precision floats like
  124.93684; the stored values keep that precision, only the display rounds.)

  Only rendered text and input values are checked: chart props in
  `data-props` attributes are data for the Svelte components, not display.

  Two kinds of value are exempt, since rounding them would misstate them:
  geographic coordinates (0.01° of latitude is ~1 km) and the directional
  survey (the Surveys tab), which keep their precision — see the last describe.
  """
  use ChinookReportsWeb.ConnCase

  import Phoenix.LiveViewTest

  alias ChinookReports.HandleData

  @wolverine Path.join([
               File.cwd!(),
               "test",
               "test_data",
               "WOLVERINE CREEK LLOYDMINSTER HZ 5-30-49-1W4M (12-19) Final Report.json"
             ])
  @northern_hawk Path.join([
                   File.cwd!(),
                   "test",
                   "test_data",
                   "NORTHERN HAWK KERROBERT 2-27-32-23 Report 2025.json"
                 ])

  @files Path.wildcard(Path.join([File.cwd!(), "test", "test_data", "*.json"]))

  # Three or more digits after a decimal point.
  @too_precise ~r/\d+\.\d{3,}/

  defp load(path) do
    {:ok, report} = path |> File.read!() |> Jason.decode!() |> HandleData.store_report_data()
    {:ok, report} = ChinookReports.Reports.update_report(report, %{"status" => "active"})
    report
  end

  # Values allowed past two decimals: coordinates, and survey stations.
  defp coordinates(report) do
    coords =
      get_in(report.import_data, ["welldata", "location_data", "geographic_coordinates"]) || %{}

    coordinates =
      for key <- ~w(latitude longitude),
          v = coords[key],
          is_float(v),
          do: v |> abs() |> to_string()

    # survey stations (e.g. the Summary's "last survey") show at survey precision
    stations =
      for leg <- report.import_data["reservoir_data"] || [],
          p <- get_in(leg, ["survey", "survey_points"]) || [],
          key <- ~w(md tvd inclination_deg azimuth_deg),
          is_number(p[key]),
          do: p[key] |> abs() |> ChinookReportsWeb.NumberFormat.survey()

    coordinates ++ stations
  end

  # Visible text plus the values sitting in inputs / textareas.
  defp shown(html) do
    doc = Floki.parse_document!(html)
    text = Floki.text(doc, sep: " ")
    inputs = doc |> Floki.find("input[type=text], input[type=number]") |> Floki.attribute("value")
    [text | inputs]
  end

  defp offenders(html, allowed) do
    html
    |> shown()
    |> Enum.flat_map(&Regex.scan(@too_precise, &1))
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.reject(&(&1 in allowed))
  end

  defp tab_ids(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("button[phx-value-tab]")
    |> Floki.attribute("phx-value-tab")
  end

  for path <- @files do
    @path path
    test "#{Path.basename(path)}: no tab shows more than 2 decimals", %{conn: conn} do
      report = load(@path)
      allowed = coordinates(report)
      {:ok, view, html} = live(conn, ~p"/reports/#{report.id}")

      found =
        for tab <- tab_ids(view) -- ["surveys"],
            reduce: %{"summary" => offenders(html, allowed)} do
          acc ->
            html = view |> element(~s(button[phx-value-tab="#{tab}"])) |> render_click()
            view_mode = offenders(html, allowed)

            # open every editor on the tab and check its inputs too
            edit_mode =
              view
              |> render()
              |> Floki.parse_document!()
              |> Floki.find(~s(button[phx-click="edit"]))
              |> Enum.flat_map(fn btn ->
                target = btn |> Floki.attribute("phx-target") |> List.first()

                html =
                  view
                  |> element(~s(button[phx-click="edit"][phx-target="#{target}"]))
                  |> render_click()

                offenders(html, allowed)
              end)

            Map.put(acc, tab, Enum.uniq(view_mode ++ edit_mode))
        end
        |> Enum.reject(fn {_tab, nums} -> nums == [] end)
        |> Map.new()

      assert found == %{}
    end
  end

  describe "surveys keep their precision" do
    test "the imported survey shows stations as extracted, view and edit", %{conn: conn} do
      report = load(@wolverine)
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      html = view |> element(~s(button[phx-value-tab="surveys"])) |> render_click()

      # an MD of 124.93684 and an inclination of 84.845, not 124.94 / 84.85
      assert html =~ "124.93684"
      assert html =~ "84.845"

      view |> element(~s(#survey-0 button[phx-click="edit"])) |> render_click()
      assert has_element?(view, ~s(#survey-0-form input[value="124.93684"]))
    end

    test "computed float noise is trimmed to the survey's 5 decimals", %{conn: conn} do
      # Northern Hawk's extracted N/S carries full doubles (0.012399953868980455)
      report = load(@northern_hawk)
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      html = view |> element(~s(button[phx-value-tab="surveys"])) |> render_click()

      assert html =~ "0.0124"
      refute html =~ "0.012399953868980455"
      refute Regex.match?(~r/\d\.\d{6,}/, html |> Floki.parse_document!() |> Floki.text())
    end
  end

  describe "saving keeps the stored precision" do
    test "editing one Mud Log cell leaves every full-precision depth untouched", %{conn: conn} do
      report = load(@wolverine)
      before = report.import_data["mud_log"]
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      view |> element(~s(button[phx-value-tab="mud_log"])) |> render_click()
      view |> element(~s(#import-mud_log button[phx-click="edit"])) |> render_click()

      # the input shows 124.94 …
      assert has_element?(view, ~s(input[name="rows[0][depth]"][value="124.94"]))

      view
      |> form("#import-mud_log-form", rows: %{"0" => %{remarks: "Checked"}})
      |> render_submit()

      after_save = ChinookReports.Reports.get_report!(report.id).import_data["mud_log"]
      # … but the stored 124.93684 survives the round trip
      assert hd(after_save)["depth"] == 124.93684
      assert hd(after_save)["remarks"] == "Checked"
      assert tl(after_save) == tl(before)
    end

    test "saving an untouched survey changes nothing", %{conn: conn} do
      report = load(@wolverine)
      before = hd(report.import_data["reservoir_data"])["survey"]
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      view |> element(~s(button[phx-value-tab="surveys"])) |> render_click()
      view |> element(~s(#survey-0 button[phx-click="edit"])) |> render_click()
      view |> form("#survey-0-form") |> render_submit()

      reloaded = ChinookReports.Reports.get_report!(report.id).import_data
      assert hd(reloaded["reservoir_data"])["survey"] == before
    end

    test "a Well Data card keeps full-precision values and coordinates", %{conn: conn} do
      report = load(@wolverine)
      before = report.import_data["welldata"]
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      view |> element(~s(button[phx-value-tab="well_data"])) |> render_click()

      for card <- ~w(location total_depth elevations) do
        view |> element(~s(#well-data-#{card} button[phx-click="edit"])) |> render_click()
        view |> form("#well-data-#{card}-form") |> render_submit()
      end

      after_save = ChinookReports.Reports.get_report!(report.id).import_data["welldata"]
      assert after_save["location_data"] == before["location_data"]
      assert after_save["total_depth_actual"] == before["total_depth_actual"]
      assert after_save["elevations"] == before["elevations"]
    end
  end
end
