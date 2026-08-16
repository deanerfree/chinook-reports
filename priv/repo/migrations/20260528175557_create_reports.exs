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
      add :secondary_target, :string
      add :country, :string
      add :province, :string
      add :latitude, :float
      add :longitude, :float
      add :geometry, :string
      add :units, :string, default: "metric"

      add :status, :string, default: "draft", null: false
      add :company_id, :binary_id

      add :created_by, :string
      add :updated_by, :string

      add :report_data, :map, default: %{}, null: false

      timestamps()
    end

    create unique_index(:reports, [:unique_well_id])
    create index(:reports, [:status])
    create index(:reports, [:company_id])
  end
end
