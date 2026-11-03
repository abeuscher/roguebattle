"""Convert the unit spreadsheet to JSON the game loads.

Usage: python tools/xlsx_to_json.py [path/to/sheet.xlsx]

Writes data/units.json, data/lines.json, data/role_templates.json,
data/mechanics.json and data/data_report.txt. Problems in the sheet are reported, never fixed.
"""
import json
import re
import sys
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
DEFAULT_SHEETS = ["units-landwar-v3.xlsx"]
STATS = ["STR", "CON", "INT", "SPD", "AGI", "PDEF", "MDEF"]
# Columns SPEC §9.1 expects. Missing ones are reported, not invented.
EXPECTED = ["Class", "Stage", "Line(s)", "Size", "Slots", "Can lead", "Alignment lean",
            "Terrain", "Speed tier", "Role", "Key stats", *STATS, "Flex min", "Flex max",
            "Front attack", "Front count", "Back attack", "Back count", "Element",
            "Traits", "Leader aura", "XP rate"]
LIST_COLUMNS = {"Key stats": ",", "Traits": ";"}


def snake(header):
    return re.sub(r"[^a-z0-9]+", "_", header.lower()).strip("_")


def read_rows(ws):
    rows = ws.iter_rows(values_only=True)
    headers = [h for h in next(rows)]
    out = []
    for row in rows:
        if row[0] is None:
            continue
        out.append({h: v for h, v in zip(headers, row) if h is not None})
    return [h for h in headers if h is not None], out


def convert_row(row):
    unit = {}
    for header, value in row.items():
        if header in STATS or header == "Line(s)":
            continue
        if isinstance(value, str):
            value = value.strip()
        if header in LIST_COLUMNS:
            value = [s.strip() for s in (value or "").split(LIST_COLUMNS[header]) if s.strip()]
            if header == "Traits":  # "Mounted: x1.5 ...; Charge: first attack x1.5" -> ["Mounted", "Charge"]
                value = [t.split(":")[0].strip() for t in value if t[0].isupper()]  # lower case continues the previous trait
        elif header == "Leader aura" and value:
            name, _, text = value.partition(":")
            unit["leader_aura_text"] = text.strip()
            value = name.strip()
        elif header == "Can lead":
            value = value == "Yes"
        unit[snake(header)] = value
    unit["base_stats"] = {s: row.get(s) for s in STATS}
    return unit


def parse_lines(rows, problems):
    """Line definitions look like 'R1: A > B > C / D'; references look like '#3'."""
    lines, declared = {}, {}
    for row in rows:
        name = row["Class"]
        declared[name] = set()
        for part in str(row.get("Line(s)") or "").split(";"):
            part = part.strip()
            if not part:
                continue
            if m := re.fullmatch(r"(\w+):\s*(.+)", part):
                line_id, path = m.group(1), m.group(2)
                stages = [[c.strip() for c in s.split("/")] for s in path.split(">")]
                if line_id in lines and lines[line_id] != stages:
                    problems.append(f"Line {line_id} is written differently on '{name}' than elsewhere.")
                lines.setdefault(line_id, stages)
                declared[name].add(line_id)
            elif m := re.fullmatch(r"#(\w+)", part):
                declared[name].add(m.group(1))
            elif part == "All Serf lines":
                declared[name].add("*serf")
            else:
                problems.append(f"'{name}': can't read line entry '{part}'.")
    return lines, declared


def check(units, lines, declared, headers, problems):
    by_name = {u["class"]: u for u in units}
    missing = [h for h in EXPECTED if h not in headers]
    if missing:
        problems.append("Sheet is missing columns the spec expects: " + ", ".join(missing) + ".")
    seen = set()
    for u in units:
        if u["class"] in seen:
            problems.append(f"Class '{u['class']}' appears more than once.")
        seen.add(u["class"])
    serf_lines = {lid for lid, st in lines.items() if st[0] == ["Serf"]}
    for line_id, stages in lines.items():
        prev = None
        for stage in stages:
            for c in stage:
                if c not in by_name:
                    problems.append(f"Line {line_id} names '{c}', which has no row.")
                elif prev is not None and by_name[c]["stage"] != prev + 1:
                    problems.append(f"Line {line_id}: '{c}' is stage {by_name[c]['stage']}, expected {prev + 1}.")
            known = [by_name[c]["stage"] for c in stage if c in by_name]
            prev = known[0] if known else None
    for u in units:
        name = u["class"]
        member = {lid for lid, st in lines.items() if any(name in s for s in st)}
        want = set(declared[name])
        if "*serf" in want:
            want = (want - {"*serf"}) | serf_lines
        if not member:
            problems.append(f"'{name}' is not in any line.")
        elif want != member:
            problems.append(f"'{name}' lists lines {sorted(want)} but appears in {sorted(member)}.")
        u["lines"] = sorted(member, key=line_sort_key)
        stat_sum = sum(v or 0 for v in u["base_stats"].values())
        if u.get("stat_total") is not None and u["stat_total"] != stat_sum:
            problems.append(f"'{name}': Stat total {u['stat_total']} but stats add to {stat_sum}.")
        for col in ("flex_min", "flex_max", "front_count", "back_count", "speed_tier"):
            if u.get(col) is None:
                problems.append(f"'{name}': {col} is empty.")


def line_sort_key(line_id):
    m = re.fullmatch(r"([A-Z]*)(\d+)", line_id)
    return (m.group(1), int(m.group(2))) if m else (line_id, 0)


def main():
    if len(sys.argv) > 1:
        sheet = Path(sys.argv[1])
    else:
        sheet = next((DATA / n for n in DEFAULT_SHEETS if (DATA / n).exists()), DATA / DEFAULT_SHEETS[0])
    wb = openpyxl.load_workbook(sheet, data_only=True)
    problems = []

    headers, rows = read_rows(wb["Units"])
    units = [convert_row(r) for r in rows]
    lines, declared = parse_lines(rows, problems)
    check(units, lines, declared, headers, problems)

    _, role_rows = read_rows(wb["Role templates"])
    roles = {}
    for r in role_rows:
        role = convert_row(r)
        roles[role.pop("role")] = role
    for u in units:
        if u.get("role") not in roles:
            problems.append(f"'{u['class']}': role '{u.get('role')}' has no template.")

    mechanics = {}
    _, mech_rows = read_rows(wb["Mechanics"])
    for r in mech_rows:
        used = [c.strip() for c in str(r.get("Used by") or "").split(",") if c.strip()]
        mechanics[str(r["Mechanic"]).strip()] = {"category": r.get("Category"), "rule": r.get("Rule"),
                                                 "numbers": r.get("Placeholder numbers"), "used_by": used}
        for c in used:
            if c not in {u["class"] for u in units} and c != "All units":
                problems.append(f"Mechanics '{r['Mechanic']}' lists '{c}', which has no row.")

    write(DATA / "units.json", units)
    write(DATA / "mechanics.json", mechanics)
    write(DATA / "lines.json", {k: lines[k] for k in sorted(lines, key=line_sort_key)})
    write(DATA / "role_templates.json", roles)
    report = [f"Source: {sheet.name}", f"Classes: {len(units)}", f"Lines: {len(lines)}",
              f"Role templates: {len(roles)}", f"Problems: {len(problems)}", ""]
    report += [f"- {p}" for p in problems]
    (DATA / "data_report.txt").write_text("\n".join(report) + "\n", encoding="utf-8")
    print("\n".join(report))


def write(path, obj):
    path.write_text(json.dumps(obj, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
