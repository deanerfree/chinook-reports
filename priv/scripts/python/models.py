"""
Pydantic models for worksheet data extraction.
All extractor modules return model instances.
extract_all calls .model_dump() for final JSON output.
"""

from pydantic import BaseModel


# ── WellData models ──────────────────────────────────────────────────────────

class Units(BaseModel):
    depth: str | None = None
    diameter: str | None = None
    rop: str | None = None
    weight: str | None = None
    gas: str | None = None


class TotalDepth(BaseModel):
    md: float | None = None
    tvd: float | None = None
    subsea: float | None = None
    unit: str | None = None


# ── Metadata model ───────────────────────────────────────────────────────────

class WellMetadata(BaseModel):
    units: Units = Units()
    well_name: str | None = None
    unique_well_id: str | None = None
    operator: str | None = None
    spud_date: str | None = None
    final_td_date: str | None = None
    target_formation: str | None = None
    country: str | None = None
    latitude: float | None = None
    longitude: float | None = None


class Elevation(BaseModel):
    reference: str | None = None
    ground_level: float | None = None
    kelly_bushing: float | None = None
    kb_to_ground: float | None = None


class GeographicCoordinates(BaseModel):
    latitude: float | None = None
    latitude_dir: str | None = None
    longitude: float | None = None
    longitude_dir: str | None = None
    datum: str | None = None


class SurfaceLocationGrid(BaseModel):
    format: str | None = None
    northing: float | None = None
    northing_dir: str | None = None
    easting: float | None = None
    easting_dir: str | None = None
    section: int | None = None
    township: int | None = None
    range: int | None = None
    meridian: int | None = None


class LocationData(BaseModel):
    coordinate_system: str | None = None
    geographic_coordinates: GeographicCoordinates = GeographicCoordinates()
    surface_coordinates: str | None = None
    surface_location_grid: SurfaceLocationGrid = SurfaceLocationGrid()
    bottom_coordinates: str | None = None


class TimingEvent(BaseModel):
    date: str | None = None
    time: str | None = None
    depth: float | None = None


class WellTiming(BaseModel):
    spud_date: TimingEvent = TimingEvent()
    surface_casing: TimingEvent = TimingEvent()
    sample_point: TimingEvent = TimingEvent()
    kick_off_point: TimingEvent = TimingEvent()
    intermediate_casing_point: TimingEvent = TimingEvent()
    heel: TimingEvent = TimingEvent()
    final_td: TimingEvent = TimingEvent()
    rig_release_date: str | None = None


class HoleSize(BaseModel):
    section: str
    bit_diameter: float | None = None
    from_depth: float | None = None
    to_depth: float | None = None
    interval: float | None = None


class Mud(BaseModel):
    section: str
    type: str | None = None
    from_depth: float | None = None
    to_depth: float | None = None


class CasingData(BaseModel):
    section: str
    size: float | None = None
    set_at: float | None = None
    weight: float | None = None
    type: str | None = None


class WellsiteGeology(BaseModel):
    company: str | None = None
    geologists: list[str | None] = []


class DrillingContractor(BaseModel):
    company: str | None = None
    rig: int | str | None = None


class Services(BaseModel):
    wellsite_geology: WellsiteGeology = WellsiteGeology()
    drilling_contractor: DrillingContractor = DrillingContractor()
    drilling_supervision: str | None = None
    gas_detection: str | None = None
    directional_drilling: str | None = None
    mwd_lwd_services: str | None = None
    mud: str | None = None
    coring: str | None = None
    wireline_logging: str | None = None
    testing: str | None = None


class GeologicalServices(BaseModel):
    samples_operator: str | None = None
    samples_government: str | None = None
    cores: str | None = None
    dst: str | None = None
    logging_suite: str | None = None


class ProfilePoint(BaseModel):
    date: str | None = None
    time: str | None = None
    depth: float | None = None


class WellProfileSection(BaseModel):
    section: str
    uwid: str | None = None
    start: ProfilePoint = ProfilePoint()
    end: ProfilePoint = ProfilePoint()
    duration_days: float | str | None = None
    length: float | None = None


class BACode(BaseModel):
    ba_code: str
    licensee: str


class WellData(BaseModel):
    units: Units = Units()
    well_name: str | None = None
    unique_well_id: str | None = None
    surface_location: str | None = None
    bottom_location: str | None = None
    field_region: str | None = None
    province: str | None = None
    country: str | None = None
    operator: str | None = None
    op_geo: str | None = None
    primary_target: str | None = None
    secondary_target: str | None = None
    terminating_zone: str | None = None
    total_depth_actual: TotalDepth = TotalDepth()
    final_well_status: str | None = None
    well_geometry: str | None = None
    afe_number: str | None = None
    well_license: str | int | None = None
    well_purpose: str | None = None
    substance: str | None = None
    well_classification: str | None = None
    security: str | None = None
    elevations: Elevation = Elevation()
    location_data: LocationData = LocationData()
    well_timing: WellTiming = WellTiming()
    hole_sizes: list[HoleSize] = []
    mud: list[Mud] = []
    casing_data: list[CasingData] = []
    services: Services = Services()
    geological_services: GeologicalServices = GeologicalServices()
    well_profile: list[WellProfileSection] = []
    ba_codes: list[BACode] = []


# ── Tops models ──────────────────────────────────────────────────────────────

class FormationPick(BaseModel):
    md: float | None = None
    tvd: float | None = None
    isopach: float | None = None
    subsea: float | None = None


class FormationTop(BaseModel):
    formation: str
    prognosis: FormationPick = FormationPick()
    samples: FormationPick = FormationPick()
    gamma: FormationPick = FormationPick()


class Tops(BaseModel):
    formations: list[FormationTop] = []


# ── Surveys models ───────────────────────────────────────────────────────────

class SurveyMarker(BaseModel):
    md: float | None = None
    inclination_deg: float | None = None
    azimuth_deg: float | None = None
    tvd: float | None = None
    north_south: float | None = None
    east_west: float | None = None
    vertical_section: float | None = None
    subsea: float | None = None
    event: str | None = None


class SurveyPoint(BaseModel):
    md: float | None = None
    inclination_deg: float | None = None
    azimuth_deg: float | None = None
    tvd: float | None = None
    north_south: float | None = None
    east_west: float | None = None
    vertical_section: float | None = None
    dogleg_severity: float | None = None
    subsea: float | None = None
    remarks: str | None = None


class PrognosedSurveyPoint(BaseModel):
    md: float | None = None
    inclination_deg: float | None = None
    azimuth_deg: float | None = None


class SlideRecord(BaseModel):
    from_depth: float | None = None
    to_depth: float | None = None
    slide: float | None = None
    toolface: str | None = None


class SurveySheet(BaseModel):
    sheet_name: str
    section_name: str | None = None
    markers: list[SurveyMarker] = []
    survey_points: list[SurveyPoint] = []
    prognosed_survey: list[PrognosedSurveyPoint] = []
    slides: list[SlideRecord] = []




# ── Reservoir models ─────────────────────────────────────────────────────────

class QualitySummary(BaseModel):
    quality: str
    metres: float | None = None
    percent: float | None = None


class LithologySummary(BaseModel):
    lithology: str
    metres: float | None = None
    percent: float | None = None


class Threshold(BaseModel):
    label: str | None = None
    value: float | str | None = None


class CurveAnalysisRow(BaseModel):
    gamma_threshold: float | None = None
    gamma_cumulative: float | None = None
    gamma_length: float | None = None
    gas_threshold: float | None = None
    gas_cumulative: float | None = None
    gas_length: float | None = None


class CurveRange(BaseModel):
    max: float | None = None
    min: float | None = None


class CurveCutoffs(BaseModel):
    gas: float | None = None
    gamma: float | None = None


class CurveMetadata(BaseModel):
    null_value: float | None = None
    rop: CurveRange = CurveRange()
    gas: CurveRange = CurveRange()
    gamma: CurveRange = CurveRange()
    curve_4: CurveRange = CurveRange()
    curve_5: CurveRange = CurveRange()
    curve_6: CurveRange = CurveRange()
    cutoffs: CurveCutoffs = CurveCutoffs()


class ReservoirInterval(BaseModel):
    from_depth: float | None = None
    to_depth: float | None = None
    interval: float | None = None
    gas: float | None = None
    porosity: str | None = None
    lithology: str | None = None
    quality: str | None = None
    remarks: str | None = None
    tag: str | None = None


class CurvePointActual(BaseModel):
    md: float | None = None
    rop: float | None = None
    gas: float | None = None
    gamma: float | None = None
    curve_4: float | None = None
    curve_5: float | None = None
    curve_6: float | None = None


class CurvePointCleaned(BaseModel):
    md: float | None = None
    interval_flag: float | str | None = None
    rop: float | None = None
    gas: float | None = None
    gamma: float | None = None


class QualityTotal(BaseModel):
    quality: str
    metres: float | None = None
    percent: float | None = None


class ReservoirMetadata(BaseModel):
    sheet_number: int | str | None = None
    leg_name: str | None = None
    last_row: int | float | None = None
    pages: int | float | None = None
    max_depth: float | None = None


class ReservoirSheet(BaseModel):
    sheet_name: str
    metadata: ReservoirMetadata = ReservoirMetadata()
    quality_summary: list[QualitySummary] = []
    lithology_summary: list[LithologySummary] = []
    thresholds: list[Threshold] = []
    curve_analysis: list[CurveAnalysisRow] = []
    curve_metadata: CurveMetadata = CurveMetadata()
    intervals: list[ReservoirInterval] = []
    curve_data_actual: list[CurvePointActual] = []
    curve_data_cleaned: list[CurvePointCleaned] = []
    totals: list[QualityTotal] = []




# ── Bit models ───────────────────────────────────────────────────────────────

class BitRecord(BaseModel):
    bit_number: int | str | None = None
    size: float | str | None = None
    make: str | None = None
    type: str | None = None
    depth_in: float | None = None
    depth_out: float | None = None
    progress: float | None = None
    hours: float | None = None
    wob: float | None = None
    rpm: float | None = None
    rop: float | None = None
    remarks: str | int | float | None = None


# ── Daily models ─────────────────────────────────────────────────────────────

class DailyEntry(BaseModel):
    date: str | None = None
    depth: float | int | None = None
    progress: float | int | None = None
    drilling_hours: float | None = None
    rop: float | None = None
    operations_summary: str | None = None
    tag: str | None = None


# ── Mud log models ───────────────────────────────────────────────────────────

class MudEntry(BaseModel):
    date: str | None = None
    depth: float | int | None = None
    mud_type: str | None = None
    density: float | None = None
    viscosity: float | None = None
    wl: float | None = None
    ph: float | None = None
    remarks: str | None = None


# ── Synopsis models ──────────────────────────────────────────────────────────

class Synopsis(BaseModel):
    well_summary: list[str] = []
    well_profile: list[str] = []
    formation_evaluation: list[str] = []


# ── Leg data model ───────────────────────────────────────────────────────────

class LegData(BaseModel):
    leg_name: str | None = None
    survey: SurveySheet | None = None
    log_data: ReservoirSheet | None = None


# ── Top-level result ─────────────────────────────────────────────────────────

class ExtractionResult(BaseModel):
    metadata: WellMetadata = WellMetadata()
    welldata: WellData = WellData()
    tops: Tops = Tops()
    reservoir_data: list[LegData] = []
    synopsis: Synopsis = Synopsis()
    daily: list[DailyEntry] = []
    mud_log: list[MudEntry] = []
    bits: list[BitRecord] = []