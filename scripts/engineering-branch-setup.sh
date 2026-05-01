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
#   4. Resolve branch name from task.md `Task branch` contract
#   5. Duplicate guard: refuse same-ticket local/remote branches and stale worktree paths
#   6. git branch {resolved_task_branch} origin/{resolved_base}
#   7. Derive worktree path: {repo_base}/.worktrees/{repo}-engineering-{KEY}
#   8. git worktree add {worktree_path} {resolved_task_branch}
#   9. stdout last line: absolute worktree path (for caller consumption)
#
# Exit codes:
#   0  Success — worktree created, path on stdout
#   1  Recoverable error — branch already exists (prints existing branch info)
#   2  Fatal error — base not found / parse failure / usage error

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_TASK_MD="$SCRIPT_DIR/parse-task-md.sh"
CASCADE_REBASE_CHAIN="$SCRIPT_DIR/cascade-rebase-chain.sh"
RESOLVE_TASK_BRANCH="$SCRIPT_DIR/resolve-task-branch.sh"

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

worktree_for_branch() {
  local branch="$1"
  git worktree list --porcelain 2>/dev/null | awk -v branch="refs/heads/${branch}" '
    /^worktree / { wt = substr($0, 10); next }
    /^branch / {
      if (substr($0, 8) == branch) {
        print wt
      }
    }
  '
}

task_branch_refs() {
  local task_key="$1"
  git for-each-ref --format='%(refname:short)' \
    "refs/heads/task/${task_key}-*" \
    "refs/remotes/origin/task/${task_key}-*" 2>/dev/null | sort -u
}

emit_duplicate_branch_error() {
  local task_key="$1"
  local branch_name="$2"
  local existing_refs="$3"

  echo "ERROR: existing task branch detected for ${task_key}; refusing to open a duplicate engineering branch." >&2
  echo "  Expected branch: ${branch_name}" >&2
  echo "  Existing refs:" >&2
  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    local branch="${ref#origin/}"
    local wt=""
    wt="$(worktree_for_branch "$branch")"
    if [[ -n "$wt" ]]; then
      echo "    - ${ref} (worktree: ${wt})" >&2
    else
      echo "    - ${ref}" >&2
    fi
  done <<<"$existing_refs"
  echo "  → Resume the existing branch/worktree, switch to revision mode if it has a PR, or clean the stale branch before retrying." >&2
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
| Task branch | task/PROJ-101-contract-branch-name |
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
  # Branch should match task.md Task branch even when the summary slug differs.
  (cd "$LOCAL" && git show-ref --verify --quiet refs/heads/task/PROJ-101-contract-branch-name) && t="found" || t="missing"
  _assert "$t" "found" "T1: task.md Task branch should exist"

  # T2: idempotent — running again should exit 1 (branch exists)
  out=$(cd "$LOCAL" && _run "$TASK_MD" --repo-base "$TMPDIR_ST" 2>/dev/null)
  rc=$?
  _assert "$rc" "1" "T2: re-run should exit 1 (branch exists)"

  # T3: guard — same ticket with a different existing branch should block
  git -C "$LOCAL" branch task/PROJ-101-other-attempt main >/dev/null 2>&1
  TASK_MD_DUP="$TMPDIR_ST/task-duplicate.md"
  sed 's/Fix login validation/Another implementation/' "$TASK_MD" > "$TASK_MD_DUP"
  out=$(cd "$LOCAL" && _run "$TASK_MD_DUP" --repo-base "$TMPDIR_ST" 2>/dev/null)
  rc=$?
  _assert "$rc" "1" "T3: duplicate same-ticket branch should exit 1"

  # T4: guard — stale worktree path should block before creating a branch
  TASK_MD_WT="$TMPDIR_ST/task-worktree-path.md"
  sed 's/PROJ-101/PROJ-102/g; s/Fix login validation/Second task/' "$TASK_MD" > "$TASK_MD_WT"
  mkdir -p "$TMPDIR_ST/.worktrees/my-app-engineering-PROJ-102"
  out=$(cd "$LOCAL" && _run "$TASK_MD_WT" --repo-base "$TMPDIR_ST" 2>/dev/null)
  rc=$?
  _assert "$rc" "1" "T4: stale worktree path should exit 1"
  (cd "$LOCAL" && git show-ref --verify --quiet refs/heads/task/PROJ-102-second-task) && t="created" || t="missing"
  _assert "$t" "missing" "T4: stale worktree path must not leave a new branch"

  # T5: error — nonexistent task_md
  out=$(cd "$LOCAL" && _run "/nonexistent.md" 2>/dev/null)
  rc=$?
  _assert "$rc" "2" "T5: missing task_md should exit 2"

  # T6: error — no args
  out=$(env -u ENGINEERING_BRANCH_SETUP_SELFTEST bash "$SCRIPT_DIR/engineering-branch-setup.sh" 2>/dev/null)
  rc=$?
  _assert "$rc" "2" "T6: no args should exit 2"

  # T7: slugify tests
  s=$(slugify "Fix Login Validation Bug")
  _assert "$s" "fix-login-validation-bug" "T7a: slugify basic"
  s=$(slugify "JP 旅遊 DX Main-Page")
  _assert "$s" "jp-dx-main-page" "T7b: slugify non-ascii → collapsed dashes"

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
BRANCH_CHAIN=$(echo "$TASK_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('operational_context',{}).get('branch_chain') or '')" 2>/dev/null)
BASE_BRANCH=$(echo "$TASK_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('operational_context',{}).get('base_branch') or '')" 2>/dev/null)

if [[ -z "$TASK_KEY" ]]; then
  echo "ERROR: task_jira_key not found in $TASK_MD" >&2
  exit 2
fi
if [[ -z "$RESOLVED_BASE" || "$RESOLVED_BASE" == "null" ]]; then
  echo "ERROR: could not resolve base branch from $TASK_MD" >&2
  exit 2
fi

# Step 1.5: If breakdown supplied an explicit branch chain, align upstream
# branches before cutting the task branch. The task branch does not exist yet,
# so cascade-rebase-chain skips the missing last link.
if [[ -n "$BRANCH_CHAIN" && -f "$CASCADE_REBASE_CHAIN" ]]; then
  if [[ "$BASE_BRANCH" == task/* && "$RESOLVED_BASE" != "$BASE_BRANCH" ]]; then
    echo "ℹ Stacked base resolved to $RESOLVED_BASE; skipping stale branch-chain cascade for completed upstream." >&2
  else
  echo "ℹ Aligning branch chain before task branch creation..." >&2
  "$CASCADE_REBASE_CHAIN" --repo "$(git rev-parse --show-toplevel)" --task-md "$TASK_MD" --skip-missing-last >/dev/null || {
    echo "ERROR: branch chain rebase failed; resolve upstream branch first." >&2
    exit 2
  }
  fi
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

# Step 4: Resolve branch name from task.md contract
if [[ ! -x "$RESOLVE_TASK_BRANCH" ]]; then
  echo "ERROR: resolve-task-branch.sh not executable at $RESOLVE_TASK_BRANCH" >&2
  exit 2
fi
BRANCH_NAME="$("$RESOLVE_TASK_BRANCH" "$TASK_MD" 2>/tmp/polaris-resolve-task-branch.err)" || {
  cat /tmp/polaris-resolve-task-branch.err >&2 2>/dev/null || true
  echo "ERROR: failed to resolve task branch from $TASK_MD" >&2
  exit 2
}

# Step 4.5: Derive worktree path before creating any branch. If the path is
# already present, fail before touching refs; otherwise a retry can leave a
# branch behind without a usable worktree.
if [[ -z "$REPO_BASE" ]]; then
  REPO_BASE=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi
WT_DIR="${REPO_BASE}/.worktrees"
WT_NAME="${REPO_NAME:-repo}-engineering-${TASK_KEY}"
WT_PATH="${WT_DIR}/${WT_NAME}"

# Step 4.6: Same-ticket duplicate guard. A different slug for the same ticket
# is almost always an accidental second first-cut. Exact local branch reuse is
# handled below; exact remote branch still blocks because first-cut would fork
# from the base branch instead of resuming the existing remote work.
EXISTING_TASK_REFS="$(task_branch_refs "$TASK_KEY")"
DUPLICATE_REFS=""
if [[ -n "$EXISTING_TASK_REFS" ]]; then
  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    if [[ "$ref" == "$BRANCH_NAME" ]]; then
      continue
    fi
    DUPLICATE_REFS="${DUPLICATE_REFS}${ref}"$'\n'
  done <<<"$EXISTING_TASK_REFS"
fi

if [[ -n "$DUPLICATE_REFS" ]]; then
  emit_duplicate_branch_error "$TASK_KEY" "$BRANCH_NAME" "$DUPLICATE_REFS"
  exit 1
fi

if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH_NAME" 2>/dev/null; then
  emit_duplicate_branch_error "$TASK_KEY" "$BRANCH_NAME" "origin/$BRANCH_NAME"
  exit 1
fi

EXACT_BRANCH_EXISTS=0
if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME" 2>/dev/null; then
  EXACT_BRANCH_EXISTS=1
  echo "ℹ Branch $BRANCH_NAME already exists." >&2
  EXISTING_WT="$(worktree_for_branch "$BRANCH_NAME")"
  if [[ -n "$EXISTING_WT" ]]; then
    echo "ℹ Worktree already at: $EXISTING_WT" >&2
    echo "$EXISTING_WT"
    exit 1
  fi
  echo "ℹ Branch exists but no worktree — creating worktree." >&2
fi

if [[ -d "$WT_PATH" ]]; then
  echo "ERROR: worktree path already exists before branch setup: $WT_PATH" >&2
  echo "  → Resume or clean this worktree before retrying; refusing to create a branch that cannot get its worktree." >&2
  exit 1
fi

# Check if branch already exists
if [[ "$EXACT_BRANCH_EXISTS" -eq 0 ]]; then
  # Step 5: Create branch from origin/{resolved_base}
  git branch "$BRANCH_NAME" "origin/$RESOLVED_BASE" 2>/dev/null || {
    echo "ERROR: git branch $BRANCH_NAME origin/$RESOLVED_BASE failed" >&2
    exit 2
  }
  echo "✓ Created branch: $BRANCH_NAME" >&2
fi

# Step 7: Create worktree
mkdir -p "$WT_DIR"

git worktree add "$WT_PATH" "$BRANCH_NAME" 2>/dev/null || {
  echo "ERROR: git worktree add failed for $WT_PATH $BRANCH_NAME" >&2
  # Cleanup branch if we just created it
  git branch -d "$BRANCH_NAME" 2>/dev/null || true
  exit 2
}

echo "✓ Worktree created: $WT_PATH" >&2

# Step 8: Output worktree path (last line = machine-readable)
echo "$WT_PATH"
