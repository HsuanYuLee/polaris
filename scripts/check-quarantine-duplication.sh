#!/usr/bin/env bash
# Purpose: 確認 plugin workflow quarantine canonical prose 只存在於 SoT，
#          並且不被複製到 pointer surfaces。
# Inputs:  無；固定掃 .claude 與 CLAUDE.md。
# Outputs: PASS 或 ERROR；exit 0/1。
set -euo pipefail

SOT=".claude/skills/references/plugin-workflow-quarantine.md"
[[ -f "$SOT" ]] || { echo "ERROR: missing quarantine SoT: $SOT" >&2; exit 1; }

phrase="OpenAI-curated and marketplace plugin-contributed skills are adapter surfaces"
count="$(rg --no-ignore -nF "$phrase" .claude CLAUDE.md 2>/dev/null | wc -l | tr -d ' ')"
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
