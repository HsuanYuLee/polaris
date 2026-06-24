#!/usr/bin/env bash
# Purpose: DP-360 T9 / AC5 — assert cascade-rebase-chain.sh's signature is
#   aligned with the framework-release SKILL.md documentation (both the legacy
#   chain `--repo --task-md [--skip-missing-last]` form AND the documented
#   `--repo --onto <ref>` form parse without an unknown-arg error), and that the
#   --onto mode actually performs a feat->main rebase followed by the re-verify
#   delivery-flow step (verify gate re-run + task.md deliverable head/block
#   rewritten to the rebased head). This is exercised against real git fixtures,
#   not a usage-string grep.
# Inputs:  none (self-contained git fixtures via mktemp).
# Outputs: stdout `cascade-rebase-chain-signature: PASS=N FAIL=M TOTAL=K`;
#   exit 0 only when FAIL=0.
#
# Contract anchors:
#   - framework-release/SKILL.md:269 documents
#       `cascade-rebase-chain.sh --repo <repo> --onto origin/main`
#     so `--onto` must be a recognised flag (exit != 2-on-unknown-arg).
#   - engineering-branch-setup / revision-rebase / conflict-restore selftest
#     depend on the chain `--task-md` form, so it must keep parsing too.
#   - DP-360 D5 / AC5: --onto mode is a delivery-flow step, not an isolated git
#     rebase — after rebasing feat onto main it must re-run the verify gate at
#     the new head and rewrite the task.md deliverable head/block to that head.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASCADE="$SCRIPT_DIR/cascade-rebase-chain.sh"

PASS=0
FAIL=0
TOTAL=0

WORK_DIR="$(mktemp -d -t cascade-rebase-signature-selftest-XXXXXX)"
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

# --- A1: chain `--repo --task-md` signature is not an unknown arg. ------------
# Run against a non-git --repo so the script exits early with a deterministic
# "not a git repo" usage error (exit 2) — but crucially WITHOUT logging
# "unknown arg". A missing-flag regression would surface as "unknown arg".
chain_err="$WORK_DIR/chain.err"
set +e
bash "$CASCADE" --repo "$WORK_DIR/not-a-repo" --task-md "$WORK_DIR/none.md" \
  --skip-missing-last >/dev/null 2>"$chain_err"
set -e
if ! grep -q 'unknown arg' "$chain_err"; then
  _assert "A1: chain --repo/--task-md/--skip-missing-last not an unknown arg" "ok"
else
  _assert "A1: chain --repo/--task-md/--skip-missing-last not an unknown arg" "fail"
  printf '       stderr:\n%s\n' "$(cat "$chain_err")" >&2
fi

# --- A2: documented `--repo --onto <ref>` signature is not an unknown arg. ----
onto_err="$WORK_DIR/onto.err"
set +e
bash "$CASCADE" --repo "$WORK_DIR/not-a-repo" --onto origin/main \
  >/dev/null 2>"$onto_err"
set -e
if ! grep -q 'unknown arg' "$onto_err"; then
  _assert "A2: --repo --onto <ref> not an unknown arg (SKILL.md:269 aligned)" "ok"
else
  _assert "A2: --repo --onto <ref> not an unknown arg (SKILL.md:269 aligned)" "fail"
  printf '       stderr:\n%s\n' "$(cat "$onto_err")" >&2
fi

# --- Fixture: bare origin + feat behind main, with a task.md whose deliverable
#     block records the pre-rebase head. The rebase + re-verify must move the
#     deliverable head to the rebased head. ------------------------------------
BARE="$WORK_DIR/origin.git"
git init -q --bare "$BARE"

REPO="$WORK_DIR/repo"
git init -q -b main "$REPO"
git -C "$REPO" config user.email selftest@example.com
git -C "$REPO" config user.name selftest
git -C "$REPO" remote add origin "$BARE"

# task.md lives in the design-plan specs tree the --onto scanner walks; its
# `Repo` metadata must match the repo basename ("repo") so run-verify-command
# resolves the repo, and Verify Command is a trivially-passing static check.
TASK_DIR="$REPO/docs-manager/src/content/docs/specs/design-plans/DP-998-sig/tasks/T1"
mkdir -p "$TASK_DIR"
TASK_MD="$TASK_DIR/index.md"
write_task_md() {
  local head_sha="$1"
  cat >"$TASK_MD" <<MD
---
title: "sig fixture task"
status: IN_PROGRESS
deliverable:
  pr_url: https://github.com/o/r/pull/9
  pr_state: OPEN
  head_sha: ${head_sha}
---

# sig fixture

> Source: DP-998 | Task: DP-998-T1 | JIRA: N/A | Repo: repo

## Verify Command

\`\`\`bash
true
\`\`\`

## Test Environment

- **Level**: static
MD
}

write_task_md "PLACEHOLDER"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m "base + task.md"
git -C "$REPO" push -q origin main

# feat branches from main and adds a non-conflicting file.
git -C "$REPO" checkout -q -b feat/DP-998 main
printf 'feat-change\n' >"$REPO/feat.txt"
git -C "$REPO" add feat.txt
git -C "$REPO" commit -q -m "feat work"

# main advances on origin (different file → conflict-free rebase).
git -C "$REPO" checkout -q main
printf 'main-change\n' >"$REPO/main2.txt"
git -C "$REPO" add main2.txt
git -C "$REPO" commit -q -m "main advances"
git -C "$REPO" push -q origin main

# Back on feat: stamp the deliverable head to the "feat work" commit, then
# commit the stamp. The recorded delivered head is therefore an ancestor of the
# pre-rebase HEAD (the scanner selects task.md whose delivered head is reachable
# from the pre-rebase head), which is exactly the rebase-orphan precondition.
git -C "$REPO" checkout -q feat/DP-998
DELIVERED_HEAD="$(git -C "$REPO" rev-parse HEAD)"
write_task_md "$DELIVERED_HEAD"
git -C "$REPO" commit -q -am "stamp deliverable head"
PRE_REBASE_HEAD="$(git -C "$REPO" rev-parse HEAD)"

recorded_head_before="$(grep -E '^  head_sha:' "$TASK_MD" | awk '{print $2}')"
if [[ "$recorded_head_before" == "$DELIVERED_HEAD" ]] \
   && git -C "$REPO" merge-base --is-ancestor "$recorded_head_before" "$PRE_REBASE_HEAD" >/dev/null 2>&1; then
  _assert "fixture: deliverable head is a pre-rebase ancestor (orphan precondition)" "ok"
else
  _assert "fixture: deliverable head is a pre-rebase ancestor (orphan precondition)" "fail"
fi

# --- Run --onto origin/main: must rebase feat AND re-verify + rewrite block. --
onto_out="$WORK_DIR/onto.out"
rc=0
bash "$CASCADE" --repo "$REPO" --onto origin/main >"$onto_out" 2>"$WORK_DIR/onto-run.err" || rc=$?

# A3 (AC5): --onto exits 0 (rebase + re-verify clean).
if [[ "$rc" -eq 0 ]]; then
  _assert "A3: --onto rebase + re-verify exits 0" "ok"
else
  _assert "A3: --onto rebase + re-verify exits 0 (rc=$rc)" "fail"
  printf '       stdout:\n%s\n       stderr:\n%s\n' \
    "$(cat "$onto_out")" "$(cat "$WORK_DIR/onto-run.err")" >&2
fi

NEW_HEAD="$(git -C "$REPO" rev-parse HEAD)"

# A4 (AC5): the rebase actually moved feat forward onto main (feat now contains
# main's advance commit AND the head SHA changed).
if [[ "$NEW_HEAD" != "$PRE_REBASE_HEAD" ]] \
   && git -C "$REPO" merge-base --is-ancestor "origin/main" "$NEW_HEAD" >/dev/null 2>&1; then
  _assert "A4: feat->main rebase happened (head moved, main is ancestor)" "ok"
else
  _assert "A4: feat->main rebase happened (head=$NEW_HEAD pre=$PRE_REBASE_HEAD)" "fail"
fi

# A5 (AC5): the verify gate was re-run at the new head (run-verify-command logs
# the head it verifies on stderr).
if grep -q "re-verify at new head $NEW_HEAD" "$WORK_DIR/onto-run.err"; then
  _assert "A5: verify gate re-run at the rebased head" "ok"
else
  _assert "A5: verify gate re-run at the rebased head" "fail"
  printf '       stderr:\n%s\n' "$(cat "$WORK_DIR/onto-run.err")" >&2
fi

# A6 (AC5): task.md deliverable head/block rewritten to the rebased head.
recorded_head_after="$(grep -E '^  head_sha:' "$TASK_MD" | awk '{print $2}')"
if [[ "$recorded_head_after" == "$NEW_HEAD" ]]; then
  _assert "A6: task.md deliverable head/block updated to rebased head" "ok"
else
  _assert "A6: task.md deliverable head/block updated to rebased head (recorded=$recorded_head_after expected=$NEW_HEAD)" "fail"
fi

printf 'cascade-rebase-chain-signature: PASS=%s FAIL=%s TOTAL=%s\n' "$PASS" "$FAIL" "$TOTAL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
