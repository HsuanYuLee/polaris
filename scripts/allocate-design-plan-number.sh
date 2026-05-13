#!/usr/bin/env bash
# Allocate the next Design Plan number across active and archive namespaces.

set -euo pipefail

specs_root="docs-manager/src/content/docs/specs"

usage() {
  cat >&2 <<'EOF'
usage: allocate-design-plan-number.sh [--specs-root <path>]

Prints the next DP-NNN number after scanning parent plan.md/index.md files in
both design-plans/DP-* and design-plans/archive/DP-*.
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --specs-root)
      specs_root="${2:-}"
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

python3 - "$specs_root" <<'PY'
import re
import sys
from pathlib import Path

specs_root = Path(sys.argv[1])
base = specs_root / "design-plans"
if not base.exists():
    print("DP-001")
    sys.exit(0)

max_number = 0
seen = set()
for parent in list(base.glob("DP-*")) + list((base / "archive").glob("DP-*")):
    if not parent.is_dir():
        continue
    if not ((parent / "index.md").is_file() or (parent / "plan.md").is_file()):
        continue
    match = re.match(r"DP-(\d+)", parent.name)
    if match and parent not in seen:
        seen.add(parent)
        max_number = max(max_number, int(match.group(1)))

print(f"DP-{max_number + 1:03d}")
PY
