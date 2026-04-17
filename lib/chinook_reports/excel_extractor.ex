defmodule ChinookReports.ExcelExtractor do
  require Logger

  @doc """
  Extract data from an Excel file using the Python extraction script.
  Accepts an optional progress_callback that receives step name strings
  (e.g. "loading", "welldata", "tops", "reservoirs", "surveys", "complete").
  """
  def extract_data(file_path, progress_callback \\ fn _ -> :ok end) do
    Logger.info("Starting Excel extraction for file: #{file_path}")
    config = Application.fetch_env!(:chinook_reports, __MODULE__)
    script_path = config[:script_path]
    script_dir = Path.dirname(script_path)
    python = System.find_executable("python3") || raise "python3 not found on PATH"

    port =
      Port.open({:spawn_executable, python}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:args, [script_path, file_path]},
        {:cd, script_dir},
        {:line, 65_536}
      ])

    collect_output(port, [], "", progress_callback)
  end

  defp collect_output(port, lines, partial, callback) do
    receive do
      {^port, {:data, {:eol, data}}} ->
        line = partial <> data

        case line do
          "PROGRESS:" <> step ->
            callback.(String.trim(step))
            collect_output(port, lines, "", callback)

          _ ->
            collect_output(port, [line | lines], "", callback)
        end

      {^port, {:data, {:noeol, data}}} ->
        collect_output(port, lines, partial <> data, callback)

      {^port, {:exit_status, 0}} ->
        all_lines = if partial != "", do: [partial | lines], else: lines
        json = all_lines |> Enum.reverse() |> Enum.join("\n") |> String.trim()
        Logger.info("Excel extraction successful for file")
        {:ok, json}

      {^port, {:exit_status, code}} ->
        all_lines = if partial != "", do: [partial | lines], else: lines
        output = all_lines |> Enum.reverse() |> Enum.join("\n")
        Logger.error("Excel extraction failed with exit code #{code}: #{output}")
        {:error, output}
    after
      120_000 ->
        Port.close(port)
        {:error, "Extraction timed out after 120 seconds"}
    end
  end
end
