#!/usr/bin/env bash
# scripts/check-base-fresh.sh — DP-032 Wave γ D19
#
# Pure base-freshness detection for a task branch. No side-effects — only
# reports whether origin/{resolved_base} has new commits that HEAD has not
# incorporated. Used by engineer-delivery-flow.md § Step 5 (Base Freshness
# Detect): stale → orchestrator retries from Step 2 (rebase via D6).
#
# Contract:
#   check-base-fresh.sh <task_md>
#
# Steps:
#   1. parse-task-md.sh --field resolved_base → base branch
#   2. git fetch origin {resolved_base}
#   3. git log HEAD..origin/{resolved_base} --oneline → count new commits
#
# Exit codes:
#   0  Fresh — base has no new commits beyond HEAD
#   1  Stale — base has N new commits; stdout: STALE: {base}, N new commits
#   2  Error — fetch failure / parse failure / usage error (fail-loud)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_TASK_MD="$SCRIPT_DIR/parse-task-md.sh"

usage() {
  cat <<EOF >&2
Usage:
  $(basename "$0") <task_md>

Pure detection — no git state mutation. Reports base freshness.

Exit:  0 = fresh, 1 = stale, 2 = error.
EOF
}

# ---------------------------------------------------------------------------
# Selftest
# ---------------------------------------------------------------------------
if [[ "${CHECK_BASE_FRESH_SELFTEST:-}" == "1" ]]; then
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

  # --- Setup: bare remote + local clone ---
  REMOTE="$TMPDIR_ST/remote.git"
  LOCAL="$TMPDIR_ST/local"
  git init --bare "$REMOTE" >/dev/null 2>&1
  git clone "$REMOTE" "$LOCAL" >/dev/null 2>&1
  (
    cd "$LOCAL"
    git checkout -b main >/dev/null 2>&1
    echo "init" > file.txt
    git add file.txt && git commit -m "init" >/dev/null 2>&1
    git push -u origin main >/dev/null 2>&1
    git checkout -b task/TEST-1-demo >/dev/null 2>&1
    echo "task work" >> file.txt
    git add file.txt && git commit -m "task work" >/dev/null 2>&1
  )

  # Create a minimal task.md
  TASK_MD="$TMPDIR_ST/task.md"
  cat > "$TASK_MD" <<'TASK'
# T1 — Demo task

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
  _run() { env -u CHECK_BASE_FRESH_SELFTEST bash "$SCRIPT_DIR/check-base-fresh.sh" "$@"; }

  # Test 1: fresh (no new commits on origin/main)
  out=$(cd "$LOCAL" && _run "$TASK_MD" 2>/dev/null)
  rc=$?
  _assert "$rc" "0" "T1: fresh base should exit 0"
  echo "$out" | grep -q "FRESH" && t1_msg="found" || t1_msg="missing"
  _assert "$t1_msg" "found" "T1: stdout should contain FRESH"

  # Test 2: stale (push new commit to origin/main)
  (
    cd "$LOCAL"
    git checkout main >/dev/null 2>&1
    echo "new work" >> file.txt
    git add file.txt && git commit -m "new work on main" >/dev/null 2>&1
    git push origin main >/dev/null 2>&1
    git checkout task/TEST-1-demo >/dev/null 2>&1
  )
  out=$(cd "$LOCAL" && _run "$TASK_MD" 2>/dev/null)
  rc=$?
  _assert "$rc" "1" "T2: stale base should exit 1"
  echo "$out" | grep -q "STALE" && t2_msg="found" || t2_msg="missing"
  _assert "$t2_msg" "found" "T2: stdout should contain STALE"

  # Test 3: error — nonexistent task_md
  out=$(_run "/nonexistent/task.md" 2>/dev/null)
  rc=$?
  _assert "$rc" "2" "T3: missing task_md should exit 2"

  # Test 4: error — no args
  out=$(env -u CHECK_BASE_FRESH_SELFTEST bash "$SCRIPT_DIR/check-base-fresh.sh" 2>/dev/null)
  rc=$?
  _assert "$rc" "2" "T4: no args should exit 2"

  echo ""
  echo "check-base-fresh.sh selftest: $PASS/$TOTAL passed, $FAIL failed"
  [[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
fi

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

TASK_MD="$1"

if [[ ! -f "$TASK_MD" ]]; then
  echo "ERROR: task_md not found: $TASK_MD" >&2
  exit 2
fi

# Step 1: Get resolved base branch
# Try resolved_base first (includes dependency chain resolution);
# fall back to base_branch if resolve fails (e.g., no git context for stacked tasks)
RESOLVED_BASE=$("$PARSE_TASK_MD" "$TASK_MD" --no-resolve --field base_branch 2>/dev/null)
if [[ -z "$RESOLVED_BASE" || "$RESOLVED_BASE" == "null" ]]; then
  echo "ERROR: could not read base_branch from $TASK_MD" >&2
  exit 2
fi

# Attempt full resolution (stacked task branches → ultimate base)
FULL_RESOLVE=$("$PARSE_TASK_MD" "$TASK_MD" --field resolved_base 2>/dev/null)
if [[ -n "$FULL_RESOLVE" && "$FULL_RESOLVE" != "null" ]]; then
  RESOLVED_BASE="$FULL_RESOLVE"
fi

# Step 2: Fetch latest from origin
if ! git fetch origin "$RESOLVED_BASE" >/dev/null 2>&1; then
  echo "ERROR: git fetch origin $RESOLVED_BASE failed (network? permissions?)" >&2
  exit 2
fi

# Step 3: Count new commits on base that HEAD hasn't incorporated
NEW_COMMITS=$(git log HEAD.."origin/$RESOLVED_BASE" --oneline 2>/dev/null)
COMMIT_COUNT=$(echo "$NEW_COMMITS" | grep -c '.' 2>/dev/null) || true

if [[ "$COMMIT_COUNT" -eq 0 || -z "$NEW_COMMITS" ]]; then
  echo "FRESH: $RESOLVED_BASE, HEAD is up to date"
  exit 0
else
  FRESH_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
  echo "STALE: $RESOLVED_BASE, $COMMIT_COUNT new commit(s) since $FRESH_SHA"
  exit 1
fi
