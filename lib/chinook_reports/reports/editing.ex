defmodule ChinookReports.Reports.Editing do
  @moduledoc """
  Shared helpers for mutating a report changeset's typed `report_data` embeds.

  Used by both the create/edit wizard (`CreateReportLive`) and the per-section
  editors on the report page (`ReportPageLive`) so the add-row / remove-row
  logic — which has some Ecto sharp edges (see `put_in_report_data/3`) — lives
  in exactly one place.
  """

  alias Ecto.Changeset
  alias ChinookReports.Reports.Report.ReportData.{ProfileSection, FormationTop, SurveyPoint}

  @lists ~w(profile_sections formation_tops surveys)a

  @doc "The `embeds_many` list names inside `report_data` that support row editing."
  def lists, do: @lists

  @doc "Append a blank row to one `report_data` embeds_many list."
  def add_row(%Changeset{} = changeset, list) when list in @lists do
    put_in_report_data(changeset, list, current_list(changeset, list) ++ [blank_row(list)])
  end

  @doc "Drop the row at `index` from one `report_data` embeds_many list."
  def remove_row(%Changeset{} = changeset, list, index)
      when list in @lists and is_integer(index) do
    put_in_report_data(changeset, list, List.delete_at(current_list(changeset, list), index))
  end

  defp current_list(changeset, list) do
    changeset
    |> Changeset.get_field(:report_data)
    |> Map.get(list, [])
  end

  # `Ecto.Changeset.put_embed/3` on report_data with a plain, already-modified
  # struct doesn't reliably register nested embeds_many changes (it diffs the
  # embeds_one as a whole against the original, and that diff can come back
  # empty even though a nested list clearly differs). Putting the list at its
  # own nesting level, via a proper changeset for report_data, is what actually
  # gets tracked.
  defp put_in_report_data(changeset, list, new_list) do
    report_data_changeset =
      changeset
      |> Changeset.get_field(:report_data)
      |> Changeset.change()
      |> Changeset.put_embed(list, new_list)

    Changeset.put_embed(changeset, :report_data, report_data_changeset)
  end

  defp blank_row(:profile_sections), do: %ProfileSection{}
  defp blank_row(:formation_tops), do: %FormationTop{}
  defp blank_row(:surveys), do: %SurveyPoint{}
end
