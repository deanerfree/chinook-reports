defmodule ChinookReports.Report do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {
    Flop.Schema,
    filterable: [
      :well_name,
      :unique_well_id,
      :operator,
      :spud_date,
      :final_td_date,
      :target_formation,
      :country
    ],
    sortable: [
      :well_name,
      :operator,
      :spud_date,
      :final_td_date
    ],
    default_limit: 25
  }

  schema "reports" do
    field :well_name, :string
    field :unique_well_id, :string
    field :operator, :string
    field :spud_date, :date
    field :final_td_date, :date
    field :target_formation, :string
    field :country, :string
    field :latitude, :float
    field :longitude, :float
    field :report_data, :map
    field :metadata, :map

    timestamps()
  end

  def changeset(report, attrs) do
    report
    |> cast(attrs, [
      :well_name,
      :unique_well_id,
      :operator,
      :spud_date,
      :final_td_date,
      :target_formation,
      :country,
      :latitude,
      :longitude,
      :report_data,
      :metadata
    ])
    |> validate_required([:well_name, :unique_well_id])
    |> unique_constraint(:unique_well_id)
  end
end
