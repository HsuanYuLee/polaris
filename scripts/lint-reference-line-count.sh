#!/usr/bin/env bash
set -euo pipefail

ROOT="."
REPORT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --report) REPORT=1; shift ;;
    -h|--help)
      echo "Usage: bash scripts/lint-reference-line-count.sh [--report] [ROOT]" >&2
      exit 0
      ;;
    --*) echo "unknown argument: $1" >&2; exit 64 ;;
    *)
      if [[ "$ROOT" != "." ]]; then
        echo "unexpected extra root argument: $1" >&2
        exit 64
      fi
      ROOT="$1"
      shift
      ;;
  esac
done
cd "$ROOT"

LIMIT_FILES=(".claude/skills/references/task-md-schema.md" ".claude/skills/references/engineer-delivery-flow.md" ".claude/rules/context-monitoring.md")
LIMIT_VALUES=(500 500 50)
ALLOWLIST_LIMIT=500

errors=()
for i in "${!LIMIT_FILES[@]}"; do
  file="${LIMIT_FILES[$i]}"
  [[ -f "$file" ]] || { errors+=("missing required reference: $file"); continue; }
  lines="$(wc -l < "$file" | tr -d ' ')"
  limit="${LIMIT_VALUES[$i]}"
  if [[ "$lines" -gt "$limit" ]]; then
    errors+=("$file has $lines lines; limit is $limit")
  fi
done

allowlist=".claude/skills/references/reference-line-count-allowlist.txt"
if [[ -f "$allowlist" ]]; then
  for forbidden in "${LIMIT_FILES[@]}"; do
    if grep -Fxq "$forbidden" "$allowlist"; then
      errors+=("$forbidden must not appear in $allowlist")
    fi
  done
fi

if [[ "$REPORT" == "1" ]]; then
  python3 - "$allowlist" "$ALLOWLIST_LIMIT" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

allowlist = Path(sys.argv[1])
target_limit = int(sys.argv[2])
items = []
if allowlist.exists():
    for raw in allowlist.read_text().splitlines():
        path = raw.strip()
        if not path or path.startswith("#"):
            continue
        file_path = Path(path)
        current_lines = len(file_path.read_text(errors="ignore").splitlines()) if file_path.exists() else 0
        items.append({
            "path": path,
            "current_lines": current_lines,
            "target_limit": target_limit,
            "exceed_by": max(0, current_lines - target_limit),
        })
print(json.dumps(items, ensure_ascii=False, indent=2))
PY
  exit 0
fi

if (( ${#errors[@]} > 0 )); then
  printf 'ERROR: %s\n' "${errors[@]}" >&2
  exit 1
fi

echo "PASS: DP-188 reference line-count limits"
