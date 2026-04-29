"""
Extract daily drilling summary data from the 'Daily' worksheet.

Layout:
  Row 8: headers (Date | Depth | Progress | Drilling | ROP | Operations Summary | tag)
  Row 9: units (None | m | m | (Hours) | m/hr | None | tag)
  Row 10+: one row per day (stop when both col A and col B are empty)
"""

from utils import serialize
from models import DailyEntry


def extract_daily(wb) -> list[DailyEntry]:
    if "Daily" not in wb.sheetnames:
        return []

    ws = wb["Daily"]

    def cell(row, col):
        return serialize(ws[f"{col}{row}"].value)

    depth_unit = cell(9, "B") or "m"

    entries = []
    for r in range(10, ws.max_row + 1):
        date = cell(r, "A")
        depth = cell(r, "B")
        operations_summary = cell(r, "F")

        if operations_summary is None or (date is None and depth is None):
            break

        entries.append(DailyEntry(
            date=date,
            depth=depth,
            progress=cell(r, "C"),
            drilling_hours=cell(r, "D"),
            rop=cell(r, "E"),
            operations_summary=operations_summary,
            tag=cell(r, "G"),
        ))

    return entries
