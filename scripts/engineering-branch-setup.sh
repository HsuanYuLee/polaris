#!/usr/bin/env bash
# scripts/engineering-branch-setup.sh — DP-032 Wave γ D4
#
# Atomic branch + worktree creation for engineering first-cut. Replaces the
# multi-step LLM-driven flow (read base → create-branch.sh → manual worktree)
# with a single deterministic script. Eliminates first-cut pre-dev rebase
# (new branch from origin/{base} HEAD is already at tip — no rebase needed).
#
# Contract:
#   engineering-branch-setup.sh <task_md> [--repo-base DIR]
#
# Steps:
#   1. parse-task-md.sh → task_jira_key, summary, resolved_base, repo
#   2. Verify resolved_base exists on origin (git ls-remote)
#   3. git fetch origin {resolved_base}
#   4. Derive branch name: task/{KEY}-{slug}
#   5. git branch task/{KEY}-{slug} origin/{resolved_base}
#   6. Derive worktree path: {repo_base}/.worktrees/{repo}-engineering-{KEY}
#   7. git worktree add {worktree_path} task/{KEY}-{slug}
#   8. stdout last line: absolute worktree path (for caller consumption)
#
# Exit codes:
#   0  Success — worktree created, path on stdout
#   1  Recoverable error — branch already exists (prints existing branch info)
#   2  Fatal error — base not found / parse failure / usage error

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_TASK_MD="$SCRIPT_DIR/parse-task-md.sh"

usage() {
  cat <<EOF >&2
Usage:
  $(basename "$0") <task_md> [--repo-base DIR]

Creates a task branch + worktree atomically from origin/{resolved_base} HEAD.

Options:
  --repo-base DIR   Base directory for .worktrees/ (default: git toplevel)

Exit:  0 = success, 1 = branch exists, 2 = fatal error.
EOF
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Sanitize summary into a branch-safe slug (kebab-case, max 40 chars)
slugify() {
  local input="$1"
  echo "$input" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g' \
    | sed 's/--*/-/g' \
    | sed 's/^-//;s/-$//' \
    | cut -c1-40
}

# ---------------------------------------------------------------------------
# Selftest
# ---------------------------------------------------------------------------
if [[ "${ENGINEERING_BRANCH_SETUP_SELFTEST:-}" == "1" ]]; then
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
    echo "init" > file.txt
    git add file.txt && git commit -m "init" >/dev/null 2>&1
    git push -u origin main >/dev/null 2>&1
  )

  TASK_MD="$TMPDIR_ST/task.md"
  cat > "$TASK_MD" <<'TASK'
# T1 — Fix login validation

> Epic: PROJ-100 | JIRA: PROJ-101 | Repo: my-app

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | PROJ-101 |
| Parent Epic | PROJ-100 |
| Base branch | main |
| Task branch | task/PROJ-101-fix-login-validation |
| Depends on | — |

## Test Command

echo ok

## Allowed Files

- `src/**`
TASK

  # Unset selftest env to avoid infinite recursion when calling self
  _run() { env -u ENGINEERING_BRANCH_SETUP_SELFTEST bash "$SCRIPT_DIR/engineering-branch-setup.sh" "$@"; }

  # T1: successful branch + worktree creation
  out=$(cd "$LOCAL" && _run "$TASK_MD" --repo-base "$TMPDIR_ST" 2>/dev/null)
  rc=$?
  _assert "$rc" "0" "T1: should succeed"
  # Last line should be a worktree path
  wt_path=$(echo "$out" | tail -1)
  [[ -d "$wt_path" ]] && t="exists" || t="missing"
  _assert "$t" "exists" "T1: worktree directory should exist"
  # Branch should exist
  (cd "$LOCAL" && git branch --list 'task/PROJ-101-*' | grep -q 'task/PROJ-101') && t="found" || t="missing"
  _assert "$t" "found" "T1: task branch should exist"

  # T2: idempotent — running again should exit 1 (branch exists)
  out=$(cd "$LOCAL" && _run "$TASK_MD" --repo-base "$TMPDIR_ST" 2>/dev/null)
  rc=$?
  _assert "$rc" "1" "T2: re-run should exit 1 (branch exists)"

  # T3: error — nonexistent task_md
  out=$(cd "$LOCAL" && _run "/nonexistent.md" 2>/dev/null)
  rc=$?
  _assert "$rc" "2" "T3: missing task_md should exit 2"

  # T4: error — no args
  out=$(env -u ENGINEERING_BRANCH_SETUP_SELFTEST bash "$SCRIPT_DIR/engineering-branch-setup.sh" 2>/dev/null)
  rc=$?
  _assert "$rc" "2" "T4: no args should exit 2"

  # T5: slugify tests
  s=$(slugify "Fix Login Validation Bug")
  _assert "$s" "fix-login-validation-bug" "T5a: slugify basic"
  s=$(slugify "JP 旅遊 DX Main-Page")
  _assert "$s" "jp-dx-main-page" "T5b: slugify non-ascii → collapsed dashes"

  # Cleanup worktree
  (cd "$LOCAL" && git worktree remove "$wt_path" --force >/dev/null 2>&1) || true

  echo ""
  echo "engineering-branch-setup.sh selftest: $PASS/$TOTAL passed, $FAIL failed"
  [[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
fi

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
TASK_MD=""
REPO_BASE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-base) REPO_BASE="$2"; shift 2 ;;
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

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# Step 1: Parse task.md
TASK_JSON=$("$PARSE_TASK_MD" "$TASK_MD" 2>/dev/null)
if [[ $? -ne 0 || -z "$TASK_JSON" ]]; then
  echo "ERROR: parse-task-md.sh failed for $TASK_MD" >&2
  exit 2
fi

TASK_KEY=$(echo "$TASK_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); oc=d.get('operational_context',{}); m=d.get('metadata',{}); print(oc.get('task_jira_key') or m.get('jira') or '')" 2>/dev/null)
SUMMARY=$(echo "$TASK_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('header',{}).get('summary') or '')" 2>/dev/null)
RESOLVED_BASE=$(echo "$TASK_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('resolved_base') or '')" 2>/dev/null)
REPO_NAME=$(echo "$TASK_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('metadata',{}).get('repo') or '')" 2>/dev/null)

if [[ -z "$TASK_KEY" ]]; then
  echo "ERROR: task_jira_key not found in $TASK_MD" >&2
  exit 2
fi
if [[ -z "$RESOLVED_BASE" || "$RESOLVED_BASE" == "null" ]]; then
  echo "ERROR: could not resolve base branch from $TASK_MD" >&2
  exit 2
fi

# Step 2: Verify resolved_base exists on remote
if ! git ls-remote --exit-code origin "refs/heads/$RESOLVED_BASE" >/dev/null 2>&1; then
  echo "ERROR: base branch '$RESOLVED_BASE' not found on origin." >&2
  echo "  → Run /breakdown to update task.md or verify the base branch exists." >&2
  exit 2
fi

# Step 3: Fetch latest
echo "ℹ Fetching origin/$RESOLVED_BASE..." >&2
git fetch origin "$RESOLVED_BASE" >/dev/null 2>&1 || {
  echo "ERROR: git fetch origin $RESOLVED_BASE failed" >&2
  exit 2
}

# Step 4: Derive branch name
SLUG=$(slugify "$SUMMARY")
if [[ -z "$SLUG" ]]; then
  SLUG="impl"
fi
BRANCH_NAME="task/${TASK_KEY}-${SLUG}"

# Check if branch already exists
if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME" 2>/dev/null; then
  echo "ℹ Branch $BRANCH_NAME already exists." >&2
  # Check if worktree exists too
  EXISTING_WT=$(git worktree list --porcelain 2>/dev/null | grep -A2 "^worktree " | grep -B1 "branch refs/heads/$BRANCH_NAME" | head -1 | sed 's/^worktree //')
  if [[ -n "$EXISTING_WT" ]]; then
    echo "ℹ Worktree already at: $EXISTING_WT" >&2
    echo "$EXISTING_WT"
    exit 1
  fi
  echo "ℹ Branch exists but no worktree — creating worktree." >&2
else
  # Step 5: Create branch from origin/{resolved_base}
  git branch "$BRANCH_NAME" "origin/$RESOLVED_BASE" 2>/dev/null || {
    echo "ERROR: git branch $BRANCH_NAME origin/$RESOLVED_BASE failed" >&2
    exit 2
  }
  echo "✓ Created branch: $BRANCH_NAME" >&2
fi

# Step 6: Derive worktree path
if [[ -z "$REPO_BASE" ]]; then
  REPO_BASE=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi
WT_DIR="${REPO_BASE}/.worktrees"
WT_NAME="${REPO_NAME:-repo}-engineering-${TASK_KEY}"
WT_PATH="${WT_DIR}/${WT_NAME}"

# Step 7: Create worktree
mkdir -p "$WT_DIR"
if [[ -d "$WT_PATH" ]]; then
  echo "ℹ Worktree path already exists: $WT_PATH — reusing." >&2
  echo "$WT_PATH"
  exit 1
fi

git worktree add "$WT_PATH" "$BRANCH_NAME" 2>/dev/null || {
  echo "ERROR: git worktree add failed for $WT_PATH $BRANCH_NAME" >&2
  # Cleanup branch if we just created it
  git branch -d "$BRANCH_NAME" 2>/dev/null || true
  exit 2
}

echo "✓ Worktree created: $WT_PATH" >&2

# Step 8: Output worktree path (last line = machine-readable)
echo "$WT_PATH"
