"""
Extract data from the 'Synopsis' worksheet.

The sheet contains free-form text in column A organised under three section
headers:
  - WELL SUMMARY
  - WELL PROFILE
  - FORMATION EVALUATION

Each non-empty cell beneath a header is collected into a list of strings
for that section, until the next section header (or end of data) is reached.
"""

import re

from utils import serialize
from models import Synopsis

SECTION_HEADERS = {
    "WELL SUMMARY": "well_summary",
    "WELL PROFILE": "well_profile",
    "FORMATION EVALUATION": "formation_evaluation",
}

# Matches the section header even when surrounded by whitespace
_HEADER_RE = re.compile(
    r"^\s*(" + "|".join(re.escape(h) for h in SECTION_HEADERS) + r")\s*$",
    re.IGNORECASE,
)


def extract_synopsis(wb) -> Synopsis:
    if "Synopsis" not in wb.sheetnames:
        return Synopsis()

    ws = wb["Synopsis"]

    sections: dict[str, list[str]] = {
        "well_summary": [],
        "well_profile": [],
        "formation_evaluation": [],
    }

    current_key: str | None = None

    for row in ws.iter_rows(min_col=1, max_col=1, values_only=True):
        raw = row[0]
        text = serialize(raw)
        if text is None:
            continue

        text_str = str(text).strip()
        if not text_str:
            continue

        # Check if this cell is a section header
        match = _HEADER_RE.match(text_str)
        if match:
            matched_header = match.group(1).upper()
            current_key = SECTION_HEADERS.get(matched_header)
            continue

        # Append to the current section
        if current_key is not None:
            sections[current_key].append(text_str)

    return Synopsis(**sections)
