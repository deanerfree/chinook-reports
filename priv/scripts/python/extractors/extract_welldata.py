"""
Extract data from the 'WellData' worksheet (columns A-H, I-Q) into a
WellData Pydantic model.
"""

from utils import serialize
from models import (
    WellData, TotalDepth, Elevation, GeographicCoordinates,
    SurfaceLocationGrid, LocationData, TimingEvent, WellTiming,
    HoleSize, Mud, CasingData, WellsiteGeology, DrillingContractor,
    Services, GeologicalServices, ProfilePoint, WellProfileSection,
    BACode,
)


def extract_welldata(wb) -> WellData:
    ws = wb["WellData"]

    def cell(row, col):
        return serialize(ws[f"{col}{row}"].value)

    # ── Hole sizes (rows 60-62) ──────────────────────────────────────────
    hole_sizes = []
    for r in [60, 61, 62]:
        label = cell(r, "A")
        if label:
            hole_sizes.append(HoleSize(
                section=label,
                bit_diameter_mm=cell(r, "B"),
                from_m=cell(r, "D"),
                to_m=cell(r, "E"),
                interval_m=cell(r, "F"),
            ))

    # ── Mud (rows 66-68) ─────────────────────────────────────────────────
    mud = []
    for r in [66, 67, 68]:
        label = cell(r, "A")
        if label:
            mud.append(Mud(
                section=label,
                type=cell(r, "B"),
                from_m=cell(r, "D"),
                to_m=cell(r, "E"),
            ))

    # ── Casing data (rows 72-74) ─────────────────────────────────────────
    casing_data = []
    for r in [72, 73, 74]:
        label = cell(r, "A")
        if label:
            casing_data.append(CasingData(
                section=label,
                size_mm=cell(r, "B"),
                set_at_m=cell(r, "C"),
                weight_kg_m=cell(r, "D"),
                type=cell(r, "F"),
            ))

    # ── Well profile (rows 102-145, paired start/end) ────────────────────
    profile_rows = [
        (102, 103, "Vertical"),
        (104, 105, "Build"),
        (106, 107, "Lateral"),
    ]
    for i in range(108, 146, 2):
        label = cell(i, "A")
        if label and cell(i, "C"):
            profile_rows.append((i, i + 1, label))

    well_profile = []
    for start_row, end_row, section_name in profile_rows:
        start_date = cell(start_row, "C")
        end_date = cell(end_row, "C")
        if start_date or end_date:
            well_profile.append(WellProfileSection(
                section=section_name,
                uwid=cell(start_row + 1, "A"),
                start=ProfilePoint(
                    date=start_date,
                    time=cell(start_row, "D"),
                    depth_m=cell(start_row, "E"),
                ),
                end=ProfilePoint(
                    date=end_date,
                    time=cell(end_row, "D"),
                    depth_m=cell(end_row, "E"),
                ),
                duration_days=cell(start_row, "G"),
                length_m=cell(end_row, "G"),
            ))

    # ── BA Codes (rows 175+) ─────────────────────────────────────────────
    ba_codes = []
    for r in range(175, ws.max_row + 1):
        code = cell(r, "A")
        name = cell(r, "B")
        if code and name:
            ba_codes.append(BACode(ba_code=code, licensee=name))

    # ── Assemble model ───────────────────────────────────────────────────
    return WellData(
        well_name=cell(4, "B"),
        unique_well_id=cell(6, "B"),
        surface_location=cell(7, "B"),
        bottom_location=cell(8, "B"),
        field_region=cell(9, "B"),
        province=cell(10, "B"),
        country=cell(11, "B"),
        operator=cell(12, "B"),
        reported_to=cell(13, "B"),
        primary_target=cell(17, "B"),
        secondary_target=cell(18, "B"),
        terminating_zone=cell(19, "B"),
        total_depth_actual=TotalDepth(
            md=cell(21, "B"),
            tvd=cell(21, "E"),
            subsea=cell(21, "G"),
            unit=cell(21, "H"),
        ),
        final_well_status=cell(23, "B"),
        well_geometry=cell(27, "B"),
        afe_number=cell(28, "B"),
        well_license=cell(29, "B"),
        well_purpose=cell(30, "B"),
        substance=cell(31, "B"),
        well_classification=cell(32, "B"),
        security=cell(33, "B"),
        elevations=Elevation(
            reference=cell(35, "C"),
            ground_level_m=cell(37, "B"),
            kelly_bushing_m=cell(38, "B"),
            kb_to_ground_m=cell(39, "B"),
        ),
        location_data=LocationData(
            coordinate_system=cell(41, "H"),
            geographic_coordinates=GeographicCoordinates(
                latitude=cell(43, "B"),
                latitude_dir=cell(43, "C"),
                longitude=cell(43, "D"),
                longitude_dir=cell(43, "E"),
                datum=cell(43, "G"),
            ),
            surface_coordinates=cell(44, "B"),
            surface_location_grid=SurfaceLocationGrid(
                format=cell(41, "I"),
                northing=cell(44, "I"),
                northing_dir=cell(44, "J"),
                easting=cell(44, "K"),
                easting_dir=cell(44, "L"),
                section=cell(44, "N"),
                township=cell(44, "O"),
                range=cell(44, "P"),
                meridian=cell(44, "Q"),
            ),
            bottom_coordinates=cell(45, "B"),
        ),
        well_timing=WellTiming(
            spud_date=TimingEvent(date=cell(49, "B"), time=cell(49, "E"), depth_m=cell(49, "G")),
            surface_casing=TimingEvent(date=cell(50, "B"), depth_m=cell(50, "G")),
            sample_point=TimingEvent(date=cell(51, "B"), time=cell(51, "E"), depth_m=cell(51, "G")),
            kick_off_point=TimingEvent(date=cell(52, "B"), time=cell(52, "E"), depth_m=cell(52, "G")),
            intermediate_casing_point=TimingEvent(date=cell(53, "B"), time=cell(53, "E"), depth_m=cell(53, "G")),
            heel=TimingEvent(date=cell(54, "B"), time=cell(54, "E"), depth_m=cell(54, "G")),
            final_td=TimingEvent(date=cell(55, "B"), time=cell(55, "E"), depth_m=cell(55, "G")),
            rig_release_date=cell(56, "B"),
        ),
        hole_sizes=hole_sizes,
        mud=mud,
        casing_data=casing_data,
        services=Services(
            wellsite_geology=WellsiteGeology(
                company=cell(78, "B"),
                geologists=[cell(78, "E"), cell(79, "E")],
            ),
            drilling_contractor=DrillingContractor(company=cell(80, "B"), rig=cell(80, "D")),
            drilling_supervision=cell(81, "B"),
            gas_detection=cell(82, "B"),
            directional_drilling=cell(83, "B"),
            mwd_lwd_services=cell(84, "B"),
            mud=cell(85, "B"),
            coring=cell(86, "B"),
            wireline_logging=cell(87, "B"),
            testing=cell(88, "B"),
        ),
        geological_services=GeologicalServices(
            samples_operator=cell(92, "B"),
            samples_government=cell(93, "B"),
            cores=cell(94, "B"),
            dst=cell(95, "B"),
            logging_suite=cell(96, "B"),
        ),
        well_profile=well_profile,
        ba_codes=ba_codes,
    )