"""
Shared utility functions for worksheet extraction.
"""

import datetime


def serialize(val):
    """Convert Excel cell values to JSON-safe types."""
    if val is None:
        return None
    if isinstance(val, datetime.datetime):
        return val.strftime("%Y-%m-%d")
    if isinstance(val, datetime.time):
        return val.strftime("%H:%M")
    if isinstance(val, str):
        val = val.strip()
        return val if val else None
    return val


def parse_percent(raw):
    """Parse percentage from '(30.34%)' string or 0.3034 float."""
    if raw is None:
        return None
    if isinstance(raw, str):
        cleaned = raw.strip("()% ")
        try:
            return float(cleaned)
        except ValueError:
            return None
    if isinstance(raw, (int, float)):
        val = float(raw)
        # Values <= 1 are likely decimals (0.3034 = 30.34%)
        return round(val * 100, 2) if val <= 1 else val
    return None