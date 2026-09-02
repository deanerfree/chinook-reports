defmodule ChinookReportsWeb.ReportPageLiveTest do
  @moduledoc """
  Coverage for per-section editing on the report page. Editing is only offered
  when the report's status is "active"; each section saves independently
  through `Reports.update_report/2` and the changes must reach the DB row.
  """

  use ChinookReportsWeb.ConnCase

  import Phoenix.LiveViewTest

  alias ChinookReports.Reports

  defp create_report(attrs) do
    {:ok, report} =
      Reports.create_report(
        Map.merge(
          %{
            "well_name" => "Test Well",
            "unique_well_id" => "100/01-01-001-01W1M/00",
            "status" => "active"
          },
          attrs
        )
      )

    report
  end

  defp open_tab(view, tab) do
    view |> element(~s(button[phx-value-tab="#{tab}"])) |> render_click()
  end

  defp tops_report(attrs \\ %{}) do
    survey_points = for md <- 0..900//100, do: %{"md" => md * 1.0, "tvd" => md * 1.0}

    import_data = %{
      "welldata" => %{"elevations" => %{"kelly_bushing" => 600.0}},
      "reservoir_data" => [
        %{"leg_name" => "Lateral", "survey" => %{"survey_points" => survey_points}}
      ],
      "tops" => %{
        "formations" => [
          %{
            "formation" => "Colony",
            "prognosis" => %{"md" => 300.0, "tvd" => 298.0},
            "samples" => %{"md" => 305.0},
            "mwd_gamma" => %{}
          },
          %{
            "formation" => "McLaren",
            "prognosis" => %{"md" => 500.0, "tvd" => 495.0},
            "samples" => %{"md" => 510.0},
            "mwd_gamma" => %{}
          }
        ]
      }
    }

    create_report(Map.merge(%{"status" => "active", "import_data" => import_data}, attrs))
  end

  describe "edit affordance gating" do
    test "an active report shows per-section Edit buttons", %{conn: conn} do
      report = create_report(%{"status" => "active"})
      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}")

      open_tab(view, "well_data")

      assert has_element?(
               view,
               ~s(button[phx-click="edit_section"][phx-value-section="identity"])
             )

      assert has_element?(
               view,
               ~s(button[phx-click="edit_section"][phx-value-section="configuration"])
             )
    end

    test "a draft report shows no Edit buttons", %{conn: conn} do
      report = create_report(%{"status" => "draft"})
      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}")

      open_tab(view, "well_data")

      refute has_element?(view, ~s(button[phx-click="edit_section"]))
    end

    test "a complete report shows no Edit buttons", %{conn: conn} do
      report = create_report(%{"status" => "complete"})
      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}")

      open_tab(view, "well_data")

      refute has_element?(view, ~s(button[phx-click="edit_section"]))
    end
  end

  describe "editing a scalar section" do
    test "saving Configuration writes the changed fields to the report", %{conn: conn} do
      report = create_report(%{"report_data" => %{"purpose" => "Production"}})
      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}")

      open_tab(view, "well_data")
      view |> element(~s(button[phx-value-section="configuration"])) |> render_click()

      assert has_element?(view, ~s(form[phx-submit="save_section"]))

      view
      |> form(~s(form[phx-submit="save_section"]),
        report: %{report_data: %{purpose: "Injection", substance: "Water"}}
      )
      |> render_submit()

      updated = Reports.get_report!(report.id)
      assert updated.report_data.purpose == "Injection"
      assert updated.report_data.substance == "Water"

      # editor closes and the read-only view is back
      refute has_element?(view, ~s(form[phx-submit="save_section"]))
    end

    test "editing one section leaves other sections' data untouched", %{conn: conn} do
      report =
        create_report(%{
          "report_data" => %{"purpose" => "Production", "gl_elevation" => "812.5"}
        })

      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}")

      open_tab(view, "well_data")
      view |> element(~s(button[phx-value-section="configuration"])) |> render_click()

      view
      |> form(~s(form[phx-submit="save_section"]),
        report: %{report_data: %{purpose: "Injection"}}
      )
      |> render_submit()

      updated = Reports.get_report!(report.id)
      assert updated.report_data.purpose == "Injection"
      assert Decimal.equal?(updated.report_data.gl_elevation, Decimal.new("812.5"))
    end
  end

  describe "editing a row-based section" do
    test "adding a formation top row and saving persists it", %{conn: conn} do
      report = create_report(%{"status" => "active"})
      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}")

      open_tab(view, "formation_tops")
      view |> element(~s(button[phx-value-section="formation_tops"])) |> render_click()

      view
      |> element(~s(button[phx-click="add_row"][phx-value-list="formation_tops"]))
      |> render_click()

      view
      |> form(~s(form[phx-submit="save_section"]),
        report: %{report_data: %{formation_tops: %{"0" => %{formation: "Sparky", md: "1200"}}}}
      )
      |> render_submit()

      updated = Reports.get_report!(report.id)
      assert [%{formation: "Sparky"}] = updated.report_data.formation_tops
    end

    test "removing a survey row and saving drops it (typed embed fallback)", %{conn: conn} do
      report =
        create_report(%{
          "report_data" => %{
            "surveys" => %{
              "0" => %{"md" => "0", "inclination" => "0", "azimuth" => "0"},
              "1" => %{"md" => "100", "inclination" => "2", "azimuth" => "185"}
            }
          }
        })

      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}")

      open_tab(view, "surveys")
      view |> element(~s(button[phx-value-section="surveys"])) |> render_click()

      view
      |> element(
        ~s(button[phx-click="remove_row"][phx-value-list="surveys"][phx-value-index="1"])
      )
      |> render_click()

      view |> form(~s(form[phx-submit="save_section"]), report: %{}) |> render_submit()

      updated = Reports.get_report!(report.id)
      assert length(updated.report_data.surveys) == 1
    end
  end

  describe "Formation Tops (import_data) editor" do
    test "renders the rich table with survey reach and derived columns", %{conn: conn} do
      report = tops_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      html = open_tab(view, "formation_tops")

      assert html =~ "Formation Tops"
      assert html =~ "Last survey"
      assert html =~ "Colony"
      # Samples MD 305 interpolates to TVD 305 on the 1:1 demo survey → subsea 295
      assert html =~ "295.0"
      # Samples is editable, Prognosis is not
      assert has_element?(view, ~s(button[phx-click="edit_group"][phx-value-group="samples"]))
      refute has_element?(view, ~s(button[phx-click="edit_group"][phx-value-group="prognosis"]))
    end

    test "a draft report shows no group pencils", %{conn: conn} do
      report = tops_report(%{"status" => "draft"})
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "formation_tops")

      refute has_element?(view, ~s(button[phx-click="edit_group"]))
    end

    test "editing a Samples MD saves and recomputes TVD/Subsea", %{conn: conn} do
      report = tops_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "formation_tops")

      view |> element(~s(button[phx-value-group="samples"])) |> render_click()

      view
      |> form("#tops-form-formation-tops",
        tops: %{rows: %{"0" => %{samples: %{md: "320"}}, "1" => %{samples: %{md: "510"}}}}
      )
      |> render_submit()

      tops = Reports.get_report!(report.id).import_data["tops"]["formations"]
      colony = Enum.find(tops, &(&1["formation"] == "Colony"))

      assert colony["samples"]["md"] == 320.0
      assert colony["samples"]["tvd"] == 320.0
      assert colony["samples"]["subsea"] == 280.0
    end

    test "a pick beyond the survey is flagged as extrapolated", %{conn: conn} do
      # survey reaches 900 m; add a sample pick past it
      base = tops_report()

      deep = %{
        "formation" => "Deep",
        "prognosis" => %{},
        "samples" => %{"md" => 1200.0},
        "mwd_gamma" => %{}
      }

      tops = update_in(base.import_data["tops"], ["formations"], &(&1 ++ [deep]))
      {:ok, report} = Reports.update_import_section(base, "tops", tops)

      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      html = open_tab(view, "formation_tops")

      assert html =~ "extrapolated"
    end

    test "a negative MD blocks the save", %{conn: conn} do
      report = tops_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "formation_tops")
      view |> element(~s(button[phx-value-group="samples"])) |> render_click()

      html =
        view
        |> form("#tops-form-formation-tops", tops: %{rows: %{"0" => %{samples: %{md: "-5"}}}})
        |> render_change()

      assert html =~ "needs a fix" or html =~ "need a fix"
      assert has_element?(view, ~s(button[type="submit"][disabled]))
    end
  end
end
