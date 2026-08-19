defmodule ChinookReports.Repo.Migrations.AddImportDataToReports do
  use Ecto.Migration

  def change do
    alter table(:reports) do
      add :import_data, :map, default: %{}, null: false
    end
  end
end
