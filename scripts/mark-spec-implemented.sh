#!/usr/bin/env bash
# Mark an Epic/Bug/Task spec as IMPLEMENTED (or ABANDONED) by updating
# the frontmatter status field in refinement.md / plan.md / task.md.
#
# Usage:
#   mark-spec-implemented.sh <ticket_key> [--status IMPLEMENTED|ABANDONED] [--workspace <path>]
#
# Examples:
#   mark-spec-implemented.sh GT-521
#   mark-spec-implemented.sh KB2CW-3847 --status IMPLEMENTED
#   mark-spec-implemented.sh GT-483 --status ABANDONED
#
# Behavior:
#   Epic/Bug anchor (refinement.md / plan.md):
#     - Updates frontmatter in-place (existing behavior, unchanged)
#     - Idempotent: already same status → NOOP exit 0
#
#   Task anchor (T{n}.md / V{n}.md  resolved by "JIRA: KEY" header):
#     - MOVE-FIRST sequence (DP-033 D6):
#         1. mv tasks/T.md → tasks/pr-release/T.md
#         2. Update frontmatter status in pr-release/T.md
#     - Idempotent:
#         - File already in pr-release/ + already IMPLEMENTED → NOOP exit 0
#         - File already in pr-release/ (different status) → update frontmatter, exit 0
#         - tasks/ copy AND pr-release/ copy with SAME content → remove active, continue
#         - tasks/ copy AND pr-release/ copy with DIFFERENT content → exit 2 (invariant violation)
#     - Creates tasks/pr-release/ directory if absent
#
# Exit codes:
#   0 — success (including idempotent no-op)
#   1 — error (file not found, parse failure, filesystem error)
#   2 — same-key invariant violation (tasks/ and pr-release/ exist with different content)
#
# Non-goals:
#   - Does NOT sync to JIRA
#   - Does NOT regenerate sidebar (docs-viewer-sync-hook handles that via PostToolUse)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARSE_TASK_MD="${SCRIPT_DIR}/parse-task-md.sh"

run_selftest() {
  local tmpdir=""
  local rc=0

  tmpdir="$(mktemp -d -t mark-spec-implemented-selftest.XXXXXX)"
  trap "rm -rf '$tmpdir'" EXIT

  mkdir -p "$tmpdir/specs/design-plans/DP-050-dp-pseudo-task-identity-separation/tasks" \
           "$tmpdir/specs/companies/kkday/GT-001/tasks" \
           "$tmpdir/specs/companies/kkday/archive/GT-OLD/tasks"
  cat > "$tmpdir/specs/design-plans/DP-050-dp-pseudo-task-identity-separation/tasks/T1.md" <<'MD'
# T1: Canonical DP task (1 pt)

> Source: DP-050 | Task: DP-050-T1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-050 |
| Task ID | DP-050-T1 |
| JIRA key | N/A |
| Base branch | main |
| Task branch | task/DP-050-T1-canonical |
MD

  rc=0
  env -u MARK_SPEC_IMPLEMENTED_SELFTEST bash "$0" DP-050-T1 --workspace "$tmpdir" >/dev/null || rc=$?
  [[ "$rc" -eq 0 ]] || { echo "[selftest] canonical DP mark implemented failed"; return 1; }
  [[ ! -f "$tmpdir/specs/design-plans/DP-050-dp-pseudo-task-identity-separation/tasks/T1.md" ]] || { echo "[selftest] active task was not moved"; return 1; }
  [[ -f "$tmpdir/specs/design-plans/DP-050-dp-pseudo-task-identity-separation/tasks/pr-release/T1.md" ]] || { echo "[selftest] pr-release task missing"; return 1; }
  grep -q '^status: IMPLEMENTED$' "$tmpdir/specs/design-plans/DP-050-dp-pseudo-task-identity-separation/tasks/pr-release/T1.md" || { echo "[selftest] status missing"; return 1; }

  cat > "$tmpdir/specs/companies/kkday/GT-001/tasks/T2.md" <<'MD'
# T2: Active product task (1 pt)
> Source: GT-001 | Task: GT-001 | JIRA: GT-001 | Repo: kkday
## Operational Context
| 欄位 | 值 |
|------|-----|
| Source type | jira |
| Source ID | GT-001 |
| Task ID | GT-001 |
| JIRA key | GT-001 |
| Base branch | main |
| Task branch | task/GT-001-active |
MD

  cat > "$tmpdir/specs/companies/kkday/archive/GT-OLD/tasks/T2.md" <<'MD'
# T2: Archived product task (1 pt)
> Source: GT-OLD | Task: GT-OLD | JIRA: GT-OLD | Repo: kkday
## Operational Context
| Task branch | task/GT-OLD-archived |
MD

  rc=0
  env -u MARK_SPEC_IMPLEMENTED_SELFTEST bash "$0" T2 --workspace "$tmpdir" >/dev/null || rc=$?
  [[ "$rc" -eq 0 ]] || { echo "[selftest] active task key mark implemented failed"; return 1; }
  [[ -f "$tmpdir/specs/companies/kkday/GT-001/tasks/pr-release/T2.md" ]] || { echo "[selftest] active T2 pr-release task missing"; return 1; }
  [[ -f "$tmpdir/specs/companies/kkday/archive/GT-OLD/tasks/T2.md" ]] || { echo "[selftest] archived T2 was moved unexpectedly"; return 1; }

  echo "[selftest] PASS"
}

if [[ "${MARK_SPEC_IMPLEMENTED_SELFTEST:-0}" == "1" ]]; then
  run_selftest
  exit $?
fi

TICKET=""
STATUS="IMPLEMENTED"
WORKSPACE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --status)     STATUS="$2"; shift 2 ;;
    --workspace)  WORKSPACE_ROOT="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,33p' "$0"
      exit 0
      ;;
    *)
      if [ -z "$TICKET" ]; then
        TICKET="$1"
        shift
      else
        echo "ERROR: unexpected arg: $1" >&2
        exit 1
      fi
      ;;
  esac
done

if [ -z "$TICKET" ]; then
  echo "ERROR: ticket key required (e.g., GT-521 or KB2CW-3847)" >&2
  exit 1
fi

case "$STATUS" in
  IMPLEMENTED|ABANDONED|LOCKED|DISCUSSION) ;;
  *)
    echo "ERROR: invalid status '$STATUS' (must be IMPLEMENTED|ABANDONED|LOCKED|DISCUSSION)" >&2
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# update_frontmatter_status <file> <new_status>
#   Updates (or inserts) `status: <new_status>` in YAML frontmatter.
#   Exits non-zero on parse failure.
# ---------------------------------------------------------------------------
update_frontmatter_status() {
  python3 - "$1" "$2" <<'PY'
import sys
import re
from pathlib import Path

path = Path(sys.argv[1])
new_status = sys.argv[2]

content = path.read_text(encoding="utf-8")
lines = content.split("\n")

if lines and lines[0] == "---":
    # Has frontmatter — find closing ---
    try:
        close_idx = lines.index("---", 1)
    except ValueError:
        print(f"ERROR: unclosed frontmatter in {path}", file=sys.stderr)
        sys.exit(1)

    fm = lines[1:close_idx]
    status_pattern = re.compile(r"^status:\s*")
    found = False
    for i, line in enumerate(fm):
        if status_pattern.match(line):
            fm[i] = f"status: {new_status}"
            found = True
            break
    if not found:
        fm.append(f"status: {new_status}")

    new_content = "---\n" + "\n".join(fm) + "\n---\n" + "\n".join(lines[close_idx+1:])
else:
    # No frontmatter — prepend
    new_content = f"---\nstatus: {new_status}\n---\n\n" + content

path.write_text(new_content, encoding="utf-8")
print(f"OK: {path} → status: {new_status}")
PY
}

# ---------------------------------------------------------------------------
# get_existing_status <file>
#   Echoes the current status value (may be empty string if absent).
# ---------------------------------------------------------------------------
get_existing_status() {
  local file="$1"
  local existing_status=""
  if head -1 "$file" | grep -q '^---$'; then
    existing_status=$(sed -n '/^---$/,/^---$/p' "$file" | grep '^status:' | head -1 | sed 's/^status:[[:space:]]*//' || true)
  fi
  printf '%s' "$existing_status"
}

# ---------------------------------------------------------------------------
# is_task_key <string>
#   Returns 0 (true) if the string looks like a task filename key: T{n}[a-z]
#   or V{n}[a-z] (i.e., a bare task ID, NOT a full path and NOT a JIRA key).
# ---------------------------------------------------------------------------
is_task_key() {
  echo "$1" | grep -qE '^[TV][0-9]+[a-z]*$'
}

# ---------------------------------------------------------------------------
# Resolve anchor file — three resolution paths:
#   1) Epic-level: {workspace}/specs/companies/<company>/<ticket>/refinement.md or plan.md
#   2) Task-level (task key T{n}/V{n}): scan specs/*/tasks/ by filename
#   3) DP task-level (DP-NNN-Tn): scan root specs/design-plans/DP-NNN-*/tasks/Tn.md
#   4) Task-level (JIRA key): parser jira_key match first, legacy "> JIRA: <ticket>" fallback
# ---------------------------------------------------------------------------
ANCHOR=""
ANCHOR_TYPE=""  # "epic" | "task"
TASK_FILENAME=""  # basename of task file (T1.md, T3b.md, V1.md, ...)
TASKS_DIR=""    # absolute path to the tasks/ directory containing the task

# Path 1 — Epic-level
for company_specs_dir in "$WORKSPACE_ROOT"/specs/companies/*/; do
  [ -d "$company_specs_dir" ] || continue
  candidate="${company_specs_dir}${TICKET}"
  if [ -d "$candidate" ]; then
    if [ -f "$candidate/refinement.md" ]; then
      ANCHOR="$candidate/refinement.md"
      ANCHOR_TYPE="epic"
      break
    fi
    if [ -f "$candidate/plan.md" ]; then
      ANCHOR="$candidate/plan.md"
      ANCHOR_TYPE="epic"
      break
    fi
  fi
done

# Path 2 — Task key (T{n}/V{n}) — look up by filename in active tasks/ or pr-release/
if [ -z "$ANCHOR" ] && is_task_key "$TICKET"; then
  # Search for T{n}[suffix].md or V{n}[suffix].md in tasks/ directories
  # The key is the "stem" (e.g., T1 matches T1.md but not T10.md).
  # We match: tasks/{TICKET}.md  or  tasks/pr-release/{TICKET}.md
  while IFS= read -r f; do
    bname="$(basename "$f")"
    stem="${bname%.md}"
    if [ "$stem" = "$TICKET" ]; then
      ANCHOR="$f"
      TASK_FILENAME="$bname"
      # Determine TASKS_DIR: strip /pr-release/ suffix if present
      dir="$(dirname "$f")"
      if [ "$(basename "$dir")" = "pr-release" ]; then
        TASKS_DIR="$(dirname "$dir")"
      else
        TASKS_DIR="$dir"
      fi
      ANCHOR_TYPE="task"
      break
    fi
  done < <(find "$WORKSPACE_ROOT" \
    \( -type d \( -name .git -o -name .worktrees -o -name node_modules -o -name archive \) -prune \) \
    -o \( -type f \( \
      -path "*/tasks/${TICKET}.md" \
      -o -path "*/tasks/pr-release/${TICKET}.md" \
    \) -print \) 2>/dev/null)
fi

# Path 3 — DP task key (DP-NNN-Tn) — look up by DP folder + task filename
if [ -z "$ANCHOR" ] && echo "$TICKET" | grep -qE '^DP-[0-9]{3}-T[0-9]+[a-z]*$'; then
  dp_id="$(printf '%s' "$TICKET" | sed -E 's/^(DP-[0-9]{3})-T[0-9]+[a-z]*$/\1/')"
  task_stem="$(printf '%s' "$TICKET" | sed -E 's/^DP-[0-9]{3}-(T[0-9]+[a-z]*)$/\1/')"
  for f in \
    "$WORKSPACE_ROOT"/specs/design-plans/"$dp_id"-*/tasks/"$task_stem".md \
    "$WORKSPACE_ROOT"/specs/design-plans/"$dp_id"-*/tasks/pr-release/"$task_stem".md
  do
    [ -f "$f" ] || continue
    ANCHOR="$f"
    TASK_FILENAME="$(basename "$f")"
    dir="$(dirname "$f")"
    if [ "$(basename "$dir")" = "pr-release" ]; then
      TASKS_DIR="$(dirname "$dir")"
    else
      TASKS_DIR="$dir"
    fi
    ANCHOR_TYPE="task"
    break
  done
fi

# Path 4 — Task-level by JIRA key in header (only if Path 1-3 missed)
if [ -z "$ANCHOR" ]; then
  # Search active tasks/ and tasks/pr-release/ by canonical parser jira_key
  # first, then legacy "> JIRA: KEY" header fallback.
  while IFS= read -r f; do
    parsed_jira=""
    if [ -x "$PARSE_TASK_MD" ]; then
      parsed_jira="$(bash "$PARSE_TASK_MD" "$f" --no-resolve --field jira_key 2>/dev/null || true)"
    fi
    if [ "$parsed_jira" = "$TICKET" ] || grep -Eq "^> .*JIRA: ${TICKET}([[:space:]]|\$|\|)" "$f"; then
      ANCHOR="$f"
      TASK_FILENAME="$(basename "$f")"
      dir="$(dirname "$f")"
      if [ "$(basename "$dir")" = "pr-release" ]; then
        TASKS_DIR="$(dirname "$dir")"
      else
        TASKS_DIR="$dir"
      fi
      ANCHOR_TYPE="task"
      break
    fi
  done < <(find "$WORKSPACE_ROOT" \
    \( -type d \( -name .git -o -name .worktrees -o -name node_modules -o -name archive \) -prune \) \
    -o \( -type f \( \
      -path "*/specs/design-plans/*/tasks/T*.md" \
      -o -path "*/specs/design-plans/*/tasks/V*.md" \
      -o -path "*/specs/design-plans/*/tasks/pr-release/T*.md" \
      -o -path "*/specs/design-plans/*/tasks/pr-release/V*.md" \
      -o -path "*/specs/*/tasks/T*.md" \
      -o -path "*/specs/*/tasks/V*.md" \
      -o -path "*/specs/*/tasks/pr-release/T*.md" \
      -o -path "*/specs/*/tasks/pr-release/V*.md" \
    \) -print \) 2>/dev/null)
fi

if [ -z "$ANCHOR" ]; then
  echo "ERROR: no spec found for $TICKET" >&2
  echo "  Searched:" >&2
  echo "    - $WORKSPACE_ROOT/specs/companies/*/$TICKET/{refinement.md,plan.md}" >&2
  echo "    - $WORKSPACE_ROOT/*/specs/*/tasks/{T,V}*.md (by filename key '$TICKET')" >&2
  echo "    - $WORKSPACE_ROOT/specs/design-plans/DP-NNN-*/tasks/{T,V}*.md (by DP task key / header)" >&2
  echo "    - $WORKSPACE_ROOT/*/specs/*/tasks/{T,V}*.md (by '> JIRA: $TICKET' header)" >&2
  echo "    - $WORKSPACE_ROOT/*/specs/*/tasks/pr-release/*.md (active→pr-release fallback)" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Epic anchor — existing in-place update (behavior unchanged)
# ---------------------------------------------------------------------------
if [ "$ANCHOR_TYPE" = "epic" ]; then
  existing_status="$(get_existing_status "$ANCHOR")"
  if [ "$existing_status" = "$STATUS" ]; then
    echo "NOOP: $ANCHOR already has status: $STATUS"
    exit 0
  fi
  update_frontmatter_status "$ANCHOR" "$STATUS"
  exit 0
fi

# ---------------------------------------------------------------------------
# Task anchor — MOVE-FIRST sequence (DP-033 D6)
# ---------------------------------------------------------------------------
# At this point ANCHOR may be:
#   a) active:   TASKS_DIR/{TASK_FILENAME}
#   b) pr-release: TASKS_DIR/pr-release/{TASK_FILENAME}
# We need to ensure the move-first invariant.

ACTIVE_PATH="${TASKS_DIR}/${TASK_FILENAME}"
PR_RELEASE_DIR="${TASKS_DIR}/pr-release"
PR_RELEASE_PATH="${PR_RELEASE_DIR}/${TASK_FILENAME}"

# Determine current state
active_exists=0
pr_release_exists=0
[ -f "$ACTIVE_PATH" ]   && active_exists=1
[ -f "$PR_RELEASE_PATH" ] && pr_release_exists=1

# Case: already in pr-release/, not in active → check status, update if needed
if [ "$pr_release_exists" -eq 1 ] && [ "$active_exists" -eq 0 ]; then
  existing_status="$(get_existing_status "$PR_RELEASE_PATH")"
  if [ "$existing_status" = "$STATUS" ]; then
    echo "NOOP: $PR_RELEASE_PATH already has status: $STATUS (already moved)"
    exit 0
  fi
  update_frontmatter_status "$PR_RELEASE_PATH" "$STATUS"
  exit 0
fi

# Case: both exist — conflict detection
if [ "$active_exists" -eq 1 ] && [ "$pr_release_exists" -eq 1 ]; then
  if cmp -s "$ACTIVE_PATH" "$PR_RELEASE_PATH"; then
    # Same content — idempotent reconciliation: remove active copy, proceed
    echo "INFO: tasks/ and pr-release/ copies are identical — removing active copy (idempotent reconciliation)" >&2
    rm "$ACTIVE_PATH"
    active_exists=0
    # Now update frontmatter in pr-release/
    existing_status="$(get_existing_status "$PR_RELEASE_PATH")"
    if [ "$existing_status" = "$STATUS" ]; then
      echo "NOOP: $PR_RELEASE_PATH already has status: $STATUS"
      exit 0
    fi
    update_frontmatter_status "$PR_RELEASE_PATH" "$STATUS"
    exit 0
  else
    # Different content — same-key invariant violation, fail loudly
    echo "ERROR: same-key invariant violation for ${TASK_FILENAME}" >&2
    echo "  Both exist with DIFFERENT content:" >&2
    echo "    active:   $ACTIVE_PATH" >&2
    echo "    pr-release: $PR_RELEASE_PATH" >&2
    echo "  Manual resolution required — do NOT clobber." >&2
    echo "  Hint: verify which copy is authoritative, then remove the other." >&2
    exit 2
  fi
fi

# Case: only active exists — execute move-first sequence
if [ "$active_exists" -eq 1 ] && [ "$pr_release_exists" -eq 0 ]; then
  # Step 1: create pr-release/ directory if absent
  mkdir -p "$PR_RELEASE_DIR"

  # Step 2: mv (atomic within same filesystem; safe because we checked pr-release/ doesn't exist)
  mv "$ACTIVE_PATH" "$PR_RELEASE_PATH"
  echo "MOVED: $ACTIVE_PATH → $PR_RELEASE_PATH" >&2

  # Step 3: update frontmatter in pr-release/ location only
  update_frontmatter_status "$PR_RELEASE_PATH" "$STATUS"
  exit 0
fi

# Unreachable: neither active nor pr-release exists (ANCHOR was found above, so this can't happen)
echo "ERROR: unexpected state — $TASK_FILENAME not found at active or pr-release paths" >&2
exit 1
