"""
Master extraction script.
Opens the workbook once and passes it to each worksheet extractor.

Usage: python extract_all.py <filepath>
"""

import json
import openpyxl
import sys
import warnings

warnings.filterwarnings("ignore", category=UserWarning, module="openpyxl")

from models import ExtractionResult, WellMetadata, LegData
from extractors.extract_welldata import extract_welldata
from extractors.extract_tops import extract_tops
from extractors.extract_reservoirs import extract_reservoirs
# from extractors.extract_daily import extract_daily
# from extractors.extract_mud import extract_mud
# from extractors.extract_bit import extract_bit
# from extractors.extract_gas import extract_gas
from extractors.extract_surveys import extract_surveys
from extractors.extract_synopsis import extract_synopsis
# ... add more as they are built


def _pair_leg_data(surveys, reservoirs) -> list[LegData]:
    survey_map = {int(s.sheet_name[7:]): s for s in surveys if s.sheet_name[7:].isdigit()}
    reservoir_map = {int(r.sheet_name[9:]): r for r in reservoirs if r.sheet_name[9:].isdigit()}
    legs = []
    for k in sorted(set(survey_map) | set(reservoir_map)):
        s = survey_map.get(k)
        r = reservoir_map.get(k)
        leg_name = (r.metadata.leg_name if r else None) or (s.section_name if s else None)
        legs.append(LegData(leg_name=leg_name, survey=s, log_data=r))
    return legs


def progress(step):
    """Emit a progress line to stdout for the Elixir Port to pick up."""
    sys.stdout.write(f"PROGRESS:{step}\n")
    sys.stdout.flush()


def extract_all(filepath) -> ExtractionResult:
    progress("loading")
    wb = openpyxl.load_workbook(filepath, data_only=True)

    progress("welldata")
    welldata = extract_welldata(wb)

    progress("tops")
    tops = extract_tops(wb)

    progress("reservoirs")
    reservoirs = extract_reservoirs(wb)

    # progress("daily")
    # daily = extract_daily(wb)
    # progress("mud")
    # mud = extract_mud(wb)
    # progress("bit")
    # bit = extract_bit(wb)
    # progress("gas")
    # gas = extract_gas(wb)

    progress("surveys")
    surveys = extract_surveys(wb)

    progress("synopsis")
    synopsis = extract_synopsis(wb)

    metadata = WellMetadata(
        well_name=welldata.well_name,
        unique_well_id=welldata.unique_well_id,
        operator=welldata.operator,
        spud_date=welldata.well_timing.spud_date.date,
        final_td_date=welldata.well_timing.final_td.date,
        target_formation=welldata.primary_target,
        country=welldata.country,
        latitude=welldata.location_data.geographic_coordinates.latitude,
        longitude=welldata.location_data.geographic_coordinates.longitude,
    )

    result = ExtractionResult(
        metadata=metadata,
        welldata=welldata,
        tops=tops,
        reservoir_data=_pair_leg_data(surveys, reservoirs),
        synopsis=synopsis,
    )

    wb.close()
    progress("complete")
    return result


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python extract_all.py <filepath>")
        sys.exit(1)

    filepath = sys.argv[1]
    result = extract_all(filepath)
    print(json.dumps(result.model_dump(), indent=2))
