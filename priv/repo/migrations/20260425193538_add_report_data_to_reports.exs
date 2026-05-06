defmodule ChinookReports.Repo.Migrations.AddReportDataToReports do
  use Ecto.Migration

  def change do
    alter table(:reports) do
      add :metadata, :map
    end
  end
end
