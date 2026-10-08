defmodule ChinookReports.Reports do
  @moduledoc """
  The Reports context — the boundary between the web layer and persistence.
  All report operations go through here. The LiveView never touches `Repo`
  or the `Report` schema directly.
  """

  import Ecto.Query, warn: false
  alias ChinookReports.Repo
  alias ChinookReports.Reports.Report

  @doc "List all reports, newest first."
  def list_reports do
    Report
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  What the Home dashboard needs in one call: report counts per status, every
  active (drilling) report, and the most recently touched drafts and completed
  reports — each list newest-activity first.
  """
  def dashboard(opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)

    counts =
      Report
      |> group_by([r], r.status)
      |> select([r], {r.status, count(r.id)})
      |> Repo.all()
      |> Map.new()

    %{
      counts: Map.new(Report.statuses(), &{&1, Map.get(counts, &1, 0)}),
      active: recent_by_status("active", nil),
      drafts: recent_by_status("draft", limit),
      complete: recent_by_status("complete", limit)
    }
  end

  defp recent_by_status(status, limit) do
    Report
    |> where([r], r.status == ^status)
    |> order_by(desc: :updated_at)
    |> then(&if(limit, do: limit(&1, ^limit), else: &1))
    |> Repo.all()
  end

  @doc "Fetch one report by id; raises if not found."
  def get_report!(id), do: Repo.get!(Report, id)

  @doc """
  Guarantee `report.report_data` is a struct with a persisted primary key.

  Reports created via Excel import/seeding (`HandleData.store_report_data/1`)
  never touch `report_data` on insert, so it's persisted as a struct with
  `id: nil`. Editing one of those reports later then crashes Ecto's embed
  diffing on update (`Ecto.NoPrimaryKeyValueError`), since it can't tell
  whether a nil-id embed is being inserted or updated. Call this on any
  report before building an edit changeset for it; the generated id is
  persisted the next time `report_data` is actually changed and saved.
  """
  def ensure_report_data(%Report{report_data: nil} = report) do
    %{report | report_data: %Report.ReportData{id: Ecto.UUID.generate()}}
  end

  def ensure_report_data(%Report{report_data: %{id: nil} = report_data} = report) do
    %{report | report_data: %{report_data | id: Ecto.UUID.generate()}}
  end

  def ensure_report_data(%Report{} = report), do: report

  @doc "Build a blank changeset for a new report form."
  def new_report_changeset(attrs \\ %{}) do
    %Report{report_data: %Report.ReportData{}}
    |> Report.changeset(attrs)
  end

  @doc """
  Build a changeset for `phx-change` validation — does not persist.

  Accepts either a `%Report{}` or an existing changeset. Passing a changeset
  (e.g. across the steps of a multi-step form) merges the new params on top
  of it, preserving changes from earlier steps that aren't present in `attrs`
  while keeping the original persisted struct as `changeset.data`.
  """
  def change_report(report_or_changeset, attrs \\ %{}) do
    Report.changeset(report_or_changeset, attrs)
  end

  @doc "Insert a new report."
  def create_report(attrs), do: create_report(%Report{report_data: %Report.ReportData{}}, attrs)

  @doc "Insert a new report, from a `%Report{}` or an accumulated multi-step changeset."
  def create_report(report_or_changeset, attrs) do
    IO.inspect(report_or_changeset, label: "Creating report with initial changeset")
    IO.inspect(attrs, label: "Attributes for new report")

    report_or_changeset
    |> Report.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Update an existing report, from a `%Report{}` or an accumulated multi-step changeset."
  def update_report(report_or_changeset, attrs) do
    report_or_changeset
    |> Report.changeset(attrs)
    |> Repo.update()
  end

  @doc "Delete a report."
  def delete_draft(%Report{} = report), do: Repo.delete(report)

  @doc """
  Merge `data` into `report.import_data` under the top-level key `section` and
  persist. The other import sections (welldata, synopsis, …) are left untouched.

  Used by the on-page editors for the still-untyped `import_data` sections; the
  caller is responsible for having recomputed any derived values first (see
  `ChinookReports.FormationTops`).

  `attrs` are typed-column changes saved in the same update, for editors whose
  section mirrors a column (e.g. welldata `well_name` → `well_name`).
  """
  def update_import_section(%Report{} = report, section, data, attrs \\ %{})
      when is_binary(section),
      do: update_import_sections(report, %{section => data}, attrs)

  @doc """
  Like `update_import_section/4`, for several top-level `import_data` keys
  saved together in one update — e.g. an edit plus the derived section it
  invalidates (see `ChinookReports.FormationTops.with_tops/2`).
  """
  def update_import_sections(%Report{} = report, sections, attrs \\ %{}) when is_map(sections) do
    merged = Map.merge(report.import_data || %{}, sections)

    report
    |> Report.changeset(Map.put(attrs, "import_data", merged))
    |> Repo.update()
  end
end
