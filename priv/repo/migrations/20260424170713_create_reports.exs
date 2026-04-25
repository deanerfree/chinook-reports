defmodule ChinookReports.Repo.Migrations.CreateReports do
  use Ecto.Migration

  def change do
    create table(:reports) do
      add :well_name, :string, null: false
      add :unique_well_id, :string, null: false
      add :operator, :string
      add :spud_date, :date
      add :final_td_date, :date
      add :target_formation, :string
      add :country, :string
      add :latitude, :float
      add :longitude, :float

      timestamps()
    end

    create unique_index(:reports, [:unique_well_id])
  end
end
