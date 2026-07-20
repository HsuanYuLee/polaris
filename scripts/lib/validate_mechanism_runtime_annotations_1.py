"""Structured validator authority extracted from scripts/validate-mechanism-runtime-annotations.sh."""

from __future__ import annotations

import re
import sys
from pathlib import Path

registry = Path(sys.argv[1])
root = Path.cwd()
text = registry.read_text()

required_hooks = sorted(str(path) for path in Path(".claude/hooks").glob("*.sh"))

section = []
capture = False
for line in text.splitlines():
    if line.strip() == "## Runtime Annotation Registry":
        capture = True
        continue
    if capture and line.startswith("## "):
        break
    if capture:
        section.append(line)

if not section:
    print("missing ## Runtime Annotation Registry", file=sys.stderr)
    sys.exit(1)

rows = []
for line in section:
    stripped = line.strip()
    if not stripped.startswith("|"):
        continue
    cells = [cell.strip().strip("`") for cell in stripped.strip("|").split("|")]
    if cells and all(
        re.fullmatch(r":?-{3,}:?", cell.replace(" ", "")) for cell in cells
    ):
        continue
    rows.append(cells)

if len(rows) < 2:
    print("runtime annotation table has no data rows", file=sys.stderr)
    sys.exit(1)

header = [cell.lower() for cell in rows[0]]
required_cols = [
    "mechanism",
    "path",
    "kind",
    "runtime",
    "fallback_script",
    "governance_role",
]
missing = [col for col in required_cols if col not in header]
if missing:
    print(
        f"runtime annotation table missing columns: {', '.join(missing)}",
        file=sys.stderr,
    )
    sys.exit(1)

idx = {col: header.index(col) for col in required_cols}
seen_paths = set()
errors = []

for row_no, row in enumerate(rows[1:], start=2):
    if len(row) < len(header):
        errors.append(f"row {row_no}: malformed row")
        continue
    mechanism = row[idx["mechanism"]].strip()
    path = row[idx["path"]].strip()
    kind = row[idx["kind"]].strip()
    runtime = row[idx["runtime"]].strip()
    fallback = row[idx["fallback_script"]].strip()
    role = row[idx["governance_role"]].strip()

    if not mechanism:
        errors.append(f"row {row_no}: mechanism is empty")
    if not path:
        errors.append(f"row {row_no}: path is empty")
    else:
        seen_paths.add(path)
        if (
            path != "N/A"
            and not any(ch in path for ch in "*?[]")
            and not (root / path).exists()
        ):
            errors.append(f"row {row_no}: path does not exist: {path}")
    if kind not in {"hook", "script", "mechanism", "workflow"}:
        errors.append(f"row {row_no}: unsupported kind: {kind}")
    if runtime not in {"portable", "claude-code-only"}:
        errors.append(f"row {row_no}: unsupported runtime: {runtime}")
    if not role:
        errors.append(f"row {row_no}: governance_role is empty")
    if runtime == "claude-code-only" and role != "ux_enhancement_only":
        if not fallback or fallback == "N/A":
            errors.append(
                f"row {row_no}: claude-code-only governance mechanism requires fallback_script"
            )
        elif not (root / fallback).exists():
            errors.append(f"row {row_no}: fallback_script does not exist: {fallback}")

missing_hooks = [path for path in required_hooks if path not in seen_paths]
if missing_hooks:
    errors.append("missing hook runtime annotations: " + ", ".join(missing_hooks))

if errors:
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    sys.exit(1)

print(f"PASS: runtime annotations valid ({len(rows) - 1} rows)")
