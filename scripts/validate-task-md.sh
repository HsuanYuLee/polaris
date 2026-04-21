#!/usr/bin/env bash
# validate-task-md.sh — schema validator for task.md work orders produced by breakdown.
#
# Usage: validate-task-md.sh <path/to/task.md>
# Exit:  0 = schema pass
#        1 = schema violations (details printed to stderr)
#        2 = usage error / file not found
#
# Contract source: skills/references/pipeline-handoff.md § task.md Schema
# Called by:       skills/breakdown/SKILL.md Step 14.5 (after Write)

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <task.md path>" >&2
  exit 2
fi

FILE="$1"

if [[ ! -f "$FILE" ]]; then
  echo "error: file not found: $FILE" >&2
  exit 2
fi

errors=()

# --- Header: # T{n}[suffix]: {summary} ({SP} pt) ---
# Suffix (a-z*) supports split subtasks (e.g. T8a, T8b) without renumbering siblings.
if ! grep -qE '^# T[0-9]+[a-z]*: .+\([0-9.]+ ?pt\)' "$FILE"; then
  errors+=("missing or malformed header: expected '# T{n}[suffix]: {summary} ({SP} pt)'")
fi

# --- Metadata quote line: > Epic: ... | JIRA: {KEY} | Repo: ... ---
# JIRA key is mandatory; Epic optional (single-ticket flow omits it)
if ! grep -qE '^> .*JIRA: [A-Z][A-Z0-9]*-[0-9]+' "$FILE"; then
  errors+=("missing metadata line: expected '> Epic: ... | JIRA: {KEY} | Repo: ...' with non-empty JIRA key")
fi
if ! grep -qE '^> .*Repo: \S+' "$FILE"; then
  errors+=("missing Repo in metadata line")
fi

# --- Required sections ---
required_sections=(
  "## Operational Context"
  "## Verification Handoff"
  "## 目標"
  "## 改動範圍"
  "## 估點理由"
  "## 測試計畫"
  "## Test Command"
  "## Test Environment"
)
for section in "${required_sections[@]}"; do
  if ! grep -qF "$section" "$FILE"; then
    errors+=("missing section: $section")
  fi
done

# --- Test Environment Level (must be static | build | runtime) ---
if grep -qF "## Test Environment" "$FILE"; then
  if ! grep -qE '^\*\*Level\*\*: (static|build|runtime)\b' "$FILE" \
     && ! grep -qE '^- \*\*Level\*\*: (static|build|runtime)\b' "$FILE"; then
    errors+=("Test Environment section missing or malformed Level line: expected '- **Level**: {static|build|runtime}'")
  fi
fi

# --- Operational Context required fields (must appear as table cells) ---
required_fields=(
  "Task JIRA key"
  "Parent Epic"
  "Test sub-tasks"
  "AC 驗收單"
  "Base branch"
  "Task branch"
  "References to load"
)
for field in "${required_fields[@]}"; do
  if ! grep -qF "$field" "$FILE"; then
    errors+=("missing Operational Context field: $field")
  fi
done

# --- Report ---
if [[ ${#errors[@]} -eq 0 ]]; then
  exit 0
fi

echo "✗ task.md schema violations in $FILE:" >&2
for err in "${errors[@]}"; do
  echo "  - $err" >&2
done
echo "" >&2
echo "Contract: skills/references/pipeline-handoff.md § task.md Schema" >&2
exit 1
