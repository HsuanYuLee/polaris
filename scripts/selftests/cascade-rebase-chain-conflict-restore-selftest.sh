#!/usr/bin/env bash
# Purpose: real-state selftest for DP-352-T3 Bug #3 — cascade-rebase-chain.sh's
#   conflict branch must `git rebase --abort` + restore the original branch
#   before exiting 1, mirroring the push_failed path, so a rebase conflict does
#   not leave the caller's checkout mid-rebase / on the wrong branch.
# Inputs:  none (self-contained git fixtures via mktemp).
# Outputs: stdout `cascade-rebase-chain-conflict-restore: PASS=N FAIL=M TOTAL=K`;
#   exit 0 only when FAIL=0.
#
# Bug reproduction fidelity: the fixture builds a real divergent stack
# (feat/DP-902 advanced on origin, task/DP-902-T1 branched earlier) that edits
# the SAME line, so rebasing the task branch onto origin/feat/DP-902 produces a
# genuine merge conflict — not a stubbed signal. Against the UNFIXED script the
# conflict path emits evidence and `exit 1` while still mid-rebase: the working
# tree is dirty, `.git/rebase-merge` survives, and HEAD is left on the task
# branch instead of the original branch (RED). After the fix aborts the rebase
# and restores the original branch, the checkout is clean and back on the
# original branch, while still failing loud (exit 1) and preserving the conflict
# evidence (GREEN).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASCADE="$SCRIPT_DIR/cascade-rebase-chain.sh"

PASS=0
FAIL=0
TOTAL=0

WORK_DIR="$(mktemp -d -t cascade-rebase-conflict-selftest-XXXXXX)"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

_assert() {
  local label="$1"
  local cond="$2" # "ok" or anything else = fail
  TOTAL=$((TOTAL + 1))
  if [[ "$cond" == "ok" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf '[FAIL] %s\n' "$label" >&2
  fi
}

# --- Fixture: bare origin + working clone with a real divergent conflict. ---
BARE="$WORK_DIR/origin.git"
git init -q --bare "$BARE"

REPO="$WORK_DIR/repo"
git init -q -b feat/DP-902 "$REPO"
git -C "$REPO" config user.email selftest@example.com
git -C "$REPO" config user.name selftest
git -C "$REPO" remote add origin "$BARE"

# Base commit (shared ancestor) edits conflict.txt.
printf 'base\n' >"$REPO/conflict.txt"
git -C "$REPO" add conflict.txt
git -C "$REPO" commit -q -m "base commit"
BASE_SHA="$(git -C "$REPO" rev-parse HEAD)"

# feat/DP-902 advances: change the same line to "from-feat", push to origin.
printf 'from-feat\n' >"$REPO/conflict.txt"
git -C "$REPO" commit -q -am "feat advances conflict.txt"
git -C "$REPO" push -q origin feat/DP-902

# task/DP-902-T1 branches from the SHARED ancestor and changes the same line to
# "from-task" — rebasing it onto origin/feat/DP-902 must conflict.
git -C "$REPO" checkout -q -b task/DP-902-T1 "$BASE_SHA"
printf 'from-task\n' >"$REPO/conflict.txt"
git -C "$REPO" commit -q -am "task changes conflict.txt"

# task.md fixture with the Branch chain the cascade resolves.
TASKS_DIR="$WORK_DIR/tasks"
mkdir -p "$TASKS_DIR"
TASK_MD="$TASKS_DIR/index.md"
cat >"$TASK_MD" <<'MD'
---
title: "fixture task"
---

# fixture

| 欄位 | 值 |
|------|-----|
| Base branch | feat/DP-902 |
| Branch chain | feat/DP-902 -> task/DP-902-T1 |
| Task branch | task/DP-902-T1 |
MD

# Start from a clean, named original branch so restoration is observable.
git -C "$REPO" checkout -q feat/DP-902
ORIG_BRANCH="$(git -C "$REPO" symbolic-ref --short HEAD)"
_assert "fixture: original branch is feat/DP-902" \
  "$([[ "$ORIG_BRANCH" == "feat/DP-902" ]] && echo ok || echo fail)"

# --- Run the cascade; it must hit a real conflict on the task branch. ---
cascade_out="$WORK_DIR/cascade.out"
rc=0
bash "$CASCADE" --repo "$REPO" --task-md "$TASK_MD" >"$cascade_out" 2>"$WORK_DIR/cascade.err" || rc=$?

# A1 (AC-NEG2): still fails loud on conflict.
if [[ "$rc" -eq 1 ]]; then
  _assert "A1: cascade exits 1 on conflict (fail-loud preserved)" "ok"
else
  _assert "A1: cascade exits 1 on conflict (fail-loud preserved) (rc=$rc)" "fail"
fi

# A2 (AC-NEG2): conflict evidence is preserved (emitted to stdout).
if grep -q '"status":"conflict"' "$cascade_out"; then
  _assert "A2: conflict evidence emitted (status:conflict preserved)" "ok"
else
  _assert "A2: conflict evidence emitted (status:conflict preserved)" "fail"
  printf '       cascade stdout:\n%s\n' "$(cat "$cascade_out")" >&2
fi

# A3 (AC3 / AC5): no rebase is left in progress and the working tree is clean.
rebase_in_progress="no"
if [[ -d "$REPO/.git/rebase-merge" || -d "$REPO/.git/rebase-apply" ]]; then
  rebase_in_progress="yes"
fi
dirty="no"
if ! git -C "$REPO" diff --quiet || ! git -C "$REPO" diff --cached --quiet; then
  dirty="yes"
fi
if [[ "$rebase_in_progress" == "no" && "$dirty" == "no" ]]; then
  _assert "A3: rebase aborted + working tree clean after conflict" "ok"
else
  _assert "A3: rebase aborted + working tree clean after conflict (rebase=$rebase_in_progress dirty=$dirty)" "fail"
fi

# A4 (AC3): the original branch is restored (HEAD back on feat/DP-902).
head_now="$(git -C "$REPO" symbolic-ref --quiet --short HEAD 2>/dev/null || echo '(detached)')"
if [[ "$head_now" == "$ORIG_BRANCH" ]]; then
  _assert "A4: original branch restored after conflict" "ok"
else
  _assert "A4: original branch restored after conflict (head=$head_now expected=$ORIG_BRANCH)" "fail"
fi

printf 'cascade-rebase-chain-conflict-restore: PASS=%s FAIL=%s TOTAL=%s\n' "$PASS" "$FAIL" "$TOTAL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
