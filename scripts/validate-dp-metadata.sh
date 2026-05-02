#!/usr/bin/env bash
# Validate Design Plan lifecycle and Starlight sidebar metadata.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: validate-dp-metadata.sh [file-or-directory...]

Default path:
  docs-manager/src/content/docs/specs/design-plans

Use scripts/sync-spec-sidebar-metadata.sh --apply to repair deterministic drift.
EOF
  exit 2
}

paths=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      usage
      ;;
    *)
      paths+=("$1")
      shift
      ;;
  esac
done

if [[ ${#paths[@]} -eq 0 ]]; then
  paths=("docs-manager/src/content/docs/specs/design-plans")
fi

python3 - "${paths[@]}" <<'PY'
import re
import sys
from pathlib import Path

inputs = [Path(p) for p in sys.argv[1:]]

VALID_STATUSES = {"SEEDED", "DISCUSSION", "LOCKED", "IMPLEMENTING", "IMPLEMENTED", "ABANDONED"}
VALID_PRIORITIES = {"P0", "P1", "P2", "P3", "P4"}
VALID_VARIANTS = {"note", "tip", "caution", "danger", "success"}


def plan_files(path: Path):
    if not path.exists():
        print(f"error: path not found: {path}", file=sys.stderr)
        sys.exit(2)
    if path.is_file():
        if path.name == "plan.md":
            yield path
        return
    for file in sorted(path.rglob("plan.md")):
        if "/design-plans/" in file.as_posix() or file.as_posix().endswith("/design-plans/plan.md"):
            yield file


def strip_quotes(value: str) -> str:
    value = value.strip()
    if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
        return value[1:-1]
    return value


def parse_frontmatter(path: Path):
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].strip() != "---":
        return None, ["missing frontmatter"]
    end = None
    for idx in range(1, len(lines)):
        if lines[idx].strip() == "---":
            end = idx
            break
    if end is None:
        return None, ["unterminated frontmatter"]

    data = {}
    errors = []
    idx = 1
    while idx < end:
        line = lines[idx]
        if line.startswith("sidebar:"):
            sidebar = {}
            idx += 1
            while idx < end:
                current = lines[idx]
                if not current.startswith("  "):
                    break
                if current.startswith("  label:"):
                    sidebar["label"] = strip_quotes(current.split(":", 1)[1])
                elif current.startswith("  order:"):
                    sidebar["order"] = strip_quotes(current.split(":", 1)[1])
                elif current.startswith("  badge:"):
                    badge = {}
                    idx += 1
                    while idx < end and lines[idx].startswith("    "):
                        child = lines[idx]
                        if child.startswith("    text:"):
                            badge["text"] = strip_quotes(child.split(":", 1)[1])
                        elif child.startswith("    variant:"):
                            badge["variant"] = strip_quotes(child.split(":", 1)[1])
                        idx += 1
                    sidebar["badge"] = badge
                    continue
                idx += 1
            data["sidebar"] = sidebar
            continue
        if ":" in line and not line.startswith((" ", "\t")):
            key, value = line.split(":", 1)
            data[key.strip()] = strip_quotes(value)
        idx += 1

    return data, errors


def dp_number(path: Path):
    for part in reversed(path.parts):
        match = re.match(r"DP-(\d+)", part)
        if match:
            return int(match.group(1))
    return None


def add(rows, path, issue, detail):
    rows.append((str(path), issue, detail))


files = []
seen = set()
for input_path in inputs:
    for file in plan_files(input_path):
        resolved = file.resolve()
        if resolved not in seen:
            seen.add(resolved)
            files.append(file)

if not files:
    print("error: no Design Plan plan.md files found", file=sys.stderr)
    sys.exit(2)

rows = []
for file in files:
    data, parse_errors = parse_frontmatter(file)
    for error in parse_errors:
        add(rows, file, error, "run sync-spec-sidebar-metadata.sh after fixing frontmatter")
    if data is None:
        continue

    status = data.get("status", "")
    priority = data.get("priority", "")
    sidebar = data.get("sidebar", {})
    badge = sidebar.get("badge", {}) if isinstance(sidebar, dict) else {}
    order = sidebar.get("order") if isinstance(sidebar, dict) else None
    expected_order = dp_number(file)

    if status == "SEED":
        add(rows, file, "legacy-status", "use SEEDED instead of SEED")
    elif status not in VALID_STATUSES:
        add(rows, file, "invalid-status", f"got {status!r}")

    if priority not in VALID_PRIORITIES:
        add(rows, file, "invalid-priority", f"got {priority!r}")

    if not sidebar:
        add(rows, file, "missing-sidebar", "frontmatter must include sidebar metadata")
    else:
        if not sidebar.get("label"):
            add(rows, file, "missing-sidebar-label", "sidebar.label is required")
        if order is None:
            add(rows, file, "missing-sidebar-order", "sidebar.order is required")
        elif expected_order is not None and str(order) != str(expected_order):
            add(rows, file, "wrong-sidebar-order", f"expected {expected_order}, got {order}")
        text = badge.get("text")
        variant = badge.get("variant")
        if not text:
            add(rows, file, "missing-sidebar-badge-text", "sidebar.badge.text is required")
        elif status and priority and text != f"{status} / {priority}":
            add(rows, file, "wrong-sidebar-badge-text", f"expected {status} / {priority}, got {text}")
        if variant not in VALID_VARIANTS:
            add(rows, file, "invalid-sidebar-badge-variant", f"got {variant!r}")

if rows:
    print("path\tissue\tdetail", file=sys.stderr)
    for row in rows:
        print("\t".join(row), file=sys.stderr)
    sys.exit(1)

print(f"PASS: DP metadata validation ({len(files)} file(s))")
PY
