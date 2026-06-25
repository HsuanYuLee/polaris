#!/usr/bin/env bash
# Purpose: Assert engineering-branch-setup.sh resolves its base / repo context
#          from the task.md work order (git -C "$REPO"), NOT from the current
#          working directory (DP-338 T5 / AC5). Running branch-setup from a cwd
#          that is not the product repo must still cut the task branch + worktree
#          against the correct repo, instead of dying on a cwd-dependent
#          `git rev-parse --show-toplevel`.
# Inputs:  none (self-contained git fixtures under a temp dir).
# Outputs: PASS/FAIL lines on stdout; exit 0 when all assertions pass, else 1.
# Side effects: creates and removes a temp git remote/clone; never touches the
#               live workspace.
#
# Contract under test (DP-338 T5 / D5):
#   AC5(a) — branch-setup invoked from a non-repo cwd resolves the repo from the
#            task.md (canonical {workspace_root}/{Repo} convention) and succeeds,
#            instead of failing with a cwd-dependent base/repo resolution error.
#   AC5(b) — the resolved base ref is correct (task branch is cut from it), proving
#            base resolution used the repo derived from task.md, not cwd.
#   AC5(c, regression) — invoked from inside the repo cwd, behavior is unchanged
#            (the canonical task.md repo resolves to the same repo as the cwd).
#   AC5(d, regression) — a non-canonical/legacy task.md whose repo cannot be
#            derived from the task.md still falls back to the cwd repo (no
#            regression for the established inline-selftest fixture shape).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP="$SCRIPT_DIR/engineering-branch-setup.sh"

PASS=0
FAIL=0
TOTAL=0

_assert() {
  TOTAL=$((TOTAL + 1))
  if [[ "$1" == "$2" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL [$TOTAL]: expected='$2' got='$1' — $3" >&2
  fi
}

TMPDIR_ST="$(mktemp -d -t polaris-branch-setup-base-res.XXXXXX)"
trap 'rm -rf "$TMPDIR_ST"' EXIT

# ---------------------------------------------------------------------------
# Fixture: a canonical workspace layout so the task.md repo can be derived.
#
#   $WORKSPACE/
#     <repo-name>/                 ← product repo (bare remote + clone)
#     docs-manager/src/content/docs/specs/design-plans/DP-901-x/tasks/T1/index.md
#
# The repo path is derived from the task.md via the canonical
# {workspace_root}/{Repo} convention (resolve-task-base.sh derive_repo_path).
# ---------------------------------------------------------------------------
WORKSPACE="$TMPDIR_ST/workspace"
REPO_NAME="exampleco-web"
REMOTE="$TMPDIR_ST/remote.git"
REPO="$WORKSPACE/$REPO_NAME"

mkdir -p "$WORKSPACE"
git init --bare "$REMOTE" >/dev/null 2>&1
git clone "$REMOTE" "$REPO" >/dev/null 2>&1
git -C "$REPO" config user.email "self-test@example.com"
git -C "$REPO" config user.name "self-test"
git -C "$REPO" checkout -b main >/dev/null 2>&1
echo "init" >"$REPO/file.txt"
git -C "$REPO" add file.txt >/dev/null 2>&1
git -C "$REPO" commit -m "init" >/dev/null 2>&1
git -C "$REPO" push -u origin main >/dev/null 2>&1
# Create the feat base on origin so base resolution has a concrete target.
git -C "$REPO" branch feat/EXCO-700 origin/main >/dev/null 2>&1
git -C "$REPO" push -u origin feat/EXCO-700 >/dev/null 2>&1
FEAT_SHA="$(git -C "$REPO" rev-parse origin/feat/EXCO-700)"

# Canonical task.md under docs-manager specs root with a "Repo:" header.
TASKS_DIR="$WORKSPACE/docs-manager/src/content/docs/specs/design-plans/DP-901-base-res/tasks/T1"
mkdir -p "$TASKS_DIR"
TASK_MD="$TASKS_DIR/index.md"
cat >"$TASK_MD" <<TASK
# T1 — base resolution from task.md

> Epic: EXCO-700 | JIRA: EXCO-701 | Repo: $REPO_NAME

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | EXCO-701 |
| Base branch | feat/EXCO-700 |
| Task branch | task/EXCO-701-base-res-from-task-md |
| Depends on | — |

## Test Command

echo ok

## Allowed Files

- \`src/**\`
TASK

# A cwd that is NOT the repo and NOT inside any git repo.
NONREPO_CWD="$TMPDIR_ST/elsewhere"
mkdir -p "$NONREPO_CWD"

# ---------------------------------------------------------------------------
# AC5(a) + AC5(b): run from a non-repo cwd; base/repo resolved from task.md.
# ---------------------------------------------------------------------------
out="$( cd "$NONREPO_CWD" && env -u ENGINEERING_BRANCH_SETUP_SELFTEST \
  POLARIS_SKIP_BASELINE_SNAPSHOT=1 \
  bash "$SETUP" "$TASK_MD" --repo-base "$WORKSPACE" 2>"$TMPDIR_ST/a.err" )"
rc=$?
if [[ "$rc" != "0" ]]; then
  echo "----- a.err -----" >&2
  cat "$TMPDIR_ST/a.err" >&2
fi
_assert "$rc" "0" "AC5(a): branch-setup from non-repo cwd must resolve repo from task.md and succeed"

git -C "$REPO" show-ref --verify --quiet refs/heads/task/EXCO-701-base-res-from-task-md && t="found" || t="missing"
_assert "$t" "found" "AC5(a): task branch must be created in the repo derived from task.md"

if [[ "$t" == "found" ]]; then
  if git -C "$REPO" merge-base --is-ancestor refs/remotes/origin/feat/EXCO-700 refs/heads/task/EXCO-701-base-res-from-task-md >/dev/null 2>&1; then
    t="based-on-feat"
  else
    t="not-based-on-feat"
  fi
  _assert "$t" "based-on-feat" "AC5(b): task branch base must be the resolved feat/EXCO-700 (base resolved via repo, not cwd)"
fi

# The worktree must be created under the resolved repo-base, not the non-repo cwd.
wt_path="$(printf '%s\n' "$out" | tail -n 1)"
[[ -d "$wt_path" ]] && t="exists" || t="missing"
_assert "$t" "exists" "AC5(a): worktree dir from non-repo cwd run must exist"
case "$wt_path" in
  "$WORKSPACE"/.worktrees/*) t="under-workspace" ;;
  *) t="elsewhere" ;;
esac
_assert "$t" "under-workspace" "AC5(a): worktree must be created under the resolved workspace, not the cwd"

# ---------------------------------------------------------------------------
# AC5(c, regression): running from inside the repo cwd still works (canonical
# task.md repo == cwd repo).
# ---------------------------------------------------------------------------
TASK_MD2_DIR="$WORKSPACE/docs-manager/src/content/docs/specs/design-plans/DP-901-base-res/tasks/T2"
mkdir -p "$TASK_MD2_DIR"
TASK_MD2="$TASK_MD2_DIR/index.md"
sed 's/EXCO-701/EXCO-702/g; s/base-res-from-task-md/base-res-from-repo-cwd/g' "$TASK_MD" > "$TASK_MD2"

out="$( cd "$REPO" && env -u ENGINEERING_BRANCH_SETUP_SELFTEST \
  POLARIS_SKIP_BASELINE_SNAPSHOT=1 \
  bash "$SETUP" "$TASK_MD2" --repo-base "$WORKSPACE" 2>"$TMPDIR_ST/c.err" )"
rc=$?
if [[ "$rc" != "0" ]]; then
  echo "----- c.err -----" >&2
  cat "$TMPDIR_ST/c.err" >&2
fi
_assert "$rc" "0" "AC5(c): running from inside the repo cwd must remain unchanged (success)"
git -C "$REPO" show-ref --verify --quiet refs/heads/task/EXCO-702-base-res-from-repo-cwd && t="found" || t="missing"
_assert "$t" "found" "AC5(c): repo-cwd run must still create the task branch"

# ---------------------------------------------------------------------------
# AC5(d, regression): a legacy/non-canonical task.md whose repo cannot be
# derived from the task.md still falls back to the cwd repo. This mirrors the
# script's own inline selftest fixture (no docs-manager specs ancestor).
# ---------------------------------------------------------------------------
LEGACY_TASK="$TMPDIR_ST/legacy-task.md"
cat >"$LEGACY_TASK" <<TASK
# T1 — legacy non-canonical task

> Epic: EXCO-700 | JIRA: EXCO-703 | Repo: $REPO_NAME

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | EXCO-703 |
| Base branch | feat/EXCO-700 |
| Task branch | task/EXCO-703-legacy-fallback |
| Depends on | — |

## Test Command

echo ok

## Allowed Files

- \`src/**\`
TASK

out="$( cd "$REPO" && env -u ENGINEERING_BRANCH_SETUP_SELFTEST \
  POLARIS_SKIP_BASELINE_SNAPSHOT=1 \
  bash "$SETUP" "$LEGACY_TASK" --repo-base "$WORKSPACE" 2>"$TMPDIR_ST/d.err" )"
rc=$?
if [[ "$rc" != "0" ]]; then
  echo "----- d.err -----" >&2
  cat "$TMPDIR_ST/d.err" >&2
fi
_assert "$rc" "0" "AC5(d): legacy task.md (no derivable repo) falls back to cwd repo"
git -C "$REPO" show-ref --verify --quiet refs/heads/task/EXCO-703-legacy-fallback && t="found" || t="missing"
_assert "$t" "found" "AC5(d): legacy fallback must still create the task branch in the cwd repo"

echo ""
echo "branch-setup-base-resolution-selftest: $PASS/$TOTAL passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
