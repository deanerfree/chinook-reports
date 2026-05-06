defmodule ChinookReports.Repo.Migrations.AddMetadataToReports do
  use Ecto.Migration

  def change do
    alter table(:reports) do
      add :metadata, :map
    end
  end
end
