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

  defp reservoir_report(attrs \\ %{}) do
    import_data = %{
      "reservoir_data" => [
        %{
          "leg_name" => "Lateral",
          "log_data" => %{
            "intervals" => [
              %{
                "from_depth" => 100.0,
                "to_depth" => 140.0,
                "interval" => 40.0,
                "quality" => "Good",
                "lithology" => "Sandstone",
                "porosity" => "12-24%",
                "gas" => 500.0,
                "remarks" => "clean sand"
              }
            ]
          }
        }
      ]
    }

    create_report(Map.merge(%{"status" => "active", "import_data" => import_data}, attrs))
  end

  # The picker is a Svelte component; drive its server round-trip by replaying
  # the "commit_intervals" event it pushes to the ReservoirQualityLive component.
  defp commit_intervals(view, intervals) do
    render_hook(view, "commit_intervals", %{"intervals" => intervals})
  end

  # The picker is client-rendered (ssr disabled); its inputs are the JSON in the
  # LiveSvelte wrapper's data-props.
  defp picker_props(view) do
    view
    |> element(~s([data-name="ReservoirQualityPicker"]))
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.attribute("data-props")
    |> List.first()
    |> Jason.decode!()
  end

  describe "edit affordance gating" do
    test "an active report shows an Edit button on every Well Data card", %{conn: conn} do
      report = create_report(%{"status" => "active"})
      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}")

      open_tab(view, "well_data")

      for card <- ChinookReportsWeb.WellDataCardLive.cards() do
        assert has_element?(view, ~s(#well-data-#{card} button[phx-click="edit"]))
      end

      assert has_element?(view, ~s(#welldata-well_profile button[phx-click="edit"]))
      # the Well Summary section is gone
      refute has_element?(view, "#well_summary")
    end

    test "a draft report shows no Edit buttons", %{conn: conn} do
      report = create_report(%{"status" => "draft"})
      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}")

      open_tab(view, "well_data")

      refute has_element?(view, ~s(button[phx-click="edit"]))
      refute has_element?(view, ~s(button[phx-click="edit_section"]))
    end

    test "a complete report shows no Edit buttons", %{conn: conn} do
      report = create_report(%{"status" => "complete"})
      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}")

      open_tab(view, "well_data")

      refute has_element?(view, ~s(button[phx-click="edit"]))
      refute has_element?(view, ~s(button[phx-click="edit_section"]))
    end
  end

  describe "Well Data cards" do
    defp edit_card(view, card) do
      view |> element(~s(#well-data-#{card} button[phx-click="edit"])) |> render_click()
    end

    # field index within the card, by label — the inputs are named fields[<i>]
    defp field_index(card, label) do
      ChinookReportsWeb.WellDataCardLive.field_labels(card) |> Enum.find_index(&(&1 == label))
    end

    defp fields(card, values) do
      Map.new(values, fn {label, v} -> {Integer.to_string(field_index(card, label)), v} end)
    end

    test "a wizard report shows its typed values before any welldata exists", %{conn: conn} do
      report =
        create_report(%{
          "operator" => "Chinook Petroleum",
          "report_data" => %{"purpose" => "Production", "kb_elevation" => "650.5"}
        })

      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}")
      html = open_tab(view, "well_data")

      assert html =~ "Chinook Petroleum"
      assert html =~ "Production"
      assert html =~ "650.5 m"
    end

    test "saving Well Identification writes welldata and the mirrored columns", %{conn: conn} do
      report = create_report(%{"status" => "active"})
      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "well_data")
      edit_card(view, "identification")

      view
      |> form("#well-data-identification-form",
        fields:
          fields("identification", %{
            "Well Name" => "Renamed Well",
            "Operator" => "New Operator",
            "AFE Number" => "AFE-42"
          })
      )
      |> render_submit()

      assert render(view) =~ "Well Identification saved."
      updated = Reports.get_report!(report.id)
      assert updated.well_name == "Renamed Well"
      assert updated.operator == "New Operator"
      assert updated.import_data["welldata"]["well_name"] == "Renamed Well"
      assert updated.import_data["welldata"]["afe_number"] == "AFE-42"
      # the header reads the typed column
      assert render(view) =~ "Renamed Well"
    end

    test "Status can be changed from Well Identification, which ends editing", %{conn: conn} do
      report = create_report(%{"status" => "active"})
      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "well_data")
      edit_card(view, "identification")

      view
      |> form("#well-data-identification-form",
        fields: fields("identification", %{"Status" => "complete"})
      )
      |> render_submit()

      assert Reports.get_report!(report.id).status == "complete"
      refute has_element?(view, ~s(button[phx-click="edit"]))
    end

    test "a blank Well Name is rejected and nothing is saved", %{conn: conn} do
      report = create_report(%{"status" => "active"})
      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "well_data")
      edit_card(view, "identification")

      html =
        view
        |> form("#well-data-identification-form",
          fields: fields("identification", %{"Well Name" => ""})
        )
        |> render_submit()

      assert html =~ "can&#39;t be blank"
      assert Reports.get_report!(report.id).well_name == "Test Well"
    end

    test "a non-numeric elevation is flagged and not saved", %{conn: conn} do
      report = create_report(%{"status" => "active"})
      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "well_data")
      edit_card(view, "elevations")

      html =
        view
        |> form("#well-data-elevations-form",
          fields: fields("elevations", %{"Ground Level" => "abc"})
        )
        |> render_change()

      assert html =~ "must be a number"
      assert Reports.get_report!(report.id).import_data["welldata"] in [nil, %{}]
    end

    test "editing one card leaves the rest of welldata untouched", %{conn: conn} do
      report = tops_report()
      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "well_data")
      edit_card(view, "services")

      view
      |> form("#well-data-services-form",
        fields:
          fields("services", %{
            "Wellsite Geologists" => "Ron Hickey, David Montgomery",
            "Rig" => "214"
          })
      )
      |> render_submit()

      wd = Reports.get_report!(report.id).import_data["welldata"]

      assert wd["services"]["wellsite_geology"]["geologists"] == [
               "Ron Hickey",
               "David Montgomery"
             ]

      assert wd["services"]["drilling_contractor"]["rig"] == "214"
      assert wd["elevations"] == %{"kelly_bushing" => 600.0}
      # blanks never invent sections
      refute Map.has_key?(wd, "geological_services")
    end

    test "KB to Ground is derived from Ground Level and Kelly Bushing", %{conn: conn} do
      report = tops_report()
      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "well_data")

      # Only the KB is known yet, so there is no KB to Ground to show.
      refute view |> element("#well-data-elevations") |> render() =~ "4.5 m"

      edit_card(view, "elevations")

      view
      |> form("#well-data-elevations-form",
        fields: fields("elevations", %{"Ground Level" => "595.5"})
      )
      |> render_submit()

      assert view |> element("#well-data-elevations") |> render() =~ "4.5 m"
      wd = Reports.get_report!(report.id).import_data["welldata"]
      assert wd["elevations"]["kb_to_ground"] == 4.5
    end

    test "changing the Kelly Bushing re-derives Formation Tops", %{conn: conn} do
      report = tops_report()
      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "well_data")
      edit_card(view, "elevations")

      view
      |> form("#well-data-elevations-form",
        fields: fields("elevations", %{"Kelly Bushing" => "610"})
      )
      |> render_submit()

      tops = Reports.get_report!(report.id).import_data["tops"]["formations"]
      colony = Enum.find(tops, &(&1["formation"] == "Colony"))
      # Samples MD 305 → TVD 305 on the 1:1 survey; subsea = 610 − 305
      assert colony["samples"]["subsea"] == 305.0
    end
  end

  describe "editing a row-based section" do
    test "wizard tops are listed as Prognosis; a Wireline pick saves the table", %{conn: conn} do
      report =
        create_report(%{
          "status" => "active",
          "report_data" => %{
            "kb_elevation" => "600",
            "formation_tops" => %{
              "0" => %{"formation" => "Colony", "md" => "300", "subsea" => "302"},
              "1" => %{"formation" => "McLaren", "md" => "500", "subsea" => "105"}
            }
          }
        })

      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}")
      html = open_tab(view, "formation_tops")

      # The full table, names from the wizard, not the plain typed one
      assert has_element?(view, "#tops-form-formation-tops")
      assert html =~ "Colony" and html =~ "McLaren"
      assert html =~ "+/− (m)"

      view
      |> element(~s(button[phx-click="compare"][phx-value-group="wireline"]))
      |> render_click()

      view
      |> element(~s(button[phx-click="edit_group"][phx-value-group="wireline"]))
      |> render_click()

      # Empty picks show the prognosed MD as a placeholder
      assert has_element?(view, ~s(input[name="tops[rows][0][wireline][md]"][placeholder="300"]))

      view
      |> form("#tops-form-formation-tops", tops: %{rows: %{"0" => %{wireline: %{md: "295"}}}})
      |> render_submit()

      [colony, mclaren] = Reports.get_report!(report.id).import_data["tops"]["formations"]
      assert colony["formation"] == "Colony"
      assert colony["prognosis"]["subsea"] == 302.0
      assert colony["wireline"]["md"] == 295.0
      assert mclaren["prognosis"]["md"] == 500.0
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

  describe "deviated well" do
    # Actual surveys drift 10 m north by 500 m MD; no plan on file yet.
    defp deviated_report do
      points =
        for md <- 0..500//100 do
          %{"md" => md * 1.0, "tvd" => md * 1.0, "north_south" => md / 50, "east_west" => 0.0}
        end

      create_report(%{
        "geometry" => "Deviated",
        "import_data" => %{
          "reservoir_data" => [%{"leg_name" => "Main", "survey" => %{"survey_points" => points}}]
        }
      })
    end

    test "adding a directional program while active feeds the Summary's plan comparison",
         %{conn: conn} do
      report = deviated_report()
      {:ok, view, html} = live(conn, ~p"/reports/#{report.id}")

      assert html =~ "Position vs plan"
      assert html =~ "No directional program on file"

      open_tab(view, "surveys")
      view |> element(~s(button[phx-value-view="planned"])) |> render_click()
      view |> element(~s(button[phx-value-section="surveys"])) |> render_click()

      for _ <- 1..2 do
        view
        |> element(~s(button[phx-click="add_row"][phx-value-list="surveys"]))
        |> render_click()
      end

      view
      |> form(~s(form[phx-submit="save_section"]),
        report: %{
          report_data: %{
            surveys: %{
              "0" => %{md: "0", inclination: "0", azimuth: "0"},
              "1" => %{md: "600", inclination: "0", azimuth: "0"}
            }
          }
        }
      )
      |> render_submit()

      assert [_, _] = Reports.get_report!(report.id).report_data.surveys

      html = open_tab(view, "summary")
      refute html =~ "No directional program on file"
      assert html =~ "Last survey"
      # 10 m north of a straight-down plan
      assert html =~ "10 m"
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
      # Prognosis subsea: KB 600 − TVD 298
      assert html =~ ">302</span>"
      # Prognosis, plus the compared tab (MWD / Gamma by default), each with a pencil
      assert has_element?(view, ~s(button[phx-click="edit_group"][phx-value-group="prognosis"]))
      assert has_element?(view, ~s(button[phx-click="edit_group"][phx-value-group="mwd_gamma"]))

      for g <- ~w(mwd_gamma wireline) do
        assert has_element?(view, ~s(button[phx-click="compare"][phx-value-group="#{g}"]))
      end

      # MWD / Gamma is the drilling tops; there's no separate Drilling group
      assert html =~ "Drilling (MWD / Gamma)"
      refute has_element?(view, ~s(button[phx-value-group="drilling"]))

      # No Samples tab, column or pencil
      refute has_element?(view, ~s(button[phx-value-group="samples"]))
      refute html =~ "Samples"
    end

    test "a draft report shows no group pencils", %{conn: conn} do
      report = tops_report(%{"status" => "draft"})
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "formation_tops")

      refute has_element?(view, ~s(button[phx-click="edit_group"]))
    end

    test "editing an MWD / Gamma MD saves and recomputes TVD/Subsea", %{conn: conn} do
      report = tops_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "formation_tops")

      view
      |> element(~s(button[phx-click="edit_group"][phx-value-group="mwd_gamma"]))
      |> render_click()

      view
      |> form("#tops-form-formation-tops",
        tops: %{rows: %{"0" => %{mwd_gamma: %{md: "320"}}, "1" => %{mwd_gamma: %{md: "510"}}}}
      )
      |> render_submit()

      tops = Reports.get_report!(report.id).import_data["tops"]["formations"]
      colony = Enum.find(tops, &(&1["formation"] == "Colony"))

      assert colony["mwd_gamma"]["md"] == 320.0
      assert colony["mwd_gamma"]["tvd"] == 320.0
      assert colony["mwd_gamma"]["subsea"] == 280.0
      # an imported Samples pick is kept as it was
      assert colony["samples"]["md"] == 305.0
    end

    test "editing a Prognosis MD and Subsea saves both and recomputes TVD", %{conn: conn} do
      report = tops_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "formation_tops")

      view
      |> element(~s(button[phx-click="edit_group"][phx-value-group="prognosis"]))
      |> render_click()

      # a Subsea below sea level is a valid (negative) datum, not an error
      view
      |> form("#tops-form-formation-tops",
        tops: %{
          rows: %{
            "0" => %{prognosis: %{md: "295", subsea: "-40"}},
            "1" => %{prognosis: %{md: "500", subsea: "495"}}
          }
        }
      )
      |> render_submit()

      tops = Reports.get_report!(report.id).import_data["tops"]["formations"]
      colony = Enum.find(tops, &(&1["formation"] == "Colony"))

      assert colony["prognosis"]["md"] == 295.0
      assert colony["prognosis"]["subsea"] == -40.0
      # TVD is KB 600 − Subsea, independent of the recorded MD
      assert colony["prognosis"]["tvd"] == 640.0
    end

    test "a pick beyond the survey is flagged as extrapolated", %{conn: conn} do
      # survey reaches 900 m; add an MWD pick past it
      base = tops_report()

      deep = %{
        "formation" => "Deep",
        "prognosis" => %{},
        "mwd_gamma" => %{"md" => 1200.0},
        "wireline" => %{}
      }

      tops = update_in(base.import_data["tops"], ["formations"], &(&1 ++ [deep]))
      {:ok, report} = Reports.update_import_section(base, "tops", tops)

      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "formation_tops")

      # "(extrapolated)" beside the name of the deep row only
      assert view |> element("tbody tr", "Deep") |> render() =~ "(extrapolated)"
      refute view |> element("tbody tr", "Colony") |> render() =~ "(extrapolated)"

      # It follows the tab: Deep has no Wireline pick, so nothing is extrapolated there.
      view
      |> element(~s(button[phx-click="compare"][phx-value-group="wireline"]))
      |> render_click()

      refute render(view) =~ "(extrapolated)"
    end

    test "a Wireline tab: its pick saves, derives TVD/Subsea and drives Diff", %{conn: conn} do
      report = tops_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "formation_tops")

      view
      |> element(~s(button[phx-click="compare"][phx-value-group="wireline"]))
      |> render_click()

      view
      |> element(~s(button[phx-click="edit_group"][phx-value-group="wireline"]))
      |> render_click()

      # Switching tabs mid-edit of a compared group is locked.
      assert has_element?(
               view,
               ~s(button[phx-click="compare"][phx-value-group="mwd_gamma"][disabled])
             )

      html =
        view
        |> form("#tops-form-formation-tops", tops: %{rows: %{"0" => %{wireline: %{md: "310"}}}})
        |> render_submit()

      colony =
        Enum.find(
          Reports.get_report!(report.id).import_data["tops"]["formations"],
          &(&1["formation"] == "Colony")
        )

      # 1:1 survey, KB 600: TVD 310, subsea 290; prognosis subsea is 600 − 298 = 302
      assert colony["wireline"]["tvd"] == 310.0
      assert colony["wireline"]["subsea"] == 290.0
      assert colony["wireline"]["difference"] == -12.0
      # Still on the Wireline tab, whose +/− shows
      assert html =~ "-12"
    end

    test "a negative MD blocks the save", %{conn: conn} do
      report = tops_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "formation_tops")

      view
      |> element(~s(button[phx-click="edit_group"][phx-value-group="mwd_gamma"]))
      |> render_click()

      html =
        view
        |> form("#tops-form-formation-tops", tops: %{rows: %{"0" => %{mwd_gamma: %{md: "-5"}}}})
        |> render_change()

      assert html =~ "needs a fix" or html =~ "need a fix"
      assert has_element?(view, ~s(button[type="submit"][disabled]))
    end
  end

  describe "Reservoir Quality (import_data) picker" do
    test "renders the picker with existing sections", %{conn: conn} do
      report = reservoir_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      html = open_tab(view, "reservoir")

      assert html =~ "Reservoir Quality"
      assert has_element?(view, ~s([data-name="ReservoirQualityPicker"]))

      props = picker_props(view)
      assert props["editable"] == true
      assert props["well_type"] == "horizontal"
      assert [%{"id" => "0", "quality" => "Good", "from_depth" => 100.0}] = props["intervals"]
    end

    test "a non-active report renders the picker read-only", %{conn: conn} do
      report = reservoir_report(%{"status" => "complete"})
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "reservoir")

      assert has_element?(view, ~s([data-name="ReservoirQualityPicker"]))
      assert picker_props(view)["editable"] == false
    end

    test "committing sections saves them and recomputes the quality summary", %{conn: conn} do
      report = reservoir_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "reservoir")

      commit_intervals(view, [
        %{
          "id" => "0",
          "from_depth" => 100,
          "to_depth" => 150,
          "quality" => "Very Good",
          "lithology" => "Sandstone"
        },
        %{
          "id" => nil,
          "from_depth" => 200,
          "to_depth" => 260,
          "quality" => "Fair",
          "lithology" => "Shale"
        }
      ])

      assert render(view) =~ "Reservoir Quality saved."

      [leg] = Reports.get_report!(report.id).import_data["reservoir_data"]
      [a, b] = Enum.sort_by(leg["log_data"]["intervals"], & &1["from_depth"])

      assert a["quality"] == "Very Good"
      assert a["to_depth"] == 150.0
      assert a["interval"] == 50.0
      # fields the picker doesn't surface survive the round trip
      assert a["porosity"] == "12-24%"
      assert a["gas"] == 500.0
      assert a["remarks"] == "clean sand"

      assert b["quality"] == "Fair"
      assert b["lithology"] == "Shale"
      assert b["interval"] == 60.0
      assert b["gas"] == nil

      summary = leg["log_data"]["quality_summary"]
      assert Enum.find(summary, &(&1["quality"] == "Very Good"))["metres"] == 50.0
      assert Enum.find(summary, &(&1["quality"] == "Total"))["metres"] == 110.0
    end

    test "a commit with an inverted interval is rejected", %{conn: conn} do
      report = reservoir_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "reservoir")

      commit_intervals(view, [
        %{
          "id" => "0",
          "from_depth" => 140,
          "to_depth" => 100,
          "quality" => "Good",
          "lithology" => "Sandstone"
        }
      ])

      assert render(view) =~ "bad depth or quality"

      [leg] = Reports.get_report!(report.id).import_data["reservoir_data"]
      [interval] = leg["log_data"]["intervals"]
      assert interval["from_depth"] == 100.0
      assert interval["to_depth"] == 140.0
    end

    test "committing an empty list removes all sections", %{conn: conn} do
      report = reservoir_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "reservoir")

      commit_intervals(view, [])

      [leg] = Reports.get_report!(report.id).import_data["reservoir_data"]
      assert leg["log_data"]["intervals"] == []
    end
  end

  describe "Well Data tables (import_data welldata) editors" do
    defp welldata_report(attrs \\ %{}) do
      welldata = %{
        "elevations" => %{"kelly_bushing" => 600.0},
        "well_timing" => %{
          "spud_date" => %{"date" => "2026-07-10", "time" => "06:00", "depth" => 0.0},
          "surface_casing" => %{"date" => "Pre-Set", "time" => nil, "depth" => 124.9},
          "rig_release_date" => "2026-07-15"
        },
        "hole_sizes" => [
          %{
            "section" => "SURFACE",
            "bit_diameter" => 375.0,
            "from_depth" => 0.0,
            "to_depth" => 124.9,
            "interval" => 124.9
          }
        ],
        "mud" => [
          %{"section" => "SURFACE", "type" => "Gel", "from_depth" => 0.0, "to_depth" => 124.9}
        ],
        "casing_data" => [
          %{
            "section" => "SURFACE CASING",
            "size" => 298.0,
            "set_at" => 124.9,
            "weight" => 62.0,
            "type" => "H-40/ST&C"
          }
        ]
      }

      create_report(
        Map.merge(%{"status" => "active", "import_data" => %{"welldata" => welldata}}, attrs)
      )
    end

    defp welldata(report), do: Reports.get_report!(report.id).import_data["welldata"]

    test "a draft report shows no table pencils", %{conn: conn} do
      report = welldata_report(%{"status" => "draft"})
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")

      assert open_tab(view, "timing") =~ "Pre-Set"
      refute has_element?(view, ~s(#well-timing button[phx-click="edit"]))
      open_tab(view, "hole_casing_mud_bits")
      refute has_element?(view, ~s(button[phx-click="edit"]))
    end

    test "editing Well Timing saves dates, times and depths", %{conn: conn} do
      report = welldata_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "timing")

      view |> element(~s(#well-timing button[phx-click="edit"])) |> render_click()

      # rows follow the milestone order; index 7 is Rig Release
      view
      |> form("#well-timing-form",
        rows: %{
          "0" => %{date: "2026-07-11", time: "07:30", depth: "0"},
          "2" => %{date: "2026-07-11", time: "13:35", depth: "412.8"},
          "7" => %{date: "2026-07-16"}
        }
      )
      |> render_submit()

      # the flash comes from the parent's handle_info, after the component's submit
      assert render(view) =~ "Well Timing saved."
      timing = welldata(report)["well_timing"]
      assert timing["spud_date"] == %{"date" => "2026-07-11", "time" => "07:30", "depth" => 0.0}
      assert timing["sample_point"]["depth"] == 412.8
      assert timing["surface_casing"]["date"] == "Pre-Set"
      assert timing["rig_release_date"] == "2026-07-16"
    end

    test "Spud and Final T.D. timing also update the typed date columns", %{conn: conn} do
      report = welldata_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "timing")
      view |> element(~s(#well-timing button[phx-click="edit"])) |> render_click()

      view
      |> form("#well-timing-form",
        rows: %{
          "0" => %{date: "2026-07-11", time: "7:30"},
          "6" => %{date: "2026-07-14", time: "19:45", depth: "2150"}
        }
      )
      |> render_submit()

      updated = Reports.get_report!(report.id)
      assert updated.spud_date == ~N[2026-07-11 07:30:00]
      assert updated.final_td_date == ~N[2026-07-14 19:45:00]
    end

    test "a bad time or negative depth is flagged and not saved", %{conn: conn} do
      report = welldata_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "timing")
      view |> element(~s(#well-timing button[phx-click="edit"])) |> render_click()

      html =
        view
        |> form("#well-timing-form", rows: %{"0" => %{time: "25:00", depth: "-5"}})
        |> render_submit()

      assert html =~ "Fix the highlighted cells"
      assert welldata(report)["well_timing"]["spud_date"]["time"] == "06:00"
    end

    test "editing Hole Sizes adds a row and re-derives interval", %{conn: conn} do
      report = welldata_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "hole_casing_mud_bits")

      view |> element(~s(#welldata-hole_sizes button[phx-click="edit"])) |> render_click()
      view |> element(~s(#welldata-hole_sizes button[phx-click="add_row"])) |> render_click()

      view
      |> form("#welldata-hole_sizes-form",
        rows: %{
          "0" => %{to_depth: "130"},
          "1" => %{section: "Main", bit_diameter: "200", from_depth: "130", to_depth: "2150"}
        }
      )
      |> render_submit()

      assert [surface, main] = welldata(report)["hole_sizes"]
      assert surface["interval"] == 130.0

      assert main == %{
               "section" => "Main",
               "bit_diameter" => 200.0,
               "from_depth" => 130.0,
               "to_depth" => 2150.0,
               "interval" => 2020.0
             }
    end

    test "editing Casing keeps columns the table doesn't show", %{conn: conn} do
      report = welldata_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "hole_casing_mud_bits")

      view |> element(~s(#welldata-casing_data button[phx-click="edit"])) |> render_click()

      view
      |> form("#welldata-casing_data-form", rows: %{"0" => %{type: "J-55/LT&C"}})
      |> render_submit()

      [casing] = welldata(report)["casing_data"]
      assert casing["type"] == "J-55/LT&C"
      assert casing["weight"] == 62.0
      # the other welldata sections are untouched
      assert welldata(report)["mud"] == welldata_report_mud()
    end

    test "editing Well Profile nests start/end and re-derives length", %{conn: conn} do
      report = welldata_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "well_data")

      view |> element(~s(#welldata-well_profile button[phx-click="edit"])) |> render_click()
      view |> element(~s(#welldata-well_profile button[phx-click="add_row"])) |> render_click()

      view
      |> form("#welldata-well_profile-form",
        rows: %{
          "0" => %{
            section: "Vertical",
            start_date: "2026-07-10",
            start_time: "06:00",
            start_depth: "0",
            end_date: "2026-07-10",
            end_time: "08:45",
            end_depth: "247.7",
            duration_days: "0.1"
          }
        }
      )
      |> render_submit()

      assert [row] = welldata(report)["well_profile"]
      assert row["section"] == "Vertical"
      assert row["start"] == %{"date" => "2026-07-10", "time" => "06:00", "depth" => 0.0}
      assert row["end"] == %{"date" => "2026-07-10", "time" => "08:45", "depth" => 247.7}
      assert row["length"] == 247.7
      assert row["duration_days"] == "0.1"
    end

    test "removing the only Mud row saves an empty list", %{conn: conn} do
      report = welldata_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "hole_casing_mud_bits")

      view |> element(~s(#welldata-mud button[phx-click="edit"])) |> render_click()
      view |> element(~s(#welldata-mud button[phx-click="remove_row"])) |> render_click()
      view |> form("#welldata-mud-form") |> render_submit()

      assert welldata(report)["mud"] == []
    end

    defp welldata_report_mud do
      [%{"section" => "SURFACE", "type" => "Gel", "from_depth" => 0.0, "to_depth" => 124.9}]
    end
  end

  describe "Synopsis, Bits, Mud Log, Daily, Reservoir intervals and Survey editors" do
    # A horizontal well (so the Reservoir tab shows) carrying every imported
    # section. The survey is vertical to 300 m on a 600 m KB.
    defp full_report(attrs \\ %{}) do
      station = fn md ->
        %{
          "md" => md,
          "inclination_deg" => 0.0,
          "azimuth_deg" => 0.0,
          "tvd" => md,
          "north_south" => 0.0,
          "east_west" => 0.0,
          "vertical_section" => 0.0,
          "dogleg_severity" => 0.0,
          "subsea" => 600.0 - md,
          "remarks" => nil
        }
      end

      import_data = %{
        "welldata" => %{"elevations" => %{"kelly_bushing" => 600.0}},
        "synopsis" => %{
          "well_summary" => ["First paragraph.", "Second paragraph."],
          "well_profile" => ["Vertical to 300m"],
          "formation_evaluation" => ["Good reservoir: 40.0m (100.0%)"]
        },
        "bits" => [
          %{
            "bit_number" => 1,
            "size" => 222.0,
            "make" => "J&L",
            "type" => "TRICONE",
            "hours" => 10.0,
            "remarks" => 63
          }
        ],
        "mud_log" => [
          %{
            "date" => "2026-07-10",
            "depth" => 99.0,
            "mud_type" => "Polymer",
            "density" => 1090.0,
            "viscosity" => 60.0,
            "wl" => nil,
            "ph" => nil,
            "remarks" => nil
          }
        ],
        "daily" => [
          %{
            "date" => "2026-07-10",
            "depth" => 99,
            "progress" => 99,
            "drilling_hours" => 1.5,
            "rop" => 66.0,
            "operations_summary" => "Spud well.",
            "tag" => "Jul 10"
          }
        ],
        "reservoir_data" => [
          %{
            "leg_name" => "Lateral",
            "survey" => %{
              "survey_points" => Enum.map([0.0, 100.0, 200.0, 300.0], station),
              "markers" => [%{"event" => "Last Survey", "md" => 300.0, "tvd" => 300.0}]
            },
            "log_data" => %{
              "intervals" => [
                %{
                  "from_depth" => 100.0,
                  "to_depth" => 140.0,
                  "interval" => 40.0,
                  "quality" => "Good",
                  "lithology" => "Sandstone",
                  "porosity" => nil,
                  "gas" => nil,
                  "remarks" => nil
                }
              ]
            }
          }
        ],
        "tops" => %{
          "formations" => [
            %{
              "formation" => "Colony",
              "prognosis" => %{"md" => 250.0, "tvd" => 250.0},
              "samples" => %{"md" => 250.0},
              "mwd_gamma" => %{}
            }
          ]
        }
      }

      create_report(
        Map.merge(
          %{"status" => "active", "geometry" => "Horizontal", "import_data" => import_data},
          attrs
        )
      )
    end

    defp import_data(report), do: Reports.get_report!(report.id).import_data

    defp click_edit(view, id),
      do: view |> element(~s(##{id} button[phx-click="edit"])) |> render_click()

    test "a draft report offers no Edit on any of these tabs", %{conn: conn} do
      report = full_report(%{"status" => "draft"})
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")

      for tab <- ~w(synopsis hole_casing_mud_bits mud_log daily_reports reservoir surveys) do
        open_tab(view, tab)
        refute has_element?(view, ~s(button[phx-click="edit"])), "Edit offered on #{tab}"
      end
    end

    test "Synopsis saves paragraphs, bullets and evaluation lines", %{conn: conn} do
      report = full_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      assert open_tab(view, "synopsis") =~ "Second paragraph."

      click_edit(view, "synopsis-editor")

      view
      |> form("#synopsis-editor-form",
        synopsis: %{
          well_summary: "Para one\nwraps here.\n\nPara two.",
          well_profile: "Vertical to 300m\nBuild to 600m\n",
          formation_evaluation: "Good reservoir: 40.0m (100.0%)\nCONCLUSIONS\nDrill it."
        }
      )
      |> render_submit()

      synopsis = import_data(report)["synopsis"]
      assert synopsis["well_summary"] == ["Para one wraps here.", "Para two."]
      assert synopsis["well_profile"] == ["Vertical to 300m", "Build to 600m"]
      assert List.last(synopsis["formation_evaluation"]) == "Drill it."
      assert render(view) =~ "Synopsis saved."
    end

    test "Bits: edit a cell and add a bit; untouched numeric cells keep their type", %{conn: conn} do
      report = full_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "hole_casing_mud_bits")

      click_edit(view, "import-bits")
      view |> element(~s(#import-bits button[phx-click="add_row"])) |> render_click()

      view
      |> form("#import-bits-form",
        rows: %{"0" => %{hours: "12.5"}, "1" => %{bit_number: "2", make: "NOV", size: "159"}}
      )
      |> render_submit()

      assert [first, second] = import_data(report)["bits"]
      assert first["hours"] == 12.5
      assert first["remarks"] == 63
      assert second["make"] == "NOV"
      assert second["size"] == 159.0
    end

    test "Mud Log: a pH above 14 is flagged and not saved", %{conn: conn} do
      report = full_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "mud_log")
      click_edit(view, "import-mud_log")

      html = view |> form("#import-mud_log-form", rows: %{"0" => %{ph: "15"}}) |> render_submit()

      assert html =~ "Fix the highlighted cells"
      assert hd(import_data(report)["mud_log"])["ph"] == nil
    end

    test "Daily Reports: ROP follows progress / drilling hours", %{conn: conn} do
      report = full_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "daily_reports")
      click_edit(view, "import-daily")

      # live preview before saving
      html =
        view
        |> form("#import-daily-form", rows: %{"0" => %{progress: "120", drilling_hours: "4"}})
        |> render_change()

      assert html =~ "30.00"

      view
      |> form("#import-daily-form",
        rows: %{
          "0" => %{progress: "120", drilling_hours: "4", operations_summary: "Drilled ahead."}
        }
      )
      |> render_submit()

      [day] = import_data(report)["daily"]
      assert day["rop"] == 30.0
      assert day["operations_summary"] == "Drilled ahead."
      assert day["tag"] == "Jul 10"
    end

    test "Interval Details: porosity / gas / lithology save and the summaries follow", %{
      conn: conn
    } do
      report = full_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "reservoir")
      click_edit(view, "reservoir-intervals")

      # From / To / Quality belong to the picker — no inputs for them here
      refute has_element?(view, ~s(#reservoir-intervals-form input[name="rows[0][from_depth]"]))

      view
      |> form("#reservoir-intervals-form",
        rows: %{"0" => %{porosity: "12-24%", gas: "500", lithology: "Siltstone"}}
      )
      |> render_submit()

      log = hd(import_data(report)["reservoir_data"])["log_data"]
      [iv] = log["intervals"]
      assert iv["porosity"] == "12-24%"
      assert iv["gas"] == 500.0
      assert iv["from_depth"] == 100.0
      silt = Enum.find(log["lithology_summary"], &(&1["lithology"] == "Siltstone"))
      assert silt["metres"] == 40.0
    end

    test "Survey: editing a station recomputes below it, and Formation Tops follow", %{conn: conn} do
      report = full_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "surveys")
      click_edit(view, "survey-0")

      # derived columns are display-only
      refute has_element?(view, ~s(#survey-0-form input[name="rows[0][tvd]"]))

      # build 30° between 100 m and 200 m, and add a station at 400 m
      view |> element(~s(#survey-0 button[phx-click="add_row"])) |> render_click()

      view
      |> form("#survey-0-form",
        rows: %{
          "2" => %{inclination_deg: "30"},
          "3" => %{inclination_deg: "30"},
          "4" => %{md: "400", inclination_deg: "30", azimuth_deg: "0"}
        }
      )
      |> render_submit()

      reservoir = hd(import_data(report)["reservoir_data"])
      points = reservoir["survey"]["survey_points"]
      assert Enum.map(points, & &1["md"]) == [0.0, 100.0, 200.0, 300.0, 400.0]

      # stations above the change are as stored
      assert Enum.at(points, 1)["tvd"] == 100.0
      at200 = Enum.at(points, 2)
      assert at200["tvd"] < 200.0
      assert at200["north_south"] > 0
      assert_in_delta at200["subsea"], 600.0 - at200["tvd"], 1.0e-9
      assert at200["dogleg_severity"] > 0

      # Last Survey follows the new deepest station
      assert hd(reservoir["survey"]["markers"])["md"] == 400.0

      # Samples MD 250 now sits on the build → shallower TVD, so subsea rises above 350
      tops = import_data(report)["tops"]["formations"]
      assert hd(tops)["samples"]["tvd"] < 250.0
      assert hd(tops)["samples"]["subsea"] > 350.0
    end

    test "Survey: a repeated MD or an azimuth past 360° is flagged", %{conn: conn} do
      report = full_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "surveys")
      click_edit(view, "survey-0")

      html =
        view
        |> form("#survey-0-form", rows: %{"2" => %{md: "100"}, "3" => %{azimuth_deg: "361"}})
        |> render_submit()

      assert html =~ "MDs must be unique"
      assert length(hd(import_data(report)["reservoir_data"])["survey"]["survey_points"]) == 4

      assert Enum.at(hd(import_data(report)["reservoir_data"])["survey"]["survey_points"], 2)[
               "md"
             ] == 200.0
    end
  end

  describe "editor Save bar and Escape" do
    defp press_escape(view, scope) do
      view
      |> element(~s(#{scope} [phx-window-keydown][phx-key="Escape"]))
      |> render_keydown(%{"key" => "Escape"})
    end

    test "every editor ends in the sticky Save / Cancel bar", %{conn: conn} do
      report = full_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "hole_casing_mud_bits")
      click_edit(view, "import-bits")

      bar = view |> element("#import-bits-form [phx-window-keydown]") |> render()
      assert bar =~ "sticky bottom-0"
      assert bar =~ "Save changes"
      assert bar =~ "Esc to cancel"
    end

    test "Escape closes a Well Data card without saving", %{conn: conn} do
      report = create_report(%{"status" => "active"})
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "well_data")
      edit_card(view, "identification")

      view
      |> form("#well-data-identification-form",
        fields: fields("identification", %{"Well Name" => "Typed but abandoned"})
      )
      |> render_change()

      press_escape(view, "#well-data-identification")

      refute has_element?(view, "#well-data-identification-form")
      assert Reports.get_report!(report.id).well_name == "Test Well"
      # the card shows the stored value again, not the abandoned edit
      assert render(view) =~ "Test Well"
      refute render(view) =~ "Typed but abandoned"
    end

    test "Escape drops rows added to an import table", %{conn: conn} do
      report = full_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "mud_log")
      click_edit(view, "import-mud_log")
      view |> element(~s(#import-mud_log button[phx-click="add_row"])) |> render_click()

      press_escape(view, "#import-mud_log")

      refute has_element?(view, "#import-mud_log-form")
      assert length(import_data(report)["mud_log"]) == 1
    end

    test "Escape closes the Synopsis editor", %{conn: conn} do
      report = full_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "synopsis")
      click_edit(view, "synopsis-editor")

      press_escape(view, "#synopsis-editor")

      refute has_element?(view, "#synopsis-editor-form")
    end

    test "Escape closes an inline report_data editor", %{conn: conn} do
      report = create_report(%{"status" => "active"})
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "timing")
      view |> element(~s(button[phx-value-section="profile_sections"])) |> render_click()
      assert has_element?(view, ~s(form[phx-submit="save_section"]))

      view
      |> element(~s([phx-window-keydown="cancel_edit"]))
      |> render_keydown(%{"key" => "Escape"})

      refute has_element?(view, ~s(form[phx-submit="save_section"]))
    end

    test "Formation Tops: Escape dismisses the delete prompt first, then the edit", %{conn: conn} do
      report = tops_report()
      {:ok, view, _} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "formation_tops")

      view
      |> element(~s(button[phx-click="edit_group"][phx-value-group="mwd_gamma"]))
      |> render_click()

      view
      |> element(~s(#row-menu-formation-tops-0 button[phx-click*="ask_delete"]))
      |> render_click()

      assert render(view) =~ "Delete this formation?"

      press_escape(view, "#tops-form-formation-tops")
      refute render(view) =~ "Delete this formation?"
      # still editing, nothing deleted
      assert has_element?(view, ~s(input[name="tops[rows][0][mwd_gamma][md]"]))

      press_escape(view, "#tops-form-formation-tops")
      refute has_element?(view, ~s(input[name="tops[rows][0][mwd_gamma][md]"]))
      assert length(import_data(report)["tops"]["formations"]) == 2
    end
  end

  describe "Surveys tab, Actual / Planned" do
    defp both_surveys_report do
      create_report(%{
        "import_data" => %{
          "reservoir_data" => [
            %{
              "leg_name" => "Main",
              "survey" => %{
                "survey_points" => [
                  %{"md" => 0.0, "inclination_deg" => 0.0, "azimuth_deg" => 0.0, "tvd" => 0.0},
                  %{
                    "md" => 111.11,
                    "inclination_deg" => 1.0,
                    "azimuth_deg" => 0.0,
                    "tvd" => 111.1
                  }
                ]
              }
            }
          ]
        },
        "report_data" => %{
          "surveys" => %{
            "0" => %{"md" => "0", "inclination" => "0", "azimuth" => "0"},
            "1" => %{"md" => "222.22", "inclination" => "2", "azimuth" => "185"}
          }
        }
      })
    end

    test "opens on the actual survey and switches to the plan", %{conn: conn} do
      report = both_surveys_report()
      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "surveys")

      assert has_element?(view, ~s(button[phx-value-view="actual"][aria-selected="true"]))
      assert has_element?(view, "#survey-0")
      refute has_element?(view, "#surveys_table")

      view |> element(~s(button[phx-value-view="planned"])) |> render_click()

      assert_patch(view, "/reports/#{report.id}?tab=surveys&survey=planned")
      assert has_element?(view, ~s(button[phx-value-view="planned"][aria-selected="true"]))
      assert has_element?(view, "#surveys_table", "222.22")
      refute has_element?(view, "#survey-0")

      view |> element(~s(button[phx-value-view="actual"])) |> render_click()
      assert has_element?(view, "#survey-0", "111.11")
    end

    test "the choice survives a reload", %{conn: conn} do
      report = both_surveys_report()
      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}?tab=surveys&survey=planned")

      assert has_element?(view, "#surveys_table")
      refute has_element?(view, "#survey-0")
    end

    test "switching closes an open plan editor", %{conn: conn} do
      report = both_surveys_report()
      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}?tab=surveys&survey=planned")
      view |> element(~s(button[phx-value-section="surveys"])) |> render_click()
      assert has_element?(view, ~s(form[phx-submit="save_section"]))

      view |> element(~s(button[phx-value-view="actual"])) |> render_click()
      view |> element(~s(button[phx-value-view="planned"])) |> render_click()
      refute has_element?(view, ~s(form[phx-submit="save_section"]))
    end

    test "a report with only a plan opens on it", %{conn: conn} do
      report =
        create_report(%{
          "report_data" => %{
            "surveys" => %{"0" => %{"md" => "222.22", "inclination" => "2", "azimuth" => "185"}}
          }
        })

      {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}")
      open_tab(view, "surveys")

      assert has_element?(view, ~s(button[phx-value-view="planned"][aria-selected="true"]))
      assert has_element?(view, "#surveys_table", "222.22")
    end
  end

  describe "Surveys tab, position vs plan" do
    # Plan runs straight down; the actual drifts 3 m north and lands 2 m high.
    defp off_plan_report(plan? \\ true) do
      create_report(%{
        "import_data" => %{
          "reservoir_data" => [
            %{
              "leg_name" => "Main",
              "survey" => %{
                "survey_points" => [
                  %{"md" => 0.0, "tvd" => 0.0, "north_south" => 0.0, "east_west" => 0.0},
                  %{"md" => 500.0, "tvd" => 498.0, "north_south" => 3.0, "east_west" => 0.0}
                ]
              }
            }
          ]
        },
        "report_data" => %{
          "surveys" =>
            if(plan?,
              do: %{
                "0" => %{"md" => "0", "inclination" => "0", "azimuth" => "0"},
                "1" => %{"md" => "600", "inclination" => "0", "azimuth" => "0"}
              },
              else: %{}
            )
        }
      })
    end

    test "shows where the last survey sits against the plan", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/reports/#{off_plan_report().id}?tab=surveys")

      # A vertical plan has no section line of its own, so it reads along north.
      assert has_element?(view, "#plan-comparison-0", "Last survey · 500 m MD")
      assert has_element?(view, "#plan-comparison-0", "2 m above")
      assert has_element?(view, "#plan-comparison-0", "3 m ahead")
      assert has_element?(view, "#plan-comparison-0-table", "on plan")
    end

    test "says so when there is no plan to compare with", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/reports/#{off_plan_report(false).id}?tab=surveys")

      assert has_element?(view, "#plan-comparison-0", "No planned survey to compare against")
    end

    test "is not shown on the Planned view", %{conn: conn} do
      {:ok, view, _html} =
        live(conn, ~p"/reports/#{off_plan_report().id}?tab=surveys&survey=planned")

      refute has_element?(view, "#plan-comparison-0")
    end
  end
end
