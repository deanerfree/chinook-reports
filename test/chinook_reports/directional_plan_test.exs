defmodule ChinookReports.DirectionalPlanTest do
  use ExUnit.Case, async: true

  alias ChinookReports.DirectionalPlan

  # A trimmed COMPASS CSV export: "H KEY :,value" header, unquoted comments
  # (the comma in "Nudge, 1.5°/30m" spills into an extra field), Latin-1 °.
  @compass_csv """
  H HEADER INFORMATION -------------------------------------------,
  H DIRECTIONAL COMPANY:,PACESETTER DIRECTIONAL DRILLING LTD.,
  H COMPANY :,Canadian Natural Resources Ltd.
  H WELL    :,CNRL Hz Wapiti 4-31-64-8W6M
  H KB ELEVN :,1116.69
  H VSECT ANGLE :,187.40
  H SURVEY TYPE INFORMATION,
  H07000.00 : 6505.51 : PROPOSAL 4 : MWD+HDGM_REV5
  H Survey List,
  MD,Incl.,Azim.,TVD,Sub-Sea,NS,EW,VSEC,Dogleg,UTM(X),UTM(Y),Latitude,Longitude,Comment
  0.00      ,0.00      ,0.00      ,0.00       ,1116.69   ,0.00       ,0.00       ,0.00     ,0.0000 ,358217.63,6052943.18,54.605960,-119.195079,\s
  665.00    ,0.00      ,0.00      ,665.00     ,451.69    ,0.00       ,0.00       ,0.00     ,0.0000 ,358217.63,6052943.18,54.605960,-119.195079,Nudge, 1.5°/30m
  690.00    ,1.25      ,300.00    ,690.00     ,426.69    ,0.14       ,-0.24      ,-0.10    ,1.5000 ,358217.40,6052943.32,54.605962,-119.195083,\s
  735.73    ,3.54      ,300.00    ,735.69     ,381.00    ,1.09       ,-1.89      ,-0.84    ,1.5000 ,358215.78,6052944.33,54.605970,-119.195108,PASKAPOO
  """

  @tab_listing """
  # Sat Sep 26 16:59:54 MDT 2026
  # CVE PARADISE HILL OBS DD 4B16-10-3C9-10-54-24
  # VSD = 220.44
  MD(m)\tInc(deg)\tAzm(deg)\tTVD(m)\tVS(m)\tNS(m)\tEW(m)\tDLS(deg/30m)\tSubsea(m)\tBuild Rate(deg/30m)\tTurn Rate(deg/30m)
  0.00\t0.00\t0.00\t0.00\t0.00\t0.00\t0.00\t0.00\t631.75\t0.00\t0.00
  24.46\t0.70\t49.98\t24.46\t-0.12\t0.08\t0.10\t1.03\t607.29\t1.03\t73.28
  #EOF
  """

  defp write_tmp!(name, content) do
    path = Path.join(System.tmp_dir!(), "#{System.unique_integer([:positive])}-#{name}")
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    path
  end

  describe "extract/1" do
    test "reads a COMPASS CSV export: header, stations and unquoted comments" do
      path =
        write_tmp!("plan.csv", :unicode.characters_to_binary(@compass_csv, :unicode, :latin1))

      assert {:ok, plan} = DirectionalPlan.extract(path)
      assert plan["source_format"] == "text"
      assert plan["header"]["design"] == "Proposal 4"
      assert plan["header"]["kb_elevation"] == 1116.69
      assert plan["header"]["vertical_section_azimuth_deg"] == 187.4

      assert [_, nudge, _, paskapoo] = plan["survey"]
      assert nudge["labels"] == ["Nudge, 1.5°/30m"]
      assert paskapoo["md"] == 735.73
      assert paskapoo["inclination_deg"] == 3.54
      assert paskapoo["labels"] == ["PASKAPOO"]
    end

    test "reads a tab-delimited survey listing with # comments" do
      assert {:ok, plan} = DirectionalPlan.extract(write_tmp!("surveys.txt", @tab_listing))

      assert plan["header"]["well_name"] == "CVE PARADISE HILL OBS DD 4B16-10-3C9-10-54-24"
      assert plan["header"]["vertical_section_azimuth_deg"] == 220.44
      assert [_, %{"md" => 24.46, "azimuth_deg" => 49.98, "subsea" => 607.29}] = plan["survey"]
    end

    test "explains a file it can't read" do
      assert {:error, message} =
               DirectionalPlan.extract(write_tmp!("notes.txt", "nothing here\n"))

      assert message =~ "No survey listing found"
    end
  end

  describe "program_rows/1" do
    test "takes MD / Inc / Azi as decimals in MD order, dropping incomplete stations" do
      plan = %{
        "survey" => [
          %{"md" => 30.0, "inclination_deg" => 1.25, "azimuth_deg" => 300.0},
          %{"md" => 0.0, "inclination_deg" => 0.0, "azimuth_deg" => 0},
          %{"md" => 60.0, "inclination_deg" => nil, "azimuth_deg" => 300.0}
        ]
      }

      assert [first, second] = DirectionalPlan.program_rows(plan)
      assert Decimal.equal?(first.md, 0)
      assert Decimal.equal?(second.md, "30.0")
      assert Decimal.equal?(second.inclination, "1.25")
      assert Decimal.equal?(second.azimuth, 300)
    end
  end

  describe "summary/2" do
    @plan %{
      "header" => %{
        "design" => "Proposal 4",
        "provider" => "Pacesetter Directional Drilling Ltd.",
        "unique_well_id" => "100/04-31-064-08W6/00"
      },
      "survey" => [%{"md" => 0.0, "inclination_deg" => 0.0, "azimuth_deg" => 0.0}]
    }

    test "names what was loaded" do
      assert DirectionalPlan.summary(@plan, "100/04-31-064-08W6/00") ==
               "Loaded 1 stations from Proposal 4 (Pacesetter Directional Drilling Ltd.)."
    end

    test "flags a plan whose UWI isn't this report's" do
      assert DirectionalPlan.summary(@plan, "102/09-10-054-24W3/00") =~
               "the plan's UWI is 100/04-31-064-08W6/00, this report's is 102/09-10-054-24W3/00"
    end
  end

  # The Formations table of each test plan, as printed: {name, MD, TVD, subsea}.
  @wapiti_tops [
    {"PASKAPOO", 735.73, 735.69, 381.0},
    {"SCOLLARD", 896.72, 895.69, 221.0},
    {"BEARPAW", 958.05, 956.69, 160.0},
    {"WAPITI", 963.06, 961.69, 155.0},
    {"BELLY RIVER GROUP", 1055.13, 1053.69, 63.0},
    {"PUSKWASKAU", 1443.73, 1442.29, -325.6},
    {"CHINOOK SAND", 1467.43, 1465.99, -349.3},
    {"COLORADO", 1501.33, 1499.89, -383.2},
    {"BADHEART", 1654.83, 1653.39, -536.7},
    {"MUSKIKI", 1688.43, 1686.99, -570.3},
    {"CARDIUM ZONE", 1725.33, 1723.89, -607.2},
    {"CARDIUM SAND", 1751.53, 1750.09, -633.4},
    {"KASKAPAU", 1787.43, 1785.99, -669.3},
    {"DOE CREEK (Uppr)", 2212.43, 2210.99, -1094.3},
    {"DOE CREEK (Lwr)", 2252.23, 2250.79, -1134.1},
    {"DUNVEGAN", 2301.93, 2300.49, -1183.8},
    {"SHAFTESBURY", 2455.33, 2453.89, -1337.2},
    {"FISH SCALES ZONE (1st hot GR below DNVG)", 2469.13, 2467.69, -1351.0},
    {"BASE OF FISH SCALES", 2526.43, 2524.99, -1408.3},
    {"PADDY", 2634.43, 2632.99, -1516.3},
    {"CADOTTE", 2657.83, 2656.39, -1539.7},
    {"HARMON", 2678.15, 2676.69, -1560.0},
    {"NOTIKEWIN", 2705.16, 2703.49, -1586.8},
    {"FALHER (A)", 2759.4, 2755.79, -1639.1},
    {"FALHER (B)", 2784.17, 2778.59, -1661.9},
    {"FALHER (C)", 2811.05, 2802.29, -1685.6},
    {"FALHER (D)", 2850.14, 2834.39, -1717.7},
    {"FALHER (E)", 2887.09, 2861.69, -1745.0},
    {"FALHER (F)", 2958.49, 2904.39, -1787.7},
    {"FALHER (G)", 3049.6, 2936.29, -1819.6}
  ]

  @paradise_hill_tops [
    {"First_White_Specks", 248.24, 248.18, 384.0},
    {"Second White Specks", 282.99, 282.18, 350.0},
    {"Belle_Fourch", 308.48, 306.18, 326.0},
    {"Base Fish Scales", 353.14, 345.18, 287.0},
    {"St_Walburg_Sand", 376.65, 363.68, 268.5},
    {"Westgate_Mbr", 406.36, 385.18, 247.0},
    {"Joli Fou", 452.4, 418.18, 214.0},
    {"Colony", 510.31, 459.68, 172.5},
    {"Colony Target", 523.56, 469.18, 163.0},
    {"Mclaren", 527.75, 472.18, 160.0},
    {"Waseca", 552.86, 490.18, 142.0},
    {"Sparky", 594.72, 520.18, 112.0}
  ]

  defp tops_of(fixture) do
    {:ok, plan} = DirectionalPlan.extract(Path.join("test/test_data/directional", fixture))
    for t <- DirectionalPlan.tops(plan), do: {t["formation"], t["md"], t["tvd"], t["subsea"]}
  end

  describe "tops/1" do
    test "takes every row of a Pacesetter plan's Formations table, across its page break" do
      assert tops_of("wapiti_plan.pdf") == @wapiti_tops
    end

    test "takes every row of an Altitude plan's Formations table, repeated names included" do
      assert tops_of("paradise_hill_plan.pdf") == @paradise_hill_tops
    end

    test "a CSV / TXT listing has no Formations table" do
      assert DirectionalPlan.tops(%{"survey" => [%{"md" => 1.0}]}) == []
    end
  end

  defp top(name, md), do: %{"formation" => name, "md" => md, "tvd" => md, "subsea" => -md}

  describe "merge_prognosis/2" do
    test "fills Prognosis by name (case and spacing ignored), keeps picks and the row's own name" do
      rows = [
        %{
          "formation" => "Joli  fou",
          "prognosis" => %{"md" => 1.0, "isopach" => 3.0},
          "samples" => %{"md" => 455.0},
          "mwd_gamma" => %{}
        }
      ]

      assert [row] = DirectionalPlan.merge_prognosis(rows, [top("Joli Fou", 452.4)])
      assert row["formation"] == "Joli  fou"

      # The plan's TVD is from its own KB; only MD and subsea are taken.
      assert row["prognosis"] == %{"md" => 452.4, "subsea" => -452.4, "isopach" => 3.0}

      assert row["samples"] == %{"md" => 455.0}
    end

    test "a repeated name fills the next row of that name, then adds a row" do
      rows = [
        %{"formation" => "Colony", "prognosis" => %{}, "samples" => %{"md" => 511.0}},
        %{"formation" => "Mclaren", "prognosis" => %{"md" => 527.0}}
      ]

      merged =
        DirectionalPlan.merge_prognosis(rows, [
          top("Colony", 510.31),
          top("Colony Target", 523.56),
          top("Mclaren", 527.75)
        ])

      assert Enum.map(merged, &{&1["formation"], &1["prognosis"]["md"]}) == [
               {"Colony", 510.31},
               {"Colony", 523.56},
               {"Mclaren", 527.75}
             ]

      assert hd(merged)["samples"] == %{"md" => 511.0}
      assert Enum.at(merged, 1)["samples"] == %{}
    end

    test "adds unmatched formations at their MD and never drops a row" do
      rows = [
        %{"formation" => "A", "prognosis" => %{"md" => 100.0}},
        %{"formation" => "Not in plan", "samples" => %{"md" => 200.0}},
        %{"formation" => "C", "prognosis" => %{"md" => 300.0}}
      ]

      merged =
        DirectionalPlan.merge_prognosis(rows, [top("B", 150.0), top("D", 400.0), top("A", 101.0)])

      assert Enum.map(merged, & &1["formation"]) == ["A", "B", "Not in plan", "C", "D"]
    end

    test "into no rows, gives the plan's tops in order" do
      merged = DirectionalPlan.merge_prognosis([], [top("X", 10.0), top("Y", 20.0)])
      assert Enum.map(merged, & &1["formation"]) == ["X", "Y"]
    end
  end

  describe "merge_formation_tops/2" do
    alias ChinookReports.Reports.Report.ReportData.FormationTop

    test "matched rows become changesets with the plan's depths; new rows are structs" do
      existing = [%FormationTop{id: "a", formation: "COLORADO", isopach: Decimal.new("12")}]

      [colorado, new] =
        DirectionalPlan.merge_formation_tops(existing, [
          top("Colorado", 1501.33),
          top("BADHEART", 1654.83)
        ])

      assert %Ecto.Changeset{changes: changes, data: %{id: "a"}} = colorado
      assert Decimal.equal?(changes.md, "1501.33")
      assert Decimal.equal?(changes.subsea, "-1501.33")
      assert changes[:tvd] == nil
      refute Map.has_key?(changes, :isopach)

      assert %FormationTop{formation: "BADHEART", isopach: nil} = new
      assert Decimal.equal?(new.md, "1654.83")
    end
  end
end
