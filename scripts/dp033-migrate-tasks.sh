#!/usr/bin/env bash
# dp033-migrate-tasks.sh — DP-033 A7: One-shot migration for all existing T*.md files.
#
# Usage:
#   dp033-migrate-tasks.sh [--dry-run] [--workspace-root <path>]
#
# Default workspace root: auto-detected from POLARIS_WORKSPACE_ROOT env or git root.
#
# Actions per task:
#   IMPLEMENTED (status: IMPLEMENTED in frontmatter)
#     → move to tasks/pr-release/{filename}   (move-first per D6)
#   Active (no IMPLEMENTED status)
#     → run validate-task-md.sh
#     → if FAIL: attempt force-backfill of missing Hard sections
#     → if still FAIL after backfill: FAIL LOUD and stop
#
# Idempotency: already-moved tasks (in pr-release/) are skipped; already-valid tasks
# are marked UNCHANGED.
#
# Exit:
#   0 = all tasks migrated or unchanged
#   1 = one or more FAILED (human must resolve before re-run)
#   2 = usage/setup error

set -euo pipefail

# ── Constants ──────────────────────────────────────────────────────────────────

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/tmp/dp033-migration-log-${TIMESTAMP}.md"
DRY_RUN=false
WORKSPACE_ROOT=""

# Counters
COUNT_MOVED=0
COUNT_BACKFILLED=0
COUNT_UNCHANGED=0
COUNT_FAILED=0
FAILED_FILES=()

# ── Helpers ────────────────────────────────────────────────────────────────────

usage() {
  cat >&2 <<EOF
usage: $0 [--dry-run] [--workspace-root <path>]

Options:
  --dry-run          Print migration plan without making changes
  --workspace-root   Root of the workspace (default: auto-detect)
EOF
  exit 2
}

log() {
  echo "$@"
}

log_to_file() {
  echo "$@" >> "$LOG_FILE"
}

# Detect workspace root: try env var, then git root
detect_workspace_root() {
  if [[ -n "${POLARIS_WORKSPACE_ROOT:-}" && -d "$POLARIS_WORKSPACE_ROOT" ]]; then
    echo "$POLARIS_WORKSPACE_ROOT"
    return
  fi
  # Try to find git root from script location
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local git_root
  git_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$git_root" ]]; then
    # workspace root is one level up from the framework repo (or is the workspace itself)
    # Convention: workspace contains {company}/ directories with specs/
    echo "$git_root"
    return
  fi
  echo ""
}

# Find all company specs directories with tasks/T*.md
find_task_files() {
  local root="$1"
  # Search in both the worktree root and the parent workspace
  # Prioritize company-scoped specs patterns
  find "$root" \
    \( -path "*/.worktrees/*" -o -path "*/node_modules/*" \) -prune -o \
    -path "*/specs/*/tasks/T*.md" -not -path "*/pr-release/*" \
    -type f -print 2>/dev/null | sort
}

# Check if a file has IMPLEMENTED status in frontmatter
is_implemented() {
  local file="$1"
  # frontmatter is between first --- and second ---
  awk '
    /^---/ { count++; next }
    count == 1 && /^status:[[:space:]]*IMPLEMENTED/ { print "yes"; exit }
    count >= 2 { exit }
  ' "$file" | grep -q "yes"
}

# Extract frontmatter block
extract_frontmatter() {
  local file="$1"
  awk '
    /^---/ { count++; if (count==2) exit; next }
    count == 1 { print }
  ' "$file"
}

# Check if validator script exists
find_validator() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local validator="${script_dir}/validate-task-md.sh"
  if [[ -f "$validator" ]]; then
    echo "$validator"
  else
    echo ""
  fi
}

# Run validator, capture output
run_validator() {
  local validator="$1"
  local file="$2"
  local output
  output=$("$validator" "$file" 2>&1) || true
  echo "$output"
}

validator_passes() {
  local validator="$1"
  local file="$2"
  "$validator" "$file" >/dev/null 2>&1
}

# ── Section presence checks ────────────────────────────────────────────────────

has_section() {
  local file="$1"
  local heading="$2"
  grep -qF "$heading" "$file"
}

has_section_with_content() {
  local file="$1"
  local heading="$2"
  if ! has_section "$file" "$heading"; then
    return 1
  fi
  local body
  body=$(awk -v heading="$heading" '
    $0 == heading { in_section=1; next }
    /^## / && in_section { exit }
    in_section { print }
  ' "$file")
  local content_lines
  content_lines=$(printf '%s\n' "$body" | awk '
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*>/ { next }
    { count++ }
    END { print count+0 }
  ')
  [[ "$content_lines" -gt 0 ]]
}

has_fenced_code_block_in_section() {
  local file="$1"
  local heading="$2"
  local body
  body=$(awk -v heading="$heading" '
    $0 == heading { in_section=1; next }
    /^## / && in_section { exit }
    in_section { print }
  ' "$file")
  printf '%s\n' "$body" | grep -q '^\`\`\`'
}

has_test_env_level() {
  local file="$1"
  grep -qE '^\*\*Level\*\*: (static|build|runtime)\b' "$file" || \
  grep -qE '^- \*\*Level\*\*: (static|build|runtime)\b' "$file"
}

has_runtime_verify_target() {
  local file="$1"
  grep -qE '^\*\*Runtime verify target\*\*: .+' "$file" || \
  grep -qE '^- \*\*Runtime verify target\*\*: .+' "$file"
}

has_env_bootstrap_command() {
  local file="$1"
  grep -qE '^\*\*Env bootstrap command\*\*: .+' "$file" || \
  grep -qE '^- \*\*Env bootstrap command\*\*: .+' "$file"
}

has_op_ctx_field() {
  local file="$1"
  local field="$2"
  grep -qF "$field" "$file"
}

# ── Operational Context Hard cell check ──────────────────────────────────────

# Returns list of missing Hard Op Ctx fields that CANNOT be backfilled (need human)
# These are: Task JIRA key, Base branch, Task branch (can be read from filename/header sometimes)
# Per DP-033 A7 design: "Operational Context table cells (Hard ones only) missing → fail loud"
check_op_ctx_cannot_backfill() {
  local file="$1"
  local missing=()

  # Check if Operational Context section exists at all
  if ! has_section "$file" "## Operational Context"; then
    # We can insert the whole section with TODOs (below), but the JIRA key itself we cannot fabricate
    # The validator requires ≥1 JIRA key in the section — we'll insert placeholder but mark as fail-loud
    # Actually: we CAN insert a placeholder section with TODO — but it won't have a real JIRA key
    # → The validator checks for JIRA key pattern; TODO won't match → still FAIL → fail loud
    echo "Operational Context section entirely missing (contains JIRA key - cannot auto-backfill)"
    return
  fi

  # Check for JIRA key in Operational Context
  local op_ctx
  op_ctx=$(awk '
    $0 == "## Operational Context" { in_section=1; next }
    /^## / && in_section { exit }
    in_section { print }
  ' "$file")
  if ! printf '%s' "$op_ctx" | grep -qE '[A-Z][A-Z0-9]+-[0-9]+'; then
    echo "Operational Context missing JIRA key - cannot auto-backfill"
  fi

  # These required fields in Op Ctx table need human knowledge:
  local hard_op_ctx_fields=("Task JIRA key" "Base branch" "Task branch")
  for field in "${hard_op_ctx_fields[@]}"; do
    if ! has_op_ctx_field "$file" "$field"; then
      echo "Operational Context missing required field: $field - cannot auto-backfill"
    fi
  done
}

# ── Backfill logic ─────────────────────────────────────────────────────────────

# Append a section to the file (at end) if not present
append_section_if_missing() {
  local file="$1"
  local heading="$2"
  local content="$3"

  if has_section "$file" "$heading"; then
    return 0  # already present
  fi

  printf '\n%s\n\n%s\n' "$heading" "$content" >> "$file"
}

# Insert content into an existing empty section
# If section exists but has no content, insert placeholder after heading
fill_empty_section() {
  local file="$1"
  local heading="$2"
  local placeholder="$3"

  if ! has_section "$file" "$heading"; then
    return 0  # not present, will be handled by append
  fi
  if has_section_with_content "$file" "$heading"; then
    return 0  # already has content
  fi

  # Use python to insert after the heading line
  python3 - "$file" "$heading" "$placeholder" <<'PYEOF'
import sys
file_path, heading, placeholder = sys.argv[1], sys.argv[2], sys.argv[3]

with open(file_path, 'r') as f:
    lines = f.readlines()

result = []
i = 0
while i < len(lines):
    line = lines[i]
    result.append(line)
    if line.rstrip() == heading:
        # Insert placeholder after heading, before next ## heading
        i += 1
        # Skip blank lines immediately after heading
        while i < len(lines) and lines[i].strip() == '':
            result.append(lines[i])
            i += 1
        # Insert placeholder if next line isn't already content or another heading
        if i >= len(lines) or lines[i].startswith('## '):
            result.append(placeholder + '\n')
            result.append('\n')
        else:
            # There might be existing (empty-looking) content — skip
            pass
        continue
    i += 1

with open(file_path, 'w') as f:
    f.writelines(result)
PYEOF
}

# Main backfill function: insert all missing Hard sections
force_backfill_file() {
  local file="$1"
  local changes_made=()

  # 1. ## Allowed Files
  if ! has_section "$file" "## Allowed Files"; then
    append_section_if_missing "$file" "## Allowed Files" \
      "- TODO(DP-033-migration): backfill — list files in scope"
    changes_made+=("Added ## Allowed Files placeholder")
  elif ! has_section_with_content "$file" "## Allowed Files"; then
    fill_empty_section "$file" "## Allowed Files" \
      "- TODO(DP-033-migration): backfill — list files in scope"
    changes_made+=("Filled empty ## Allowed Files placeholder")
  fi

  # 2. ## 改動範圍
  if ! has_section "$file" "## 改動範圍"; then
    append_section_if_missing "$file" "## 改動範圍" \
      "> TODO(DP-033-migration): backfill — describe scope of change"
    changes_made+=("Added ## 改動範圍 placeholder")
  elif ! has_section_with_content "$file" "## 改動範圍"; then
    fill_empty_section "$file" "## 改動範圍" \
      "> TODO(DP-033-migration): backfill — describe scope of change"
    changes_made+=("Filled empty ## 改動範圍 placeholder")
  fi

  # 3. ## 估點理由
  if ! has_section "$file" "## 估點理由"; then
    append_section_if_missing "$file" "## 估點理由" \
      "> TODO(DP-033-migration): backfill — story-points justification"
    changes_made+=("Added ## 估點理由 placeholder")
  elif ! has_section_with_content "$file" "## 估點理由"; then
    fill_empty_section "$file" "## 估點理由" \
      "> TODO(DP-033-migration): backfill — story-points justification"
    changes_made+=("Filled empty ## 估點理由 placeholder")
  fi

  # 4. ## Test Command (needs fenced code block)
  if ! has_section "$file" "## Test Command"; then
    append_section_if_missing "$file" "## Test Command" \
      '```bash
# TODO(DP-033-migration): real test command pending
```'
    changes_made+=("Added ## Test Command placeholder")
  elif ! has_fenced_code_block_in_section "$file" "## Test Command"; then
    # Section exists but no fenced code block — append one
    python3 - "$file" "## Test Command" <<'PYEOF'
import sys
file_path, heading = sys.argv[1], sys.argv[2]
placeholder = '```bash\n# TODO(DP-033-migration): real test command pending\n```\n'

with open(file_path, 'r') as f:
    content = f.read()

lines = content.split('\n')
result = []
in_section = False
inserted = False
i = 0
while i < len(lines):
    line = lines[i]
    if line == heading:
        in_section = True
        result.append(line)
        i += 1
        continue
    if in_section and line.startswith('## ') and line != heading:
        if not inserted:
            result.append('```bash')
            result.append('# TODO(DP-033-migration): real test command pending')
            result.append('```')
            result.append('')
            inserted = True
        in_section = False
    result.append(line)
    i += 1

if in_section and not inserted:
    result.append('```bash')
    result.append('# TODO(DP-033-migration): real test command pending')
    result.append('```')

with open(file_path, 'w') as f:
    f.write('\n'.join(result))
PYEOF
    changes_made+=("Added fenced code block to ## Test Command")
  fi

  # 5. ## Test Environment
  if ! has_section "$file" "## Test Environment"; then
    append_section_if_missing "$file" "## Test Environment" \
"- **Level**: static
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A"
    changes_made+=("Added ## Test Environment placeholder (Level=static)")
  else
    # Check for required sub-fields
    local env_changed=false
    if ! has_test_env_level "$file"; then
      # Insert Level line
      python3 - "$file" "## Test Environment" "- **Level**: static" <<'PYEOF'
import sys, re
file_path, heading, insert_line = sys.argv[1], sys.argv[2], sys.argv[3]

with open(file_path, 'r') as f:
    lines = f.readlines()

result = []
in_section = False
inserted = False
for i, line in enumerate(lines):
    result.append(line)
    if line.rstrip() == heading:
        in_section = True
        continue
    if in_section and not inserted and (line.strip() == '' or line.startswith('- **')):
        if line.strip() == '' or (not re.search(r'\*\*Level\*\*', line)):
            result.insert(len(result)-1, insert_line + '\n')
            inserted = True
            in_section = False

with open(file_path, 'w') as f:
    f.writelines(result)
PYEOF
      changes_made+=("Added missing Level line to ## Test Environment")
      env_changed=true
    fi

    if ! has_runtime_verify_target "$file"; then
      echo "- **Runtime verify target**: N/A" >> "$file"
      changes_made+=("Added missing Runtime verify target to ## Test Environment")
      env_changed=true
    fi

    if ! has_env_bootstrap_command "$file"; then
      echo "- **Env bootstrap command**: N/A" >> "$file"
      changes_made+=("Added missing Env bootstrap command to ## Test Environment")
      env_changed=true
    fi
  fi

  # 6. ## Verify Command (needs fenced code block)
  if ! has_section "$file" "## Verify Command"; then
    append_section_if_missing "$file" "## Verify Command" \
      '```bash
# TODO(DP-033-migration): verify command pending (Level=static assumed)
# Replace with actual verification command when Level is known
true  # no-op for static level
```'
    changes_made+=("Added ## Verify Command placeholder")
  elif ! has_fenced_code_block_in_section "$file" "## Verify Command"; then
    python3 - "$file" "## Verify Command" <<'PYEOF'
import sys
file_path, heading = sys.argv[1], sys.argv[2]

with open(file_path, 'r') as f:
    content = f.read()

lines = content.split('\n')
result = []
in_section = False
inserted = False
i = 0
while i < len(lines):
    line = lines[i]
    if line == heading:
        in_section = True
        result.append(line)
        i += 1
        continue
    if in_section and line.startswith('## ') and line != heading:
        if not inserted:
            result.append('```bash')
            result.append('# TODO(DP-033-migration): verify command pending (Level=static assumed)')
            result.append('true  # no-op for static level')
            result.append('```')
            result.append('')
            inserted = True
        in_section = False
    result.append(line)
    i += 1

if in_section and not inserted:
    result.append('```bash')
    result.append('# TODO(DP-033-migration): verify command pending (Level=static assumed)')
    result.append('true  # no-op for static level')
    result.append('```')

with open(file_path, 'w') as f:
    f.write('\n'.join(result))
PYEOF
    changes_made+=("Added fenced code block to ## Verify Command")
  fi

  # 6b. Missing Operational Context table rows (backfillable ones)
  # The validator requires these rows in the Op Ctx table; we can insert TODO rows.
  # Non-backfillable rows (Task JIRA key, Base branch, Task branch) already handled above.
  local backfillable_op_ctx_rows=("Test sub-tasks" "AC 驗收單" "References to load")
  for ctx_row in "${backfillable_op_ctx_rows[@]}"; do
    if ! has_op_ctx_field "$file" "$ctx_row"; then
      # Insert a TODO row into the Op Ctx table
      python3 - "$file" "$ctx_row" <<'PYEOF'
import sys
file_path, field = sys.argv[1], sys.argv[2]
todo_row = f"| {field} | TODO(DP-033-migration): backfill — {field} |"

with open(file_path, 'r') as f:
    lines = f.readlines()

result = []
in_op_ctx = False
table_ended = False
for i, line in enumerate(lines):
    if line.rstrip() == "## Operational Context":
        in_op_ctx = True
        result.append(line)
        continue
    if in_op_ctx and not table_ended:
        # Insert before the next ## heading or blank line after table
        if line.startswith('## ') and line.rstrip() != "## Operational Context":
            # End of section — insert before it
            result.append(todo_row + '\n')
            result.append('\n')
            table_ended = True
            in_op_ctx = False
            result.append(line)
            continue
        elif line.startswith('|'):
            result.append(line)
            continue
        else:
            # blank line or non-table line after table — insert before it
            result.append(todo_row + '\n')
            table_ended = True
            in_op_ctx = False
    result.append(line)

if in_op_ctx and not table_ended:
    result.append(todo_row + '\n')

with open(file_path, 'w') as f:
    f.writelines(result)
PYEOF
      changes_made+=("Added missing Op Ctx row: $ctx_row (TODO placeholder)")
    fi
  done

  # 7. ## Verification Handoff (soft-required, but validator checks existence)
  if ! has_section "$file" "## Verification Handoff"; then
    append_section_if_missing "$file" "## Verification Handoff" \
      "> TODO(DP-033-migration): backfill — specify AC verification delegation"
    changes_made+=("Added ## Verification Handoff placeholder")
  fi

  # 8. ## 目標 (soft-required but validator checks non-empty)
  if ! has_section "$file" "## 目標"; then
    append_section_if_missing "$file" "## 目標" \
      "> TODO(DP-033-migration): backfill — describe task objective"
    changes_made+=("Added ## 目標 placeholder")
  elif ! has_section_with_content "$file" "## 目標"; then
    fill_empty_section "$file" "## 目標" \
      "> TODO(DP-033-migration): backfill — describe task objective"
    changes_made+=("Filled empty ## 目標 placeholder")
  fi

  # Return list of changes
  printf '%s\n' "${changes_made[@]:-}"
}

# ── Move logic ─────────────────────────────────────────────────────────────────

move_to_complete() {
  local file="$1"
  local dry_run="$2"
  local tasks_dir
  tasks_dir="$(dirname "$file")"
  local pr_release_dir="${tasks_dir}/pr-release"
  local filename
  filename="$(basename "$file")"
  local dest="${pr_release_dir}/${filename}"

  if [[ "$dry_run" == "true" ]]; then
    log "  [DRY-RUN] Would move: $file → $dest"
    return 0
  fi

  mkdir -p "$pr_release_dir"
  mv "$file" "$dest"
  log "  Moved: $file → $dest"
}

# ── Per-file migration ─────────────────────────────────────────────────────────

migrate_file() {
  local file="$1"
  local validator="$2"
  local dry_run="$3"
  local rel_file="${file#$WORKSPACE_ROOT/}"

  log ""
  log "### Processing: $rel_file"
  log_to_file ""
  log_to_file "### $rel_file"

  # ── 0. Already in pr-release/? (idempotency) ──────────────────────────────
  if [[ "$file" == */pr-release/* ]]; then
    log "  UNCHANGED (already in pr-release/)"
    log_to_file "- action: UNCHANGED (already in pr-release/)"
    COUNT_UNCHANGED=$((COUNT_UNCHANGED + 1))
    return 0
  fi

  # ── 1. Check if IMPLEMENTED → move ────────────────────────────────────
  if is_implemented "$file"; then
    local tasks_dir
    tasks_dir="$(dirname "$file")"
    local pr_release_dir="${tasks_dir}/pr-release"
    local filename
    filename="$(basename "$file")"
    local dest="${pr_release_dir}/${filename}"

    if [[ -f "$dest" ]]; then
      log "  UNCHANGED (dest already exists: $dest)"
      log_to_file "- action: UNCHANGED (already completed at $dest)"
      COUNT_UNCHANGED=$((COUNT_UNCHANGED + 1))
      return 0
    fi

    log "  Status: IMPLEMENTED → moving to pr-release/"
    log_to_file "- action: MOVED"
    log_to_file "- source: $file"
    log_to_file "- dest: $dest"

    move_to_complete "$file" "$dry_run"
    COUNT_MOVED=$((COUNT_MOVED + 1))
    return 0
  fi

  # ── 2. Active task → validate ─────────────────────────────────────────
  log "  Status: ACTIVE → running validator"

  local pre_validate_output
  pre_validate_output=$(run_validator "$validator" "$file")
  local pre_validate_exit=0
  "$validator" "$file" >/dev/null 2>&1 || pre_validate_exit=$?

  if [[ "$pre_validate_exit" -eq 0 ]]; then
    log "  Validator: PASS (no backfill needed)"
    log_to_file "- action: UNCHANGED"
    log_to_file "- validator-before: PASS"
    COUNT_UNCHANGED=$((COUNT_UNCHANGED + 1))
    return 0
  fi

  log "  Validator: FAIL"
  log "  Violations:"
  echo "$pre_validate_output" | sed 's/^/    /'
  log_to_file "- validator-before: FAIL"
  log_to_file "- violations-before: |"
  echo "$pre_validate_output" | sed 's/^/    /' >> "$LOG_FILE"

  # ── 3. Check for Operational Context hard cells (cannot backfill) ──────
  local op_ctx_errors
  op_ctx_errors=$(check_op_ctx_cannot_backfill "$file")
  if [[ -n "$op_ctx_errors" ]]; then
    log "  FAIL LOUD — Operational Context has non-backfillable errors:"
    echo "$op_ctx_errors" | sed 's/^/    [CANNOT BACKFILL] /'
    log "  Human intervention required. Halting migration."
    log_to_file "- action: FAILED"
    log_to_file "- reason: Operational Context non-backfillable"
    log_to_file "- op-ctx-errors: |"
    echo "$op_ctx_errors" | sed 's/^/    /' >> "$LOG_FILE"
    COUNT_FAILED=$((COUNT_FAILED + 1))
    FAILED_FILES+=("$file")
    return 1
  fi

  # ── 4. Attempt force backfill ─────────────────────────────────────────
  if [[ "$dry_run" == "true" ]]; then
    log "  [DRY-RUN] Would attempt force-backfill of missing Hard sections"
    log_to_file "- action: WOULD-BACKFILL (dry-run)"
    COUNT_BACKFILLED=$((COUNT_BACKFILLED + 1))
    return 0
  fi

  log "  Attempting force-backfill..."
  local backfill_changes
  backfill_changes=$(force_backfill_file "$file")

  if [[ -n "$backfill_changes" ]]; then
    log "  Backfill applied:"
    echo "$backfill_changes" | sed 's/^/    + /'
    log_to_file "- backfill-changes: |"
    echo "$backfill_changes" | sed 's/^/    /' >> "$LOG_FILE"
  else
    log "  No backfill changes made (sections may already exist)"
  fi

  # ── 5. Re-validate after backfill ─────────────────────────────────────
  local post_validate_output
  post_validate_output=$(run_validator "$validator" "$file")
  local post_validate_exit=0
  "$validator" "$file" >/dev/null 2>&1 || post_validate_exit=$?

  log_to_file "- validator-after: $([ $post_validate_exit -eq 0 ] && echo PASS || echo FAIL)"

  if [[ "$post_validate_exit" -eq 0 ]]; then
    log "  Validator: PASS (after backfill)"
    log_to_file "- action: BACKFILLED"
    COUNT_BACKFILLED=$((COUNT_BACKFILLED + 1))
    return 0
  fi

  # Still failing after backfill → FAIL LOUD
  log "  FAIL LOUD — validator still failing after backfill:"
  echo "$post_validate_output" | sed 's/^/    [STILL FAILING] /'
  log "  Remaining violations require human intervention. Halting migration."
  log_to_file "- action: FAILED"
  log_to_file "- reason: validator still failing after backfill"
  log_to_file "- violations-after: |"
  echo "$post_validate_output" | sed 's/^/    /' >> "$LOG_FILE"

  COUNT_FAILED=$((COUNT_FAILED + 1))
  FAILED_FILES+=("$file")
  return 1
}

# ── Main ───────────────────────────────────────────────────────────────────────

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --workspace-root)
      if [[ $# -lt 2 ]]; then usage; fi
      WORKSPACE_ROOT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

# Auto-detect workspace root if not provided
if [[ -z "$WORKSPACE_ROOT" ]]; then
  WORKSPACE_ROOT=$(detect_workspace_root)
fi
if [[ -z "$WORKSPACE_ROOT" || ! -d "$WORKSPACE_ROOT" ]]; then
  echo "error: could not detect workspace root. Use --workspace-root or set POLARIS_WORKSPACE_ROOT." >&2
  exit 2
fi

# Find validator
VALIDATOR=$(find_validator)
if [[ -z "$VALIDATOR" ]]; then
  echo "error: validate-task-md.sh not found in $(dirname "${BASH_SOURCE[0]}")" >&2
  exit 2
fi

# Initialize log
cat > "$LOG_FILE" <<HEADER
# DP-033 Migration Log
- timestamp: ${TIMESTAMP}
- workspace_root: ${WORKSPACE_ROOT}
- mode: $([ "$DRY_RUN" == "true" ] && echo "DRY-RUN" || echo "APPLY")
- validator: ${VALIDATOR}

## Tasks

HEADER

log "=================================================="
log "DP-033 A7: Task.md Migration Script"
log "Mode: $([ "$DRY_RUN" == "true" ] && echo "DRY-RUN" || echo "APPLY")"
log "Workspace: $WORKSPACE_ROOT"
log "Log: $LOG_FILE"
log "=================================================="

# Inventory all T*.md files
log ""
log "## Inventory"
TASK_FILES=()
while IFS= read -r f; do
  TASK_FILES+=("$f")
done < <(find_task_files "$WORKSPACE_ROOT")

TOTAL="${#TASK_FILES[@]}"
log "Found $TOTAL T*.md file(s) in active tasks/ directories"
log ""
log "## Migration"

log_to_file "total-found: $TOTAL"
log_to_file ""

# Process each file
EXIT_CODE=0
for file in "${TASK_FILES[@]}"; do
  if ! migrate_file "$file" "$VALIDATOR" "$DRY_RUN"; then
    EXIT_CODE=1
    # Per spec: fail loud and stop remaining tasks
    log ""
    log "!! HALTED: migration stopped at first FAIL. Resolve the file above and re-run."
    break
  fi
done

# ── Summary ────────────────────────────────────────────────────────────────────

log ""
log "=================================================="
log "## Summary"
log "  moved:       $COUNT_MOVED"
log "  backfilled:  $COUNT_BACKFILLED"
log "  unchanged:   $COUNT_UNCHANGED"
log "  failed:      $COUNT_FAILED"
log "  total:       $TOTAL"
log "=================================================="
log "Log written to: $LOG_FILE"

# Write summary to log
cat >> "$LOG_FILE" <<SUMMARY

## Summary

| Action | Count |
|--------|-------|
| moved (IMPLEMENTED → pr-release/) | $COUNT_MOVED |
| backfilled (Hard sections inserted) | $COUNT_BACKFILLED |
| unchanged (already valid or already pr-release) | $COUNT_UNCHANGED |
| failed (human intervention required) | $COUNT_FAILED |
| **total** | **$TOTAL** |

SUMMARY

if [[ ${#FAILED_FILES[@]} -gt 0 ]]; then
  log ""
  log "Failed files:"
  log_to_file ""
  log_to_file "## Failed Files (require human intervention)"
  for f in "${FAILED_FILES[@]}"; do
    log "  - $f"
    log_to_file "- $f"
  done
fi

if [[ "$DRY_RUN" == "true" ]]; then
  log ""
  log "DRY-RUN complete. No files were modified."
fi

exit $EXIT_CODE
