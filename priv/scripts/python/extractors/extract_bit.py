"""
Extract bit record data from the 'Bits' worksheet.

Layout:
  Row 13+: one row per bit (stop when both col A and col B are empty)
  Columns A-L: Bit No | Size | Make | Type | Depth In | Depth Out |
               Progress | Hours | WOB | RPM | ROP | Remarks
"""

from utils import serialize
from models import BitRecord


def extract_bit(wb) -> list[BitRecord]:
    sheet_name = next((n for n in wb.sheetnames if n in ("Bits", "Bit")), None)
    if sheet_name is None:
        return []

    ws = wb[sheet_name]

    def cell(row, col):
        return serialize(ws[f"{col}{row}"].value)

    records = []
    for r in range(13, ws.max_row + 1):
        bit_no = cell(r, "A")
        size = cell(r, "B")

        if bit_no is None and size is None:
            break

        records.append(BitRecord(
            bit_number=bit_no,
            size=size,
            make=cell(r, "C"),
            type=cell(r, "D"),
            depth_in=cell(r, "F"),
            depth_out=cell(r, "G"),
            progress=cell(r, "H"),
            hours=cell(r, "I"),
            wob=cell(r, "J"),
            rpm=cell(r, "K"),
            rop=cell(r, "L")

        ))

    return records
