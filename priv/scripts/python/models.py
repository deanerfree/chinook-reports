"""
Pydantic models for worksheet data extraction.
All extractor modules return model instances.
extract_all calls .model_dump() for final JSON output.
"""

from pydantic import BaseModel


# ── WellData models ──────────────────────────────────────────────────────────

class TotalDepth(BaseModel):
    md: float | None = None
    tvd: float | None = None
    subsea: float | None = None
    unit: str | None = None


class Elevation(BaseModel):
    reference: str | None = None
    ground_level_m: float | None = None
    kelly_bushing_m: float | None = None
    kb_to_ground_m: float | None = None


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
    depth_m: float | None = None


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
    bit_diameter_mm: float | None = None
    from_m: float | None = None
    to_m: float | None = None
    interval_m: float | None = None


class Mud(BaseModel):
    section: str
    type: str | None = None
    from_m: float | None = None
    to_m: float | None = None


class CasingData(BaseModel):
    section: str
    size_mm: float | None = None
    set_at_m: float | None = None
    weight_kg_m: float | None = None
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
    depth_m: float | None = None


class WellProfileSection(BaseModel):
    section: str
    uwid: str | None = None
    start: ProfilePoint = ProfilePoint()
    end: ProfilePoint = ProfilePoint()
    duration_days: float | str | None = None
    length_m: float | None = None


class BACode(BaseModel):
    ba_code: str
    licensee: str


class WellData(BaseModel):
    well_name: str | None = None
    unique_well_id: str | None = None
    surface_location: str | None = None
    bottom_location: str | None = None
    field_region: str | None = None
    province: str | None = None
    country: str | None = None
    operator: str | None = None
    reported_to: str | None = None
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
    md_m: float | None = None
    tvd_m: float | None = None
    isopach_m: float | None = None
    ss_m: float | None = None


class FormationTop(BaseModel):
    formation: str
    prognosis: FormationPick = FormationPick()
    samples: FormationPick = FormationPick()
    mwd_gamma: FormationPick = FormationPick()
    difference_m: float | None = None


class Tops(BaseModel):
    well_name: str | None = None
    uwid: str | None = None
    kb_m: float | None = None
    gl_m: float | None = None
    formations: list[FormationTop] = []


# ── Surveys models ───────────────────────────────────────────────────────────

class SurveyMarker(BaseModel):
    md_m: float | None = None
    inclination_deg: float | None = None
    azimuth_deg: float | None = None
    tvd_m: float | None = None
    north_south_m: float | None = None
    east_west_m: float | None = None
    vertical_section_m: float | None = None
    subsea_m: float | None = None
    event: str | None = None


class SurveyPoint(BaseModel):
    md_m: float | None = None
    inclination_deg: float | None = None
    azimuth_deg: float | None = None
    tvd_m: float | None = None
    north_south_m: float | None = None
    east_west_m: float | None = None
    vertical_section_m: float | None = None
    dogleg_severity: float | None = None
    subsea_m: float | None = None
    remarks: str | None = None


class PrognosedSurveyPoint(BaseModel):
    md_m: float | None = None
    inclination_deg: float | None = None
    azimuth_deg: float | None = None


class SlideRecord(BaseModel):
    from_m: float | None = None
    to_m: float | None = None
    slide_m: float | None = None
    toolface: str | None = None


class SurveySheet(BaseModel):
    sheet_name: str
    section_name: str | None = None
    markers: list[SurveyMarker] = []
    survey_points: list[SurveyPoint] = []
    prognosed_survey: list[PrognosedSurveyPoint] = []
    slides: list[SlideRecord] = []


class Surveys(BaseModel):
    sheets: list[SurveySheet] = []


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
    from_m: float | None = None
    to_m: float | None = None
    interval_m: float | None = None
    gas_units: float | None = None
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


class Reservoirs(BaseModel):
    well_name: str | None = None
    uwi: str | None = None
    reservoirs: list[ReservoirSheet] = []


# ── Top-level result ─────────────────────────────────────────────────────────

class ExtractionResult(BaseModel):
    welldata: WellData = WellData()
    tops: Tops = Tops()
    surveys: Surveys = Surveys()
    reservoirs: Reservoirs = Reservoirs()
    # daily: Daily = Daily()
    # ... add as worksheets are built