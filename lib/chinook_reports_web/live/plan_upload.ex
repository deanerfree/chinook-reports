defmodule ChinookReportsWeb.PlanUpload do
  @moduledoc """
  Drag-and-drop import of a directional plan file (COMPASS PDF, CSV or TXT)
  into the Directional Program table. Shared by the wizard (`CreateReportLive`,
  step 6) and the report page's Surveys editor (`ReportPageLive`).

  The file uploads as soon as it's dropped, is parsed off the LiveView process
  (`start_async/3`, as `:plan_import`), and its stations *replace* the rows in
  the open form. Nothing is saved until the form is — so Cancel / Back still
  throws the import away.

  A LiveView using this calls `allow/1` in `mount/3`, renders
  `ChinookReportsWeb.ReportFormComponents.plan_drop_zone/1` inside its form,
  and forwards `handle_async(:plan_import, result, socket)` to `apply_result/4`.

  When the plan has a Formations table (a PDF plan), its tops are held in
  `@plan_tops` and the drop zone asks whether to import them as well. The
  LiveView handles `"import_plan_tops"` (merging them in with
  `ChinookReports.DirectionalPlan.merge_tops/3`, then `clear_tops/1`) and
  `"skip_plan_tops"` (`clear_tops/1`).

  An empty Formation Tops editor (`FormationTopsLive`, or the report page's
  typed tops) takes a dropped plan too, for its tops alone — see
  `apply_tops_result/3`.
  """

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias ChinookReports.DirectionalPlan

  @doc "Register the `:plan` upload and the `@plan_importing` / `@plan_tops` assigns."
  def allow(socket) do
    socket
    |> assign(:plan_importing, nil)
    |> assign(:plan_tops, nil)
    |> allow_upload(:plan,
      accept: ~w(.pdf .csv .txt),
      max_entries: 1,
      max_file_size: 25_000_000,
      auto_upload: true,
      progress: &__MODULE__.handle_progress/3
    )
  end

  @doc false
  def handle_progress(:plan, %{done?: true} = entry, socket) do
    # The upload's temp file is deleted once consumed, so parse a copy.
    path =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        dest = Path.join(System.tmp_dir!(), "plan-#{entry.uuid}")
        File.cp!(path, dest)
        {:ok, dest}
      end)

    {:noreply,
     socket
     |> assign(:plan_importing, entry.client_name)
     |> start_async(:plan_import, fn ->
       try do
         DirectionalPlan.extract(path)
       after
         File.rm(path)
       end
     end)}
  end

  def handle_progress(:plan, _entry, socket), do: {:noreply, socket}

  @doc """
  Finish an import: on success hand the rows to `put_rows.(socket, rows)` (which
  puts them in the open form), flash what was loaded and hold any formation
  tops in `@plan_tops` for the import prompt; otherwise flash why not.
  `report_uwi` is the open report's UWI, for the wrong-well check.
  """
  def apply_result(socket, result, report_uwi, put_rows) do
    socket = socket |> assign(:plan_importing, nil) |> clear_tops()

    case result do
      {:ok, {:ok, plan}} ->
        case DirectionalPlan.program_rows(plan) do
          [] ->
            put_flash(socket, :error, "No survey stations found in that file.")

          rows ->
            socket
            |> put_rows.(rows)
            |> assign(:plan_tops, nonempty(DirectionalPlan.tops(plan)))
            |> put_flash(:info, DirectionalPlan.summary(plan, report_uwi))
        end

      {:ok, {:error, reason}} ->
        put_flash(socket, :error, "Couldn't read that plan: #{reason}")

      {:exit, _reason} ->
        put_flash(socket, :error, "Couldn't read that plan.")
    end
  end

  @doc """
  Finish an import dropped on an empty Formation Tops editor: on success hand
  the plan's tops to `put_tops.(socket, tops)` (which puts them in the open
  form) and flash how many were loaded; otherwise flash why not. Only a PDF
  plan has a Formations table, so a CSV / TXT listing loads nothing.

  `flash.(socket, kind, message)` shows the outcome; it defaults to
  `put_flash/3`, but a LiveComponent's own flash only reaches the page on a
  redirect, so `FormationTopsLive` passes one that asks its parent to.
  """
  def apply_tops_result(socket, result, put_tops, flash \\ &put_flash/3) do
    socket = assign(socket, :plan_importing, nil)

    case result do
      {:ok, {:ok, plan}} ->
        case DirectionalPlan.tops(plan) do
          [] ->
            flash.(
              socket,
              :error,
              "No formation tops found in that file — only a PDF plan lists them."
            )

          tops ->
            socket
            |> put_tops.(tops)
            |> flash.(:info, "Loaded #{tops_count(tops)} from the plan. Save to keep them.")
        end

      {:ok, {:error, reason}} ->
        flash.(socket, :error, "Couldn't read that plan: #{reason}")

      {:exit, _reason} ->
        flash.(socket, :error, "Couldn't read that plan.")
    end
  end

  @doc "Drop the plan's pending formation tops (imported, skipped or abandoned)."
  def clear_tops(socket), do: assign(socket, :plan_tops, nil)

  defp tops_count([_]), do: "1 formation top"
  defp tops_count(tops), do: "#{length(tops)} formation tops"

  defp nonempty([]), do: nil
  defp nonempty(list), do: list
end
