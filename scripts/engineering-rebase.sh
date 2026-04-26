#!/usr/bin/env bash
# scripts/engineering-rebase.sh — DP-032 Wave γ D6
#
# Mechanical rebase for engineering tasks. Fetches origin, resolves base,
# rebases if stale, preserves conflict state for LLM to resolve in Phase 3.
# Post-rebase: calls changeset-clean-inherited.sh to remove inherited
# .changeset/ files (D24).
#
# Called by:
#   - engineer-delivery-flow.md § Step 2 前置 (always, idempotent)
#   - engineering/SKILL.md § Revision R0 (revision entry)
#
# Contract:
#   engineering-rebase.sh <task_md> [--cwd DIR]
#
# Steps:
#   1. parse-task-md.sh → resolved_base, task_jira_key, repo
#   2. git fetch origin {resolved_base}
#   3. git log HEAD..origin/{resolved_base} — any new commits?
#   4. No new commits → REBASE_NOOP, exit 0
#   5. git rebase origin/{resolved_base}
#   6. Conflict → preserve .git/rebase-merge/, REBASE_CONFLICT: files, exit 0
#   7. Success → changeset-clean-inherited.sh → REBASE_OK, exit 0
#
# Exit codes:
#   0  Success — REBASE_OK / REBASE_NOOP / REBASE_CONFLICT (stdout tells which)
#   2  Fatal error — fetch failure / parse failure / usage error

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_TASK_MD="$SCRIPT_DIR/parse-task-md.sh"
CHANGESET_CLEAN="$SCRIPT_DIR/changeset-clean-inherited.sh"

usage() {
  cat <<EOF >&2
Usage:
  $(basename "$0") <task_md> [--cwd DIR]

Rebase current branch onto origin/{resolved_base}. Conflict → preserved for
LLM resolution. Post-rebase cleans inherited changesets.

Options:
  --cwd DIR   Run git commands in DIR (default: current directory)

Stdout protocol:
  REBASE_NOOP                          — no new commits on base
  REBASE_OK                            — rebased successfully
  REBASE_CONFLICT: file1.ts, file2.ts  — conflict, .git/rebase-merge/ preserved

Exit:  0 = success (all three states), 2 = fatal error.
EOF
}

# ---------------------------------------------------------------------------
# Selftest
# ---------------------------------------------------------------------------
if [[ "${ENGINEERING_REBASE_SELFTEST:-}" == "1" ]]; then
  PASS=0; FAIL=0; TOTAL=0
  _assert() {
    TOTAL=$((TOTAL + 1))
    if [[ "$1" == "$2" ]]; then
      PASS=$((PASS + 1))
    else
      FAIL=$((FAIL + 1))
      echo "FAIL [$TOTAL]: expected='$2' got='$1' — $3" >&2
    fi
  }

  TMPDIR_ST=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_ST"' EXIT

  # Setup: bare remote + local clone
  REMOTE="$TMPDIR_ST/remote.git"
  LOCAL="$TMPDIR_ST/local"
  git init --bare "$REMOTE" >/dev/null 2>&1
  git clone "$REMOTE" "$LOCAL" >/dev/null 2>&1
  (
    cd "$LOCAL"
    git checkout -b main >/dev/null 2>&1
    echo "line1" > file.txt
    git add file.txt && git commit -m "init" >/dev/null 2>&1
    git push -u origin main >/dev/null 2>&1
    git checkout -b task/TEST-1-demo >/dev/null 2>&1
    echo "task work" >> file.txt
    git add file.txt && git commit -m "task" >/dev/null 2>&1
  )

  TASK_MD="$TMPDIR_ST/task.md"
  cat > "$TASK_MD" <<'TASK'
# T1 — Demo

> Epic: TEST-1 | JIRA: TEST-1 | Repo: test

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | TEST-1 |
| Parent Epic | TEST-1 |
| Base branch | main |
| Task branch | task/TEST-1-demo |
| Depends on | — |

## Test Command

echo ok

## Allowed Files

- `file.txt`
TASK

  # Unset selftest env to avoid infinite recursion when calling self
  _run() { env -u ENGINEERING_REBASE_SELFTEST bash "$SCRIPT_DIR/engineering-rebase.sh" "$@"; }

  # T1: REBASE_NOOP — no new commits on base
  out=$(cd "$LOCAL" && _run "$TASK_MD" 2>/dev/null)
  rc=$?
  _assert "$rc" "0" "T1: noop should exit 0"
  echo "$out" | grep -q "REBASE_NOOP" && t="found" || t="missing"
  _assert "$t" "found" "T1: should say REBASE_NOOP"

  # T2: REBASE_OK — new non-conflicting commit on base
  (
    cd "$LOCAL"
    git checkout main >/dev/null 2>&1
    echo "new feature" > other.txt
    git add other.txt && git commit -m "parallel work" >/dev/null 2>&1
    git push origin main >/dev/null 2>&1
    git checkout task/TEST-1-demo >/dev/null 2>&1
  )
  out=$(cd "$LOCAL" && _run "$TASK_MD" 2>/dev/null)
  rc=$?
  _assert "$rc" "0" "T2: clean rebase should exit 0"
  echo "$out" | grep -q "REBASE_OK" && t="found" || t="missing"
  _assert "$t" "found" "T2: should say REBASE_OK"

  # T3: REBASE_CONFLICT — conflicting change on base
  (
    cd "$LOCAL"
    git checkout main >/dev/null 2>&1
    echo "conflicting change" > file.txt
    git add file.txt && git commit -m "conflict on main" >/dev/null 2>&1
    git push origin main >/dev/null 2>&1
    git checkout task/TEST-1-demo >/dev/null 2>&1
  )
  out=$(cd "$LOCAL" && _run "$TASK_MD" 2>/dev/null)
  rc=$?
  _assert "$rc" "0" "T3: conflict rebase should still exit 0"
  echo "$out" | grep -q "REBASE_CONFLICT" && t="found" || t="missing"
  _assert "$t" "found" "T3: should say REBASE_CONFLICT"
  # Verify rebase-merge state is preserved
  (cd "$LOCAL" && [[ -d .git/rebase-merge || -d .git/rebase-apply ]]) && t="exists" || t="missing"
  _assert "$t" "exists" "T3: rebase-merge state should be preserved"
  # Cleanup conflict for subsequent tests
  (cd "$LOCAL" && git rebase --abort >/dev/null 2>&1) || true

  # T4: error — no args
  out=$(env -u ENGINEERING_REBASE_SELFTEST bash "$SCRIPT_DIR/engineering-rebase.sh" 2>/dev/null)
  rc=$?
  _assert "$rc" "2" "T4: no args should exit 2"

  echo ""
  echo "engineering-rebase.sh selftest: $PASS/$TOTAL passed, $FAIL failed"
  [[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
fi

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
TASK_MD=""
CWD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cwd) CWD="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    -*) echo "ERROR: unknown option: $1" >&2; usage; exit 2 ;;
    *)
      if [[ -z "$TASK_MD" ]]; then
        TASK_MD="$1"
      else
        echo "ERROR: unexpected argument: $1" >&2; usage; exit 2
      fi
      shift
      ;;
  esac
done

if [[ -z "$TASK_MD" ]]; then
  usage
  exit 2
fi

if [[ ! -f "$TASK_MD" ]]; then
  echo "ERROR: task_md not found: $TASK_MD" >&2
  exit 2
fi

# Switch working directory if --cwd specified
if [[ -n "$CWD" ]]; then
  if [[ ! -d "$CWD" ]]; then
    echo "ERROR: --cwd directory not found: $CWD" >&2
    exit 2
  fi
  cd "$CWD"
fi

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# Step 1: Parse task.md
RESOLVED_BASE=$("$PARSE_TASK_MD" "$TASK_MD" --field resolved_base 2>/dev/null)
if [[ -z "$RESOLVED_BASE" || "$RESOLVED_BASE" == "null" ]]; then
  echo "ERROR: could not resolve base branch from $TASK_MD" >&2
  exit 2
fi

TASK_KEY=$("$PARSE_TASK_MD" "$TASK_MD" --field task_jira_key 2>/dev/null)
if [[ -z "$TASK_KEY" || "$TASK_KEY" == "null" ]]; then
  TASK_KEY=$("$PARSE_TASK_MD" "$TASK_MD" --field jira 2>/dev/null)
fi

# Step 2: Fetch origin
echo "ℹ Fetching origin/$RESOLVED_BASE..." >&2
if ! git fetch origin "$RESOLVED_BASE" >/dev/null 2>&1; then
  echo "ERROR: git fetch origin $RESOLVED_BASE failed" >&2
  exit 2
fi

# Step 3: Check for new commits
NEW_COMMITS=$(git log HEAD.."origin/$RESOLVED_BASE" --oneline 2>/dev/null || echo "")
COMMIT_COUNT=0
if [[ -n "$NEW_COMMITS" ]]; then
  COMMIT_COUNT=$(echo "$NEW_COMMITS" | wc -l | tr -d ' ')
fi

# Step 4: No new commits → NOOP
if [[ "$COMMIT_COUNT" -eq 0 ]]; then
  echo "REBASE_NOOP"
  exit 0
fi

echo "ℹ $COMMIT_COUNT new commit(s) on origin/$RESOLVED_BASE — rebasing..." >&2

# Step 5: Attempt rebase
REBASE_OUTPUT=$(git rebase "origin/$RESOLVED_BASE" 2>&1)
REBASE_RC=$?

if [[ $REBASE_RC -eq 0 ]]; then
  # Step 7: Success — clean inherited changesets
  echo "ℹ Rebase successful, cleaning inherited changesets..." >&2
  REPO_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  if [[ -x "$CHANGESET_CLEAN" && -d "$REPO_DIR/.changeset" && -n "$TASK_KEY" ]]; then
    "$CHANGESET_CLEAN" --repo "$REPO_DIR" --current-ticket "$TASK_KEY" --base "$RESOLVED_BASE" 2>&1 | sed 's/^/  /' >&2 || true
  fi
  echo "REBASE_OK"
  exit 0
fi

# Step 6: Conflict — preserve state, report conflicting files
CONFLICT_FILES=$(git diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
if [[ -z "$CONFLICT_FILES" ]]; then
  # Fallback: try to extract from rebase output
  CONFLICT_FILES=$(echo "$REBASE_OUTPUT" | grep -oE 'CONFLICT.*: [^ ]+' | sed 's/CONFLICT.*: //' | tr '\n' ', ' | sed 's/,$//')
fi

if [[ -n "$CONFLICT_FILES" ]]; then
  echo "REBASE_CONFLICT: $CONFLICT_FILES"
else
  echo "REBASE_CONFLICT: (unable to list files — check git status)"
fi
exit 0
