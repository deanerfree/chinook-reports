defmodule ChinookReportsWeb.DirectionalPlanUploadTest do
  @moduledoc """
  Dropping a directional plan file on the Directional Program — in the wizard
  (step 6) and in the report page's Surveys editor — replaces the program's
  rows in the open form, and saving persists them.
  """

  use ChinookReportsWeb.ConnCase

  import Phoenix.LiveViewTest

  alias ChinookReports.Repo
  alias ChinookReports.Reports
  alias ChinookReports.Reports.Report

  @plan_csv """
  H WELL    :,CNRL Hz Wapiti 4-31-64-8W6M
  H07000.00 : 6505.51 : PROPOSAL 4 : MWD+HDGM_REV5
  MD,Incl.,Azim.,TVD,Sub-Sea,NS,EW,VSEC,Dogleg,Comment
  0.00,0.00,0.00,0.00,1116.69,0.00,0.00,0.00,0.0000,\s
  665.00,0.00,0.00,665.00,451.69,0.00,0.00,0.00,0.0000,Nudge, 1.5°/30m
  690.00,1.25,300.00,690.00,426.69,0.14,-0.24,-0.10,1.5000,\s
  735.73,3.54,300.00,735.69,381.00,1.09,-1.89,-0.84,1.5000,PASKAPOO
  """

  @expected [
    {"0.00", "0.00", "0.00"},
    {"665.00", "0.00", "0.00"},
    {"690.00", "1.25", "300.00"},
    {"735.73", "3.54", "300.00"}
  ]

  defp drop_plan(view, form_sel, name, content) do
    view
    |> file_input(form_sel, :plan, [%{name: name, content: content, type: "text/plain"}])
    |> render_upload(name)

    render_async(view, 10_000)
    render(view)
  end

  defp assert_program(surveys) do
    assert length(surveys) == length(@expected)

    for {row, {md, inc, azi}} <- Enum.zip(surveys, @expected) do
      assert Decimal.equal?(row.md, md)
      assert Decimal.equal?(row.inclination, inc)
      assert Decimal.equal?(row.azimuth, azi)
    end
  end

  describe "wizard, Directional Program step" do
    @form_sel ~s(form[phx-submit="create_report"])

    setup do
      {:ok, report} =
        %Report{report_data: %Report.ReportData{}}
        |> Report.changeset(%{
          "well_name" => "Plan Well",
          "unique_well_id" => "100/04-31-064-08W6/00",
          "latitude" => "54.6",
          "longitude" => "-119.2",
          "report_data" => %{"classification" => "DEV"}
        })
        |> Repo.insert()

      %{report: report}
    end

    test "a dropped CSV fills the program and saves with the report", %{
      conn: conn,
      report: report
    } do
      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}/draft")
      render_click(view, "navigate_to_step", %{"step" => "6"})

      html = drop_plan(view, @form_sel, "Proposal 4.csv", @plan_csv)
      assert html =~ "Loaded 4 stations from Proposal 4."

      view |> element(~s(#{@form_sel} button[phx-click="next"])) |> render_click()
      {:error, {:live_redirect, _}} = view |> form(@form_sel, report: %{}) |> render_submit()

      assert_program(Repo.get!(Report, report.id).report_data.surveys)
    end

    test "an unreadable file leaves the program alone and says why", %{conn: conn, report: report} do
      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}/draft")
      render_click(view, "navigate_to_step", %{"step" => "6"})

      html = drop_plan(view, @form_sel, "notes.txt", "not a survey\n")
      assert html =~ "Couldn&#39;t read that plan: No survey listing found"
      refute html =~ ~s(name="report[report_data][surveys][0][md]")
    end
  end

  describe "report page, Surveys editor" do
    test "a dropped CSV replaces the program's rows and saves", %{conn: conn} do
      {:ok, report} =
        Reports.create_report(%{
          "well_name" => "Plan Well",
          "unique_well_id" => "100/04-31-064-08W6/00",
          "status" => "active",
          "report_data" => %{
            "surveys" => %{"0" => %{"md" => "100", "inclination" => "2", "azimuth" => "185"}}
          }
        })

      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}")
      view |> element(~s(button[phx-value-tab="surveys"])) |> render_click()
      view |> element(~s(button[phx-value-section="surveys"])) |> render_click()

      html = drop_plan(view, ~s(form[phx-submit="save_section"]), "Proposal 4.csv", @plan_csv)
      assert html =~ "Loaded 4 stations"

      view |> form(~s(form[phx-submit="save_section"]), report: %{}) |> render_submit()

      assert_program(Reports.get_report!(report.id).report_data.surveys)
    end
  end

  describe "formation tops from a PDF plan" do
    @pdf_sel_wizard ~s(form[phx-submit="create_report"])
    @pdf_sel_page ~s(form[phx-submit="save_section"])

    # The Paradise Hill plan's Formations table, as printed: {name, MD, subsea}.
    @plan_tops [
      {"First_White_Specks", "248.24", "384"},
      {"Second White Specks", "282.99", "350"},
      {"Belle_Fourch", "308.48", "326"},
      {"Base Fish Scales", "353.14", "287"},
      {"St_Walburg_Sand", "376.65", "268.5"},
      {"Westgate_Mbr", "406.36", "247"},
      {"Joli Fou", "452.4", "214"},
      {"Colony", "510.31", "172.5"},
      {"Colony", "523.56", "163"},
      {"Mclaren", "527.75", "160"},
      {"Waseca", "552.86", "142"},
      {"Sparky", "594.72", "112"}
    ]

    defp parse(s), do: elem(Float.parse(s), 0)

    defp drop_pdf(view, form_sel) do
      pdf = File.read!("test/test_data/directional/paradise_hill_plan.pdf")

      view
      |> file_input(form_sel, :plan, [
        %{name: "Plan #2.pdf", content: pdf, type: "application/pdf"}
      ])
      |> render_upload("Plan #2.pdf")

      render_async(view, 30_000)
      render(view)
    end

    defp wizard_report do
      {:ok, report} =
        %Report{report_data: %Report.ReportData{}}
        |> Report.changeset(%{
          "well_name" => "Plan Well",
          "unique_well_id" => "1QQ/16-10-054-24W3/00",
          "latitude" => "53.6",
          "longitude" => "-109.4",
          "report_data" => %{
            "classification" => "DEV",
            "formation_tops" => %{
              "0" => %{"formation" => "JOLI FOU", "md" => "450", "isopach" => "40"},
              "1" => %{"formation" => "Lloydminster", "md" => "560"}
            }
          }
        })
        |> Repo.insert()

      report
    end

    test "wizard: asks, then fills the Formation Tops step and saves it with the report", %{
      conn: conn
    } do
      report = wizard_report()
      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}/draft")
      render_click(view, "navigate_to_step", %{"step" => "6"})

      html = drop_pdf(view, @pdf_sel_wizard)
      assert html =~ "This plan also lists 12 formation tops"

      html = view |> element("#plan-tops-prompt button", "Import tops") |> render_click()
      refute html =~ "plan-tops-prompt"
      assert html =~ "Imported 12 formation tops into the Formation Tops step."

      view |> element(~s(#{@pdf_sel_wizard} button[phx-click="next"])) |> render_click()

      {:error, {:live_redirect, _}} =
        view |> form(@pdf_sel_wizard, report: %{}) |> render_submit()

      tops = Repo.get!(Report, report.id).report_data.formation_tops

      # Every plan row, plus the row the plan doesn't list; the existing
      # Joli Fou row keeps its name.
      assert Enum.map(tops, & &1.formation) == [
               "First_White_Specks",
               "Second White Specks",
               "Belle_Fourch",
               "Base Fish Scales",
               "St_Walburg_Sand",
               "Westgate_Mbr",
               "JOLI FOU",
               "Colony",
               "Colony",
               "Mclaren",
               "Waseca",
               "Lloydminster",
               "Sparky"
             ]

      joli = Enum.find(tops, &(&1.formation == "JOLI FOU"))
      assert Decimal.equal?(joli.md, "452.4")
      assert Decimal.equal?(joli.subsea, "214")
      # Isopach is calculated, not kept: the plan's TVD down to Colony,
      # 459.68 − 418.18 (the hole is deviated — the MD gap is 57.91).
      assert Decimal.equal?(joli.isopach, "41.5")
    end

    test "wizard: Skip leaves Formation Tops alone", %{conn: conn} do
      report = wizard_report()
      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}/draft")
      render_click(view, "navigate_to_step", %{"step" => "6"})

      drop_pdf(view, @pdf_sel_wizard)
      html = view |> element("#plan-tops-prompt button", "Skip") |> render_click()
      refute html =~ "plan-tops-prompt"

      view |> element(~s(#{@pdf_sel_wizard} button[phx-click="next"])) |> render_click()

      {:error, {:live_redirect, _}} =
        view |> form(@pdf_sel_wizard, report: %{}) |> render_submit()

      assert Enum.map(Repo.get!(Report, report.id).report_data.formation_tops, & &1.formation) ==
               ["JOLI FOU", "Lloydminster"]
    end

    test "report page: fills the imported tops' Prognosis column and keeps the picks", %{
      conn: conn
    } do
      {:ok, report} =
        Reports.create_report(%{
          "well_name" => "Plan Well",
          "unique_well_id" => "1QQ/16-10-054-24W3/00",
          "status" => "active",
          "import_data" => %{
            "welldata" => %{"elevations" => %{"kelly_bushing" => 632.18}},
            "tops" => %{
              "formations" => [
                %{
                  "formation" => "Colony",
                  "prognosis" => %{"md" => nil, "subsea" => nil},
                  "samples" => %{"md" => 511.0},
                  "mwd_gamma" => %{}
                }
              ]
            }
          }
        })

      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}")
      view |> element(~s(button[phx-value-tab="surveys"])) |> render_click()
      view |> element(~s(button[phx-value-section="surveys"])) |> render_click()

      html = drop_pdf(view, @pdf_sel_page)
      assert html =~ "Fills the Prognosis column"

      html = view |> element("#plan-tops-prompt button", "Import tops") |> render_click()
      assert html =~ "Imported 12 formation tops into Formation Tops."

      formations = Reports.get_report!(report.id).import_data["tops"]["formations"]

      assert for(f <- formations, do: {f["formation"], f["prognosis"]["md"]}) ==
               for({name, md, _} <- @plan_tops, do: {name, String.to_float(md)})

      colony = hd(Enum.filter(formations, &(&1["formation"] == "Colony")))
      assert colony["samples"]["md"] == 511.0
      assert colony["prognosis"]["subsea"] == 172.5
    end

    test "report page: with no tops table yet, the plan starts one's Prognosis", %{conn: conn} do
      {:ok, report} =
        Reports.create_report(%{
          "well_name" => "Plan Well",
          "unique_well_id" => "1QQ/16-10-054-24W3/00",
          "status" => "active"
        })

      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}")
      view |> element(~s(button[phx-value-tab="surveys"])) |> render_click()
      view |> element(~s(button[phx-value-section="surveys"])) |> render_click()

      drop_pdf(view, @pdf_sel_page)
      view |> element("#plan-tops-prompt button", "Import tops") |> render_click()

      formations = Reports.get_report!(report.id).import_data["tops"]["formations"]

      assert for(
               f <- formations,
               do: {f["formation"], f["prognosis"]["md"], f["prognosis"]["subsea"]}
             ) ==
               for({name, md, ss} <- @plan_tops, do: {name, String.to_float(md), parse(ss)})
    end
  end

  describe "empty Formation Tops" do
    @tops_form "#tops-form-formation-tops"

    defp empty_tops_report(attrs \\ %{}) do
      {:ok, report} =
        Reports.create_report(
          Map.merge(
            %{
              "well_name" => "Plan Well",
              "unique_well_id" => "1QQ/16-10-054-24W3/00",
              "status" => "active",
              "import_data" => %{
                "welldata" => %{"elevations" => %{"kelly_bushing" => 632.18}},
                "tops" => %{"formations" => []}
              }
            },
            attrs
          )
        )

      report
    end

    defp open_tops(conn, report) do
      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}")
      html = view |> element(~s(button[phx-value-tab="formation_tops"])) |> render_click()
      {view, html}
    end

    test "imported tops: opens in Prognosis editing with a drop zone", %{conn: conn} do
      {view, _html} = open_tops(conn, empty_tops_report())

      assert has_element?(view, "#tops-plan-drop-formation-tops")
      assert has_element?(view, ~s(input[name="tops[rows][0][prognosis][md]"]))
      assert has_element?(view, ~s(button[phx-click="add_row"]), "Add formation")
    end

    test "imported tops: a dropped PDF fills Prognosis, saved on Save", %{conn: conn} do
      report = empty_tops_report()
      {view, _html} = open_tops(conn, report)

      html = drop_pdf(view, @tops_form)
      assert html =~ "Loaded 12 formation tops from the plan."
      assert has_element?(view, ~s(input[name="tops[rows][11][formation]"][value="Sparky"]))
      # Nothing saved yet.
      assert Reports.get_report!(report.id).import_data["tops"]["formations"] == []

      view |> form(@tops_form) |> render_submit()

      formations = Reports.get_report!(report.id).import_data["tops"]["formations"]

      assert for(f <- formations, do: {f["formation"], f["prognosis"]["md"]}) ==
               for({name, md, _} <- @plan_tops, do: {name, String.to_float(md)})

      refute has_element?(view, "#tops-plan-drop-formation-tops")
    end

    test "imported tops: a top typed by hand saves", %{conn: conn} do
      report = empty_tops_report()
      {view, _html} = open_tops(conn, report)

      view
      |> form(@tops_form,
        tops: %{rows: %{"0" => %{formation: "Colony", prognosis: %{md: "510", subsea: "172.5"}}}}
      )
      |> render_submit()

      assert [%{"formation" => "Colony", "prognosis" => %{"md" => 510.0}}] =
               Reports.get_report!(report.id).import_data["tops"]["formations"]
    end

    test "imported tops: a CSV plan has no tops to load", %{conn: conn} do
      {view, _html} = open_tops(conn, empty_tops_report())

      html = drop_plan(view, @tops_form, "Proposal 4.csv", @plan_csv)
      assert html =~ "No formation tops found in that file"
    end

    test "a draft report is not opened for editing", %{conn: conn} do
      {view, html} = open_tops(conn, empty_tops_report(%{"status" => "draft"}))

      refute has_element?(view, "#tops-plan-drop-formation-tops")
      assert html =~ "No formation tops recorded."
    end

    test "no tops at all: the full editor opens with a drop zone; Save starts the table", %{
      conn: conn
    } do
      report = empty_tops_report(%{"import_data" => %{}})
      {view, _html} = open_tops(conn, report)

      assert has_element?(view, "#tops-plan-drop-formation-tops")

      drop_pdf(view, @tops_form)
      assert Reports.get_report!(report.id).import_data["tops"] == nil

      view |> form(@tops_form) |> render_submit()

      formations = Reports.get_report!(report.id).import_data["tops"]["formations"]
      assert Enum.map(formations, & &1["formation"]) == Enum.map(@plan_tops, &elem(&1, 0))
      # First White Specks → Second White Specks: subsea 384 − 350
      assert hd(formations)["prognosis"]["isopach"] == 34.0
    end

    test "imported tops: with no KB, TVD stays blank (the plan's is from its KB); isopach from subsea",
         %{conn: conn} do
      report = empty_tops_report(%{"import_data" => %{"tops" => %{"formations" => []}}})
      {view, _html} = open_tops(conn, report)

      drop_pdf(view, @tops_form)
      view |> form(@tops_form) |> render_submit()

      [first | _] = formations = Reports.get_report!(report.id).import_data["tops"]["formations"]
      assert first["prognosis"]["tvd"] == nil
      # First White Specks → Second White Specks: subsea 384 − 350
      assert first["prognosis"]["isopach"] == 34.0
      assert List.last(formations)["prognosis"]["isopach"] == nil
    end

    test "imported tops: TVD is our KB − the plan's subsea, not the plan's TVD", %{conn: conn} do
      # Our KB sits 2 m above the plan's (632.18), so every TVD is 2 m deeper.
      report =
        empty_tops_report(%{
          "import_data" => %{
            "welldata" => %{"elevations" => %{"kelly_bushing" => 634.18}},
            "tops" => %{"formations" => []}
          }
        })

      {view, _html} = open_tops(conn, report)
      drop_pdf(view, @tops_form)
      view |> form(@tops_form) |> render_submit()

      [first | _] = Reports.get_report!(report.id).import_data["tops"]["formations"]
      assert first["prognosis"]["subsea"] == 384.0
      assert first["prognosis"]["tvd"] == 250.2
    end
  end
end
