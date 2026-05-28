#!/usr/bin/env bash
# lint-skill-size.sh — DP-237 T5 deterministic gate.
#
# 對 `.claude/skills/{skill}/SKILL.md` 維持 per-skill line-count cap，避免 thin SKILL
# 設計被偷渡擴張回胖 prompt。結構刻意 mirror `scripts/lint-reference-line-count.sh`：
# 用 inline LIMIT_FILES / LIMIT_VALUES parallel arrays 描述 cap，新增 skill 時直接擴張
# 陣列即可，不需改 control flow。
#
# Usage:
#   bash scripts/lint-skill-size.sh [--report] [ROOT]
#
# Exit:
#   0 PASS (或 --report 模式列印 JSON 報表)
#   1 任一 LIMIT_FILES 超 cap、或檔案缺少
#
# 參考：
#   - .claude/rules/mechanism-registry.md `skill-size-policy` script_candidate entry
#   - .claude/skills/auto-pass/SKILL.md ≤ 120 行 (DP-237 D7 / AC6)
#   - scripts/lint-reference-line-count.sh (canonical pattern)

set -euo pipefail

ROOT="."
REPORT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --report) REPORT=1; shift ;;
    -h|--help)
      echo "Usage: bash scripts/lint-skill-size.sh [--report] [ROOT]" >&2
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

# Per-skill caps. Order between LIMIT_FILES and LIMIT_VALUES must stay aligned;
# selftest fixture parses these arrays so structural changes propagate to tests
# automatically.
LIMIT_FILES=(".claude/skills/auto-pass/SKILL.md")
LIMIT_VALUES=(120)

errors=()
for i in "${!LIMIT_FILES[@]}"; do
  file="${LIMIT_FILES[$i]}"
  limit="${LIMIT_VALUES[$i]}"
  if [[ ! -f "$file" ]]; then
    errors+=("missing required skill: $file")
    continue
  fi
  lines="$(wc -l < "$file" | tr -d ' ')"
  if [[ "$lines" -gt "$limit" ]]; then
    errors+=("$file has $lines lines; limit is $limit")
  fi
done

if [[ "$REPORT" == "1" ]]; then
  python3 - "${LIMIT_FILES[@]}" --values "${LIMIT_VALUES[@]}" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

args = sys.argv[1:]
sep = args.index("--values")
files = args[:sep]
values = [int(v) for v in args[sep + 1:]]

items = []
for path, limit in zip(files, values):
    file_path = Path(path)
    current_lines = (
        len(file_path.read_text(errors="ignore").splitlines())
        if file_path.exists()
        else 0
    )
    items.append(
        {
            "path": path,
            "current_lines": current_lines,
            "limit": limit,
            "exceed_by": max(0, current_lines - limit),
        }
    )
print(json.dumps(items, ensure_ascii=False, indent=2))
PY
  exit 0
fi

if (( ${#errors[@]} > 0 )); then
  printf 'ERROR: %s\n' "${errors[@]}" >&2
  exit 1
fi

echo "PASS: skill-size policy (DP-237 AC6, ${#LIMIT_FILES[@]} skill(s) within cap)"
