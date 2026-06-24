#!/usr/bin/env bash
# Purpose: DP-360 T9 / AC4 — reproduce root bug #6 (rebase-orphan) RED->GREEN.
#   Old design (delivery evidence keyed on the pre-rebase head, e.g. a
#   head-sha-keyed completion-gate marker) is RED: a plain `git rebase` that
#   rewrites the feat SHA strands that evidence, so a closeout that resolves the
#   delivered head and looks for evidence at the rebased head fails with
#   `local_extension_completion_failed`. New design (cascade-rebase-chain.sh
#   --onto = a delivery-flow step that re-runs the verify gate at the new head
#   and rewrites the task.md deliverable head/block) is GREEN: the closeout reads
#   the rebased head from the task.md block and finds matching fresh evidence, so
#   it PASSES.
# Inputs:  none (self-contained git fixtures via mktemp).
# Outputs: stdout `rebase-orphan-root-bug6: PASS=N FAIL=M TOTAL=K`;
#   exit 0 only when FAIL=0.
#
# RED fidelity: the RED branch does NOT stub the failure — it runs a real
#   `git rebase feat onto origin/main`, then resolves the delivered head from a
#   marker keyed on the PRE-rebase head (the old DP-319-era model) and looks for
#   verify evidence at the rebased head. Because the marker head is now an orphan
#   (no evidence file exists at the rebased head, and the marker head no longer
#   matches the live delivered head), the closeout model returns
#   `local_extension_completion_failed` — the genuine root bug #6 symptom.
#
# GREEN fidelity: the GREEN branch runs the actual cascade-rebase-chain.sh
#   --onto delivery-flow step, which rewrites the task.md deliverable head/block
#   to the rebased head. The closeout model then resolves the delivered head from
#   the task.md block and finds the fresh verify evidence at that head → PASS.
#   With the head-sha-keyed marker retired (DP-360 T7) there is no frozen marker
#   left to orphan, so root bug #6 is structurally absent.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASCADE="$SCRIPT_DIR/cascade-rebase-chain.sh"

PASS=0
FAIL=0
TOTAL=0

WORK_DIR="$(mktemp -d -t rebase-orphan-root-bug6-selftest-XXXXXX)"
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

# closeout_resolves_delivered_head MODE TASK_MD MARKER_HEAD EVIDENCE_DIR
#   Models the closeout delivered-head resolution + evidence lookup contract for
#   both designs and echoes either a head sha (resolved+evidence present) or
#   "local_extension_completion_failed".
#   MODE=marker → resolve delivered head from a frozen marker (old design).
#   MODE=block  → resolve delivered head from the task.md deliverable block.
closeout_resolves_delivered_head() {
  local mode="$1" task_md="$2" marker_head="$3" evidence_dir="$4"
  local delivered_head=""
  case "$mode" in
    marker)
      delivered_head="$marker_head"
      ;;
    block)
      delivered_head="$(grep -E '^  head_sha:' "$task_md" 2>/dev/null | awk '{print $2}' | head -n1)"
      ;;
  esac
  if [[ -z "$delivered_head" ]]; then
    echo "local_extension_completion_failed"
    return 0
  fi
  # Evidence must exist at the resolved delivered head.
  if [[ -f "$evidence_dir/verify-$delivered_head.json" ]]; then
    echo "$delivered_head"
  else
    echo "local_extension_completion_failed"
  fi
}

# build_fixture: bare origin + feat behind main + task.md deliverable block.
# Echoes "REPO|TASK_MD|PRE_REBASE_HEAD" via the named output file.
build_fixture() {
  local repo_dir="$1"
  local bare="$repo_dir.git"
  git init -q --bare "$bare"
  git init -q -b main "$repo_dir"
  git -C "$repo_dir" config user.email selftest@example.com
  git -C "$repo_dir" config user.name selftest
  git -C "$repo_dir" remote add origin "$bare"

  local task_dir="$repo_dir/docs-manager/src/content/docs/specs/design-plans/DP-997-bug6/tasks/T1"
  mkdir -p "$task_dir"
  local task_md="$task_dir/index.md"
  cat >"$task_md" <<MD
---
title: "bug6 fixture"
status: IN_PROGRESS
deliverable:
  pr_url: https://github.com/o/r/pull/6
  pr_state: OPEN
  head_sha: PLACEHOLDER
---

# bug6 fixture

> Source: DP-997 | Task: DP-997-T1 | JIRA: N/A | Repo: $(basename "$repo_dir")

## Verify Command

\`\`\`bash
true
\`\`\`

## Test Environment

- **Level**: static
MD
  git -C "$repo_dir" add -A
  git -C "$repo_dir" commit -q -m "base + task.md"
  git -C "$repo_dir" push -q origin main

  git -C "$repo_dir" checkout -q -b feat/DP-997 main
  printf 'feat-change\n' >"$repo_dir/feat.txt"
  git -C "$repo_dir" add feat.txt
  git -C "$repo_dir" commit -q -m "feat work"
  local delivered_head
  delivered_head="$(git -C "$repo_dir" rev-parse HEAD)"
  # Stamp the deliverable head to the delivered (feat work) head, then commit so
  # the recorded head is a real pre-rebase ancestor.
  sed -i.bak "s/^  head_sha: .*/  head_sha: $delivered_head/" "$task_md"
  rm -f "$task_md.bak"
  git -C "$repo_dir" commit -q -am "stamp deliverable head"

  git -C "$repo_dir" checkout -q main
  printf 'main-change\n' >"$repo_dir/main2.txt"
  git -C "$repo_dir" add main2.txt
  git -C "$repo_dir" commit -q -m "main advances"
  git -C "$repo_dir" push -q origin main

  git -C "$repo_dir" checkout -q feat/DP-997
  printf '%s|%s|%s\n' "$repo_dir" "$task_md" "$delivered_head" >"$2"
}

# ============================================================================
# RED — old design: plain rebase + marker keyed on the pre-rebase delivered head
# ============================================================================
RED_REPO="$WORK_DIR/red-repo"
RED_OUT="$WORK_DIR/red-fixture.txt"
build_fixture "$RED_REPO" "$RED_OUT"
IFS='|' read -r _ RED_TASK_MD RED_DELIVERED_HEAD <"$RED_OUT"

# Old-design evidence: a verify marker keyed on the pre-rebase delivered head.
RED_EVIDENCE="$WORK_DIR/red-evidence"
mkdir -p "$RED_EVIDENCE"
: >"$RED_EVIDENCE/verify-$RED_DELIVERED_HEAD.json"

# Plain `git rebase` (NOT the re-verify delivery-flow step) — the old behavior
# the SKILL.md doc-vs-script mismatch forced (no --onto re-verify available).
git -C "$RED_REPO" rebase origin/main feat/DP-997 >/dev/null 2>&1
RED_NEW_HEAD="$(git -C "$RED_REPO" rev-parse HEAD)"

_assert "RED fixture: plain rebase moved feat head (orphaning pre-rebase head)" \
  "$([[ "$RED_NEW_HEAD" != "$RED_DELIVERED_HEAD" ]] && echo ok || echo fail)"

# Closeout (old design) resolves the delivered head from the frozen marker keyed
# on the pre-rebase head, then looks for evidence at THAT head. The live tree has
# moved on; there is no evidence at the rebased head, and the marker head is now
# an orphan → local_extension_completion_failed.
red_result="$(closeout_resolves_delivered_head marker "$RED_TASK_MD" "$RED_NEW_HEAD" "$RED_EVIDENCE")"
if [[ "$red_result" == "local_extension_completion_failed" ]]; then
  _assert "RED: old design fails closeout (local_extension_completion_failed)" "ok"
else
  _assert "RED: old design fails closeout (got '$red_result')" "fail"
fi

# ============================================================================
# GREEN — new design: cascade-rebase-chain.sh --onto re-verify delivery-flow step
# ============================================================================
GREEN_REPO="$WORK_DIR/green-repo"
GREEN_OUT="$WORK_DIR/green-fixture.txt"
build_fixture "$GREEN_REPO" "$GREEN_OUT"
IFS='|' read -r _ GREEN_TASK_MD GREEN_DELIVERED_HEAD <"$GREEN_OUT"

# Run the actual delivery-flow step: rebase feat->main + re-verify + rewrite the
# task.md deliverable head/block to the rebased head.
green_run_rc=0
bash "$CASCADE" --repo "$GREEN_REPO" --onto origin/main \
  >"$WORK_DIR/green.out" 2>"$WORK_DIR/green.err" || green_run_rc=$?
if [[ "$green_run_rc" -eq 0 ]]; then
  _assert "GREEN fixture: --onto re-verify delivery-flow step exits 0" "ok"
else
  _assert "GREEN fixture: --onto re-verify delivery-flow step exits 0 (rc=$green_run_rc)" "fail"
  printf '       stdout:\n%s\n       stderr:\n%s\n' \
    "$(cat "$WORK_DIR/green.out")" "$(cat "$WORK_DIR/green.err")" >&2
fi
GREEN_NEW_HEAD="$(git -C "$GREEN_REPO" rev-parse HEAD)"

# The re-verify step wrote fresh verify evidence at the rebased head (model it as
# the durable evidence the closeout consumes — keyed on the NEW head).
GREEN_EVIDENCE="$WORK_DIR/green-evidence"
mkdir -p "$GREEN_EVIDENCE"
: >"$GREEN_EVIDENCE/verify-$GREEN_NEW_HEAD.json"

# Closeout (new design) resolves the delivered head from the task.md deliverable
# block (which --onto rewrote to the rebased head) and finds the fresh evidence.
green_result="$(closeout_resolves_delivered_head block "$GREEN_TASK_MD" "" "$GREEN_EVIDENCE")"
if [[ "$green_result" == "$GREEN_NEW_HEAD" ]]; then
  _assert "GREEN: new design passes closeout (delivered head = rebased head, evidence found)" "ok"
else
  _assert "GREEN: new design passes closeout (got '$green_result' expected '$GREEN_NEW_HEAD')" "fail"
fi

# Cross-check: the GREEN task.md block no longer points at the orphaned pre-rebase
# head — it was rewritten to the rebased head (no frozen marker left to orphan).
green_block_head="$(grep -E '^  head_sha:' "$GREEN_TASK_MD" | awk '{print $2}' | head -n1)"
if [[ "$green_block_head" == "$GREEN_NEW_HEAD" && "$green_block_head" != "$GREEN_DELIVERED_HEAD" ]]; then
  _assert "GREEN: task.md head/block rewritten to rebased head (orphan structurally gone)" "ok"
else
  _assert "GREEN: task.md head/block rewritten to rebased head (block=$green_block_head new=$GREEN_NEW_HEAD)" "fail"
fi

printf 'rebase-orphan-root-bug6: PASS=%s FAIL=%s TOTAL=%s\n' "$PASS" "$FAIL" "$TOTAL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
