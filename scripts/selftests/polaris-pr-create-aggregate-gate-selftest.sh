#!/usr/bin/env bash
# scripts/selftests/polaris-pr-create-aggregate-gate-selftest.sh
# DP-303 T4 (S4) — bundle-PR canonical path + gate-evidence aggregate-aware,
#                  close bundle escape-hatch.
#
# Purpose: prove the single canonical bundle-PR build path
#   (polaris-pr-create.sh --aggregate-release) passes the evidence gate WITHOUT
#   --skip-gates, and that the escape-hatch cannot be used as a bundle bypass.
# Inputs:  none (self-contained git fixtures under mktemp).
# Outputs: stdout PASS/FAIL summary; exit 0 = all PASS, 1 = at least one FAIL.
#
# Coverage:
#   AC5     — gate-evidence.sh --aggregate-release treats each bundled task's
#             task.md deliverable block (deliverable.head_sha present, status PASS)
#             as satisfying the evidence gate; no --skip-gates needed. DP-360 T7:
#             the task.md block is the sole delivery-evidence record (the head-sha
#             completion_gate marker is retired — no dual-source, NEG2).
#   AC-NEG1 — bundle release must not depend on the POLARIS_PR_WORKFLOW=1
#             escape-hatch: the legacy bare `gh pr create` escape-hatch is NOT a
#             bundle build path, and a bundled task whose deliverable block lacks a
#             PASS verification still fails closed.
#
# DP-360 T7 (AC3 / NEG1): a bundled task whose task.md deliverable block has no
# verification PASS (missing sub-block or non-PASS status) is rejected fail-closed;
# the gate never reads a separate marker and never falls back to a branch ref.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE_EVIDENCE="$ROOT_DIR/scripts/gates/gate-evidence.sh"
PR_CREATE="$ROOT_DIR/scripts/polaris-pr-create.sh"
PR_GUARD="$ROOT_DIR/scripts/pr-create-guard.sh"

PASS=0
FAIL=0
TOTAL=0

_assert() {
  TOTAL=$((TOTAL + 1))
  if [[ "$1" == "$2" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf '[FAILED %d]: expected=%q got=%q — %s\n' "$TOTAL" "$2" "$1" "$3" >&2
  fi
}

_assert_contains() {
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$1" | grep -qF -- "$2"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf '[FAILED %d]: substring not found: %q — %s\n' "$TOTAL" "$2" "$3" >&2
    printf '       in: %s\n' "$1" >&2
  fi
}

TMPROOT="$(mktemp -d -t polaris-aggregate-gate-XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

# write_bundled_task_md <task_md_path> <source_id> <task_id> <repo_name> <head_sha> [verification]
# Emits a minimal canonical task.md carrying a deliverable block. DP-360 T7: the
# task.md deliverable block (head_sha + verification.status) is the SOLE delivery
# evidence the aggregate gate reads — there is no head-sha completion_gate marker.
#   verification = PASS  -> deliverable.verification.status: PASS (default)
#   verification = FAIL  -> deliverable.verification.status: FAIL
#   verification = none  -> no verification sub-block (delivery head, no PASS proof)
write_bundled_task_md() {
  local task_md="$1" source_id="$2" task_id="$3" repo_name="$4" head_sha="$5"
  local verification="${6:-PASS}"
  mkdir -p "$(dirname "$task_md")"
  {
    cat <<EOF
---
title: "${task_id}"
status: IMPLEMENTED
depends_on: []
deliverable:
  pr_url: https://github.com/demo/example/pull/100
  pr_state: MERGED
  head_sha: ${head_sha}
EOF
    if [[ "$verification" != "none" ]]; then
      cat <<EOF
  verification:
    status: ${verification}
    ac_counts:
      ac_total: 0
      ac_pass: 0
      ac_fail: 0
      ac_manual_required: 0
      ac_uncertain: 0
EOF
    fi
    cat <<EOF
---

# ${task_id}

> Source: ${source_id} | Task: ${task_id} | JIRA: N/A | Repo: ${repo_name}

## Allowed Files

- \`scripts/foo.sh\`

## Verify Command

\`\`\`bash
echo ok
\`\`\`
EOF
  } >"$task_md"
}

# ---------------------------------------------------------------------------
# Case 1 (AC5): aggregate-release evidence gate PASSES when every bundled task
#               has a completion_gate marker with head == delivery head, status
#               PASS — without --skip-gates.
# ---------------------------------------------------------------------------
{
  workspace="$TMPROOT/c1-ws"
  repo="$workspace/repo"
  mkdir -p "$repo"
  git init -q -b main "$repo"
  git -C "$repo" config user.name selftest
  git -C "$repo" config user.email selftest@example.invalid
  echo init >"$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m base
  git -C "$repo" checkout -q -b bundle-DP-303-v9.9.9

  tasks_dir="$workspace/docs-manager/src/content/docs/specs/design-plans/DP-303-fixture/tasks"
  head1="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  head2="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  write_bundled_task_md "$tasks_dir/T1/index.md" DP-303 DP-303-T1 repo "$head1" PASS
  write_bundled_task_md "$tasks_dir/T2/index.md" DP-303 DP-303-T2 repo "$head2" PASS

  set +e
  output=$(
    POLARIS_WORKSPACE_ROOT="$workspace" \
      bash "$GATE_EVIDENCE" --repo "$repo" --aggregate-release \
        --source DP-303 --bundled-tasks DP-303-T1,DP-303-T2 2>&1
  )
  rc=$?
  set -e
  _assert "$rc" "0" "C1: aggregate evidence gate must PASS with valid per-task deliverable blocks"
  _assert_contains "$output" "aggregate" "C1: gate output must reference aggregate mode"
}

# ---------------------------------------------------------------------------
# Case 2 (AC-NEG1 / no PASS proof): a bundled task whose deliverable block records
#               a head but has NO verification sub-block is rejected fail-closed —
#               a recorded delivery head without a PASS proof is not evidence.
# ---------------------------------------------------------------------------
{
  workspace="$TMPROOT/c2-ws"
  repo="$workspace/repo"
  mkdir -p "$repo"
  git init -q -b main "$repo"
  git -C "$repo" config user.name selftest
  git -C "$repo" config user.email selftest@example.invalid
  echo init >"$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m base
  git -C "$repo" checkout -q -b bundle-DP-303-v9.9.8

  tasks_dir="$workspace/docs-manager/src/content/docs/specs/design-plans/DP-303-fixture/tasks"
  real_head="cccccccccccccccccccccccccccccccccccccccc"
  # Delivery head present, but NO deliverable.verification PASS proof.
  write_bundled_task_md "$tasks_dir/T1/index.md" DP-303 DP-303-T1 repo "$real_head" none

  set +e
  output=$(
    POLARIS_WORKSPACE_ROOT="$workspace" \
      bash "$GATE_EVIDENCE" --repo "$repo" --aggregate-release \
        --source DP-303 --bundled-tasks DP-303-T1 2>&1
  )
  rc=$?
  set -e
  _assert "$rc" "2" "C2: deliverable head without a verification PASS must fail-closed (exit 2)"
  _assert_contains "$output" "DP-303-T1" "C2: failure must name the offending task"
}

# ---------------------------------------------------------------------------
# Case 3 (AC-NEG1 / missing task.md): a bundled task with NO resolvable task.md
#               fails closed (no silent pass, no branch-ref fallback).
# ---------------------------------------------------------------------------
{
  workspace="$TMPROOT/c3-ws"
  repo="$workspace/repo"
  mkdir -p "$repo"
  git init -q -b main "$repo"
  git -C "$repo" config user.name selftest
  git -C "$repo" config user.email selftest@example.invalid
  echo init >"$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m base
  git -C "$repo" checkout -q -b bundle-DP-303-v9.9.7

  # No task.md written for DP-303-T1 → unresolvable → fail closed.
  set +e
  output=$(
    POLARIS_WORKSPACE_ROOT="$workspace" \
      bash "$GATE_EVIDENCE" --repo "$repo" --aggregate-release \
        --source DP-303 --bundled-tasks DP-303-T1 2>&1
  )
  rc=$?
  set -e
  _assert "$rc" "2" "C3: unresolvable bundled task.md must fail-closed (exit 2)"
}

# ---------------------------------------------------------------------------
# Case 4 (AC-NEG1 / non-PASS status): a bundled task whose deliverable block
#               records verification.status != PASS fails closed.
# ---------------------------------------------------------------------------
{
  workspace="$TMPROOT/c4-ws"
  repo="$workspace/repo"
  mkdir -p "$repo"
  git init -q -b main "$repo"
  git -C "$repo" config user.name selftest
  git -C "$repo" config user.email selftest@example.invalid
  echo init >"$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m base
  git -C "$repo" checkout -q -b bundle-DP-303-v9.9.6

  tasks_dir="$workspace/docs-manager/src/content/docs/specs/design-plans/DP-303-fixture/tasks"
  head1="ffffffffffffffffffffffffffffffffffffffff"
  write_bundled_task_md "$tasks_dir/T1/index.md" DP-303 DP-303-T1 repo "$head1" FAIL

  set +e
  output=$(
    POLARIS_WORKSPACE_ROOT="$workspace" \
      bash "$GATE_EVIDENCE" --repo "$repo" --aggregate-release \
        --source DP-303 --bundled-tasks DP-303-T1 2>&1
  )
  rc=$?
  set -e
  _assert "$rc" "2" "C4: non-PASS deliverable.verification.status must fail-closed (exit 2)"
}

# ---------------------------------------------------------------------------
# Case 5 (AC5): polaris-pr-create.sh forwards the aggregate context to
#               gate-evidence so the bundle PR builds the canonical way (no
#               --skip-gates). The evidence gate invocation in the production
#               wrapper must thread --aggregate-release / --source /
#               --bundled-tasks into the gate-evidence args. We assert the
#               wiring is present in the production script (no second canonical
#               path / no hidden --skip-gates dependency).
# ---------------------------------------------------------------------------
{
  # Production wrapper must pass the aggregate context into the evidence gate.
  evidence_block="$(awk '/^# Gate 2: evidence/{p=1} p{print} /^# Gate 3:/{if(p)exit}' "$PR_CREATE")"
  _assert_contains "$evidence_block" "--aggregate-release" \
    "C5: evidence gate invocation must forward --aggregate-release"
  _assert_contains "$evidence_block" "--bundled-tasks" \
    "C5: evidence gate invocation must forward --bundled-tasks"

  # The aggregate-release path must NOT silently require --skip-gates: the
  # --skip-gates branch is an explicit opt-out, never an implicit bundle default.
  if grep -nE 'AGGREGATE_RELEASE.*SKIP_GATES=1|SKIP_GATES=1.*AGGREGATE_RELEASE' "$PR_CREATE" >/dev/null; then
    auto_skip=found
  else
    auto_skip=absent
  fi
  _assert "$auto_skip" "absent" \
    "C5: aggregate-release must not auto-enable --skip-gates"
}

# ---------------------------------------------------------------------------
# Case 6 (AC-NEG1): the POLARIS_PR_WORKFLOW=1 escape-hatch is NOT a bundle build
#               path. pr-create-guard.sh still blocks bare `gh pr create` for the
#               bundle title unless the escape-hatch env is set — and the
#               canonical bundle path never relies on it. We assert the guard
#               blocks bare bundle `gh pr create` without the escape-hatch.
# ---------------------------------------------------------------------------
{
  cmd='gh pr create --base main --title "chore(release): bundle DP-303 -> v9.9.5" --body x'
  payload="$(python3 -c '
import json, sys
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))
' "$cmd")"

  set +e
  output=$(printf '%s' "$payload" | bash "$PR_GUARD" 2>&1)
  rc=$?
  set -e
  _assert "$rc" "2" "C6: bare bundle gh pr create must be blocked (escape-hatch not a bundle path)"
  _assert_contains "$output" "polaris-pr-create" "C6: guard must steer bundle to canonical wrapper"
}

# ---------------------------------------------------------------------------
echo ""
printf 'polaris-pr-create aggregate-gate selftest: %d/%d PASS, %d failed\n' \
  "$PASS" "$TOTAL" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
