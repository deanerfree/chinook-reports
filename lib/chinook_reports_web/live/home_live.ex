defmodule ChinookReportsWeb.HomeLive do
  use ChinookReportsWeb, :live_view

  alias ChinookReports.GenServer

  @extraction_steps [
    {"loading", "Loading workbook"},
    {"welldata", "Well Data"},
    {"tops", "Formation Tops"},
    {"reservoirs", "Reservoirs"},
    {"surveys", "Surveys"}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <form phx-submit="upload_excel" phx-change="validate">
      <.live_file_input upload={@uploads.excel} class="hidden" />
      <.svelte
        name="Home"
        props={
          %{
            files:
              Enum.map(@uploads.excel.entries, fn e ->
                %{name: e.client_name, size: e.client_size, ref: e.ref, progress: e.progress}
              end),
            extraction_status: @extraction_status
          }
        }
      />
    </form>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(results: [], error: nil, extraction_status: nil)
     |> allow_upload(:excel,
       accept: ~w(.xlsx .xls),
       max_entries: 10,
       max_file_size: 50_000_000,
       auto_upload: true
     )}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :excel, ref)}
  end

  @impl true
  def handle_event("upload_excel", _params, socket) do
    IO.puts("Processing Excel files...")

    try do
      consumed =
        consume_uploaded_entries(socket, :excel, fn %{path: path}, entry ->
          ext = Path.extname(entry.client_name)
          dest = path <> ext
          File.cp!(path, dest)
          {:ok, {entry.client_name, dest}}
        end)

      # Start extraction in a linked task so the LiveView is free
      # to receive progress messages and push updated props
      lv = self()

      for {name, dest} <- consumed do
        Task.start_link(fn ->
          result = GenServer.extract_excel_data(dest, lv)
          File.rm(dest)
          send(lv, {:extraction_done, name, result})
        end)
      end

      {:noreply,
       assign(socket,
         extraction_status: build_extraction_status(nil),
         pending_files: length(consumed)
       )}
    catch
      :exit, _ ->
        socket =
          socket.assigns.uploads.excel.entries
          |> Enum.reduce(socket, fn entry, acc ->
            try do
              cancel_upload(acc, :excel, entry.ref)
            catch
              :exit, _ -> acc
            end
          end)

        {:noreply,
         assign(socket, :error, "Upload session expired. Please re-upload your file(s).")}
    end
  end

  # ── Progress & completion messages from the extraction Task ──

  @impl true
  def handle_info({:extraction_progress, step}, socket) do
    {:noreply, assign(socket, extraction_status: build_extraction_status(step))}
  end

  @impl true
  def handle_info({:extraction_done, name, result}, socket) do
    pending = socket.assigns.pending_files - 1

    socket =
      case result do
        {:ok, data} ->
          assign(socket, results: [%{name: name, data: data} | socket.assigns.results])

        {:error, reason} ->
          assign(socket, error: "#{name}: #{reason}")
      end

    if pending <= 0 do
      {:noreply, assign(socket, extraction_status: nil, pending_files: 0)}
    else
      {:noreply, assign(socket, pending_files: pending)}
    end
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # ── Helpers ──

  defp build_extraction_status(nil) do
    %{
      steps:
        Enum.map(@extraction_steps, fn {name, label} ->
          %{name: name, label: label, status: "pending"}
        end)
    }
  end

  defp build_extraction_status("complete") do
    %{
      steps:
        Enum.map(@extraction_steps, fn {name, label} ->
          %{name: name, label: label, status: "completed"}
        end)
    }
  end

  defp build_extraction_status(current_step) do
    {steps, _past} =
      Enum.reduce(@extraction_steps, {[], false}, fn {name, label}, {acc, past_current} ->
        status =
          cond do
            past_current -> "pending"
            name == current_step -> "extracting"
            true -> "completed"
          end

        {acc ++ [%{name: name, label: label, status: status}],
         past_current or name == current_step}
      end)

    %{steps: steps}
  end
end
