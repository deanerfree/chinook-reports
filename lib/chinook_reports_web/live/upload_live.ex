defmodule ChinookReportsWeb.UploadLive do
  use ChinookReportsWeb, :live_view

  alias ChinookReports.GenServer

  @extraction_steps [
    {"loading", "Loading workbook"},
    {"welldata", "Well Data"},
    {"tops", "Formation Tops"},
    {"reservoirs", "Reservoirs"},
    {"surveys", "Surveys"},
    {"synopsis", "Synopsis"}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full">
      <.heading>
        <:title>Upload Report</:title>
        <:subtitle>Upload your Chinook Report Excel file to get started.</:subtitle>
      </.heading>

      <form class="flex w-full justify-center items-center mt-8" phx-submit="upload_excel" phx-change="validate">
        <%= if @extraction_status do %>
          <div class="w-full max-w-md mx-auto">
            <p class="text-sm font-semibold text-copy mb-4">Extracting data…</p>
            <div class="space-y-2">
              <%= for step <- @extraction_status.steps do %>
                <div class={[
                  "flex items-center gap-3 rounded-md border px-4 py-2 text-sm transition-all",
                  step.status == "extracting" && "border-primary bg-primary/10",
                  step.status == "completed" && "border-success bg-success/10",
                  step.status == "pending" && "border-border bg-surface-card"
                ]}>
                  <%= cond do %>
                    <% step.status == "completed" -> %>
                      <svg
                        class="h-4 w-4 shrink-0 text-success"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke-width="2.5"
                        stroke="currentColor"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M4.5 12.75l6 6 9-13.5"
                        />
                      </svg>
                    <% step.status == "extracting" -> %>
                      <div class="h-4 w-4 shrink-0 rounded-full border-2 border-primary border-t-transparent animate-spin"></div>
                    <% true -> %>
                      <div class="h-4 w-4 shrink-0 rounded-full border-2 border-border"></div>
                  <% end %>
                  <span class={[
                    "font-medium",
                    step.status == "extracting" && "text-primary",
                    step.status == "completed" && "text-success",
                    step.status == "pending" && "text-copy-secondary"
                  ]}>
                    {step.label}
                  </span>
                </div>
              <% end %>
            </div>
          </div>
        <% else %>
          <div class="w-full">
            <div
              class="rounded-lg border-2 border-dashed p-10 text-center transition-colors border-border hover:border-muted"
              phx-drop-target={@uploads.excel.ref}
            >
              <svg
                class="mx-auto h-12 w-12 text-muted"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5m-13.5-9L12 3m0 0 4.5 4.5M12 3v13.5"
                />
              </svg>
              <p class="mt-4 text-lg font-medium text-copy">Drag & drop Excel file here</p>
              <p class="mt-1 text-sm text-copy-secondary">or</p>
              <label class="mt-3 inline-block cursor-pointer rounded-full px-6 py-2 text-sm font-bold btn-primary">
                Browse files
                <.live_file_input upload={@uploads.excel} class="hidden" />
              </label>
              <p class="mt-3 text-xs text-copy-secondary">Accepted formats: .xlsx, .xls, .xlsm</p>
            </div>

            <%= if @error do %>
              <div class="mt-4 rounded-md border border-danger/30 bg-danger/10 px-4 py-3 text-sm text-danger">
                {@error}
              </div>
            <% end %>

            <%= for {_ref, msg} <- upload_errors(@uploads.excel) do %>
              <div class="mt-4 rounded-md border border-danger/30 bg-danger/10 px-4 py-3 text-sm text-danger">
                {upload_error_to_string(msg)}
              </div>
            <% end %>

            <%= if @uploads.excel.entries != [] do %>
              <% uploading? = Enum.any?(@uploads.excel.entries, & &1.progress < 100) %>
              <div class="flex flex-col items-center gap-8">
                <ul class="mt-6 w-full space-y-2">
                  <%= for entry <- @uploads.excel.entries do %>
                    <li class="flex items-center justify-between rounded-md border border-border-light bg-surface-card px-4 py-3">
                      <div class="flex items-center gap-3">
                        <svg
                          class="h-5 w-5 text-primary"
                          fill="none"
                          viewBox="0 0 24 24"
                          stroke-width="1.5"
                          stroke="currentColor"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z"
                          />
                        </svg>
                        <span class="text-sm font-medium text-copy">{entry.client_name}</span>
                        <span class="text-xs text-copy-secondary">({Float.round(entry.client_size / 1024, 1)} KB)</span>
                        <span class="text-xs text-copy-secondary">{entry.progress}%</span>
                      </div>
                      <button
                        type="button"
                        phx-click="cancel_upload"
                        phx-value-ref={entry.ref}
                        class="text-copy-secondary transition-colors hover:text-danger"
                        aria-label={"Remove #{entry.client_name}"}
                      >
                        <svg
                          class="h-5 w-5"
                          fill="none"
                          viewBox="0 0 24 24"
                          stroke-width="1.5"
                          stroke="currentColor"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            d="M6 18 18 6M6 6l12 12"
                          />
                        </svg>
                      </button>
                    </li>
                  <% end %>
                </ul>
                <button type="submit" class="btn-primary" disabled={uploading?}>
                  {if uploading?, do: "Uploading…", else: "Process File"}
                </button>
              </div>
            <% end %>
          </div>
        <% end %>
      </form>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(results: [], error: nil, extraction_status: nil)
     |> allow_upload(:excel,
       accept: ~w(.xlsx .xls .xlsm),
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

  defp upload_error_to_string(:too_large), do: "File too large (max 50 MB)"
  defp upload_error_to_string(:not_accepted), do: "File type not accepted"
  defp upload_error_to_string(:too_many_files), do: "Too many files selected"
  defp upload_error_to_string(_), do: "Upload error"
end
