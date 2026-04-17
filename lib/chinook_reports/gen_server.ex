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
      {:ok, data} ->
        new_state = Map.update(state, :results, [data], &[data | &1])
        {:reply, {:ok, data}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
