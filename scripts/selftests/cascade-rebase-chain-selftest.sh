#!/usr/bin/env bash
# Purpose: real-state selftest for DP-324-T3 — cascade-rebase-chain.sh's chain-mode
#   upstream fallback must be fail-closed. When the chain upstream exists only as a
#   LOCAL branch (origin/<upstream> missing), the script must refuse to rebase onto
#   the local ref: it must exit non-zero AND print POLARIS_REBASE_LOCAL_FALLBACK,
#   instead of silently setting target_ref="$upstream" and rebasing onto local.
# Inputs:  none (self-contained git fixtures via mktemp).
# Outputs: stdout `cascade-rebase-chain: PASS=N FAIL=M TOTAL=K`; exit 0 only when FAIL=0.
#
# Bug reproduction fidelity:
#   Case (a) — origin/<upstream> MISSING: the fixture pushes only the task branch to
#   origin, leaving feat/<upstream> as a local-only branch. Against the UNFIXED
#   script the `origin/$upstream` rev-parse fails, the local `$upstream` rev-parse
#   succeeds, so target_ref="$upstream" (local) and the rebase silently proceeds onto
#   the local branch (exit 0, no marker = RED). After the fail-closed fix the script
#   emits POLARIS_REBASE_LOCAL_FALLBACK and exits non-zero (GREEN).
#
#   Case (b) — origin/<upstream> PRESENT: the fixture pushes feat/<upstream> to
#   origin so origin/<upstream> resolves; the cascade rebases the task branch onto
#   origin/<upstream> and exits 0 (proves the fail-closed change does not break the
#   normal main path origin/$RESOLVED_BASE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASCADE="$SCRIPT_DIR/cascade-rebase-chain.sh"

PASS=0
FAIL=0
TOTAL=0

WORK_DIR="$(mktemp -d -t cascade-rebase-chain-selftest-XXXXXX)"
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

# build_fixture <repo_dir> <push_upstream_to_origin: yes|no>
# Builds a bare origin + working clone with a two-entry chain
# (feat/<upstream> -> task/<key>-T1). The task branch is always pushed to origin so
# ensure_local_branch is satisfied. Whether feat/<upstream> is also pushed to origin
# controls whether origin/<upstream> resolves.
build_fixture() {
  local repo="$1" push_upstream="$2"
  local bare="$repo.git"
  git init -q --bare "$bare"

  git init -q -b feat/DP-901 "$repo"
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name selftest
  git -C "$repo" remote add origin "$bare"

  # Base commit on feat/DP-901.
  printf 'base\n' >"$repo/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -q -m "base commit"
  local base_sha
  base_sha="$(git -C "$repo" rev-parse HEAD)"

  # feat/DP-901 advances one commit (so a rebase is actually needed / not no-op).
  printf 'feat-advance\n' >>"$repo/file.txt"
  git -C "$repo" commit -q -am "feat advances"

  if [[ "$push_upstream" == "yes" ]]; then
    git -C "$repo" push -q origin feat/DP-901
  fi

  # task/DP-901-T1 branches from the SHARED ancestor (so it is behind upstream and a
  # rebase moves it forward), edits a different file (no conflict), and is pushed to
  # origin so ensure_local_branch resolves it.
  git -C "$repo" checkout -q -b task/DP-901-T1 "$base_sha"
  printf 'task-work\n' >"$repo/task.txt"
  git -C "$repo" add task.txt
  git -C "$repo" commit -q -m "task work"
  git -C "$repo" push -q origin task/DP-901-T1

  # Land on a clean named original branch.
  git -C "$repo" checkout -q feat/DP-901
}

write_task_md() {
  local task_md="$1"
  cat >"$task_md" <<'MD'
---
title: "fixture task"
---

# fixture

| 欄位 | 值 |
|------|-----|
| Base branch | feat/DP-901 |
| Branch chain | feat/DP-901 -> task/DP-901-T1 |
| Task branch | task/DP-901-T1 |
MD
}

# ===========================================================================
# Case (a): origin/<upstream> MISSING -> must fail-closed with marker.
# ===========================================================================
REPO_A="$WORK_DIR/repo_a"
build_fixture "$REPO_A" "no"
TASK_MD_A="$WORK_DIR/tasks_a/index.md"
mkdir -p "$WORK_DIR/tasks_a"
write_task_md "$TASK_MD_A"

out_a="$WORK_DIR/a.out"
err_a="$WORK_DIR/a.err"
rc_a=0
bash "$CASCADE" --repo "$REPO_A" --task-md "$TASK_MD_A" >"$out_a" 2>"$err_a" || rc_a=$?

# A1: non-zero exit (refused to rebase onto local branch).
if [[ "$rc_a" -ne 0 ]]; then
  _assert "A1: origin missing -> cascade exits non-zero (fail-closed)" "ok"
else
  _assert "A1: origin missing -> cascade exits non-zero (fail-closed) (rc=$rc_a)" "fail"
fi

# A2: POLARIS_REBASE_LOCAL_FALLBACK marker printed (stdout or stderr).
if grep -q 'POLARIS_REBASE_LOCAL_FALLBACK' "$out_a" "$err_a"; then
  _assert "A2: origin missing -> POLARIS_REBASE_LOCAL_FALLBACK emitted" "ok"
else
  _assert "A2: origin missing -> POLARIS_REBASE_LOCAL_FALLBACK emitted" "fail"
  printf '       stdout:\n%s\n       stderr:\n%s\n' "$(cat "$out_a")" "$(cat "$err_a")" >&2
fi

# A3: it must NOT have rebased onto the local upstream (task branch unchanged base).
# The task branch's merge-base with local feat/DP-901 stays the shared ancestor,
# i.e. the task branch did not silently absorb the local-only feat advance.
local_feat_sha="$(git -C "$REPO_A" rev-parse feat/DP-901)"
task_mb="$(git -C "$REPO_A" merge-base feat/DP-901 task/DP-901-T1)"
if [[ "$task_mb" != "$local_feat_sha" ]]; then
  _assert "A3: origin missing -> did NOT rebase task branch onto local upstream" "ok"
else
  _assert "A3: origin missing -> did NOT rebase task branch onto local upstream" "fail"
fi

# ===========================================================================
# Case (b): origin/<upstream> PRESENT -> rebase proceeds, exit 0.
# ===========================================================================
REPO_B="$WORK_DIR/repo_b"
build_fixture "$REPO_B" "yes"
TASK_MD_B="$WORK_DIR/tasks_b/index.md"
mkdir -p "$WORK_DIR/tasks_b"
write_task_md "$TASK_MD_B"

out_b="$WORK_DIR/b.out"
err_b="$WORK_DIR/b.err"
rc_b=0
bash "$CASCADE" --repo "$REPO_B" --task-md "$TASK_MD_B" >"$out_b" 2>"$err_b" || rc_b=$?

# B1: exit 0 (normal main path origin/<upstream> still works).
if [[ "$rc_b" -eq 0 ]]; then
  _assert "B1: origin present -> cascade exits 0 (normal rebase)" "ok"
else
  _assert "B1: origin present -> cascade exits 0 (normal rebase) (rc=$rc_b)" "fail"
  printf '       stdout:\n%s\n       stderr:\n%s\n' "$(cat "$out_b")" "$(cat "$err_b")" >&2
fi

# B2: no fallback marker on the happy path.
if grep -q 'POLARIS_REBASE_LOCAL_FALLBACK' "$out_b" "$err_b"; then
  _assert "B2: origin present -> no POLARIS_REBASE_LOCAL_FALLBACK marker" "fail"
else
  _assert "B2: origin present -> no POLARIS_REBASE_LOCAL_FALLBACK marker" "ok"
fi

# B3: the task branch was rebased onto origin/feat/DP-901 (merge-base == origin sha).
origin_feat_sha="$(git -C "$REPO_B" rev-parse origin/feat/DP-901)"
task_mb_b="$(git -C "$REPO_B" merge-base origin/feat/DP-901 task/DP-901-T1)"
if [[ "$task_mb_b" == "$origin_feat_sha" ]]; then
  _assert "B3: origin present -> task branch rebased onto origin/feat/DP-901" "ok"
else
  _assert "B3: origin present -> task branch rebased onto origin/feat/DP-901" "fail"
fi

printf 'cascade-rebase-chain: PASS=%s FAIL=%s TOTAL=%s\n' "$PASS" "$FAIL" "$TOTAL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
