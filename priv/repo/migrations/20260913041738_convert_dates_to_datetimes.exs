defmodule ChinookReports.Repo.Migrations.ConvertDatesToDatetimes do
  @moduledoc """
  Widens spud_date/final_td_date/profile_sections.start_date from :date to
  :naive_datetime so a time can be captured alongside the date (wellsite
  local wall-clock time -- no timezone conversion).

  spud_date/final_td_date are real columns: Postgres casts date -> timestamp
  implicitly (filling 00:00:00), so `modify` alone is safe for them.

  profile_sections.start_date lives inside the report_data jsonb blob, so the
  schema's field-type change doesn't touch stored bytes on its own -- a row
  saved before this migration with a bare "YYYY-MM-DD" string would fail to
  load once NaiveDateTime.from_iso8601/1 is what's parsing it. Pad those out
  to midnight first.
  """

  use Ecto.Migration
  import Ecto.Query

  @bare_date ~r/^\d{4}-\d{2}-\d{2}$/

  def up do
    backfill_profile_section_start_dates()

    alter table(:reports) do
      modify :spud_date, :naive_datetime
      modify :final_td_date, :naive_datetime
    end
  end

  def down do
    alter table(:reports) do
      modify :spud_date, :date
      modify :final_td_date, :date
    end
  end

  defp backfill_profile_section_start_dates do
    from(r in "reports", select: %{id: r.id, report_data: r.report_data})
    |> repo().all()
    |> Enum.each(&pad_row/1)
  end

  defp pad_row(%{id: id, report_data: %{"profile_sections" => sections} = data})
       when is_list(sections) do
    padded = Enum.map(sections, &pad_start_date/1)

    if padded != sections do
      repo().update_all(from(r in "reports", where: r.id == ^id),
        set: [report_data: %{data | "profile_sections" => padded}]
      )
    end
  end

  defp pad_row(_row), do: :ok

  defp pad_start_date(%{"start_date" => date} = section) when is_binary(date) do
    if Regex.match?(@bare_date, date) do
      %{section | "start_date" => date <> "T00:00:00"}
    else
      section
    end
  end

  defp pad_start_date(section), do: section
end
