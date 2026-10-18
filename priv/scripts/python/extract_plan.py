"""
Extract a directional plan into a DirectionalPlan Pydantic model, from either
a COMPASS planning report PDF or a delimited survey listing (CSV / TXT).

Usage: python extract_plan.py <filepath>

The format is sniffed from the file's content, not its name, so an upload's
temp path works as-is.

── PDF ──
Handles the layout COMPASS (Landmark) prints regardless of which directional
company's template wraps it (seen: Altitude "Standard Planning Report",
Pacesetter "Directional Planning Report").

Layout:
  Page 1: cover — company, project, site, well, wellbore, plan, UWI, date
  Plot page(s): skipped (no "Database:" header block)
  Every other page: a repeated header block ending at the "Design:" line,
  a footer ("<date> <time> Page N COMPASS ..."), and sections that continue
  across pages until the next section title:
    Plan Sections    MD Inc Azi TVD N/S E/W <rates> TFO [target]
    Planned Survey   MD Inc Azi TVD Subsea N/S E/W VS <rates>
                     a label line (formation/annotation) sits on the line
                     above the station it belongs to
    Design Targets   name dip dip-dir TVD N/S E/W northing easting lat long
    Formations       MD TVD name
    Plan Annotations MD TVD N/S E/W comment
    Casing Points    MD TVD name casing-dia hole-dia

The three rate columns (Dogleg/Build/Turn) are in a different order per
template, so they're mapped from the column header, not by position.

Formation names are kept exactly as printed. Annotation N/S and E/W are taken
from the survey station at the same MD — the printed Plan Annotations table
can be shifted by a row.

── CSV / TXT ──
COMPASS text exports (comma- or whitespace-delimited) and tab-delimited survey
listings:
  "H KEY : value" lines (CSV: "H KEY :,value") — well header
  "# ..." lines — comments ("# VSD = 220.44" is the vertical-section azimuth)
  one column-header row (MD, Inc, Azi, ... in any order, any of the usual
  spellings), then one station per row, optionally ending in a free-text
  comment. COMPASS doesn't quote that comment, so a comma inside it
  ("Nudge, 1.5°/30m") spills into extra CSV fields and is joined back up.
These listings don't say which comments are formations, so every comment is
kept as a station label and `tops` stays empty.
"""

import datetime
import json
import re
import sys

import pdfplumber

from models import (
    DirectionalPlan, PlanHeader, PlanMagnetics, PlanSection, PlanStation,
    PlanAnnotation, PlanTarget, PlanCasingPoint, Tops, FormationTop,
    FormationPick,
)

SECTION_TITLES = {
    "Plan Sections": "plan_sections",
    "Planned Survey": "survey",
    "Design Targets": "targets",
    "Formations": "formations",
    "Plan Annotations": "annotations",
    "Casing Points": "casing_points",
}

NUM = re.compile(r"-?\d[\d,]*(?:\.\d+)?")
FOOTER = re.compile(r"^\d{4}-\d{2}-\d{2} .*Page \d+")
UWI = re.compile(r"\b\d[0-9A-Z]{2}/\d{2}-\d{2}-\d{3}-\d{2}W\d/\d{2}\b")
RATE_COLUMNS = {"Dogleg": "dogleg_severity", "Build": "build_rate", "Turn": "turn_rate"}
DEFAULT_RATE_ORDER = ["dogleg_severity", "build_rate", "turn_rate"]


def _num(token):
    return float(token.replace(",", ""))


def _leading_numbers(line):
    """Split a line into its leading numeric tokens and the remaining text."""
    tokens = line.split()
    nums = []
    for t in tokens:
        if not NUM.fullmatch(t):
            break
        nums.append(_num(t))
    return nums, " ".join(tokens[len(nums):])


def _search(pattern, text, group=1):
    m = re.search(pattern, text, re.M)
    return m.group(group).strip() if m else None


def _search_num(pattern, text):
    raw = _search(pattern, text)
    return _num(raw) if raw else None


def _parse_coordinate(raw):
    """Decimal ('54.605960') or DMS ('53° 39' 16.2597 N') → signed decimal degrees."""
    if raw is None:
        return None
    m = re.match(r"(\d+)°\s*(\d+)'\s*([\d.]+)\s*([NSEW])", raw)
    if m:
        deg, minutes, seconds, hemi = m.groups()
        value = int(deg) + int(minutes) / 60 + float(seconds) / 3600
        return round(-value if hemi in "SW" else value, 6)
    try:
        return float(raw)
    except ValueError:
        return None


def _rate_order(header_line):
    """Order of the Dogleg/Build/Turn columns as printed in a 'Measured ...' header."""
    order = [RATE_COLUMNS[w] for w in header_line.split() if w in RATE_COLUMNS]
    return order if len(order) == 3 else DEFAULT_RATE_ORDER


# ── Header ───────────────────────────────────────────────────────────────────

def _extract_header(cover_text, info_text, pages_text) -> PlanHeader:
    info_lines = info_text.splitlines()

    report_date = None
    for line in cover_text.splitlines():
        try:
            report_date = datetime.datetime.strptime(line.strip(), "%d %B, %Y").strftime("%Y-%m-%d")
            break
        except ValueError:
            continue

    uwi = UWI.search(cover_text) or UWI.search(info_text)

    well_name = next(
        (m.group(1).strip() for line in info_lines
         if (m := re.match(r"^Well (?!Position)(.+)$", line))),
        None,
    )

    northing = easting = latitude = longitude = None
    for i, line in enumerate(info_lines):
        if line.startswith("Well Position"):
            northing = _search_num(r"Northing:\s*([\d,.]+)", line)
            latitude = _parse_coordinate(_search(r"Latitude:\s*(.+)$", line))
            following = info_lines[i + 1] if i + 1 < len(info_lines) else ""
            easting = _search_num(r"Easting:\s*([\d,.]+)", following)
            longitude = _parse_coordinate(_search(r"Longitude:\s*(.+)$", following))
            break

    vs_azimuth = None
    for i, line in enumerate(info_lines):
        if line.startswith("Vertical Section:"):
            for following in info_lines[i + 1:]:
                nums, rest = _leading_numbers(following)
                if len(nums) == 4 and not rest:
                    vs_azimuth = nums[3]
                    break
            break

    magnetics = PlanMagnetics()
    m = re.search(r"^(\S+)\s+(\d{4}-\d{2}-\d{2})\s+([\d.]+)\s+([\d.]+)\s+([\d,.]+)$", info_text, re.M)
    if m:
        magnetics = PlanMagnetics(
            model=m.group(1),
            sample_date=m.group(2),
            declination_deg=_num(m.group(3)),
            dip_angle_deg=_num(m.group(4)),
            field_strength_nt=_num(m.group(5)),
        )

    return PlanHeader(
        provider=info_lines[0].strip() if info_lines else None,
        report_title=info_lines[1].strip() if len(info_lines) > 1 else None,
        report_date=report_date,
        compass_version=_search(r"(COMPASS [\d.]+ Build \d+)", pages_text),
        company=_search(r"^Company:\s*(.*?)\s*(?:TVD Reference:|$)", info_text),
        project=_search(r"^Project:\s*(.*?)\s*(?:MD Reference:|$)", info_text),
        site=_search(r"^Site:\s*(.*?)\s*(?:North Reference:|$)", info_text),
        wellbore=_search(r"^Wellbore:\s*(.*)$", info_text),
        design=_search(r"^Design:\s*(.*)$", info_text),
        well_name=well_name,
        unique_well_id=uwi.group(0) if uwi else None,
        kb_elevation=_search_num(r"TVD Reference:.*?@\s*([\d,.]+)\s*m", info_text),
        ground_elevation=_search_num(r"Ground Level:\s*([\d,.]+)", info_text),
        north_reference=_search(r"North Reference:\s*(\S+)", info_text),
        calculation_method=_search(r"Survey Calculation Method:\s*(.*)$", info_text),
        geo_datum=_search(r"^Geo Datum:\s*(.*)$", info_text),
        map_zone=_search(r"^Map Zone:\s*(Zone \S+(?: \([^)]*\))?)", info_text),
        northing=northing,
        easting=easting,
        latitude=latitude,
        longitude=longitude,
        vertical_section_azimuth_deg=vs_azimuth,
        magnetics=magnetics,
    )


# ── Section lines ────────────────────────────────────────────────────────────

def _section_lines(page_texts):
    """
    Yield (section, line) for every body line of every report page, with the
    repeated page header/footer stripped and the section carried across pages.
    """
    section = None
    for text in page_texts:
        lines = text.splitlines()
        start = next((i + 1 for i, l in enumerate(lines) if l.startswith("Design:")), 0)
        for line in lines[start:]:
            line = line.strip()
            if not line or FOOTER.match(line):
                continue
            title = next((t for t in SECTION_TITLES if line.startswith(t)), None)
            if title:
                section = SECTION_TITLES[title]
                continue
            if section:
                yield section, line


def _is_column_header(line):
    return line.startswith(("Measured", "Depth", "(m)", "(°)", "Name", "Target Name", "TVD"))


def _extract_sections(page_texts):
    plan_sections, survey, formations, annotations, targets, casing = [], [], [], [], [], []
    rate_order = {"plan_sections": DEFAULT_RATE_ORDER, "survey": DEFAULT_RATE_ORDER}
    pending_labels = []

    for section, line in _section_lines(page_texts):
        if line.startswith("Measured") and section in rate_order:
            rate_order[section] = _rate_order(line)
        nums, rest = _leading_numbers(line)

        if section == "plan_sections":
            if len(nums) >= 10:
                rates = dict(zip(rate_order[section], nums[6:9]))
                plan_sections.append(PlanSection(
                    md=nums[0], inclination_deg=nums[1], azimuth_deg=nums[2],
                    tvd=nums[3], north_south=nums[4], east_west=nums[5],
                    tool_face_deg=nums[9], target=rest or None, **rates,
                ))

        elif section == "survey":
            if len(nums) >= 11:
                rates = dict(zip(rate_order[section], nums[8:11]))
                survey.append(PlanStation(
                    md=nums[0], inclination_deg=nums[1], azimuth_deg=nums[2],
                    tvd=nums[3], subsea=nums[4], north_south=nums[5],
                    east_west=nums[6], vertical_section=nums[7],
                    labels=pending_labels, **rates,
                ))
                pending_labels = []
            elif not nums and not _is_column_header(line):
                pending_labels.append(line)

        elif section == "formations":
            if len(nums) >= 2 and rest:
                formations.append((nums[0], nums[1], rest))

        elif section == "annotations":
            if len(nums) >= 4 and rest:
                annotations.append(PlanAnnotation(
                    md=nums[0], tvd=nums[1], north_south=nums[2],
                    east_west=nums[3], comment=rest,
                ))

        elif section == "targets":
            m = re.match(r"^(.+?)\s+((?:-?\d[\d,]*\.\d+\s+){6}-?\d[\d,]*\.\d+)", line)
            if m and not _is_column_header(line):
                vals = [_num(v) for v in m.group(2).split()]
                targets.append(PlanTarget(
                    name=m.group(1), tvd=vals[2], north_south=vals[3],
                    east_west=vals[4], northing=vals[5], easting=vals[6],
                ))
            elif line.startswith("- ") and targets:
                targets[-1].notes.append(line[2:].strip())

        elif section == "casing_points":
            tail = re.match(r"^(.*?)\s+(-?[\d,.]+)\s+(-?[\d,.]+)$", rest)
            if len(nums) >= 2 and tail:
                casing.append(PlanCasingPoint(
                    md=nums[0], tvd=nums[1], name=tail.group(1),
                    casing_diameter_mm=_num(tail.group(2)),
                    hole_diameter_mm=_num(tail.group(3)),
                ))

    return plan_sections, survey, formations, annotations, targets, casing


def _station_at(survey, md):
    return next((s for s in survey if s.md is not None and abs(s.md - md) < 0.005), None)


# ── CSV / TXT listings ───────────────────────────────────────────────────────

# Normalised column name (lowercase, units and punctuation stripped) → field.
TEXT_COLUMNS = {
    "md": "md",
    "inc": "inclination_deg", "incl": "inclination_deg", "inclination": "inclination_deg",
    "azi": "azimuth_deg", "azim": "azimuth_deg", "azm": "azimuth_deg", "azimuth": "azimuth_deg",
    "tvd": "tvd",
    "ss": "subsea", "subsea": "subsea",
    "ns": "north_south",
    "ew": "east_west",
    "vs": "vertical_section", "vsec": "vertical_section",
    "dls": "dogleg_severity", "dogleg": "dogleg_severity",
    "buildrate": "build_rate", "build": "build_rate",
    "turnrate": "turn_rate", "turn": "turn_rate",
    "comment": "comment", "comments": "comment",
}


def _decode(raw: bytes) -> str:
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        return raw.decode("latin-1")


def _column_key(name):
    return re.sub(r"[^a-z]", "", re.sub(r"\(.*?\)", "", name.lower()))


def _split(line, delimiter):
    return [f.strip() for f in line.split(delimiter)] if delimiter else line.split()


def _text_header(h, comments) -> PlanHeader:
    def num(key):
        try:
            return _num(h[key])
        except (KeyError, ValueError):
            return None

    report_date = None
    m = re.search(r"\d{1,2}-[A-Za-z]{3}-\d{4}", h.get("TEXT FILE EXPORT DATE", "") + h.get("TEXT FILE EXPORT DATE / TIME", ""))
    if m:
        report_date = datetime.datetime.strptime(m.group(0), "%d-%b-%Y").strftime("%Y-%m-%d")

    vs = num("VSECT ANGLE")
    if vs is None:
        vs = next((_num(m.group(1)) for c in comments if (m := re.match(r"VSD\s*=\s*([-\d.]+)", c))), None)

    return PlanHeader(
        provider=h.get("DIRECTIONAL COMPANY"),
        company=h.get("COMPANY"),
        project=h.get("FIELD"),
        site=h.get("SITE"),
        well_name=h.get("WELL"),
        wellbore=h.get("WELLPATH"),
        unique_well_id=next((m.group(0) for v in h.values() if (m := UWI.search(v))), None),
        design=h.get("DESIGN"),
        report_date=report_date,
        kb_elevation=num("KB ELEVN"),
        ground_elevation=num("GRD LVL"),
        north_reference=h.get("NORTH REF"),
        northing=num("WELL NS MAP"),
        easting=num("WELL EW MAP"),
        vertical_section_azimuth_deg=vs,
    )


def _extract_text(text) -> DirectionalPlan:
    header, comments = {}, []
    columns = delimiter = None
    survey = []
    latlong = None

    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            continue

        if columns is None:
            if stripped.startswith("H"):
                # "H07000.00 : 6505.51 : PROPOSAL 4 : MWD+HDGM_REV5" names the design.
                if (m := re.match(r"^H\d[\d.]*\s*:.*?:\s*(.*?)\s*:", stripped)):
                    header.setdefault("DESIGN", m.group(1).title())
                elif (m := re.match(r"^H\s+([^:]+?)\s*:,?\s*(.*?)[\s,]*$", stripped)):
                    header[m.group(1).strip()] = m.group(2)
                continue
            if stripped.startswith("#"):
                comments.append(stripped.lstrip("#").strip())
                continue
            delimiter = "," if "," in stripped else "\t" if "\t" in stripped else None
            names = [_column_key(n) for n in _split(stripped, delimiter)]
            if "md" in names and any(TEXT_COLUMNS.get(n) == "inclination_deg" for n in names):
                columns = names
            continue

        fields = _split(stripped, delimiter)
        n = next((i for i, c in enumerate(columns) if TEXT_COLUMNS.get(c) == "comment"), len(columns))
        if len(fields) < n or not all(NUM.fullmatch(f) for f in fields[:n]):
            if survey:
                break  # trailer, e.g. "#EOF"
            continue

        values = {TEXT_COLUMNS[c]: _num(f) for c, f in zip(columns[:n], fields[:n]) if c in TEXT_COLUMNS}
        comment = (", " if delimiter == "," else " ").join(f for f in fields[n:] if f).strip()
        survey.append(PlanStation(**values, labels=[comment] if comment else []))

        if latlong is None and {"latitude", "longitude"} <= set(columns[:n]):
            latlong = (_num(fields[columns.index("latitude")]), _num(fields[columns.index("longitude")]))

    if columns is None or not survey:
        raise ValueError("No survey listing found (expected a header row with MD and Inc columns)")

    plan_header = _text_header(header, comments)
    if latlong:
        plan_header.latitude, plan_header.longitude = latlong
    if plan_header.well_name is None:
        # surveys.txt-style listings name the well in a leading "# ..." comment.
        plan_header.well_name = next(
            (c for c in comments if c and not re.match(r"^(VSD\b|\w{3} \w{3} \d)", c)), None
        )

    return DirectionalPlan(source_format="text", header=plan_header, survey=survey)


# ── Entry point ──────────────────────────────────────────────────────────────

def extract_plan(filepath) -> DirectionalPlan:
    with open(filepath, "rb") as f:
        raw = f.read()
    if raw.startswith(b"%PDF"):
        return _extract_pdf(filepath)
    return _extract_text(_decode(raw))


def _extract_pdf(filepath) -> DirectionalPlan:
    with pdfplumber.open(filepath) as pdf:
        texts = [page.extract_text() or "" for page in pdf.pages]

    report_pages = [t for t in texts if re.search(r"^Database:", t, re.M)]
    if not report_pages:
        raise ValueError("No COMPASS planning report pages found in that PDF")

    info_page = next((t for t in report_pages if "Well Position" in t), report_pages[0])
    header = _extract_header(texts[0], info_page, "\n".join(report_pages))

    plan_sections, survey, formations, annotations, targets, casing = _extract_sections(report_pages)

    # Annotation coordinates come from the survey station at the same MD.
    for a in annotations:
        station = _station_at(survey, a.md)
        if station:
            a.north_south, a.east_west = station.north_south, station.east_west

    # Formations → prognosis tops. Subsea is the plan's own value at that
    # station (falling back to KB - TVD); isopach is left to FormationTops.
    tops = []
    for md, tvd, name in formations:
        station = _station_at(survey, md)
        subsea = station.subsea if station else (
            round(header.kb_elevation - tvd, 2) if header.kb_elevation is not None else None
        )
        tops.append(FormationTop(
            formation=name,
            prognosis=FormationPick(md=md, tvd=tvd, subsea=subsea),
        ))

    return DirectionalPlan(
        source_format="pdf",
        header=header,
        plan_sections=plan_sections,
        survey=survey,
        tops=Tops(formations=tops),
        annotations=annotations,
        targets=targets,
        casing_points=casing,
    )


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python extract_plan.py <filepath>")
        sys.exit(1)

    # Failures go to stdout as {"error": ...} so the caller can show the reason.
    try:
        result = extract_plan(sys.argv[1])
    except Exception as e:  # noqa: BLE001 — any parse failure is reported, not raised
        print(json.dumps({"error": str(e) or e.__class__.__name__}))
        sys.exit(1)
    print(json.dumps(result.model_dump(), indent=2))
