"""
Extract mud log data from all Mud{N} sheets in a Chinook well report.

Layout (per sheet):
  Row 9+: one row per entry (cols A-H), stop when both Date and Depth are empty
  A: Date | B: Depth | C: Mud Type | D: Density | E: Viscosity | F: WL | G: pH | H: Remarks
"""

from utils import serialize
from models import MudEntry


def find_mud_sheets(wb):
    """Find all sheets matching Mud, Mud1, Mud2, ..."""
    sheets = []
    for name in wb.sheetnames:
        if name == "Mud" or (name.startswith("Mud") and name[3:].isdigit()):
            sheets.append(name)
    sheets.sort(key=lambda n: int(n[3:]) if n[3:].isdigit() else 0)
    return sheets


def extract_mud_sheet(ws) -> list[MudEntry]:
    def cell(row, col):
        return serialize(ws[f"{col}{row}"].value)

    entries = []
    for r in range(9, ws.max_row + 1):
        date = cell(r, "A")
        depth = cell(r, "B")

        if date is None and depth is None:
            break

        entries.append(MudEntry(
            date=date,
            depth=depth,
            mud_type=cell(r, "C"),
            density=cell(r, "D"),
            viscosity=cell(r, "E"),
            wl=cell(r, "F"),
            ph=cell(r, "G"),
            remarks=cell(r, "H"),
        ))

    return entries


def extract_mud(wb) -> list[MudEntry]:
    sheet_names = find_mud_sheets(wb)

    if not sheet_names:
        return []

    entries = []
    for name in sheet_names:
        entries.extend(extract_mud_sheet(wb[name]))

    return entries
