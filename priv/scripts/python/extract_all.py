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

from models import ExtractionResult
from extractors.extract_welldata import extract_welldata
from extractors.extract_tops import extract_tops
from extractors.extract_reservoirs import extract_reservoirs
# from extractors.extract_daily import extract_daily
# from extractors.extract_mud import extract_mud
# from extractors.extract_bit import extract_bit
# from extractors.extract_gas import extract_gas
from extractors.extract_surveys import extract_surveys
# ... add more as they are built


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

    result = ExtractionResult(
        welldata=welldata,
        tops=tops,
        reservoirs=reservoirs,
        surveys=surveys,
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
