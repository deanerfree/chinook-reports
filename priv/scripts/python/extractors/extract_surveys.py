"""
Extract data from all 'Surveys' worksheets (Surveys1, Surveys2, ...) into a
Surveys Pydantic model.

Layout per sheet:
  Row 3: well name
  Row 4: UWID
  Row 5: section name (Lateral, Leg 2, etc.)
  Row 6: directional services provider
  Row 9: average dogleg (H9), dogleg interval (I9), max dogleg (J9)
  Rows 12-14: column headers
  Rows 15-23: markers/events (same cols A-J as surveys, event name in J)
  Row 24: section header "Survey Points"
  Row 25+: survey data
    A-J: survey points (MD, Inc, Azi, TVD, N/S, E/W, VS, DLS, SS, Remarks)
    K-M: prognosed survey (MD, Inc, Azi)
    N-Q: slides (From, To, Slide length, Toolface)
"""

from utils import serialize
from models import (
    SurveySheet, SurveyMarker, SurveyPoint,
    PrognosedSurveyPoint, SlideRecord,
)


def _extract_single_survey(ws, sheet_name: str) -> SurveySheet:
    """Extract data from a single survey worksheet."""

    def cell(row, col):
        return serialize(ws[f"{col}{row}"].value)

    # ── Section name (e.g. Lateral, Leg 2) ───────────────────────────────
    section_name = cell(5, "A")

    # ── Markers/Events (rows 16-23) ──────────────────────────────────────
    markers = []
    for r in range(16, 24):
        md = cell(r, "A")
        event = cell(r, "J")
        if md is not None and event:
            markers.append(SurveyMarker(
                md=md,
                inclination_deg=cell(r, "B"),
                azimuth_deg=cell(r, "C"),
                tvd=cell(r, "D"),
                north_south=cell(r, "E"),
                east_west=cell(r, "F"),
                vertical_section=cell(r, "G"),
                subsea=cell(r, "I"),
                event=event,
            ))

    # ── Survey points (row 25+, cols A-J) ────────────────────────────────
    survey_points = []
    for r in range(25, ws.max_row + 1):
        md = cell(r, "A")
        if md is None:
            break
        survey_points.append(SurveyPoint(
            md=md,
            inclination_deg=cell(r, "B"),
            azimuth_deg=cell(r, "C"),
            tvd=cell(r, "D"),
            north_south=cell(r, "E"),
            east_west=cell(r, "F"),
            vertical_section=cell(r, "G"),
            dogleg_severity=cell(r, "H"),
            subsea=cell(r, "I"),
            remarks=cell(r, "J"),
        ))

    # ── Prognosed survey (row 25+, cols K-M) ─────────────────────────────
    prognosed_survey = []
    for r in range(25, ws.max_row + 1):
        md = cell(r, "K")
        if md is None:
            break
        prognosed_survey.append(PrognosedSurveyPoint(
            md=md,
            inclination_deg=cell(r, "L"),
            azimuth_deg=cell(r, "M"),
        ))

    # ── Slides (row 25+, cols N-Q) ───────────────────────────────────────
    slides = []
    for r in range(25, ws.max_row + 1):
        from_m = cell(r, "N")
        if from_m is None:
            break
        to_m = cell(r, "O")
        slide_m = cell(r, "P")
        toolface = cell(r, "Q")
        if any(v is not None for v in [from_m, to_m, slide_m, toolface]):
            slides.append(SlideRecord(
                from_depth=from_m,
                to_depth=to_m,
                slide=slide_m,
                toolface=toolface,
            ))

    return SurveySheet(
        sheet_name=sheet_name,
        section_name=section_name,
        markers=markers,
        survey_points=survey_points,
        prognosed_survey=prognosed_survey,
        slides=slides,
    )


def _has_data(sheet: SurveySheet) -> bool:
    """Check if a survey sheet has any meaningful data beyond the template."""
    # Check if survey points have any non-zero MD values
    real_points = [p for p in sheet.survey_points if p.md and p.md > 0]
    return len(real_points) > 0


def extract_surveys(wb) -> list[SurveySheet]:
    """Find all Surveys worksheets and extract data from each."""
    sheets = []
    for name in wb.sheetnames:
        if name.startswith("Surveys"):
            sheet = _extract_single_survey(wb[name], name)
            if _has_data(sheet):
                sheets.append(sheet)

    return sheets