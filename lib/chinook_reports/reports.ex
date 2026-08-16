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

  @doc "Fetch one report by id; raises if not found."
  def get_report!(id), do: Repo.get!(Report, id)

  @doc "Build a blank changeset for a new report form."
  def new_report_changeset(attrs \\ %{}) do
    %Report{report_data: %Report.ReportData{}}
    |> Report.changeset(attrs)
  end

  @doc "Build a changeset for `phx-change` validation — does not persist."
  def change_report(%Report{} = report, attrs \\ %{}) do
    Report.changeset(report, attrs)
  end

  @doc "Insert a new report."
  def create_report(attrs) do
    %Report{report_data: %Report.ReportData{}}
    |> Report.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Update an existing report."
  def update_report(%Report{} = report, attrs) do
    report
    |> Report.changeset(attrs)
    |> Repo.update()
  end

  @doc "Delete a report."
  def delete_draft(%Report{} = report), do: Repo.delete(report)
end
