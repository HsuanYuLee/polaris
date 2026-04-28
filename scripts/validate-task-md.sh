#!/usr/bin/env bash
# validate-task-md.sh — full enforcer for task.md schema (T{n}.md + V{n}.md, dual-path).
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
# Schema source:  skills/references/task-md-schema.md (DP-033 Phase A + Phase B, single source of truth)
# Called by:      skills/breakdown/SKILL.md Step 14.5 (after Write)
#                 .claude/hooks/pipeline-artifact-gate.sh (PreToolUse hook)
#
# Mode dispatch (DP-033 Phase B):
#   filename T*.md → T mode (Implementation Schema, § 3)
#   filename V*.md → V mode (Verification Schema, § 4)
#   filename 由 entry 偵測；mode 為 唯一 type 訊號（DP-033 D2，frontmatter 無 type 欄位）
#   T/V 共用：Title regex / Header / status invariant / Test Environment / jira_transition_log /
#             pr-release-skip / move-first / depends_on schema (cross-file, validate-task-md-deps.sh)
#   T-only:   ## 改動範圍 / ## Allowed Files / ## Test Command / ## Verify Command /
#             Operational Context Test sub-tasks/AC 驗收單/Task branch cells /
#             DP-028 Depends on ⇒ task/ Base branch cross-field /
#             deliverable lifecycle
#   V-only:   ## 驗收項目 / ## 驗收步驟 / Operational Context Implementation tasks cell /
#             ac_verification + ac_verification_log lifecycle (§ 4.7 對稱 D7)
#
# DP history:
#   DP-023 — runtime contract fields (Level / Runtime verify target / Env bootstrap)
#   DP-025 — non-runtime required sections (Operational Context JIRA keys, 改動範圍 / 估點理由 non-empty)
#   DP-028 — cross-field rule: Depends on (non-empty) ⇒ Base branch must be task/...
#   DP-032 — lifecycle write-back: deliverable / jira_transition_log
#   DP-033 — Phase A enforcer (D5/D6/D7 T mode); Phase B V mode dual-path + ac_verification

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

  # --- G: Skip rule — files under tasks/pr-release/ are never validated (DP-033 D6) ---
  case "$FILE" in
    */tasks/pr-release/*)
      return 0
      ;;
  esac

  # --- Mode detection (DP-033 Phase B): filename pattern → schema mode ---
  local _basename mode verify_section_name
  _basename=$(basename "$FILE")
  case "$_basename" in
    T[0-9]*.md)  mode="T" ;;
    V[0-9]*.md)  mode="V" ;;
    *)
      # Fallback: file is not a T*.md or V*.md → apply T mode (backward compat)
      # for legacy/unknown filenames; the dispatch hook should have routed
      # canonical V*.md / T*.md before this point.
      mode="T"
      ;;
  esac
  # Driver section that holds the executable / step block:
  #   T mode: ## Verify Command  (deterministic shell, fenced code block)
  #   V mode: ## 驗收步驟        (verify-AC LLM driver entry + per-AC step list)
  if [[ "$mode" == "V" ]]; then
    verify_section_name="## 驗收步驟"
  else
    verify_section_name="## Verify Command"
  fi

  local errors=()
  local warnings=()

  # ---------------------------------------------------------------------------
  # § 5.5 Hard invariant — completion location (exit 2, DP-033 D6)
  # If frontmatter status: IMPLEMENTED AND file is NOT in tasks/pr-release/ → HARD FAIL.
  # move-first contract: mark-spec-implemented.sh always mv before updating frontmatter,
  # so the only way to hit this is a manual edit that bypassed the helper.
  # ---------------------------------------------------------------------------
  local fm_status
  fm_status=$(extract_frontmatter_scalar "$FILE" "status" 2>/dev/null || true)
  if [[ "$fm_status" == "IMPLEMENTED" ]]; then
    echo "✗✗ HARD FAIL (exit 2) — task.md completion invariant violated in $FILE:" >&2
    echo "   frontmatter 'status: IMPLEMENTED' but file is NOT in tasks/pr-release/." >&2
    echo "   Fix: run 'scripts/mark-spec-implemented.sh' (move-first: mv tasks/T.md tasks/pr-release/T.md → update frontmatter)." >&2
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
  # HARD REQUIRED: Section existence (§ 3.1 / § 4.1, mode-aware)
  # ---------------------------------------------------------------------------
  local hard_sections=()
  local soft_sections=()
  if [[ "$mode" == "T" ]]; then
    hard_sections=(
      "## Operational Context"
      "## 改動範圍"
      "## Allowed Files"
      "## 估點理由"
      "## Test Command"
      "## Test Environment"
    )
    soft_sections=(
      "## 目標"
      "## 測試計畫（code-level）"
    )
  else
    # V mode (DP-033 Phase B § 4.1) — symmetric to T but driver section names differ:
    #   T 改動範圍       → V 驗收項目      (語意對稱：T 列檔案改動，V 列 AC 覆蓋)
    #   T 測試計畫 code-level → V 驗收計畫（AC level）
    # T-only sections (Allowed Files / Test Command) are omitted — V doesn't write code.
    # Verify Command analog `## 驗收步驟` is checked separately below (level-conditional).
    hard_sections=(
      "## Operational Context"
      "## 驗收項目"
      "## 估點理由"
      "## Test Environment"
    )
    soft_sections=(
      "## 目標"
      "## 驗收計畫（AC level）"
    )
  fi
  local section
  for section in "${hard_sections[@]}"; do
    if ! grep -qF "$section" "$FILE"; then
      errors+=("missing Hard required section: $section")
    fi
  done
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

  if [[ "$mode" == "T" ]]; then
    check_section_non_empty "## 改動範圍" "Hard required"
  else
    # V mode (§ 4.3): 驗收項目 must be non-empty (≥ 1 markdown row OR bullet)
    if grep -qF "## 驗收項目" "$FILE"; then
      local v_body
      v_body=$(extract_markdown_section "$FILE" "## 驗收項目")
      local v_lines
      v_lines=$(printf '%s\n' "$v_body" | awk '
        /^[[:space:]]*$/ { next }
        /^[[:space:]]*>/ { next }
        /^[[:space:]]*\|/ { count++ }
        /^[[:space:]]*-/ { count++ }
        END { print count+0 }
      ')
      if [[ "$v_lines" -eq 0 ]]; then
        errors+=("section '## 驗收項目' has no AC entries (Hard required — must have at least one markdown row '|' or bullet '- ')")
      fi
    fi
  fi
  check_section_non_empty "## 估點理由" "Hard required"

  # ---------------------------------------------------------------------------
  # HARD REQUIRED (T mode only): ## Allowed Files — non-empty bullet list (DP-033 D5, no grace)
  # V mode 不寫 code → 不需 Allowed Files。
  # ---------------------------------------------------------------------------
  if [[ "$mode" == "T" ]] && grep -qF "## Allowed Files" "$FILE"; then
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

    # Hard required cells — mode-aware (§ 3.2 for T, § 4.2 for V)
    local required_cells=()
    if [[ "$mode" == "T" ]]; then
      required_cells=(
        "Task JIRA key"
        "Parent Epic"
        "Test sub-tasks"
        "AC 驗收單"
        "Base branch"
        "Task branch"
        "References to load"
      )
    else
      # V mode (§ 4.2): drops T-only cells (Test sub-tasks / AC 驗收單 / Task branch)
      # and adds Implementation tasks (the T list this V verifies).
      required_cells=(
        "Task JIRA key"
        "Parent Epic"
        "Implementation tasks"
        "Base branch"
        "References to load"
      )
    fi
    local cell
    for cell in "${required_cells[@]}"; do
      if ! grep -qF "$cell" "$FILE"; then
        errors+=("missing Hard required Operational Context cell: '$cell'")
      fi
    done

    # Soft: 'Depends on' — warn only (absent = no deps, which is valid; T/V common)
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

        # Verify Command / 驗收步驟 host must equal Runtime verify target host (§ 5.1 rule 4)
        if grep -qF "$verify_section_name" "$FILE"; then
          local verify_section verify_cmd verify_cmd_compact
          verify_section=$(extract_markdown_section "$FILE" "$verify_section_name")
          verify_cmd=$(printf '%s\n' "$verify_section" | extract_first_fenced_code_block)
          verify_cmd_compact=$(printf '%s' "$verify_cmd" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g' | xargs 2>/dev/null || true)

          if [[ -z "$verify_cmd_compact" ]]; then
            errors+=("$verify_section_name fenced code block is empty (Level=runtime requires a live endpoint URL inside)")
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
  # HARD REQUIRED: ## Verify Command (T) / ## 驗收步驟 (V) — only Hard when Level ≠ static
  # § 3.1 / § 4.1 / § 4.5
  # For Level=static: section is Optional (no check).
  # For Level=build|runtime: section must exist with fenced code block.
  # (runtime host-alignment check already done above inside Test Environment block.)
  # T/V 共用，使用 verify_section_name 動態指向。
  # ---------------------------------------------------------------------------
  if [[ -n "$level" && "$level" != "static" ]]; then
    if ! grep -qF "$verify_section_name" "$FILE"; then
      errors+=("missing Hard required section: $verify_section_name (required when Level=$level)")
    else
      local vc_code
      vc_code=$(extract_markdown_section "$FILE" "$verify_section_name" | extract_first_fenced_code_block | tr -d '[:space:]')
      if [[ -z "$vc_code" ]]; then
        errors+=("$verify_section_name section missing executable fenced code block (required when Level=$level)")
      fi
    fi
  elif [[ -z "$level" ]]; then
    # Level unknown (Test Environment missing or malformed) — check section integrity
    # if the section exists, it must have a code block (preserve prior behavior).
    if grep -qF "$verify_section_name" "$FILE"; then
      local vc_code2
      vc_code2=$(extract_markdown_section "$FILE" "$verify_section_name" | extract_first_fenced_code_block | tr -d '[:space:]')
      if [[ -z "$vc_code2" ]]; then
        errors+=("$verify_section_name section missing executable fenced code block")
      fi
    fi
  fi

  # ---------------------------------------------------------------------------
  # HARD REQUIRED (T mode only): ## Test Command must contain a fenced code block (§ 3.5)
  # V mode 不跑 unit test → 不需 Test Command（§ 4.1 「合理省略」）。
  # ---------------------------------------------------------------------------
  if [[ "$mode" == "T" ]] && grep -qF "## Test Command" "$FILE"; then
    local tc_code
    tc_code=$(extract_markdown_section "$FILE" "## Test Command" | extract_first_fenced_code_block | tr -d '[:space:]')
    if [[ -z "$tc_code" ]]; then
      errors+=("## Test Command section missing executable fenced code block")
    fi
  fi

  # ---------------------------------------------------------------------------
  # DP-028 Cross-field (T mode only): Depends on (non-empty) ⇒ Base branch must start with task/
  # § 5.2 — V mode 通常從 feat/... 或 develop 跑驗收，不適用此 cross-field（§ 5.2 表格）。
  # ---------------------------------------------------------------------------
  if [[ "$mode" == "T" ]]; then
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
  fi

  # ---------------------------------------------------------------------------
  # LIFECYCLE-CONDITIONAL (T mode only): deliverable schema (§ 2.1 + § 3.6 + DP-033 D7)
  # Not required to exist; validator only checks schema WHEN the block is present.
  # V mode 對稱 lifecycle 是 ac_verification（見下方 V-only block）。
  # ---------------------------------------------------------------------------
  if [[ "$mode" == "T" ]] && frontmatter_key_exists "$FILE" "deliverable" 2>/dev/null; then
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
  # LIFECYCLE-CONDITIONAL (V mode only): ac_verification schema (§ 4.6 + § 4.7,
  # symmetric to deliverable D7). verify-AC writes summary on every run.
  # Not required to exist (breakdown stage absent is legal); only check WHEN present.
  # ---------------------------------------------------------------------------
  if [[ "$mode" == "V" ]] && frontmatter_key_exists "$FILE" "ac_verification" 2>/dev/null; then
    local fm_block_v
    fm_block_v=$(extract_frontmatter_block "$FILE")

    # Helper: extract scalar field under `ac_verification:` block (state machine).
    # Stops at the next top-level (unindented) YAML key.
    extract_av_field() {
      printf '%s\n' "$fm_block_v" | awk -v key="$1" '
        /^ac_verification:/ { in_block=1; next }
        in_block && /^[^[:space:]#]/ { exit }
        in_block && match($0, "^[[:space:]]+" key ":[[:space:]]") {
          val = $0; sub(/^[^:]*:[[:space:]]*/, "", val); sub(/[[:space:]]+$/, "", val)
          print val; exit
        }
      '
    }

    local av_status av_last_run av_total av_pass av_fail av_manual av_uncertain av_disposition
    av_status=$(extract_av_field "status")
    av_last_run=$(extract_av_field "last_run_at")
    av_total=$(extract_av_field "ac_total")
    av_pass=$(extract_av_field "ac_pass")
    av_fail=$(extract_av_field "ac_fail")
    av_manual=$(extract_av_field "ac_manual_required")
    av_uncertain=$(extract_av_field "ac_uncertain")
    av_disposition=$(extract_av_field "human_disposition")

    # status enum
    if [[ -z "$av_status" ]]; then
      errors+=("ac_verification.status is missing or empty (required when ac_verification block is present)")
    else
      case "$av_status" in
        PASS|FAIL|MANUAL_REQUIRED|UNCERTAIN|IN_PROGRESS) ;;
        *) errors+=("ac_verification.status must be PASS|FAIL|MANUAL_REQUIRED|UNCERTAIN|IN_PROGRESS (got: '$av_status')") ;;
      esac
    fi

    # last_run_at ISO 8601 (loose: must look like YYYY-MM-DDThh:mm:ss with optional Z/±offset)
    if [[ -z "$av_last_run" ]]; then
      errors+=("ac_verification.last_run_at is missing or empty (required when ac_verification block is present)")
    elif ! printf '%s' "$av_last_run" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?$'; then
      errors+=("ac_verification.last_run_at must be ISO 8601 timestamp (got: '$av_last_run')")
    fi

    # ac_total / ac_pass / ac_fail / ac_manual_required / ac_uncertain — int ≥ 0; sum == total
    local _is_int='^-?[0-9]+$'
    local sum=0 has_count_error=0
    local field val
    for field in ac_total ac_pass ac_fail ac_manual_required ac_uncertain; do
      val=$(extract_av_field "$field")
      if [[ -z "$val" ]]; then
        errors+=("ac_verification.$field is missing or empty (required when ac_verification block is present)")
        has_count_error=1
        continue
      fi
      if ! [[ "$val" =~ ^[0-9]+$ ]]; then
        errors+=("ac_verification.$field must be a non-negative integer (got: '$val')")
        has_count_error=1
        continue
      fi
      if [[ "$field" != "ac_total" ]]; then
        sum=$((sum + val))
      fi
    done
    if [[ "$has_count_error" -eq 0 && -n "$av_total" ]]; then
      if [[ "$sum" -ne "$av_total" ]]; then
        errors+=("ac_verification: ac_pass + ac_fail + ac_manual_required + ac_uncertain ($sum) must equal ac_total ($av_total)")
      fi
    fi

    # human_disposition: required when status != PASS
    if [[ -n "$av_status" && "$av_status" != "PASS" && "$av_status" != "IN_PROGRESS" ]]; then
      if [[ -z "$av_disposition" ]]; then
        errors+=("ac_verification.human_disposition is required when status='$av_status' (FAIL/MANUAL_REQUIRED/UNCERTAIN need human triage)")
      else
        case "$av_disposition" in
          passed|rejected|deferred) ;;
          *) errors+=("ac_verification.human_disposition must be passed|rejected|deferred (got: '$av_disposition')") ;;
        esac
      fi
    elif [[ -n "$av_disposition" ]]; then
      # status=PASS or IN_PROGRESS but human_disposition is set — must still be valid enum
      case "$av_disposition" in
        passed|rejected|deferred) ;;
        *) errors+=("ac_verification.human_disposition must be passed|rejected|deferred (got: '$av_disposition')") ;;
      esac
    fi
  fi

  # ---------------------------------------------------------------------------
  # LIFECYCLE-CONDITIONAL (V mode only): ac_verification_log schema (§ 4.6 + § 4.7, loose)
  # Same精神 as jira_transition_log — list-of-maps，time 建議不強制；其他欄位 freeform。
  # ---------------------------------------------------------------------------
  if [[ "$mode" == "V" ]] && frontmatter_key_exists "$FILE" "ac_verification_log" 2>/dev/null; then
    local fm_block_avl
    fm_block_avl=$(extract_frontmatter_block "$FILE")

    # Reject inline scalar (e.g., `ac_verification_log: some_string`).
    local avl_inline
    avl_inline=$(printf '%s\n' "$fm_block_avl" | awk '
      /^ac_verification_log:/ {
        val = $0
        sub(/^ac_verification_log:[[:space:]]*/, "", val)
        sub(/[[:space:]]+$/, "", val)
        if (val != "" && val != "[]" && val != "~" && val != "null") {
          print val
        }
        exit
      }
    ')
    if [[ -n "$avl_inline" ]]; then
      errors+=("ac_verification_log must be a YAML list (array), not a scalar (got inline value: '$avl_inline')")
    else
      # Each entry must be a map (key: value), not a bare scalar.
      local avl_bad
      avl_bad=$(printf '%s\n' "$fm_block_avl" | awk '
        /^ac_verification_log:/ { in_blk=1; next }
        in_blk && /^[^[:space:]]/ { exit }
        in_blk && /^[[:space:]]+-[[:space:]]+[^{]/ {
          sub(/^[[:space:]]+-[[:space:]]*/, "", $0)
          if ($0 !~ /:/) { print "bare scalar entry: " $0 }
        }
      ')
      if [[ -n "$avl_bad" ]]; then
        errors+=("ac_verification_log entries must be YAML maps (key: value), not bare scalars ($avl_bad)")
      fi
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
# Scan mode: recursively validate all T*.md and V*.md in specs/*/tasks/ (skip pr-release/)
# Always exits 0; produces PASS/FAIL/HARD summary lines.
# DP-033 Phase B: filename pattern擴展到 V*.md (filename dispatch 對 T/V 共用).
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
      */tasks/pr-release/*) continue ;;
    esac
    case "$f" in
      */specs/*/tasks/T*.md) ;;
      */specs/*/tasks/V*.md) ;;
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
  done < <(find "$root" -type f \( -name 'T*.md' -o -name 'V*.md' \) 2>/dev/null | sort)

  echo ""
  echo "task.md scan: $pass pass, $fail fail ($hard hard-fail) — total $((pass+fail))"
  exit 0
fi

# ---------------------------------------------------------------------------
# Single-file mode
# ---------------------------------------------------------------------------
validate_file "$1"
exit $?
