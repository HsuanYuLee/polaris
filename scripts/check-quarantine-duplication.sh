#!/usr/bin/env bash
set -euo pipefail

SOT=".claude/skills/references/plugin-workflow-quarantine.md"
[[ -f "$SOT" ]] || { echo "ERROR: missing quarantine SoT: $SOT" >&2; exit 1; }

phrase="OpenAI-curated and marketplace plugin-contributed skills are adapter surfaces"
count="$(rg -nF "$phrase" .claude CLAUDE.md 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$count" != "1" ]]; then
  echo "ERROR: quarantine canonical phrase must appear exactly once; found $count" >&2
  exit 1
fi

for file in .claude/rules/skill-routing.md CLAUDE.md; do
  [[ -f "$file" ]] || continue
  if grep -Fq "$phrase" "$file"; then
    echo "ERROR: quarantine canonical text leaked into pointer surface: $file" >&2
    exit 1
  fi
done

echo "PASS: plugin workflow quarantine SoT is unique"
