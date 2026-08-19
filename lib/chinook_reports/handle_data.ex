defmodule ChinookReports.HandleData do
  require Logger

  alias ChinookReports.{Repo, Reports.Report}

  def fetch_report(params \\ %{}) do
    IO.inspect("Fetching report with params: #{inspect(params["id"])}")
    # convert id to integer if it's a string
    id = String.to_integer(params["id"])

    case Repo.get_by(Report, id: id) do
      nil -> {:error, :not_found}
      report -> {:ok, report}
    end
  end

  def fetch_reports_list(params \\ %{}) do
    Flop.validate_and_run(Report, params, for: Report, repo: Repo)
  rescue
    e -> {:error, Exception.message(e)}
  end

  def store_report_data(json_map) when is_map(json_map) do
    meta = json_map["metadata"]

    attrs = %{
      well_name: meta["well_name"],
      unique_well_id: meta["unique_well_id"],
      operator: meta["operator"],
      spud_date: parse_date(meta["spud_date"]),
      final_td_date: parse_date(meta["final_td_date"]),
      target_formation: meta["target_formation"],
      secondary_target: meta["secondary_target"],
      country: meta["country"],
      province: meta["province"],
      latitude: meta["latitude"],
      longitude: meta["longitude"],
      geometry: meta["geometry"],
      status: meta["status"],
      company_id: meta["company_id"],
      metadata: meta
    }

    %Report{}
    |> Report.changeset(attrs)
    |> Repo.insert(on_conflict: :replace_all, conflict_target: :unique_well_id)
  end

  def seed_from_test_data do
    dir = Path.expand("test/test_data")

    case Path.wildcard(Path.join(dir, "*.json")) do
      [] ->
        {:error, :no_files}

      paths ->
        results =
          Enum.map(paths, fn path ->
            with {:ok, content} <- File.read(path),
                 {:ok, json} <- Jason.decode(content),
                 {:ok, report} <- store_report_data(json) do
              Logger.info("Seeded report from #{path}")
              {:ok, report}
            else
              {:error, reason} ->
                Logger.warning("Failed to seed #{path}: #{inspect(reason)}")
                {:error, reason}
            end
          end)

        {:ok, results}
    end
  end

  defp parse_date(nil), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
