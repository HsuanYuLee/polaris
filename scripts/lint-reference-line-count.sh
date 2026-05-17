#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

LIMIT_FILES=(".claude/skills/references/task-md-schema.md" ".claude/skills/references/engineer-delivery-flow.md" ".claude/rules/context-monitoring.md")
LIMIT_VALUES=(500 500 50)

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

if (( ${#errors[@]} > 0 )); then
  printf 'ERROR: %s\n' "${errors[@]}" >&2
  exit 1
fi

echo "PASS: DP-188 reference line-count limits"
