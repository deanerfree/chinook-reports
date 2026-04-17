"""
Extract reservoir data from all Reservoir{N} sheets in a Chinook well report.

Each Reservoir sheet contains:
  - Summary tables: reservoir quality + lithology breakdown (rows 6-14)
  - Thresholds: quality category definitions (rows 19-22, cols A-B)
  - Curve analysis config: gamma/gas thresholds & cumulative tallies (V3:AA8)
  - Curve metadata: null value, max/min, cutoffs (rows 14-25)
  - Curve data: MD, ROP, Gas, Gamma at 1m intervals (row 27+, cols L-V)
  - Interval table: from/to/gas/porosity/lithology/quality/remarks (row 27+, cols A-I)
"""

from utils import serialize, parse_percent
from models import (
    Reservoirs, ReservoirSheet, ReservoirMetadata,
    QualitySummary, LithologySummary, Threshold,
    CurveAnalysisRow, CurveMetadata, CurveRange, CurveCutoffs,
    ReservoirInterval, CurvePointActual, CurvePointCleaned,
    QualityTotal,
)


NULL_SENTINEL = -999.25

QUALITY_ROWS = {
    7: "Very Good",
    8: "Good",
    9: "Fair",
    10: "Poor",
    11: "Nil",
    12: "Total",
}

LITHOLOGY_ROWS = {
    7: "Sandstone",
    8: "Siltstone",
    9: "Shale",
    10: "Limestone",
    11: "Dolomite",
    12: "Chert",
    13: "Other",
    14: "Total",
}


# ---------------------------------------------------------------------------
# Section extractors
# ---------------------------------------------------------------------------

def extract_quality_summary(ws, cell):
    """B6:D12 — reservoir quality breakdown."""
    results = []
    for row_num, label in QUALITY_ROWS.items():
        results.append(QualitySummary(
            quality=label,
            metres=cell(row_num, "C"),
            percent=parse_percent(cell(row_num, "D")),
        ))
    return results


def extract_lithology_summary(ws, cell):
    """F6:H14 — lithology breakdown."""
    results = []
    for row_num, label in LITHOLOGY_ROWS.items():
        results.append(LithologySummary(
            lithology=label,
            metres=cell(row_num, "G"),
            percent=parse_percent(cell(row_num, "H")),
        ))
    return results


def extract_thresholds(ws, cell):
    """Rows 19-22, cols A-B — quality category definitions."""
    thresholds = []
    for r in range(19, 23):
        label = cell(r, "A")
        value = cell(r, "B")
        if label is not None or value is not None:
            thresholds.append(Threshold(
                label=str(label).strip() if label else None,
                value=value,
            ))
    return thresholds


def extract_curve_analysis(ws, cell):
    """V3:AA8 — curve analysis thresholds and cumulative tallies."""
    rows = []
    for r in range(5, 9):
        gamma_threshold = cell(r, "V")
        gas_threshold = cell(r, "Y")

        if gamma_threshold is None and gas_threshold is None:
            continue

        rows.append(CurveAnalysisRow(
            gamma_threshold=gamma_threshold,
            gamma_cumulative=cell(r, "W"),
            gamma_length=cell(r, "X"),
            gas_threshold=gas_threshold,
            gas_cumulative=cell(r, "Z"),
            gas_length=cell(r, "AA"),
        ))
    return rows


def extract_curve_metadata(ws, cell):
    """Curve config: null value, max/min per curve, and quality cutoffs."""
    return CurveMetadata(
        null_value=cell(15, "N"),
        rop=CurveRange(max=cell(17, "M"), min=cell(18, "M")),
        gas=CurveRange(max=cell(17, "N"), min=cell(18, "N")),
        gamma=CurveRange(max=cell(17, "O"), min=cell(18, "O")),
        curve_4=CurveRange(max=cell(17, "P"), min=cell(18, "P")),
        curve_5=CurveRange(max=cell(17, "Q"), min=cell(18, "Q")),
        curve_6=CurveRange(max=cell(17, "R"), min=cell(18, "R")),
        cutoffs=CurveCutoffs(gas=cell(25, "N"), gamma=cell(25, "O")),
    )


def extract_intervals(ws, cell, last_row):
    """A27:I{last_row} — reservoir interval breakdown."""
    intervals = []
    end_row = 26 + last_row
    for r in range(27, end_row + 1):
        from_m = cell(r, "A")
        to_m = cell(r, "B")

        if from_m is None and to_m is None:
            break

        # Skip non-numeric rows (e.g. sub-headers or annotation text)
        if isinstance(from_m, str):
            try:
                from_m = float(from_m)
            except (ValueError, TypeError):
                continue
        if isinstance(to_m, str):
            try:
                to_m = float(to_m)
            except (ValueError, TypeError):
                continue

        intervals.append(ReservoirInterval(
            from_m=from_m,
            to_m=to_m,
            interval_m=cell(r, "C"),
            gas_units=cell(r, "D"),
            porosity=str(cell(r, "E")) if cell(r, "E") is not None else None,
            lithology=serialize(cell(r, "F")),
            quality=serialize(cell(r, "G")),
            remarks=serialize(cell(r, "H")),
            tag=serialize(cell(r, "I")),
        ))
    return intervals


def extract_curve_data(ws, cell, null_value=NULL_SENTINEL):
    """L27:V{end} — curve data at 1m MD intervals."""
    actual = []
    cleaned = []

    def clean(val):
        if val is not None and val == null_value:
            return None
        return val

    max_scan = min(ws.max_row, 27 + 5000)

    for r in range(27, max_scan + 1):
        md = cell(r, "L")
        if md is None:
            break

        actual.append(CurvePointActual(
            md=md,
            rop=clean(cell(r, "M")),
            gas=clean(cell(r, "N")),
            gamma=clean(cell(r, "O")),
            curve_4=clean(cell(r, "P")),
            curve_5=clean(cell(r, "Q")),
            curve_6=clean(cell(r, "R")),
        ))

        t_val = cell(r, "T")
        if t_val is not None:
            cleaned.append(CurvePointCleaned(
                md=md,
                interval_flag=cell(r, "S"),
                rop=clean(t_val),
                gas=clean(cell(r, "U")),
                gamma=clean(cell(r, "V")),
            ))

    return actual, cleaned


def extract_totals(ws, cell):
    """AF1:AH8 — per-sheet reservoir quality totals."""
    totals = []
    labels = {3: "Very Good", 4: "Good", 5: "Fair", 6: "Poor", 7: "Nil", 8: "Total"}
    for r, label in labels.items():
        metres = cell(r, "AG")
        pct = cell(r, "AH")
        if metres is not None or pct is not None:
            totals.append(QualityTotal(quality=label, metres=metres, percent=pct))
    return totals


# ---------------------------------------------------------------------------
# Per-sheet extraction
# ---------------------------------------------------------------------------

def extract_reservoir_sheet(ws, sheet_name):
    """Extract all data from a single Reservoir sheet."""
    def cell(row, col):
        return serialize(ws[f"{col}{row}"].value)

    meta = ReservoirMetadata(
        sheet_number=cell(1, "W"),
        leg_name=cell(5, "E"),
        last_row=cell(6, "K"),
        pages=cell(7, "K"),
        max_depth=cell(4, "K"),
    )

    null_val = cell(15, "N") or NULL_SENTINEL
    last_row = meta.last_row or 100

    actual_curves, cleaned_curves = extract_curve_data(ws, cell, null_val)

    return ReservoirSheet(
        sheet_name=sheet_name,
        metadata=meta,
        quality_summary=extract_quality_summary(ws, cell),
        lithology_summary=extract_lithology_summary(ws, cell),
        thresholds=extract_thresholds(ws, cell),
        curve_analysis=extract_curve_analysis(ws, cell),
        curve_metadata=extract_curve_metadata(ws, cell),
        intervals=extract_intervals(ws, cell, last_row),
        curve_data_actual=actual_curves,
        curve_data_cleaned=cleaned_curves,
        totals=extract_totals(ws, cell),
    )


# ---------------------------------------------------------------------------
# Main: extract all Reservoir{N} sheets
# ---------------------------------------------------------------------------

def find_reservoir_sheets(wb):
    """Find all sheets matching Reservoir1, Reservoir2, ..., Reservoir10."""
    sheets = []
    for name in wb.sheetnames:
        if name.startswith("Reservoir") and name[9:].isdigit():
            sheets.append(name)
    sheets.sort(key=lambda n: int(n[9:]))
    return sheets


def extract_reservoirs(wb) -> Reservoirs:
    """Extract reservoir data from all Reservoir sheets in the workbook."""
    sheet_names = find_reservoir_sheets(wb)

    if not sheet_names:
        return Reservoirs()

    first = wb[sheet_names[0]]
    well_name = serialize(first["A3"].value)
    uwi = serialize(first["A4"].value)

    reservoirs = []
    for name in sheet_names:
        ws = wb[name]
        # Skip blank placeholder sheets (max_depth=0 means no data)
        max_depth = ws["K4"].value
        if max_depth is None or max_depth == 0:
            continue
        reservoirs.append(extract_reservoir_sheet(ws, name))

    return Reservoirs(
        well_name=well_name,
        uwi=uwi,
        reservoirs=reservoirs,
    )
