defmodule ChinookReports.ReservoirQuality do
  @moduledoc """
  Recompute the derived pieces of a reservoir leg's `log_data` after its
  interval table is edited.

  Each leg under `import_data["reservoir_data"]` carries `log_data.intervals`
  — the From / To footage picks with a lithology, porosity, gas and quality
  call — and `log_data.quality_summary`, the metres/percent-per-band totals
  the Summary tab's quality chart reads. `recompute_for_report/2` rebuilds
  `quality_summary` from an edited interval list so the two never drift.
  """

  @quality_order ["Very Good", "Good", "Fair", "Poor", "Nil"]

  @doc "The five reservoir-quality labels an interval row may be tagged with."
  @spec quality_options() :: [String.t()]
  def quality_options, do: @quality_order

  @doc """
  Index of the leg whose `log_data` the Reservoir tab edits — the first leg
  carrying a `log_data` map, or `0` when none do (a blank leg to start
  filling in). `nil` when the report carries no legs at all.
  """
  @spec leg_index(struct() | map()) :: non_neg_integer() | nil
  def leg_index(report) do
    case (report.import_data || %{})["reservoir_data"] do
      [_ | _] = legs -> Enum.find_index(legs, &is_map(&1["log_data"])) || 0
      _ -> nil
    end
  end

  @doc "The edited leg's current interval rows, or `[]`."
  @spec intervals_for_report(struct() | map()) :: [map()]
  def intervals_for_report(report) do
    case leg_index(report) do
      nil ->
        []

      i ->
        leg = report.import_data["reservoir_data"] |> Enum.at(i)
        get_in(leg, ["log_data", "intervals"]) || []
    end
  end

  @doc """
  The edited leg's interval rows, each tagged with a stable string `"id"` (its
  position in the stored list) so the Reservoir Quality picker can round-trip
  row identity while it is being dragged and re-classified. The `"id"` is not
  persisted — the picker sends it back on save and the LiveComponent drops it.
  """
  @spec interval_rows_for_report(struct() | map()) :: [map()]
  def interval_rows_for_report(report) do
    report
    |> intervals_for_report()
    |> Enum.with_index()
    |> Enum.map(fn {iv, i} -> Map.put(iv, "id", Integer.to_string(i)) end)
  end

  @doc """
  Whether the edited leg is a horizontal or a vertical well — decides which
  layout the picker opens in (the user can still flip the toggle). Horizontal
  unless the leg name mentions "vertical".
  """
  @spec well_type_for_report(struct() | map()) :: :horizontal | :vertical
  def well_type_for_report(report) do
    name =
      case leg_index(report) do
        nil ->
          ""

        i ->
          leg = report.import_data["reservoir_data"] |> Enum.at(i)
          get_in(leg, ["log_data", "metadata", "leg_name"]) || leg["leg_name"] || ""
      end

    if name =~ ~r/vert/i, do: :vertical, else: :horizontal
  end

  @doc """
  The GR / ROP / Gas curve trace behind the picker's chart, downsampled and
  paired with the ranges + cutoffs the chart scales against. Returns an empty
  trace (`points: []`) when the edited leg carries no `log_data` — the picker
  then shows only the coverage ribbon and the table.
  """
  @spec curve_data_for_report(struct() | map()) :: %{
          points: [map()],
          metadata: map(),
          md_min: number() | nil,
          md_max: number() | nil,
          rop_max: number()
        }
  def curve_data_for_report(report) do
    empty = %{points: [], metadata: %{}, md_min: nil, md_max: nil, rop_max: 300}

    with i when is_integer(i) <- leg_index(report),
         leg = report.import_data["reservoir_data"] |> Enum.at(i),
         log_data when is_map(log_data) <- leg["log_data"],
         [_ | _] = raw <- log_data["curve_data_cleaned"] || [] do
      meta = log_data["curve_metadata"] || %{}
      null_value = meta["null_value"]

      points =
        raw
        |> Enum.with_index()
        |> Enum.filter(fn {_p, idx} -> rem(idx, 4) == 0 end)
        |> Enum.map(fn {p, _idx} ->
          %{
            "md" => numeric(p["md"]),
            "gamma" => curve_val(p["gamma"], null_value),
            "rop" => curve_val(p["rop"], null_value),
            "gas" => curve_val(p["gas"], null_value)
          }
        end)
        |> Enum.filter(& &1["md"])

      mds = Enum.map(points, & &1["md"])

      rop_max =
        points
        |> Enum.map(& &1["rop"])
        |> Enum.filter(&is_number/1)
        |> case do
          [] -> 300
          rops -> (rops |> Enum.max() |> Kernel./(10) |> Float.ceil() |> trunc()) * 10
        end

      %{
        points: points,
        metadata: meta,
        md_min: mds |> Enum.min(fn -> nil end),
        md_max: mds |> Enum.max(fn -> nil end),
        rop_max: max(rop_max, 10)
      }
    else
      _ -> empty
    end
  end

  defp curve_val(v, null_value) when is_number(v) do
    if null_value && v == null_value, do: nil, else: v
  end

  defp curve_val(_v, _null_value), do: nil

  @doc """
  Rebuild `import_data["reservoir_data"]` with the edited leg's
  `log_data.intervals` replaced by `intervals` and `log_data.quality_summary`
  recomputed to match. Returns `nil` when the report carries no legs.
  """
  @spec recompute_for_report(struct() | map(), [map()]) :: [map()] | nil
  def recompute_for_report(report, intervals) do
    case leg_index(report) do
      nil ->
        nil

      i ->
        legs = report.import_data["reservoir_data"]

        List.update_at(legs, i, fn leg ->
          log_data =
            (leg["log_data"] || %{})
            |> Map.put("intervals", intervals)
            |> Map.put("quality_summary", quality_summary(intervals))

          Map.put(leg, "log_data", log_data)
        end)
    end
  end

  @doc """
  Apply the Reservoir Quality picker's committed section list to `report`.

  `raw_list` is the full set of sections from the picker — each a map with
  `"from_depth"`, `"to_depth"`, `"quality"`, `"lithology"` and an optional
  `"id"` (the stable position handed out by `interval_rows_for_report/1`).
  Rows carrying an `id` are merged over the stored interval so the fields the
  picker never shows — `porosity`, `remarks`, the operator-entered `gas`
  reading — survive; deleted rows are simply absent. Returns the rebuilt
  `reservoir_data` legs (with `quality_summary` recomputed) or an error.
  """
  @spec commit_intervals(struct() | map(), [map()]) ::
          {:ok, [map()]} | {:error, :invalid | :no_legs}
  def commit_intervals(report, raw_list) when is_list(raw_list) do
    stored = interval_rows_for_report(report)

    with :ok <- validate_picks(raw_list) do
      intervals = Enum.map(raw_list, &coerce_pick(&1, stored))

      case recompute_for_report(report, intervals) do
        nil -> {:error, :no_legs}
        legs -> {:ok, legs}
      end
    end
  end

  defp validate_picks(list) do
    ok? =
      Enum.all?(list, fn row ->
        with {:ok, f} when is_number(f) <- num(row["from_depth"]),
             {:ok, t} when is_number(t) <- num(row["to_depth"]) do
          t > f and row["quality"] in @quality_order
        else
          _ -> false
        end
      end)

    if ok?, do: :ok, else: {:error, :invalid}
  end

  defp coerce_pick(row, stored) do
    {:ok, from} = num(row["from_depth"])
    {:ok, to} = num(row["to_depth"])
    base = Enum.find(stored, %{}, &(&1["id"] == row["id"]))

    %{
      "from_depth" => from,
      "to_depth" => to,
      "interval" => round1(to - from),
      "quality" => row["quality"],
      "lithology" => blank(row["lithology"]) || base["lithology"] || "Sandstone",
      "porosity" => base["porosity"],
      "gas" => base["gas"],
      "remarks" => base["remarks"]
    }
  end

  defp num(n) when is_number(n), do: {:ok, n / 1}

  defp num(s) when is_binary(s) do
    case Float.parse(String.trim(s)) do
      {f, ""} -> {:ok, f}
      _ -> :error
    end
  end

  defp num(_), do: :error

  defp blank(s) when is_binary(s), do: ((t = String.trim(s)) != "" && t) || nil
  defp blank(_), do: nil

  @doc "Metres / percent per quality band, aggregated from `intervals`, plus a Total row."
  @spec quality_summary([map()]) :: [map()]
  def quality_summary(intervals) do
    totals =
      Enum.reduce(intervals, %{}, fn iv, acc ->
        w = numeric(iv["interval"]) || 0
        Map.update(acc, iv["quality"], w, &(&1 + w))
      end)

    total = totals |> Map.values() |> Enum.sum()

    bands =
      Enum.map(@quality_order, fn q ->
        m = Map.get(totals, q, 0)
        %{"quality" => q, "metres" => round1(m), "percent" => percent(m, total)}
      end)

    bands ++ [%{"quality" => "Total", "metres" => round1(total), "percent" => 100.0}]
  end

  defp percent(_m, total) when total in [0, 0.0], do: 0.0
  defp percent(m, total), do: round1(m / total * 100)

  defp numeric(n) when is_number(n), do: n
  defp numeric(_), do: nil

  defp round1(n) when is_number(n), do: Float.round(n / 1, 2)
end
