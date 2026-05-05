#!/usr/bin/env bash
# Validate Design Plan number uniqueness across active and archive namespaces.

set -euo pipefail

specs_root="docs-manager/src/content/docs/specs"
mode="hard"
plan_scope=""

usage() {
  cat >&2 <<'EOF'
usage: validate-dp-number-uniqueness.sh [--specs-root <path>] [--report] [--plan <plan.md>]

Default mode hard-fails on any duplicate DP number found in active or archive.
--report prints the duplicate inventory but exits 0.
--plan only hard-fails when the supplied plan's DP number is duplicated.
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --specs-root)
      specs_root="${2:-}"
      shift 2
      ;;
    --report)
      mode="report"
      shift
      ;;
    --plan)
      plan_scope="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      ;;
  esac
done

python3 - "$specs_root" "$mode" "$plan_scope" <<'PY'
import re
import sys
from collections import defaultdict
from pathlib import Path

specs_root = Path(sys.argv[1])
mode = sys.argv[2]
plan_scope = Path(sys.argv[3]) if sys.argv[3] else None
base = specs_root / "design-plans"

if plan_scope and not plan_scope.exists():
    print(f"error: plan not found: {plan_scope}", file=sys.stderr)
    sys.exit(2)

entries = defaultdict(list)
if base.exists():
    for plan in sorted(base.glob("DP-*/plan.md")) + sorted((base / "archive").glob("DP-*/plan.md")):
        match = re.match(r"DP-(\d+)", plan.parent.name)
        if not match:
            continue
        namespace = "archive" if plan.parent.parent.name == "archive" else "active"
        rel = plan.parent.relative_to(base).as_posix()
        entries[f"DP-{int(match.group(1)):03d}"].append((namespace, rel, plan))

duplicates = {number: rows for number, rows in entries.items() if len(rows) > 1}

if duplicates:
    print("DP number\tcollision type\tcontainers")
    for number, rows in sorted(duplicates.items()):
        namespaces = {row[0] for row in rows}
        if namespaces == {"active"}:
            collision = "active + active"
        elif namespaces == {"archive"}:
            collision = "archive + archive"
        else:
            collision = "active + archive"
        containers = ", ".join(row[1] for row in rows)
        print(f"{number}\t{collision}\t{containers}")

if mode == "report":
    if not duplicates:
        print("PASS: DP number uniqueness report has no duplicates")
    sys.exit(0)

if plan_scope:
    match = re.match(r"DP-(\d+)", plan_scope.parent.name)
    if not match:
        print(f"error: plan path is not inside a DP-NNN container: {plan_scope}", file=sys.stderr)
        sys.exit(2)
    scoped_number = f"DP-{int(match.group(1)):03d}"
    if scoped_number in duplicates:
        print(f"error: {scoped_number} is duplicated; cannot validate {plan_scope}", file=sys.stderr)
        sys.exit(1)
    print(f"PASS: DP number unique for {scoped_number}")
    sys.exit(0)

if duplicates:
    sys.exit(1)

print("PASS: DP number uniqueness")
PY
