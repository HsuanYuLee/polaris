#!/usr/bin/env bash
# validate-task-md.sh — schema validator for task.md work orders produced by breakdown.
#
# Usage:
#   validate-task-md.sh <path/to/task.md>
#   validate-task-md.sh --scan <workspace_root>
#
# Exit:  0 = schema pass (single) / scan complete (scan mode, always 0)
#        1 = schema violations (single mode; details printed to stderr)
#        2 = usage error / file not found
#
# Contract source: skills/references/pipeline-handoff.md § Artifact Schemas — task.md
# Called by:       skills/breakdown/SKILL.md Step 14.5 (after Write)
#                  .claude/hooks/pipeline-artifact-gate.sh (PreToolUse hook)
#
# DP-023 enforces runtime contract fields (Level / Runtime verify target / Env bootstrap).
# DP-025 extends to non-runtime required sections (Operational Context JIRA keys, 改動範圍
# non-empty, 估點理由 non-empty) and adds --scan mode.
# DP-028 adds cross-field rule for `Depends on` + `Base branch`: when Depends on is non-empty
# (not "N/A" / "-" / whitespace), Base branch must start with `task/` (stacked PR).

set -euo pipefail

usage() {
  cat >&2 <<EOF
usage: $0 <path/to/task.md>
       $0 --scan <workspace_root>
EOF
  exit 2
}

if [[ $# -lt 1 ]]; then
  usage
fi

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

# Extract the value cell of an Operational Context table row.
# task.md convention: `| {field} | {value} |` — the first match wins.
# Returns the trimmed value (no leading/trailing whitespace, no trailing `|`).
# Returns empty string if the field is not present.
extract_op_ctx_field() {
  local file="$1"
  local field="$2"
  # Match rows like "| Depends on | KB2CW-3711 ... |" — allow surrounding whitespace around the field name.
  awk -v field="$field" '
    BEGIN {
      # Build regex for the field cell: start of row = `|`, optional spaces, field, optional spaces, `|`
      # We match literally via split + trim.
    }
    /^\|/ {
      # Split on `|`; task.md uses exactly two content columns, so fields[2] = name, fields[3] = value
      n = split($0, fields, "|")
      if (n < 4) next
      name = fields[2]
      val  = fields[3]
      # Trim leading/trailing whitespace
      sub(/^[[:space:]]+/, "", name); sub(/[[:space:]]+$/, "", name)
      sub(/^[[:space:]]+/, "", val);  sub(/[[:space:]]+$/, "", val)
      if (name == field) {
        print val
        exit
      }
    }
  ' "$file"
}

# Returns 0 (pass) / 1 (fail) / 2 (file not found). Writes errors to stderr.
validate_file() {
  local FILE="$1"
  if [[ ! -f "$FILE" ]]; then
    echo "error: file not found: $FILE" >&2
    return 2
  fi

  local errors=()

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

  # --- Required sections (existence) ---
  local required_sections=(
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
  local section
  for section in "${required_sections[@]}"; do
    if ! grep -qF "$section" "$FILE"; then
      errors+=("missing section: $section")
    fi
  done

  # --- DP-025: Non-empty content checks for human-authored sections ---
  local section_non_empty
  check_section_non_empty() {
    local heading="$1"
    if ! grep -qF "$heading" "$FILE"; then
      return  # missing section already reported above
    fi
    local body
    body=$(extract_markdown_section "$FILE" "$heading")
    # "Non-empty" = at least one line of actual content beyond blockquote markers, blank lines,
    # and the leading commentary. Count lines that have real text.
    local content_lines
    content_lines=$(printf '%s\n' "$body" | awk '
      /^\s*$/ { next }                         # skip blank
      /^\s*>/ { next }                         # skip blockquote commentary
      { count++ }
      END { print count+0 }
    ')
    if [[ "$content_lines" -eq 0 ]]; then
      errors+=("section '$heading' is empty (expected at least 1 line of content)")
    fi
  }

  check_section_non_empty "## 目標"
  check_section_non_empty "## 改動範圍"
  check_section_non_empty "## 估點理由"

  # --- DP-025: Operational Context must contain ≥ 1 JIRA key pattern ---
  if grep -qF "## Operational Context" "$FILE"; then
    local op_ctx
    op_ctx=$(extract_markdown_section "$FILE" "## Operational Context")
    if ! printf '%s' "$op_ctx" | grep -qE '[A-Z][A-Z0-9]+-[0-9]+'; then
      errors+=("Operational Context section missing JIRA key (pattern [A-Z][A-Z0-9]+-[0-9]+)")
    fi
  fi

  # --- DP-023: Test Environment Level (must be static | build | runtime) ---
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
      local level_line target_line bootstrap_line level target bootstrap
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

        local normalized_target
        normalized_target=$(echo "$target" | sed -E 's/^`|`$//g' | xargs)
        if ! echo "$normalized_target" | grep -Eq '^https?://'; then
          errors+=("Level=runtime requires Runtime verify target to be a live URL (http/https)")
        fi

        local verify_section verify_cmd verify_cmd_compact
        verify_section=$(extract_markdown_section "$FILE" "## Verify Command")
        verify_cmd=$(printf '%s\n' "$verify_section" | extract_first_fenced_code_block)
        verify_cmd_compact=$(echo "$verify_cmd" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g' | xargs || true)

        if [[ -z "$verify_cmd_compact" ]]; then
          errors+=("Verify Command section missing executable code block")
        else
          local verify_url target_host verify_host
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
  local required_fields=(
    "Task JIRA key"
    "Parent Epic"
    "Test sub-tasks"
    "AC 驗收單"
    "Base branch"
    "Task branch"
    "References to load"
  )
  local field
  for field in "${required_fields[@]}"; do
    if ! grep -qF "$field" "$FILE"; then
      errors+=("missing Operational Context field: $field")
    fi
  done

  # --- DP-028: Cross-field rule — Depends on (non-empty) ⇒ Base branch must be task/... ---
  # When `Depends on` row has a real value (not N/A / - / empty / whitespace), the task is
  # stacked on a dependency's task branch — `Base branch` must start with `task/`.
  local depends_on_val base_branch_val
  depends_on_val=$(extract_op_ctx_field "$FILE" "Depends on")
  base_branch_val=$(extract_op_ctx_field "$FILE" "Base branch")
  # Treat these as "no dependency" sentinels (case-insensitive)
  local deps_normalized
  deps_normalized=$(echo "$depends_on_val" | tr '[:upper:]' '[:lower:]' | xargs || true)
  if [[ -n "$deps_normalized" \
        && "$deps_normalized" != "n/a" \
        && "$deps_normalized" != "-" \
        && "$deps_normalized" != "無" \
        && "$deps_normalized" != "none" ]]; then
    # Depends on is non-empty → Base branch must be a task/ branch
    if [[ -z "$base_branch_val" ]]; then
      errors+=("[FAIL] $FILE: depends_on non-empty but Base branch is not a task/ branch (found: <empty>). See DP-028.")
    elif [[ "$base_branch_val" != task/* ]]; then
      errors+=("[FAIL] $FILE: depends_on non-empty but Base branch is not a task/ branch (found: $base_branch_val). See DP-028.")
    fi
  fi

  # --- DP-025: Test Command / Verify Command must contain a fenced code block ---
  local test_cmd verify_cmd
  test_cmd=$(extract_markdown_section "$FILE" "## Test Command" | extract_first_fenced_code_block | tr -d '[:space:]')
  if [[ -z "$test_cmd" ]]; then
    errors+=("Test Command section missing executable code block")
  fi
  if grep -qF "## Verify Command" "$FILE"; then
    verify_cmd=$(extract_markdown_section "$FILE" "## Verify Command" | extract_first_fenced_code_block | tr -d '[:space:]')
    if [[ -z "$verify_cmd" ]]; then
      errors+=("Verify Command section missing executable code block")
    fi
  fi

  # --- Report ---
  if [[ ${#errors[@]} -eq 0 ]]; then
    return 0
  fi

  echo "✗ task.md schema violations in $FILE:" >&2
  local err
  for err in "${errors[@]}"; do
    echo "  - $err" >&2
  done
  echo "" >&2
  echo "Contract: skills/references/pipeline-handoff.md § Artifact Schemas — task.md" >&2
  return 1
}

# --- Scan mode ---
if [[ "$1" == "--scan" ]]; then
  if [[ $# -ne 2 ]]; then
    usage
  fi
  root="$2"
  if [[ ! -d "$root" ]]; then
    echo "error: scan root not found: $root" >&2
    exit 2
  fi

  pass=0
  fail=0
  while IFS= read -r f; do
    case "$f" in
      */.worktrees/*|*/node_modules/*|*/archive/*) continue ;;
    esac
    # Only validate T{n}.md files under specs/*/tasks/
    case "$f" in
      */specs/*/tasks/T*.md) ;;
      *) continue ;;
    esac
    if validate_file "$f" >/dev/null 2>&1; then
      printf "PASS  %s\n" "$f"
      pass=$((pass+1))
    else
      printf "FAIL  %s\n" "$f"
      validate_file "$f" 2>&1 | sed 's/^/      /' >&2 || true
      fail=$((fail+1))
    fi
  done < <(find "$root" -type f -name 'T*.md' 2>/dev/null | sort)

  echo ""
  echo "task.md scan: $pass pass, $fail fail (total $((pass+fail)))"
  exit 0
fi

# --- Single-file mode ---
validate_file "$1"
exit $?
