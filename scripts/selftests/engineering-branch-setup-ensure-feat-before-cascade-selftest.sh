#!/usr/bin/env bash
# Purpose: Assert engineering-branch-setup.sh ensures the feat/DP-NNN aggregation
#          base exists BEFORE the Step 1.5 branch-chain cascade runs, so a fresh
#          feat-model DP's first task does not die in cascade-rebase when
#          feat/DP-NNN is still absent (DP-352 T1 / Bug #1 / AC1 / AC-NEG1 / AC5).
# Inputs:  none (self-contained git fixtures under a temp dir).
# Outputs: PASS/FAIL lines on stdout; exit 0 when all assertions pass, else 1.
# Side effects: creates and removes a temp git remote/clone; never touches the
#               live workspace.
#
# Real-state under test (why the pre-existing feat-dp selftest missed this):
#   The pre-existing engineering-branch-setup-feat-dp-selftest.sh fixture task.md
#   has NO "Branch chain" row, so BRANCH_CHAIN parses empty, Step 1.5 cascade is
#   skipped, and Step 2 ensure_feat_dp_branch creates feat/DP-NNN — the bug never
#   triggers. Breakdown's derive-task-md now writes a real
#   "| Branch chain | feat/DP-NNN -> task/DP-NNN-Tn-... |" row, which makes
#   BRANCH_CHAIN non-empty so Step 1.5 cascade runs first. With feat/DP-NNN still
#   absent, cascade-rebase-chain reports "upstream branch not found: feat/DP-NNN"
#   and the setup dies (exit 2) BEFORE ensure_feat_dp_branch ever runs. That is
#   the v3.76.19-onward "zero release" root cause: every fresh feat-model DP's
#   first task dies here. This selftest reproduces that exact branch-chain +
#   feat-absent state.
#
# Cases:
#   1. AC1   feat-absent + Branch chain present → setup SUCCEEDS (was RED: died in
#            cascade). feat/DP-NNN auto-created; task branch cut from feat tip.
#   2. AC-NEG1 feat-present + Branch chain present → setup SUCCEEDS, feat/DP-NNN
#            reused (not duplicated); reorder must not double-create the feat base.
#   3. AC5   no-branch-chain + feat-absent (Base branch = fresh feat/DP-NNN, no
#            Branch chain row) → setup SUCCEEDS; the reorder must not gate
#            ensure_feat_dp_branch behind the cascade `if`, so feat is still
#            created when the cascade block is skipped (the path the pre-existing
#            feat-dp selftest exercised).

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

TMPDIR_ST="$(mktemp -d -t polaris-feat-cascade-order.XXXXXX)"
trap 'rm -rf "$TMPDIR_ST"' EXIT

# ---------------------------------------------------------------------------
# Fixture: bare remote + local clone with origin/main.
# engineering-branch-setup.sh resolves the repo via cwd (git without -C), so all
# dispatch must run inside the local clone — same pattern as the sibling
# feat-dp selftest. Legacy "Epic/JIRA/Repo" header keeps is_canonical_pipeline_task
# false so the heavy readiness pack is skipped; the feat / cascade behaviour keys
# off the resolved Base branch + Branch chain, not header canonicality.
# ---------------------------------------------------------------------------
REMOTE="$TMPDIR_ST/remote.git"
LOCAL="$TMPDIR_ST/local"
git init --bare "$REMOTE" >/dev/null 2>&1
git clone "$REMOTE" "$LOCAL" >/dev/null 2>&1
git -C "$LOCAL" config user.email "self-test@example.com"
git -C "$LOCAL" config user.name "self-test"
git -C "$LOCAL" checkout -b main >/dev/null 2>&1
echo "init" >"$LOCAL/file.txt"
git -C "$LOCAL" add file.txt >/dev/null 2>&1
git -C "$LOCAL" commit -m "init" >/dev/null 2>&1
git -C "$LOCAL" push -u origin main >/dev/null 2>&1
MAIN_SHA="$(git -C "$LOCAL" rev-parse origin/main)"

_run() {
  ( cd "$LOCAL" && env -u ENGINEERING_BRANCH_SETUP_SELFTEST POLARIS_SKIP_BASELINE_SNAPSHOT=1 \
    bash "$SETUP" "$@" )
}

# ---------------------------------------------------------------------------
# Case 1 (AC1, RED→GREEN): feat-absent + Branch chain present.
# This is the bug: cascade (Step 1.5) runs before ensure_feat_dp_branch (Step 2),
# and feat/DP-902 does not exist yet → must NOT die.
# ---------------------------------------------------------------------------
TASK1="$TMPDIR_ST/t1.md"
cat >"$TASK1" <<'TASK'
# T1 — feat absent + branch chain

> Epic: DP-902 | JIRA: DP-902-T1 | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DP-902-T1 |
| Base branch | feat/DP-902 |
| Branch chain | feat/DP-902 -> task/DP-902-T1-feat-absent-chain |
| Task branch | task/DP-902-T1-feat-absent-chain |
| Depends on | — |

## Test Command

echo ok

## Allowed Files

- `scripts/**`
TASK

# Precondition: feat/DP-902 absent locally and on origin.
git -C "$LOCAL" show-ref --verify --quiet refs/heads/feat/DP-902 && pre="present" || pre="absent"
_assert "$pre" "absent" "Case1 precondition: feat/DP-902 must start absent"

out="$(_run "$TASK1" --repo-base "$TMPDIR_ST" 2>"$TMPDIR_ST/c1.err")"
rc=$?
if [[ "$rc" != "0" ]]; then
  echo "----- c1.err -----" >&2
  cat "$TMPDIR_ST/c1.err" >&2
fi
_assert "$rc" "0" "Case1 AC1: fresh feat-model first task (feat absent + branch chain) must succeed"

# It must NOT have died in the cascade-rebase step.
if grep -q 'branch chain rebase failed\|upstream branch not found' "$TMPDIR_ST/c1.err"; then
  t="died-in-cascade"
else
  t="cascade-ok"
fi
_assert "$t" "cascade-ok" "Case1 AC-NEG1: must not die in cascade-rebase before feat base is created"

# feat/DP-902 must now exist, created from origin/main HEAD.
git -C "$LOCAL" show-ref --verify --quiet refs/heads/feat/DP-902 && t="found" || t="missing"
_assert "$t" "found" "Case1 AC1: feat/DP-902 must be created"
if [[ "$t" == "found" ]]; then
  _assert "$(git -C "$LOCAL" rev-parse refs/heads/feat/DP-902)" "$MAIN_SHA" \
    "Case1 AC1: feat/DP-902 must be created from origin/main HEAD"
fi

# Task branch must exist and be based on feat/DP-902.
git -C "$LOCAL" show-ref --verify --quiet refs/heads/task/DP-902-T1-feat-absent-chain && t="found" || t="missing"
_assert "$t" "found" "Case1 AC1: task branch must be created"
if [[ "$t" == "found" ]]; then
  if git -C "$LOCAL" merge-base --is-ancestor refs/heads/feat/DP-902 \
       refs/heads/task/DP-902-T1-feat-absent-chain >/dev/null 2>&1; then
    t="based-on-feat"
  else
    t="not-based-on-feat"
  fi
  _assert "$t" "based-on-feat" "Case1 AC1: task branch base must be feat/DP-902"
fi

# ---------------------------------------------------------------------------
# Case 2 (AC-NEG1): feat-present + Branch chain present.
# Re-run reuses feat/DP-902 (the reorder must not double-create the feat base).
# ---------------------------------------------------------------------------
git -C "$LOCAL" worktree prune >/dev/null 2>&1 || true
out="$(_run "$TASK1" --repo-base "$TMPDIR_ST" 2>"$TMPDIR_ST/c2.err")"
rc=$?
if [[ "$rc" != "0" ]]; then
  echo "----- c2.err -----" >&2
  cat "$TMPDIR_ST/c2.err" >&2
fi
_assert "$rc" "0" "Case2 AC-NEG1: re-run with existing feat/DP-902 must succeed"
feat_count="$(git -C "$LOCAL" for-each-ref --format='%(refname)' 'refs/heads/feat/DP-902' | wc -l | tr -d ' ')"
_assert "$feat_count" "1" "Case2 AC-NEG1: feat/DP-902 must not be duplicated on re-run"

# ---------------------------------------------------------------------------
# Case 3 (AC5): no-branch-chain + feat-absent (fresh feat/DP-903, no Branch chain
# row). The reorder must NOT gate ensure_feat_dp_branch behind the cascade `if`:
# when BRANCH_CHAIN is empty the cascade block is skipped, yet ensure_feat must
# still create the feat base. This is the path the pre-existing feat-dp selftest
# exercised — the regression guard for the reorder.
# ---------------------------------------------------------------------------
TASK3="$TMPDIR_ST/t3.md"
cat >"$TASK3" <<'TASK'
# T1 — no branch chain, feat absent

> Epic: DP-903 | JIRA: DP-903-T1 | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DP-903-T1 |
| Base branch | feat/DP-903 |
| Task branch | task/DP-903-T1-no-chain-feat-absent |
| Depends on | — |

## Test Command

echo ok

## Allowed Files

- `scripts/**`
TASK

# Precondition: feat/DP-903 absent.
git -C "$LOCAL" show-ref --verify --quiet refs/heads/feat/DP-903 && pre="present" || pre="absent"
_assert "$pre" "absent" "Case3 precondition: feat/DP-903 must start absent"

out="$(_run "$TASK3" --repo-base "$TMPDIR_ST" 2>"$TMPDIR_ST/c3.err")"
rc=$?
if [[ "$rc" != "0" ]]; then
  echo "----- c3.err -----" >&2
  cat "$TMPDIR_ST/c3.err" >&2
fi
_assert "$rc" "0" "Case3 AC5: no-branch-chain + feat-absent must succeed"

# feat/DP-903 must be created even though the cascade block is skipped.
git -C "$LOCAL" show-ref --verify --quiet refs/heads/feat/DP-903 && t="found" || t="missing"
_assert "$t" "found" "Case3 AC5: ensure_feat must create feat/DP-903 with no Branch chain (not gated behind cascade)"
if [[ "$t" == "found" ]]; then
  _assert "$(git -C "$LOCAL" rev-parse refs/heads/feat/DP-903)" "$MAIN_SHA" \
    "Case3 AC5: feat/DP-903 must be created from origin/main HEAD"
fi

git -C "$LOCAL" show-ref --verify --quiet refs/heads/task/DP-903-T1-no-chain-feat-absent && t="found" || t="missing"
_assert "$t" "found" "Case3 AC5: task branch must be created"
if [[ "$t" == "found" ]]; then
  if git -C "$LOCAL" merge-base --is-ancestor refs/heads/feat/DP-903 \
       refs/heads/task/DP-903-T1-no-chain-feat-absent >/dev/null 2>&1; then
    t="based-on-feat"
  else
    t="not-based-on-feat"
  fi
  _assert "$t" "based-on-feat" "Case3 AC5: task branch base must be feat/DP-903"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "engineering-branch-setup-ensure-feat-before-cascade-selftest: PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
