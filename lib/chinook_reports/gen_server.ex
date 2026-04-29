defmodule ChinookReports.GenServer do
  use GenServer
  alias ChinookReports.ExcelExtractor

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  def extract_excel_data(file_path) do
    GenServer.call(__MODULE__, {:extract_excel_data, file_path, nil}, 120_000)
  end

  def fetch_reports_list(params \\ %{}) do
    GenServer.call(__MODULE__, {:fetch_reports_list, params})
  end

  def fetch_report(params \\ %{}) do
    GenServer.call(__MODULE__, {:fetch_report, params})
  end

  @doc """
  Synchronous extraction that sends {:extraction_progress, step} messages
  to notify_pid as each section is processed.
  """
  def extract_excel_data(file_path, notify_pid) do
    GenServer.call(__MODULE__, {:extract_excel_data, file_path, notify_pid}, 120_000)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %{results: []}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:extract_excel_data, file_path, notify_pid}, _from, state) do
    IO.puts("GenServer received request to extract data from: #{file_path}")

    callback =
      case notify_pid do
        nil -> fn _ -> :ok end
        pid -> fn step -> send(pid, {:extraction_progress, step}) end
      end

    case ExcelExtractor.extract_data(file_path, callback) do
      {:ok, json} ->
        with {:ok, data} <- Jason.decode(json),
             {:ok, report} <- ChinookReports.HandleData.store_report_data(data) do
          new_state = Map.update(state, :results, [report], &[report | &1])
          {:reply, {:ok, report}, new_state}
        else
          {:error, reason} -> {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:fetch_reports_list, params}, _from, state) do
    case ChinookReports.HandleData.fetch_reports_list(params) do
      {:ok, {data, meta}} ->
        new_state = Map.put(state, :results, data)
        {:reply, {:ok, {data, meta}}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
