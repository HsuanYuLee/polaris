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

extract_markdown_section() {
  local file="$1"
  local heading="$2"
  awk -v heading="$heading" '
    $0 == heading { in_section=1; next }
    /^## / && in_section { exit }
    in_section { print }
  ' "$file"
}

extract_first_fenced_code_block() {
  awk '
    /^```/ {
      if (in_block == 0) { in_block=1; next }
      exit
    }
    in_block { print }
  '
}

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
  "## Verify Command"
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

  if ! grep -qE '^\*\*Runtime verify target\*\*: .+' "$FILE" \
     && ! grep -qE '^- \*\*Runtime verify target\*\*: .+' "$FILE"; then
    errors+=("Test Environment section missing Runtime verify target line: expected '- **Runtime verify target**: {url|N/A}'")
  fi

  if ! grep -qE '^\*\*Env bootstrap command\*\*: .+' "$FILE" \
     && ! grep -qE '^- \*\*Env bootstrap command\*\*: .+' "$FILE"; then
    errors+=("Test Environment section missing Env bootstrap command line: expected '- **Env bootstrap command**: {command|N/A}'")
  else
    level_line=$(grep -E '^\*\*Level\*\*: |^- \*\*Level\*\*: ' "$FILE" | head -n1 || true)
    target_line=$(grep -E '^\*\*Runtime verify target\*\*: |^- \*\*Runtime verify target\*\*: ' "$FILE" | head -n1 || true)
    bootstrap_line=$(grep -E '^\*\*Env bootstrap command\*\*: |^- \*\*Env bootstrap command\*\*: ' "$FILE" | head -n1 || true)
    level=$(echo "$level_line" | sed -E 's/.*\*\*Level\*\*: *([a-z]+).*/\1/' | tr '[:upper:]' '[:lower:]')
    target=$(echo "$target_line" | sed -E 's/.*\*\*Runtime verify target\*\*: *//' | tr -d '\r')
    bootstrap=$(echo "$bootstrap_line" | sed -E 's/.*\*\*Env bootstrap command\*\*: *//' | tr -d '\r')

    if [[ "$level" == "runtime" ]]; then
      if [[ -z "$target" || "$target" == "N/A" || "$target" == "n/a" ]]; then
        errors+=("Level=runtime requires non-N/A Runtime verify target")
      fi
      if [[ -z "$bootstrap" || "$bootstrap" == "N/A" || "$bootstrap" == "n/a" ]]; then
        errors+=("Level=runtime requires non-N/A Env bootstrap command")
      fi

      normalized_target=$(echo "$target" | sed -E 's/^`|`$//g' | xargs)
      if ! echo "$normalized_target" | grep -Eq '^https?://'; then
        errors+=("Level=runtime requires Runtime verify target to be a live URL (http/https)")
      fi

      verify_section=$(extract_markdown_section "$FILE" "## Verify Command")
      verify_cmd=$(printf '%s\n' "$verify_section" | extract_first_fenced_code_block)
      verify_cmd_compact=$(echo "$verify_cmd" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g' | xargs || true)

      if [[ -z "$verify_cmd_compact" ]]; then
        errors+=("Verify Command section missing executable code block")
      else
        verify_url=$(python3 -c "import re,sys; s=sys.stdin.read(); m=re.search(r'https?://[^\\s\"\\'\\)]+', s); print(m.group(0) if m else '')" <<< "$verify_cmd_compact")
        if [[ -z "$verify_url" ]]; then
          errors+=("Level=runtime requires Verify Command to hit a live endpoint URL (http/https)")
        else
          target_host=$(python3 -c "from urllib.parse import urlparse; import sys; u=sys.argv[1]; print((urlparse(u).hostname or '').lower())" "$normalized_target" 2>/dev/null || true)
          verify_host=$(python3 -c "from urllib.parse import urlparse; import sys; u=sys.argv[1]; print((urlparse(u).hostname or '').lower())" "$verify_url" 2>/dev/null || true)
          if [[ -z "$target_host" || -z "$verify_host" ]]; then
            errors+=("unable to parse host from Runtime verify target or Verify Command URL")
          elif [[ "$target_host" != "$verify_host" ]]; then
            errors+=("Level=runtime requires Verify Command URL host ($verify_host) to match Runtime verify target host ($target_host)")
          fi
        fi
      fi
    elif [[ "$level" == "static" || "$level" == "build" ]]; then
      if [[ "$target" != "N/A" && "$target" != "n/a" ]]; then
        errors+=("Level=$level expects Runtime verify target to be N/A")
      fi
      if [[ "$bootstrap" != "N/A" && "$bootstrap" != "n/a" ]]; then
        errors+=("Level=$level expects Env bootstrap command to be N/A")
      fi
    fi
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
