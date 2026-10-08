defmodule ChinookReports.Reports.Report do
  use Ecto.Schema
  import Ecto.Changeset

  alias ChinookReports.Countries
  alias ChinookReports.Reports.UWI

  # "Deviated" is a vertical well drilled to a directional plan: it keeps the
  # vertical summary layout but adds the actual-vs-plan comparison.
  @geometries ["Vertical", "Deviated", "Directional", "Horizontal"]
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
    # Wellsite local wall-clock time, stored as entered -- no timezone
    # conversion. See the ConvertDatesToDatetimes migration for why these
    # were widened from :date to :naive_datetime.
    field :spud_date, :naive_datetime
    field :final_td_date, :naive_datetime
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

    # --- Raw imported JSON (Excel extraction / seeded test data) ---
    # welldata / tops / reservoir_data / synopsis / daily / mud_log / bits,
    # as extracted — distinct from the wizard's typed `report_data` below.
    field :import_data, :map, default: %{}

    # --- Everything else: structured JSONB ---
    embeds_one :report_data, ReportData, on_replace: :update do
      field :surface_location, :string
      field :bottom_location, :string
      field :field_region, :string

      field :gl_elevation, :decimal
      field :kb_elevation, :decimal
      field :kb_to_ground, :decimal
      field :datum, :string, default: "UTM"
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
        field :start_date, :naive_datetime
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
  - country must be one of `ChinookReports.Countries.all/0`
  - unique_well_id must match the country's UWI format, where one is defined
    (`ChinookReports.Reports.UWI`)
  - geometry must be one of the predefined geometries
  - status must be one of the predefined statuses
  - report_data.units must be "metric" or "imperial"
  """
  def changeset(report, attrs) do
    attrs = merge_split_datetime_fields(attrs)

    report
    |> reset_errors()
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
      :updated_by,
      :import_data
    ])
    |> cast_report_data(attrs)
    |> validate_required(@required_fields)
    |> validate_inclusion(:country, Countries.all())
    |> validate_uwi()
    |> validate_inclusion(:geometry, @geometries)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:units, ~w(metric imperial))
    |> unique_constraint(:unique_well_id)
  end

  # The UWI format depends on the country, so re-check it when either one
  # changes (switching an existing report to Canada must flag a non-Canadian
  # UWI). Untouched records with a legacy UWI aren't blocked from other edits.
  defp validate_uwi(changeset) do
    uwi = get_field(changeset, :unique_well_id)
    country = get_field(changeset, :country)

    cond do
      not (changed?(changeset, :unique_well_id) or changed?(changeset, :country)) ->
        changeset

      is_nil(uwi) ->
        changeset

      UWI.valid?(uwi, country) ->
        changeset

      true ->
        add_error(
          changeset,
          :unique_well_id,
          "must be a #{country} UWI, e.g. #{UWI.example(country)}"
        )
    end
  end

  # spud_date, final_td_date, and profile_sections[].start_date are entered
  # as a separate date input and time input (see
  # ChinookReportsWeb.ReportFormComponents.datetime_field/1) rather than one
  # combined `datetime-local` control, so the raw web params carry them as
  # "<field>_date"/"<field>_time" pairs instead of the real field name.
  # Recombine each pair into one ISO datetime string before casting, walking
  # the whole (possibly nested, e.g. report_data.profile_sections) attrs tree
  # so every occurrence is covered in one pass.
  #
  # A blank time defaults to midnight, matching the pre-existing date-only
  # behaviour; a blank date with a time is dropped (there's no date to hang
  # it on). Attrs coming from internal callers (e.g. HandleData, already
  # atom-keyed with real NaiveDateTime values) never match these string keys,
  # so this is a no-op for them.
  @split_datetime_fields ~w(spud_date final_td_date start_date)

  defp merge_split_datetime_fields(map) when is_map(map) and not is_struct(map) do
    map
    |> Map.new(fn {k, v} -> {k, merge_split_datetime_fields(v)} end)
    |> combine_datetime_parts()
  end

  defp merge_split_datetime_fields(list) when is_list(list) do
    Enum.map(list, &merge_split_datetime_fields/1)
  end

  defp merge_split_datetime_fields(value), do: value

  defp combine_datetime_parts(map) do
    Enum.reduce(@split_datetime_fields, map, fn field, acc ->
      date_key = field <> "_date"
      time_key = field <> "_time"

      if Map.has_key?(acc, date_key) or Map.has_key?(acc, time_key) do
        date = Map.get(acc, date_key, "")
        time = Map.get(acc, time_key, "")

        acc
        |> Map.delete(date_key)
        |> Map.delete(time_key)
        |> Map.put(field, combine_datetime(date, time))
      else
        acc
      end
    end)
  end

  defp combine_datetime("", _time), do: ""
  defp combine_datetime(date, ""), do: date <> "T00:00"
  defp combine_datetime(date, time), do: date <> "T" <> time

  defp profile_section_changeset(section, attrs) do
    section
    |> reset_errors()
    |> cast(attrs, [:section, :start_depth, :end_depth, :start_date])
  end

  defp formation_top_changeset(top, attrs) do
    top
    |> reset_errors()
    |> cast(attrs, [:formation, :md, :tvd, :isopach, :subsea])
  end

  defp survey_point_changeset(survey_point, attrs) do
    survey_point
    |> reset_errors()
    |> cast(attrs, [:md, :inclination, :azimuth])
    |> validate_number(:md, greater_than_or_equal_to: 0)
    |> validate_number(:inclination, greater_than_or_equal_to: 0, less_than_or_equal_to: 180)
    |> validate_number(:azimuth, greater_than_or_equal_to: 0, less_than_or_equal_to: 360)
  end

  defp report_data_changeset(data, attrs) do
    data
    |> reset_errors()
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

  # `cast/3` accepts an existing changeset (e.g. a multi-step form re-casting
  # itself), but it carries that changeset's `errors` forward as-is — a stale
  # error from an earlier, blank step would otherwise persist forever even
  # after the field becomes valid, since these functions always recompute
  # every validation from scratch on each call anyway.
  defp reset_errors(%Ecto.Changeset{} = changeset), do: %{changeset | errors: [], valid?: true}
  defp reset_errors(data), do: data

  # `cast_embed/3` always diffs the embed against `changeset.data.report_data`
  # (the true persisted value) — never against an already-accumulated
  # `changes[:report_data]` from an earlier step, unlike plain `cast/3`, which
  # correctly merges onto an existing changeset. Since report_data is touched
  # by several separate wizard steps (Elevations, Configuration, Well Profile,
  # ...), relying on cast_embed's default would silently wipe out an earlier
  # step's changes the moment a later step touches report_data again. So we
  # manage the accumulation ourselves: reuse the existing nested changeset (if
  # any) as the base passed to report_data_changeset/2.
  defp cast_report_data(changeset, attrs) do
    case fetch_report_data_params(attrs) do
      :error ->
        changeset

      {:ok, report_data_attrs} ->
        base =
          case fetch_change(changeset, :report_data) do
            {:ok, existing} -> existing
            :error -> changeset.data.report_data
          end

        put_embed(changeset, :report_data, report_data_changeset(base, report_data_attrs))
    end
  end

  defp fetch_report_data_params(%{"report_data" => report_data}), do: {:ok, report_data}
  defp fetch_report_data_params(%{report_data: report_data}), do: {:ok, report_data}
  defp fetch_report_data_params(_attrs), do: :error
end
