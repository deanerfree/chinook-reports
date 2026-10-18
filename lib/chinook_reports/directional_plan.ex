defmodule ChinookReports.DirectionalPlan do
  @moduledoc """
  Reads a directional plan file into the stations the Directional Program
  (`report_data.surveys`) holds.

  Accepts what the directional companies send: a COMPASS planning report PDF,
  or the same plan's CSV / TXT survey listing (comma-, tab- or
  whitespace-delimited). The parsing lives in
  `priv/scripts/python/extract_plan.py`, which sniffs the format from the
  file's content; this module runs it and shapes its JSON.

  Only MD / inclination / azimuth are taken into the program — TVD, N/S, E/W
  and dogleg are recomputed from those by `ChinookReports.Trajectory`, the same
  as for a program typed in by hand.
  """

  require Logger

  alias ChinookReports.Reports.Report.ReportData.{FormationTop, SurveyPoint}

  @timeout 60_000

  @doc """
  Parse the plan file at `path`. Returns `{:ok, plan}` with the script's JSON
  as a string-keyed map, or `{:error, reason}` with a message fit to show.
  """
  @spec extract(Path.t()) :: {:ok, map()} | {:error, String.t()}
  def extract(path) do
    case System.find_executable("python3") do
      nil -> {:error, "python3 is not available on the server"}
      python -> run(python, path)
    end
  end

  defp run(python, path) do
    script = Application.app_dir(:chinook_reports, "priv/scripts/python/extract_plan.py")

    task =
      Task.async(fn ->
        System.cmd(python, [script, Path.expand(path)], cd: Path.dirname(script))
      end)

    case Task.yield(task, @timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {out, 0}} ->
        case Jason.decode(out) do
          {:ok, %{} = plan} -> {:ok, plan}
          _ -> {:error, "the plan reader returned unreadable output"}
        end

      {:ok, {out, code}} ->
        Logger.error("Plan extraction failed with exit code #{code}: #{out}")

        case Jason.decode(out) do
          {:ok, %{"error" => message}} -> {:error, message}
          _ -> {:error, "the plan reader failed"}
        end

      nil ->
        {:error, "reading the plan timed out"}
    end
  end

  @doc """
  The plan's survey stations as Directional Program rows, in MD order. Stations
  missing MD, inclination or azimuth are dropped.
  """
  @spec program_rows(map()) :: [SurveyPoint.t()]
  def program_rows(plan) do
    (plan["survey"] || [])
    |> Enum.flat_map(fn station ->
      case {decimal(station["md"]), decimal(station["inclination_deg"]),
            decimal(station["azimuth_deg"])} do
        {%Decimal{} = md, %Decimal{} = inc, %Decimal{} = azi} ->
          [%SurveyPoint{md: md, inclination: inc, azimuth: azi}]

        _ ->
          []
      end
    end)
    |> Enum.sort_by(& &1.md, Decimal)
  end

  @doc """
  The plan's formation tops, every row of its Formations table in the order
  printed, each as `%{"formation", "md", "tvd", "subsea"}`. Names are kept
  verbatim and repeated names are kept as separate rows. Only a PDF plan has a
  Formations table; a CSV / TXT listing gives `[]`.
  """
  @spec tops(map()) :: [map()]
  def tops(plan) do
    (get_in(plan, ["tops", "formations"]) || [])
    |> Enum.flat_map(fn
      %{"formation" => name, "prognosis" => pick} when is_binary(name) and is_map(pick) ->
        [
          %{
            "formation" => name,
            "md" => pick["md"],
            "tvd" => pick["tvd"],
            "subsea" => pick["subsea"]
          }
        ]

      _ ->
        []
    end)
  end

  @doc """
  Merge `plan_tops` (from `tops/1`) into an existing tops list, keeping every
  row of both.

  Each plan top is matched to an existing row by formation name (case and
  whitespace ignored); a name the plan repeats matches the next existing row
  of that name in order. A matched row is passed to `fill.(row, top)`; an
  unmatched top becomes `new.(top)`, inserted ahead of the first row whose
  `md.(row)` is deeper (appended when there is none, or it has no MD). Existing
  rows keep their order and are never dropped.

  The row shape is the caller's — `name`, `md`, `fill` and `new` read and
  build it — so the same matching serves `report_data.formation_tops` and
  `import_data["tops"]`.
  """
  @spec merge_tops([row], [map()], keyword()) :: [row] when row: term()
  def merge_tops(rows, plan_tops, opts) do
    name = Keyword.fetch!(opts, :name)
    md = Keyword.fetch!(opts, :md)
    fill = Keyword.fetch!(opts, :fill)
    new = Keyword.fetch!(opts, :new)

    slots =
      rows
      |> Enum.with_index()
      |> Enum.group_by(fn {row, _} -> match_key(name.(row)) end, fn {_, i} -> i end)
      |> Map.delete(nil)

    {fills, additions, _seen} =
      Enum.reduce(plan_tops, {%{}, [], %{}}, fn top, {fills, additions, seen} ->
        key = match_key(top["formation"])
        n = Map.get(seen, key, 0)
        seen = Map.put(seen, key, n + 1)

        case slots |> Map.get(key, []) |> Enum.at(n) do
          nil -> {fills, [new.(top) | additions], seen}
          i -> {Map.put(fills, i, top), additions, seen}
        end
      end)

    filled =
      rows
      |> Enum.with_index()
      |> Enum.map(fn {row, i} ->
        case fills do
          %{^i => top} -> fill.(row, top)
          _ -> row
        end
      end)

    additions
    |> Enum.reverse()
    |> Enum.reduce(filled, &insert_by_md(&2, &1, md))
  end

  @doc """
  `merge_tops/3` into `import_data["tops"]["formations"]` rows: the plan's MD
  and subsea go into each row's `"prognosis"` group (see `pick/1` on TVD); the compared
  groups (Samples, MWD / Gamma, Wireline) are left as they are. Run the result through
  `ChinookReports.FormationTops.recompute/2` before saving.
  """
  @spec merge_prognosis([map()], [map()]) :: [map()]
  def merge_prognosis(formations, plan_tops) do
    merge_tops(formations, plan_tops,
      name: & &1["formation"],
      md: &import_row_md/1,
      fill: fn row, top ->
        Map.update(row, "prognosis", pick(top), &Map.merge(&1 || %{}, pick(top)))
      end,
      new: fn top ->
        ChinookReports.FormationTops.compared_groups()
        |> Map.new(&{&1, %{}})
        |> Map.merge(%{"formation" => top["formation"], "prognosis" => pick(top)})
      end
    )
  end

  @doc """
  `merge_tops/3` into `report_data.formation_tops` (`FormationTop` structs, as
  `Ecto.Changeset.get_field/2` gives them): a matched row gets the plan's MD
  and subsea as changes (TVD and isopach are re-derived); an unmatched top becomes a
  new row. The result goes to `Editing.replace_rows(changeset, :formation_tops, rows)`.
  """
  @spec merge_formation_tops([struct()], [map()]) :: [struct() | Ecto.Changeset.t()]
  def merge_formation_tops(rows, plan_tops) do
    merge_tops(rows, plan_tops,
      name: &typed_field(&1, :formation),
      md: &(&1 |> typed_field(:md) |> to_number()),
      fill: fn row, top -> Ecto.Changeset.change(row, typed_pick(top)) end,
      new: fn top ->
        struct(FormationTop, Map.put(typed_pick(top), :formation, top["formation"]))
      end
    )
  end

  # A plan's TVD is measured from the plan's KB, not ours, so only its MD and
  # subsea (the KB-independent pick) are taken; TVD is re-derived from our KB
  # (`ChinookReports.FormationTops`). Only a top with no subsea — the plan
  # gave no KB to convert it — falls back to the plan's TVD.
  defp pick(%{"subsea" => ss} = top) when not is_nil(ss), do: Map.take(top, ~w(md subsea))
  defp pick(top), do: Map.take(top, ~w(md tvd subsea))

  defp typed_pick(top) do
    pick = pick(top)
    %{md: decimal(pick["md"]), tvd: decimal(pick["tvd"]), subsea: decimal(pick["subsea"])}
  end

  # A row in the list being merged is a struct or (once filled) a changeset.
  defp typed_field(row, field),
    do: row |> Ecto.Changeset.change() |> Ecto.Changeset.get_field(field)

  defp import_row_md(row) do
    Enum.find_value(
      ["prognosis" | ChinookReports.FormationTops.compared_groups()],
      &to_number(get_in(row, [&1, "md"]))
    )
  end

  defp to_number(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_number(n) when is_number(n), do: n
  defp to_number(_), do: nil

  defp match_key(name) when is_binary(name) do
    case name |> String.split() |> Enum.join(" ") |> String.downcase() do
      "" -> nil
      key -> key
    end
  end

  defp match_key(_), do: nil

  defp insert_by_md(rows, row, md) do
    case md.(row) do
      nil ->
        rows ++ [row]

      depth ->
        index = Enum.find_index(rows, fn r -> (d = md.(r)) && d > depth end)
        List.insert_at(rows, index || -1, row)
    end
  end

  @doc """
  A one-line description of what was loaded, e.g.
  `"Loaded 192 stations from Proposal 4 (Pacesetter Directional Drilling Ltd.)."`.
  Notes when the plan's UWI differs from `report_uwi` (the plan may be for
  another well).
  """
  @spec summary(map(), String.t() | nil) :: String.t()
  def summary(plan, report_uwi) do
    header = plan["header"] || %{}
    count = length(program_rows(plan))
    name = header["design"] || header["well_name"]
    provider = header["provider"]

    source =
      case {name, provider} do
        {nil, nil} -> ""
        {nil, p} -> " from #{p}"
        {n, nil} -> " from #{n}"
        {n, p} -> " from #{n} (#{p})"
      end

    "Loaded #{count} stations#{source}." <> uwi_note(header["unique_well_id"], report_uwi)
  end

  defp uwi_note(plan_uwi, report_uwi)
       when is_binary(plan_uwi) and is_binary(report_uwi) and report_uwi != "" do
    if normalize(plan_uwi) == normalize(report_uwi),
      do: "",
      else: " Check the well: the plan's UWI is #{plan_uwi}, this report's is #{report_uwi}."
  end

  defp uwi_note(_, _), do: ""

  defp normalize(uwi), do: uwi |> String.upcase() |> String.replace(~r/\s+/, "")

  defp decimal(v) when is_float(v), do: Decimal.from_float(v)
  defp decimal(v) when is_integer(v), do: Decimal.new(v)
  defp decimal(_), do: nil
end
