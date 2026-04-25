"""
Extract data from the 'Tops' worksheet into a Tops Pydantic model.

Layout:
  Row 3: well name | Row 4: UWID
  Row 6-7: KB / GL elevations
  Row 8-9: headers (Formation | Prognosis MD/TVD/Isopach/SS | Samples | MWD Gamma | Difference)
  Row 10+: formation data (until column A is empty)
"""

from utils import serialize
from models import Tops, FormationTop, FormationPick


def extract_tops(wb) -> Tops:
    ws = wb["Tops"]

    def cell(row, col):
        return serialize(ws[f"{col}{row}"].value)

    # ── Formation rows (row 10 onward, stop when col A is empty) ─────────
    formations = []
    for r in range(10, ws.max_row + 1):
        name = cell(r, "A")
        if not name:
            break
        formations.append(FormationTop(
            formation=name,
            prognosis=FormationPick(
                md_m=cell(r, "B"),
                tvd_m=cell(r, "C"),
                isopach_m=cell(r, "D"),
                ss_m=cell(r, "E"),
            ),
            samples=FormationPick(
                md_m=cell(r, "F"),
                tvd_m=cell(r, "G"),
                isopach_m=cell(r, "H"),
                ss_m=cell(r, "I"),
            ),
            mwd_gamma=FormationPick(
                md_m=cell(r, "J"),
                tvd_m=cell(r, "K"),
                isopach_m=cell(r, "L"),
                ss_m=cell(r, "M"),
            ),
            difference_m=cell(r, "N"),
        ))

    return Tops(formations=formations)