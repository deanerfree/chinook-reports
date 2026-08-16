defmodule ChinookReports.Reports.Report do
  use Ecto.Schema
  import Ecto.Changeset

  @geometries ["Vertical", "Directional", "Horizontal"]
  @statuses ~w(draft active complete)

  @derive {
    Flop.Schema,
    filterable: [
      :well_name,
      :unique_well_id,
      :operator,
      :spud_date,
      :final_td_date,
      :target_formation,
      :secondary_target,
      :country,
      :province,
      :geometry,
      :status
    ],
    sortable: [
      :well_name,
      :operator,
      :spud_date,
      :final_td_date,
      :target_formation
    ],
    default_limit: 25
  }

  schema "reports" do
    # --- Real columns: queryable / indexable ---
    field :well_name, :string
    field :unique_well_id, :string
    field :operator, :string
    field :spud_date, :date
    field :final_td_date, :date
    field :target_formation, :string
    field :secondary_target, :string
    field :country, :string
    field :province, :string
    field :latitude, :float
    field :longitude, :float
    field :geometry, :string
    field :units, :string, default: "metric"

    field :status, :string, default: "draft"
    field :company_id, :binary_id

    field :created_by, :string
    field :updated_by, :string

    # --- Everything else: structured JSONB ---
    embeds_one :report_data, ReportData, on_replace: :update do
      field :surface_location, :string
      field :bottom_location, :string
      field :field_region, :string

      field :gl_elevation, :decimal
      field :kb_elevation, :decimal
      field :kb_to_ground, :decimal
      field :datum, :string
      field :surface_coordinates, :string

      field :classification, :string
      field :license, :string
      field :purpose, :string
      field :substance, :string
      field :terminating_zone, :string

      embeds_many :profile_sections, ProfileSection, on_replace: :delete do
        field :section, :string
        field :start_depth, :decimal
        field :end_depth, :decimal
        field :start_date, :date
      end

      embeds_many :formation_tops, FormationTop, on_replace: :delete do
        field :formation, :string
        field :md, :decimal
        field :tvd, :decimal
        field :isopach, :decimal
        field :subsea, :decimal
      end

      embeds_many :surveys, SurveyPoint, on_replace: :delete do
        field :md, :decimal
        field :inclination, :decimal
        field :azimuth, :decimal
      end
    end

    timestamps()
  end

  @required_fields [:well_name, :unique_well_id]

  def required?(field), do: field in @required_fields
  # Expose option lists for the form dropdowns.
  def geometries, do: @geometries
  def statuses, do: @statuses
  def datums, do: ~w(ATS NTS DLS UTM Other)
  def units, do: ~w(metric imperial)
  def classifications, do: ["DEV", "EXP", "Other"]

  @doc """
  Returns a changeset for a report.
  Validations:
  - Required: well_name, unique_well_id
  - unique_well_id must be unique in the database
  - geometry must be one of the predefined geometries
  - status must be one of the predefined statuses
  - report_data.units must be "metric" or "imperial"
  """
  def changeset(report, attrs) do
    report
    |> cast(attrs, [
      :well_name,
      :unique_well_id,
      :operator,
      :spud_date,
      :final_td_date,
      :target_formation,
      :secondary_target,
      :country,
      :province,
      :latitude,
      :longitude,
      :geometry,
      :status,
      :company_id,
      :units,
      :created_by,
      :updated_by
    ])
    |> cast_embed(:report_data, with: &report_data_changeset/2)
    |> validate_required(@required_fields)
    |> validate_inclusion(:geometry, @geometries)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:units, ~w(metric imperial))
    |> unique_constraint(:unique_well_id)
  end

  defp profile_section_changeset(section, attrs) do
    cast(section, attrs, [:section, :start_depth, :end_depth, :start_date])
  end

  defp formation_top_changeset(top, attrs) do
    cast(top, attrs, [:formation, :md, :tvd, :isopach, :subsea])
  end

  defp survey_point_changeset(survey_point, attrs) do
    survey_point
    |> cast(attrs, [:md, :inclination, :azimuth])
    |> validate_number(:md, greater_than_or_equal_to: 0)
    |> validate_number(:inclination, greater_than_or_equal_to: 0, less_than_or_equal_to: 180)
    |> validate_number(:azimuth, greater_than_or_equal_to: 0, less_than_or_equal_to: 360)
  end

  defp report_data_changeset(data, attrs) do
    data
    |> cast(attrs, [
      :surface_location,
      :bottom_location,
      :field_region,
      :gl_elevation,
      :kb_elevation,
      :kb_to_ground,
      :datum,
      :surface_coordinates,
      :classification,
      :license,
      :purpose,
      :substance,
      :terminating_zone
    ])
    |> cast_embed(:profile_sections, with: &profile_section_changeset/2)
    |> cast_embed(:formation_tops, with: &formation_top_changeset/2)
    |> cast_embed(:surveys, with: &survey_point_changeset/2)
    |> validate_inclusion(:datum, ~w(ATS NTS DLS UTM Other))
    |> validate_inclusion(:classification, ["DEV", "EXP", "Other"])
  end
end
