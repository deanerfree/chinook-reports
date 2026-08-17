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
end
