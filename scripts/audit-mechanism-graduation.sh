#!/usr/bin/env bash
set -euo pipefail

PREFIX="[mechanism-graduation]"
REGISTRY="${1:-.claude/rules/mechanism-registry.md}"

[[ -f "$REGISTRY" ]] || { echo "$PREFIX registry not found: $REGISTRY" >&2; exit 2; }

python3 - "$REGISTRY" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

registry = Path(sys.argv[1])
text = registry.read_text()
allowed_milestones = {"M1", "M2", "M3", "M-future"}

section = []
capture = False
for line in text.splitlines():
    if line.strip() == "## Script Candidate Graduation Schedule":
        capture = True
        continue
    if capture and line.startswith("## "):
        break
    if capture:
        section.append(line)

if not section:
    print("missing ## Script Candidate Graduation Schedule", file=sys.stderr)
    sys.exit(1)

rows = []
for line in section:
    stripped = line.strip()
    if not stripped.startswith("|"):
        continue
    cells = [cell.strip().strip("`") for cell in stripped.strip("|").split("|")]
    if cells and all(re.fullmatch(r":?-{3,}:?", cell.replace(" ", "")) for cell in cells):
        continue
    rows.append(cells)

if len(rows) < 2:
    print("graduation schedule has no data rows", file=sys.stderr)
    sys.exit(1)

header = [cell.lower() for cell in rows[0]]
required_cols = ["mechanism", "disposition", "graduation_milestone", "owner"]
missing = [col for col in required_cols if col not in header]
if missing:
    print(f"graduation schedule missing columns: {', '.join(missing)}", file=sys.stderr)
    sys.exit(1)

idx = {col: header.index(col) for col in required_cols}
errors = []
candidate_count = 0
future_count = 0

for row_no, row in enumerate(rows[1:], start=2):
    if len(row) < len(header):
        errors.append(f"row {row_no}: malformed row")
        continue
    disposition = row[idx["disposition"]].strip()
    if disposition != "script_candidate":
        continue
    candidate_count += 1
    milestone = row[idx["graduation_milestone"]].strip()
    owner = row[idx["owner"]].strip()
    if milestone not in allowed_milestones:
        errors.append(f"row {row_no}: invalid graduation_milestone: {milestone}")
    if milestone == "M-future":
        future_count += 1
    if not owner:
        errors.append(f"row {row_no}: owner is empty")

if candidate_count == 0:
    errors.append("no script_candidate rows found in graduation schedule")
elif future_count / candidate_count > 0.40:
    errors.append(f"M-future ratio too high: {future_count}/{candidate_count} > 40%")

if errors:
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    sys.exit(1)

print(f"PASS: script_candidate graduation schedule valid ({candidate_count} candidates, {future_count} M-future)")
PY
