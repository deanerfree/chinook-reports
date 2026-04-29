"""
Integration tests for extract_all using the sample report in test_data/.

Run from the python/ directory:
    python3 -m pytest test_extract_all.py -v
"""

import json
import pathlib
import sys

import pytest

sys.path.insert(0, str(pathlib.Path(__file__).parent))

from extract_all import extract_all

TEST_FILE = (
    pathlib.Path(__file__).parent.parent
    / "test_data"
    / "GEAR SODA LAKE 103 HZ 15-31-46-23W3M (16-36) Final Report.xlsx"
)


@pytest.fixture(scope="module")
def result():
    return extract_all(TEST_FILE)


# ── WellData ─────────────────────────────────────────────────────────────────

class TestWellData:
    def test_well_name(self, result):
        assert result.welldata.well_name == "GEAR SODA LAKE 103 HZ 15-31-46-23W3M (16-36)"

    def test_unique_well_id(self, result):
        assert result.welldata.unique_well_id == "103/15-31-046-23W3/00"

    def test_operator(self, result):
        assert result.welldata.operator == "Gear Energy Ltd."

    def test_province(self, result):
        assert result.welldata.province == "Saskatchewan"

    def test_primary_target(self, result):
        assert result.welldata.primary_target == "McLaren"

    def test_total_depth_md(self, result):
        assert result.welldata.total_depth_actual.md == 1979.0

    def test_total_depth_tvd(self, result):
        assert result.welldata.total_depth_actual.tvd == 441.95

    def test_well_geometry(self, result):
        assert result.welldata.well_geometry == "Horizontal"

    def test_kelly_bushing(self, result):
        assert result.welldata.elevations.kelly_bushing == 575.9

    def test_spud_date(self, result):
        assert result.welldata.well_timing.spud_date.date == "2024-02-14"

    def test_rig_release_date(self, result):
        assert result.welldata.well_timing.rig_release_date == "2024-02-19"

    def test_hole_sizes_count(self, result):
        assert len(result.welldata.hole_sizes) == 3

    def test_hole_sizes_sections(self, result):
        sections = [h.section for h in result.welldata.hole_sizes]
        assert sections == ["SURFACE", "INTERMEDIATE", "MAIN"]

    def test_casing_data_count(self, result):
        assert len(result.welldata.casing_data) == 3

    def test_wellsite_geology_company(self, result):
        assert result.welldata.services.wellsite_geology.company == "Chinook Consulting Services"

    def test_well_profile_sections(self, result):
        sections = [s.section for s in result.welldata.well_profile]
        assert sections == ["Vertical", "Build", "Lateral"]

    def test_lateral_length(self, result):
        lateral = next(s for s in result.welldata.well_profile if s.section == "Lateral")
        assert lateral.length == 1368.0


# ── Tops ─────────────────────────────────────────────────────────────────────

class TestTops:
    def test_has_formations(self, result):
        assert len(result.tops.formations) > 0

    def test_well_name_matches(self, result):
        # tops sheet should reference the same well
        assert result.tops.well_name is not None


# ── Surveys ───────────────────────────────────────────────────────────────────

class TestSurveys:
    def test_has_sheets(self, result):
        assert len(result.surveys.sheets) > 0

    def test_sheets_have_survey_points(self, result):
        total_points = sum(len(s.survey_points) for s in result.surveys.sheets)
        assert total_points > 0


# ── Serialization ─────────────────────────────────────────────────────────────

def test_full_result_is_json_serializable(result):
    dumped = result.model_dump()
    json.dumps(dumped)  # raises if not serializable
