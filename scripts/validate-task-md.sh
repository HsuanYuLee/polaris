#!/usr/bin/env bash
# validate-task-md.sh — full enforcer for implementation task.md (T{n}.md) schema.
#
# Usage:
#   validate-task-md.sh <path/to/task.md>
#   validate-task-md.sh --scan <workspace_root>
#
# Exit:  0 = schema pass (single) / scan complete (scan mode, always 0)
#        1 = schema violations (single mode; details printed to stderr)
#        2 = hard fail — completion invariant violated (status: IMPLEMENTED in tasks/)
#            OR usage error / file not found
#
# Schema source:  skills/references/task-md-schema.md (DP-033 Phase A, single source of truth)
# Called by:      skills/breakdown/SKILL.md Step 14.5 (after Write)
#                 .claude/hooks/pipeline-artifact-gate.sh (PreToolUse hook)
#
# DP history:
#   DP-023 — runtime contract fields (Level / Runtime verify target / Env bootstrap)
#   DP-025 — non-runtime required sections (Operational Context JIRA keys, 改動範圍 / 估點理由 non-empty)
#   DP-028 — cross-field rule: Depends on (non-empty) ⇒ Base branch must be task/...
#   DP-032 — lifecycle write-back: deliverable / jira_transition_log
#   DP-033 — full enforcer upgrade: D5 four-tier classification, D6 complete/ invariant (exit 2), D7 lifecycle schema

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

# ---------------------------------------------------------------------------
# Helper: extract all content lines under a markdown section heading.
# Stops at the next ## heading.
# ---------------------------------------------------------------------------
extract_markdown_section() {
  local file="$1"
  local heading="$2"
  awk -v heading="$heading" '
    $0 == heading { in_section=1; next }
    /^## / && in_section { exit }
    in_section { print }
  ' "$file"
}

# ---------------------------------------------------------------------------
# Helper: extract the first fenced code block from stdin.
# ---------------------------------------------------------------------------
extract_first_fenced_code_block() {
  awk '
    /^```/ {
      if (in_block == 0) { in_block=1; next }
      exit
    }
    in_block { print }
  '
}

# ---------------------------------------------------------------------------
# Helper: extract the value cell of an Operational Context table row.
# task.md convention: `| {field} | {value} |`
# Returns the trimmed value; empty string if field is not present.
# ---------------------------------------------------------------------------
extract_op_ctx_field() {
  local file="$1"
  local field="$2"
  awk -v field="$field" '
    /^\|/ {
      n = split($0, fields, "|")
      if (n < 4) next
      name = fields[2]; val = fields[3]
      sub(/^[[:space:]]+/, "", name); sub(/[[:space:]]+$/, "", name)
      sub(/^[[:space:]]+/, "", val);  sub(/[[:space:]]+$/, "", val)
      if (name == field) { print val; exit }
    }
  ' "$file"
}

# ---------------------------------------------------------------------------
# Helper: extract a YAML scalar from the frontmatter block (first --- block).
# Returns the trimmed value for a top-level key: "key: value".
# Outputs nothing if key is absent or has a complex (block/list) value.
# ---------------------------------------------------------------------------
extract_frontmatter_scalar() {
  local file="$1"
  local key="$2"
  awk -v key="$key" '
    /^---$/ { if (fm==0) { fm=1; next } else { exit } }
    fm==1 {
      if (/^[[:space:]]/) next   # skip indented (nested) lines
      n = split($0, parts, ":")
      if (n >= 2) {
        k = parts[1]
        sub(/^[[:space:]]+/, "", k); sub(/[[:space:]]+$/, "", k)
        if (k == key) {
          val = $0
          sub(/^[^:]*:[[:space:]]*/, "", val)
          sub(/[[:space:]]+$/, "", val)
          print val
          exit
        }
      }
    }
  ' "$file"
}

# ---------------------------------------------------------------------------
# Helper: check if a top-level YAML key exists in the frontmatter block.
# Returns 0 if found, 1 if not.
# ---------------------------------------------------------------------------
frontmatter_key_exists() {
  local file="$1"
  local key="$2"
  awk -v key="$key" '
    /^---$/ { if (fm==0) { fm=1; next } else { exit } }
    fm==1 {
      if (/^[[:space:]]/) next
      n = split($0, parts, ":")
      if (n >= 2) {
        k = parts[1]
        sub(/^[[:space:]]+/, "", k); sub(/[[:space:]]+$/, "", k)
        if (k == key) { found=1; exit }
      }
    }
    END { exit (found ? 0 : 1) }
  ' "$file"
}

# ---------------------------------------------------------------------------
# Helper: extract raw frontmatter block (between first --- delimiters).
# ---------------------------------------------------------------------------
extract_frontmatter_block() {
  local file="$1"
  awk '
    /^---$/ { if (fm==0) { fm=1; next } else { exit } }
    fm==1 { print }
  ' "$file"
}

# ---------------------------------------------------------------------------
# Main single-file validator.
# Returns 0 (pass) / 1 (violations) / 2 (hard fail — completion invariant).
# Writes all output to stderr.
# ---------------------------------------------------------------------------
validate_file() {
  local FILE="$1"

  if [[ ! -f "$FILE" ]]; then
    echo "error: file not found: $FILE" >&2
    return 2
  fi

  # --- G: Skip rule — files under tasks/complete/ are never validated (DP-033 D6) ---
  case "$FILE" in
    */tasks/complete/*)
      return 0
      ;;
  esac

  local errors=()
  local warnings=()

  # ---------------------------------------------------------------------------
  # § 5.5 Hard invariant — completion location (exit 2, DP-033 D6)
  # If frontmatter status: IMPLEMENTED AND file is NOT in tasks/complete/ → HARD FAIL.
  # move-first contract: mark-spec-implemented.sh always mv before updating frontmatter,
  # so the only way to hit this is a manual edit that bypassed the helper.
  # ---------------------------------------------------------------------------
  local fm_status
  fm_status=$(extract_frontmatter_scalar "$FILE" "status" 2>/dev/null || true)
  if [[ "$fm_status" == "IMPLEMENTED" ]]; then
    echo "✗✗ HARD FAIL (exit 2) — task.md completion invariant violated in $FILE:" >&2
    echo "   frontmatter 'status: IMPLEMENTED' but file is NOT in tasks/complete/." >&2
    echo "   Fix: run 'scripts/mark-spec-implemented.sh' (move-first: mv tasks/T.md tasks/complete/T.md → update frontmatter)." >&2
    echo "   Reference: skills/references/task-md-schema.md § 5.5 + DP-033 D6" >&2
    return 2
  fi

  # ---------------------------------------------------------------------------
  # HARD REQUIRED: Title line regex (§ 2.2)
  # ^# (T|V)[0-9]+[a-z]*: .+\([0-9.]+ ?pt\)
  # ---------------------------------------------------------------------------
  if ! grep -qE '^# (T|V)[0-9]+[a-z]*: .+\([0-9.]+ ?pt\)' "$FILE"; then
    errors+=("missing or malformed title: expected '# T{n}[suffix]: {summary} ({SP} pt)' — regex: ^# (T|V)[0-9]+[a-z]*: .+\\([0-9.]+ ?pt\\)")
  fi

  # ---------------------------------------------------------------------------
  # HARD REQUIRED: Header metadata line — JIRA + Repo (§ 2.3)
  # SOFT: Epic (warn only — Bug tasks may omit Epic)
  # ---------------------------------------------------------------------------
  if ! grep -qE '^> .*JIRA: [A-Z][A-Z0-9]*-[0-9]+' "$FILE"; then
    errors+=("missing JIRA key in metadata line: expected '> ... | JIRA: {KEY} | ...' (regex: ^> .*JIRA: [A-Z][A-Z0-9]*-[0-9]+)")
  fi
  if ! grep -qE '^> .*Repo: \S+' "$FILE"; then
    errors+=("missing Repo in metadata line: expected '> ... | Repo: {repo_name}'")
  fi
  # Soft: Epic: — warn only (Bug tasks are a real no-Epic case, per DP-033 D5)
  if ! grep -qE '^> .*Epic: \S+' "$FILE"; then
    warnings+=("metadata line missing 'Epic:' cell — Soft required (Bug tasks may omit; warn only)")
  fi

  # ---------------------------------------------------------------------------
  # HARD REQUIRED: Section existence (§ 3.1)
  # ---------------------------------------------------------------------------
  local hard_sections=(
    "## Operational Context"
    "## 改動範圍"
    "## Allowed Files"
    "## 估點理由"
    "## Test Command"
    "## Test Environment"
  )
  local section
  for section in "${hard_sections[@]}"; do
    if ! grep -qF "$section" "$FILE"; then
      errors+=("missing Hard required section: $section")
    fi
  done

  # SOFT REQUIRED: warn-only sections (§ 3.1)
  local soft_sections=(
    "## 目標"
    "## 測試計畫（code-level）"
  )
  for section in "${soft_sections[@]}"; do
    if ! grep -qF "$section" "$FILE"; then
      warnings+=("missing Soft required section: $section (warn only — presence expected but not enforced)")
    fi
  done

  # ---------------------------------------------------------------------------
  # HARD REQUIRED: Non-empty body checks (§ 3.1)
  # 改動範圍, 估點理由 — must have at least 1 non-blank, non-comment line.
  # ---------------------------------------------------------------------------
  check_section_non_empty() {
    local heading="$1"
    local label="$2"
    if ! grep -qF "$heading" "$FILE"; then
      return  # missing section already reported above
    fi
    local body
    body=$(extract_markdown_section "$FILE" "$heading")
    local content_lines
    content_lines=$(printf '%s\n' "$body" | awk '
      /^[[:space:]]*$/ { next }
      /^[[:space:]]*>/ { next }
      { count++ }
      END { print count+0 }
    ')
    if [[ "$content_lines" -eq 0 ]]; then
      errors+=("section '$heading' body is empty ($label — must have at least 1 non-comment line)")
    fi
  }

  check_section_non_empty "## 改動範圍" "Hard required"
  check_section_non_empty "## 估點理由" "Hard required"

  # ---------------------------------------------------------------------------
  # HARD REQUIRED: ## Allowed Files — non-empty bullet list (DP-033 D5, no grace)
  # Upgrade from Soft to Hard (2026-04-26 lock); A7 migration script backfills.
  # ---------------------------------------------------------------------------
  if grep -qF "## Allowed Files" "$FILE"; then
    local allowed_files_body
    allowed_files_body=$(extract_markdown_section "$FILE" "## Allowed Files")
    local bullet_lines
    bullet_lines=$(printf '%s\n' "$allowed_files_body" | awk '
      /^[[:space:]]*$/ { next }
      /^[[:space:]]*>/ { next }
      /^[[:space:]]*-/ { count++ }
      END { print count+0 }
    ')
    if [[ "$bullet_lines" -eq 0 ]]; then
      errors+=("section '## Allowed Files' has no bullet list entries (Hard required — must have at least one '- ' bullet; A7 migration script can backfill)")
    fi
  fi

  # ---------------------------------------------------------------------------
  # HARD REQUIRED: Operational Context (§ 3.2)
  # Must contain ≥ 1 JIRA key pattern AND all required cells.
  # ---------------------------------------------------------------------------
  if grep -qF "## Operational Context" "$FILE"; then
    local op_ctx
    op_ctx=$(extract_markdown_section "$FILE" "## Operational Context")

    # At least one JIRA key anywhere in the section
    if ! printf '%s' "$op_ctx" | grep -qE '[A-Z][A-Z0-9]+-[0-9]+'; then
      errors+=("Operational Context section missing JIRA key (pattern [A-Z][A-Z0-9]+-[0-9]+)")
    fi

    # Hard required cells (§ 3.2 table)
    local required_cells=(
      "Task JIRA key"
      "Parent Epic"
      "Test sub-tasks"
      "AC 驗收單"
      "Base branch"
      "Task branch"
      "References to load"
    )
    local cell
    for cell in "${required_cells[@]}"; do
      if ! grep -qF "$cell" "$FILE"; then
        errors+=("missing Hard required Operational Context cell: '$cell'")
      fi
    done

    # Soft: 'Depends on' — warn only (absent = no deps, which is valid)
    if ! grep -qF "Depends on" "$FILE"; then
      warnings+=("Operational Context missing 'Depends on' cell (Soft — N/A is valid; warn only)")
    fi
  fi

  # ---------------------------------------------------------------------------
  # HARD REQUIRED: Test Environment — Level enum + Level-specific field rules
  # § 3.3 + § 5.1
  # ---------------------------------------------------------------------------
  local level=""
  if grep -qF "## Test Environment" "$FILE"; then

    # Extract Level value
    local level_line
    level_line=$(grep -E '^\*\*Level\*\*: |^- \*\*Level\*\*: ' "$FILE" | head -n1 || true)
    if [[ -z "$level_line" ]]; then
      errors+=("Test Environment section missing 'Level' field (expected '- **Level**: {static|build|runtime}')")
    else
      level=$(printf '%s' "$level_line" \
        | sed -E 's/.*\*\*Level\*\*:[[:space:]]*//' \
        | sed -E 's/[[:space:]].*//' \
        | tr '[:upper:]' '[:lower:]' \
        | tr -d '\r')
      case "$level" in
        static|build|runtime) ;;
        *) errors+=("Test Environment 'Level' must be one of {static, build, runtime} (got: '$level')") ; level="" ;;
      esac
    fi

    # Extract Runtime verify target + Env bootstrap command
    local target_line bootstrap_line target="" bootstrap=""
    target_line=$(grep -E '^\*\*Runtime verify target\*\*: |^- \*\*Runtime verify target\*\*: ' "$FILE" | head -n1 || true)
    bootstrap_line=$(grep -E '^\*\*Env bootstrap command\*\*: |^- \*\*Env bootstrap command\*\*: ' "$FILE" | head -n1 || true)

    if [[ -z "$target_line" ]]; then
      errors+=("Test Environment missing 'Runtime verify target' field (expected '- **Runtime verify target**: {url|N/A}')")
    else
      target=$(printf '%s' "$target_line" | sed -E 's/.*\*\*Runtime verify target\*\*:[[:space:]]*//' | tr -d '\r')
    fi

    if [[ -z "$bootstrap_line" ]]; then
      errors+=("Test Environment missing 'Env bootstrap command' field (expected '- **Env bootstrap command**: {command|N/A}')")
    else
      bootstrap=$(printf '%s' "$bootstrap_line" | sed -E 's/.*\*\*Env bootstrap command\*\*:[[:space:]]*//' | tr -d '\r')
    fi

    # Apply Level-specific cross-field rules (§ 5.1 + § 3.3)
    if [[ -n "$level" ]]; then
      if [[ "$level" == "runtime" ]]; then
        # --- Level=runtime rules ---
        local normalized_target
        normalized_target=$(printf '%s' "${target:-}" | sed -E 's/^`|`$//g' | xargs 2>/dev/null || true)

        if [[ -z "$normalized_target" || "$normalized_target" == "N/A" || "$normalized_target" == "n/a" ]]; then
          errors+=("Level=runtime requires non-N/A Runtime verify target (got: '${normalized_target:-<empty>}')")
        elif ! printf '%s' "$normalized_target" | grep -Eq '^https?://'; then
          errors+=("Level=runtime requires Runtime verify target to be an http/https URL (got: '$normalized_target')")
        fi

        local normalized_bootstrap
        normalized_bootstrap=$(printf '%s' "${bootstrap:-}" | xargs 2>/dev/null || true)
        if [[ -z "$normalized_bootstrap" || "$normalized_bootstrap" == "N/A" || "$normalized_bootstrap" == "n/a" ]]; then
          errors+=("Level=runtime requires non-N/A Env bootstrap command")
        fi

        # Verify Command host must equal Runtime verify target host (§ 5.1 rule 4)
        if grep -qF "## Verify Command" "$FILE"; then
          local verify_section verify_cmd verify_cmd_compact
          verify_section=$(extract_markdown_section "$FILE" "## Verify Command")
          verify_cmd=$(printf '%s\n' "$verify_section" | extract_first_fenced_code_block)
          verify_cmd_compact=$(printf '%s' "$verify_cmd" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g' | xargs 2>/dev/null || true)

          if [[ -z "$verify_cmd_compact" ]]; then
            errors+=("## Verify Command fenced code block is empty (Level=runtime requires a live endpoint URL inside)")
          else
            local verify_url target_host verify_host
            verify_url=$(python3 -c "
import re, sys
s = sys.stdin.read()
m = re.search(r'https?://[^\s\"\'\\)]+', s)
print(m.group(0) if m else '')
" <<< "$verify_cmd_compact" 2>/dev/null || true)

            if [[ -z "$verify_url" ]]; then
              errors+=("Level=runtime requires Verify Command fenced block to contain a live http/https endpoint URL")
            else
              target_host=$(python3 -c "
from urllib.parse import urlparse
import sys
u = sys.argv[1]
print((urlparse(u).hostname or '').lower())
" "$normalized_target" 2>/dev/null || true)
              verify_host=$(python3 -c "
from urllib.parse import urlparse
import sys
u = sys.argv[1]
print((urlparse(u).hostname or '').lower())
" "$verify_url" 2>/dev/null || true)

              if [[ -z "$target_host" || -z "$verify_host" ]]; then
                errors+=("unable to parse host from Runtime verify target ('$normalized_target') or Verify Command URL ('$verify_url')")
              elif [[ "$target_host" != "$verify_host" ]]; then
                errors+=("Level=runtime: Verify Command URL host ($verify_host) must match Runtime verify target host ($target_host) — DP-023 Target-first rule")
              fi
            fi
          fi
        fi

      elif [[ "$level" == "static" || "$level" == "build" ]]; then
        # --- Level=static|build: Runtime verify target + Env bootstrap must be N/A ---
        local t_val b_val
        t_val=$(printf '%s' "${target:-}" | sed -E 's/^`|`$//g' | xargs 2>/dev/null || true)
        b_val=$(printf '%s' "${bootstrap:-}" | xargs 2>/dev/null || true)
        if [[ -n "$t_val" && "$t_val" != "N/A" && "$t_val" != "n/a" ]]; then
          errors+=("Level=$level expects Runtime verify target = N/A (got: '$t_val') — avoid false declarations")
        fi
        if [[ -n "$b_val" && "$b_val" != "N/A" && "$b_val" != "n/a" ]]; then
          errors+=("Level=$level expects Env bootstrap command = N/A (got: '$b_val') — avoid false declarations")
        fi
      fi
    fi
  fi

  # ---------------------------------------------------------------------------
  # HARD REQUIRED: ## Verify Command — only Hard when Level ≠ static (§ 3.1)
  # For Level=static: section is Optional (no check).
  # For Level=build|runtime: section must exist with fenced code block.
  # (runtime host-alignment check already done above inside Test Environment block.)
  # ---------------------------------------------------------------------------
  if [[ -n "$level" && "$level" != "static" ]]; then
    if ! grep -qF "## Verify Command" "$FILE"; then
      errors+=("missing Hard required section: ## Verify Command (required when Level=$level)")
    else
      local vc_code
      vc_code=$(extract_markdown_section "$FILE" "## Verify Command" | extract_first_fenced_code_block | tr -d '[:space:]')
      if [[ -z "$vc_code" ]]; then
        errors+=("## Verify Command section missing executable fenced code block (required when Level=$level)")
      fi
    fi
  elif [[ -z "$level" ]]; then
    # Level unknown (Test Environment missing or malformed) — check Verify Command section integrity
    # if the section exists, it must have a code block (preserve prior behavior).
    if grep -qF "## Verify Command" "$FILE"; then
      local vc_code2
      vc_code2=$(extract_markdown_section "$FILE" "## Verify Command" | extract_first_fenced_code_block | tr -d '[:space:]')
      if [[ -z "$vc_code2" ]]; then
        errors+=("## Verify Command section missing executable fenced code block")
      fi
    fi
  fi

  # ---------------------------------------------------------------------------
  # HARD REQUIRED: ## Test Command must contain a fenced code block (§ 3.5)
  # ---------------------------------------------------------------------------
  if grep -qF "## Test Command" "$FILE"; then
    local tc_code
    tc_code=$(extract_markdown_section "$FILE" "## Test Command" | extract_first_fenced_code_block | tr -d '[:space:]')
    if [[ -z "$tc_code" ]]; then
      errors+=("## Test Command section missing executable fenced code block")
    fi
  fi

  # ---------------------------------------------------------------------------
  # DP-028 Cross-field: Depends on (non-empty) ⇒ Base branch must start with task/
  # § 5.2
  # ---------------------------------------------------------------------------
  local depends_on_val base_branch_val
  depends_on_val=$(extract_op_ctx_field "$FILE" "Depends on")
  base_branch_val=$(extract_op_ctx_field "$FILE" "Base branch")
  local deps_normalized
  deps_normalized=$(printf '%s' "$depends_on_val" | tr '[:upper:]' '[:lower:]' | xargs 2>/dev/null || true)
  if [[ -n "$deps_normalized" \
        && "$deps_normalized" != "n/a" \
        && "$deps_normalized" != "-" \
        && "$deps_normalized" != "無" \
        && "$deps_normalized" != "none" ]]; then
    if [[ -z "$base_branch_val" ]]; then
      errors+=("DP-028 cross-field: 'Depends on' is non-empty but 'Base branch' is not a task/ branch (got: <empty>)")
    elif [[ "$base_branch_val" != task/* ]]; then
      errors+=("DP-028 cross-field: 'Depends on' is non-empty but 'Base branch' is not a task/ branch (got: '$base_branch_val')")
    fi
  fi

  # ---------------------------------------------------------------------------
  # LIFECYCLE-CONDITIONAL: deliverable schema (§ 2.1 + § 3.6 + DP-033 D7)
  # Not required to exist; validator only checks schema WHEN the block is present.
  # ---------------------------------------------------------------------------
  if frontmatter_key_exists "$FILE" "deliverable" 2>/dev/null; then
    local fm_block
    fm_block=$(extract_frontmatter_block "$FILE")

    # Extract indented scalar fields under deliverable:
    # pr_url, pr_state, head_sha
    local pr_url pr_state head_sha
    pr_url=$(printf '%s\n' "$fm_block" | awk '
      /^[[:space:]]+pr_url:[[:space:]]/ {
        val = $0; sub(/^[^:]*:[[:space:]]*/, "", val); sub(/[[:space:]]+$/, "", val)
        print val; exit
      }
    ')
    pr_state=$(printf '%s\n' "$fm_block" | awk '
      /^[[:space:]]+pr_state:[[:space:]]/ {
        val = $0; sub(/^[^:]*:[[:space:]]*/, "", val); sub(/[[:space:]]+$/, "", val)
        print val; exit
      }
    ')
    head_sha=$(printf '%s\n' "$fm_block" | awk '
      /^[[:space:]]+head_sha:[[:space:]]/ {
        val = $0; sub(/^[^:]*:[[:space:]]*/, "", val); sub(/[[:space:]]+$/, "", val)
        print val; exit
      }
    ')

    # Validate pr_url
    if [[ -z "$pr_url" ]]; then
      errors+=("deliverable.pr_url is missing or empty (required when deliverable block is present)")
    elif ! printf '%s' "$pr_url" | grep -qE '^https://github\.com/.+/pull/[0-9]+$'; then
      errors+=("deliverable.pr_url must match '^https://github\\.com/.+/pull/[0-9]+\$' (got: '$pr_url')")
    fi

    # Validate pr_state
    if [[ -z "$pr_state" ]]; then
      errors+=("deliverable.pr_state is missing or empty (required when deliverable block is present)")
    else
      case "$pr_state" in
        OPEN|MERGED|CLOSED) ;;
        *) errors+=("deliverable.pr_state must be OPEN, MERGED, or CLOSED (got: '$pr_state')") ;;
      esac
    fi

    # Validate head_sha (7+ hex chars)
    if [[ -z "$head_sha" ]]; then
      errors+=("deliverable.head_sha is missing or empty (required when deliverable block is present)")
    elif ! printf '%s' "$head_sha" | grep -qE '^[0-9a-fA-F]{7,}$'; then
      errors+=("deliverable.head_sha must be a hex string of ≥ 7 characters (got: '$head_sha')")
    fi
  fi

  # ---------------------------------------------------------------------------
  # LIFECYCLE-CONDITIONAL: jira_transition_log schema (§ 2.1 + DP-033 D7, loose)
  # Not required to exist; WHEN present: must be a YAML list (not scalar).
  # Each entry should be a map; time is recommended but not enforced.
  # ---------------------------------------------------------------------------
  if frontmatter_key_exists "$FILE" "jira_transition_log" 2>/dev/null; then
    local fm_block2
    fm_block2=$(extract_frontmatter_block "$FILE")

    # Check that jira_transition_log is NOT a scalar (inline value on the key line).
    # Valid forms: empty value (list follows on next lines) or "[]"
    # Invalid: jira_transition_log: some_string
    local jtl_inline
    jtl_inline=$(printf '%s\n' "$fm_block2" | awk '
      /^jira_transition_log:/ {
        val = $0
        sub(/^jira_transition_log:[[:space:]]*/, "", val)
        sub(/[[:space:]]+$/, "", val)
        if (val != "" && val != "[]" && val != "~" && val != "null") {
          print val
        }
        exit
      }
    ')
    if [[ -n "$jtl_inline" ]]; then
      errors+=("jira_transition_log must be a YAML list (array), not a scalar (got inline value: '$jtl_inline')")
    else
      # Verify each list entry (lines starting with "  - ") is a map (has at least one sub-key: value pair).
      # Loose check: each "  - " line must be followed by at least one "    key: value" line.
      # We just verify that if there are entries, they don't look like raw scalars on the same line.
      local jtl_bad_entries
      jtl_bad_entries=$(printf '%s\n' "$fm_block2" | awk '
        /^jira_transition_log:/ { in_jtl=1; next }
        in_jtl && /^[^[:space:]]/ { exit }
        in_jtl && /^[[:space:]]+-[[:space:]]+[^{]/ {
          # "  - value" (bare scalar entry) — not a map
          sub(/^[[:space:]]+-[[:space:]]*/, "", $0)
          # If remainder looks like a plain scalar (no colon), it might be a scalar entry.
          # But since YAML allows "- key: val" on one line too, only flag obvious non-map.
          if ($0 !~ /:/) { print "bare scalar entry: " $0 }
        }
      ')
      if [[ -n "$jtl_bad_entries" ]]; then
        errors+=("jira_transition_log entries must be YAML maps (key: value), not bare scalars ($jtl_bad_entries)")
      fi
    fi
  fi

  # ---------------------------------------------------------------------------
  # Output: warnings (non-blocking) + errors (violations → exit 1)
  # ---------------------------------------------------------------------------
  if [[ ${#warnings[@]} -gt 0 ]]; then
    echo "⚠ task.md soft warnings in $FILE:" >&2
    local w
    for w in "${warnings[@]}"; do
      echo "  ~ $w" >&2
    done
    echo "" >&2
  fi

  if [[ ${#errors[@]} -eq 0 ]]; then
    return 0
  fi

  echo "✗ task.md schema violations in $FILE:" >&2
  local err
  for err in "${errors[@]}"; do
    echo "  - $err" >&2
  done
  echo "" >&2
  echo "Contract: skills/references/task-md-schema.md (DP-033 A2 full enforcer)" >&2
  return 1
}

# ---------------------------------------------------------------------------
# Scan mode: recursively validate all T*.md in specs/*/tasks/ (skip complete/)
# Always exits 0; produces PASS/FAIL/HARD summary lines.
# ---------------------------------------------------------------------------
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
  hard=0
  while IFS= read -r f; do
    case "$f" in
      */.worktrees/*|*/node_modules/*) continue ;;
      */tasks/complete/*) continue ;;
    esac
    case "$f" in
      */specs/*/tasks/T*.md) ;;
      *) continue ;;
    esac

    rc=0
    validate_file "$f" >/dev/null 2>&1 || rc=$?
    case "$rc" in
      0)
        printf "PASS  %s\n" "$f"
        pass=$((pass+1))
        ;;
      2)
        printf "HARD  %s\n" "$f"
        validate_file "$f" 2>&1 | sed 's/^/      /' >&2 || true
        hard=$((hard+1))
        fail=$((fail+1))
        ;;
      *)
        printf "FAIL  %s\n" "$f"
        validate_file "$f" 2>&1 | sed 's/^/      /' >&2 || true
        fail=$((fail+1))
        ;;
    esac
  done < <(find "$root" -type f -name 'T*.md' 2>/dev/null | sort)

  echo ""
  echo "task.md scan: $pass pass, $fail fail ($hard hard-fail) — total $((pass+fail))"
  exit 0
fi

# ---------------------------------------------------------------------------
# Single-file mode
# ---------------------------------------------------------------------------
validate_file "$1"
exit $?
