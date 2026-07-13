#!/usr/bin/env bash
# Purpose: DP-417 T13 selftest — proves the real-epic trial-run harness
#          (scripts/spec-check-real-epic-trial-run.sh) enforces its exit-code
#          contract against generic fixtures (no live ticket key):
#            AC20 / AC-N1  : a spec-CONFORMANT specimen => 0 bounces => exit 0.
#            AC-NEG11 (chain) : a specimen with an un-reconciled task-shape drift
#                               (prose env_bootstrap on a runtime impl task) makes
#                               the chain stage bounce => harness exit 2.
#            AC-NEG11 (contract): a clean specimen but a repo-root whose spec<->check
#                               parity manifest anchors are gone makes the contract
#                               stage bounce => harness exit 2 (warning-only never
#                               passes).
#            fail-closed   : missing --source => exit 2.
# Inputs:  none (builds tmpdir refinement.json fixtures)
# Outputs: stdout PASS line; exit 0 PASS, exit 1 FAIL

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$REPO_ROOT/scripts/spec-check-real-epic-trial-run.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

fail() { echo "FAIL: $1"; exit 1; }

# Runtime fixture probe host: a non-8080 local port so validate-task-md treats it
# as a legal runtime verify target (matches the lock-preflight selftest constant).
RUNTIME_PROBE_URL="http://127.0.0.1:7317/health"

# canonical_impl_task — a fully-derivable implementation T-task object.
# Args: $1=id $2=title $3=level $4=env_bootstrap $5=runtime_target $6=verify_command
canonical_impl_task() {
  local id="$1" title="$2" level="$3" bootstrap="$4" runtime_target="$5" verify_command="$6"
  cat <<JSON
    {
      "id": "${id}",
      "kind": "implementation",
      "title": "${title}",
      "scope": "DP-417 T13 trial-run fixture for ${id}",
      "task_shape": "implementation",
      "tracked_deliverable_hint": "tracked",
      "allowed_files": ["scripts/${id}-dp417-t13-fixture.sh"],
      "modules": ["scripts/${id}-dp417-t13-fixture.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "${verify_command}",
        "behavior_contract": { "applies": false, "reason": "framework trial-run fixture；無 runtime / UI 行為變更" },
        "test_environment": { "level": "${level}", "runtime_verify_target": "${runtime_target}", "env_bootstrap_command": "${bootstrap}" },
        "verify_command": "${verify_command}",
        "references": []
      }
    }
JSON
}

# --- fixture: conformant specimen (a static implementation task) -----------------
cat >"$tmpdir/clean.json" <<JSON
{
  "source": { "type": "dp", "id": "DP-417", "base_branch": "feat/DP-417" },
  "acceptance_criteria": [ { "id": "AC1", "text": "trial-run clean specimen" } ],
  "modules": [],
  "tasks": [
$(canonical_impl_task "T1" "DP-417 T13 clean static task" "static" "N/A" "N/A" "echo PASS")
  ]
}
JSON

# --- fixture: chain drift (runtime task with PROSE env_bootstrap) ----------------
cat >"$tmpdir/chain-drift.json" <<JSON
{
  "source": { "type": "dp", "id": "DP-417", "base_branch": "feat/DP-417" },
  "acceptance_criteria": [ { "id": "AC1", "text": "trial-run chain drift" } ],
  "modules": [],
  "tasks": [
$(canonical_impl_task "T1" "DP-417 T13 runtime task prose env bootstrap" "runtime" \
    "啟動 app.example.test 三層 stack 並把 dev server 釘在 3001" \
    "$RUNTIME_PROBE_URL" "curl -fsS $RUNTIME_PROBE_URL")
  ]
}
JSON

run_harness() {
  # run_harness <label> <expected_exit> <args...>
  local label="$1" expect="$2"; shift 2
  local rc=0
  bash "$HARNESS" "$@" >"$tmpdir/$label.out" 2>"$tmpdir/$label.err" || rc=$?
  if [[ "$rc" -ne "$expect" ]]; then
    echo "--- $label stdout ---"; cat "$tmpdir/$label.out"
    echo "--- $label stderr ---"; cat "$tmpdir/$label.err"
    fail "$label: expected exit $expect, got $rc"
  fi
}

# Case 1 (AC20 / AC-N1): conformant specimen + real (green) repo => 0 bounces, exit 0.
run_harness "clean" 0 --source "$tmpdir/clean.json" --repo-root "$REPO_ROOT"
grep -q 'TRIAL RUN CLEAN' "$tmpdir/clean.out" \
  || fail "clean: expected 'TRIAL RUN CLEAN' banner"

# Case 2 (AC-NEG11 chain): un-reconciled task-shape drift => chain stage bounce, exit 2.
run_harness "chain-drift" 2 --source "$tmpdir/chain-drift.json" --repo-root "$REPO_ROOT"
grep -q 'POLARIS_SPEC_CHECK_TRIAL_RUN_BOUNCE' "$tmpdir/chain-drift.err" \
  || fail "chain-drift: expected POLARIS_SPEC_CHECK_TRIAL_RUN_BOUNCE"
grep -q 'chain(' "$tmpdir/chain-drift.out" \
  || fail "chain-drift: expected the chain stage to be reported as bounced"

# Case 3 (AC-NEG11 contract): clean specimen but repo-root with stale parity anchors
# => contract (spec<->check parity) stage bounce, exit 2. (empty repo = anchors gone)
empty_repo="$tmpdir/empty-repo"
mkdir -p "$empty_repo"
run_harness "parity-drift" 2 --source "$tmpdir/clean.json" --repo-root "$empty_repo"
grep -q 'contract(' "$tmpdir/parity-drift.out" \
  || fail "parity-drift: expected the contract stage to be reported as bounced"

# Case 4 (fail-closed): missing --source => exit 2, not a silent pass.
run_harness "missing-source" 2
grep -q 'POLARIS_SPEC_CHECK_TRIAL_RUN_BOUNCE' "$tmpdir/missing-source.err" \
  || fail "missing-source: expected fail-closed marker"

echo "spec-check-real-epic-trial-run selftest: 4 pass, 0 fail"
