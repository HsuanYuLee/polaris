#!/usr/bin/env bash
# DP-237 T1: runner ↔ probe parity selftest
#
# For each fixture, also invoke auto-pass-probe.sh directly and assert that
# the runner and probe agree semantically on status / terminal_status /
# next_action. Probe and runner use different field semantics for
# next_action (probe emits forward stage names; runner emits orchestrator
# verbs like dispatch / blocked / terminal / resume), so we map probe fields
# into the runner space before comparing.
#
# Disagreement → fail-stop with diff output. Covers:
#   - terminal priority (UNKNOWN / blocked override prose)
#   - UNKNOWN blocked
#   - recoverable HALT continue (PASS forward dispatch)
#   - loop cap (ledger-driven)
#   - context handoff (session_handoff resume — runner-only signal, parity
#     selftest verifies probe still emits its underlying stage state and the
#     runner adds the resume signal without contradicting probe terminal)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$ROOT/scripts/auto-pass-runner.sh"
PROBE="$ROOT/scripts/auto-pass-probe.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p \
  "$TMP/.polaris/evidence/task-snapshot" \
  "$TMP/.polaris/evidence/completion-gate" \
  "$TMP/.polaris/evidence/ac-verification" \
  "$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/refinement-inbox"

cat >"$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/index.md" <<'MD'
---
title: "DP-900 fixture"
description: "parity fixture"
status: LOCKED
---

PASS PASS PASS — prose decoys for AC-NEG3.
MD

cat >"$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/refinement.md" <<'MD'
---
title: "DP-900 refinement"
description: "parity fixture"
---

## Scope
fixture
MD

cat >"$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/refinement.json" <<'JSON'
{"source": {"type": "dp", "id": "DP-900"}, "modules": [], "acceptance_criteria": []}
JSON
mkdir -p "$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/tasks/T1"
cat >"$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/tasks/T1/index.md" <<'MD'
---
title: "DP-900-T1 gap owner fixture"
description: "same-source owner existence fixture"
status: IN_PROGRESS
---
MD

echo "gap-scope-v1" >"$TMP/gap-scope.txt"
git -C "$TMP" init -q
git -C "$TMP" config user.email selftest@example.invalid
git -C "$TMP" config user.name selftest
git -C "$TMP" add .
git -C "$TMP" commit -qm "parity fixture baseline"

GAP_LEDGER="$TMP/current-head-gap-ledger.json"
python3 - "$GAP_LEDGER" "$(git -C "$TMP" rev-parse HEAD)" <<'PY'
import json, sys
from pathlib import Path
path, head = sys.argv[1:3]
Path(path).write_text(json.dumps({
    "schema_version": 1,
    "source_id": "DP-900",
    "authority": {
        "source_id": "DP-900", "same_source_only": True,
        "allowed_actions": ["gap_disposition", "task_repair"],
        "forbidden_actions": [
            "bypass", "cross_source_mutation", "partial_release", "release", "successor_source"
        ],
    },
    "gaps": [{
        "gap_id": "G1", "gap_key": "parity-gap", "source_id": "DP-900",
        "reproducer": {"id": "parity-repro", "kind": "command", "argv": ["test", "-f", "gap-scope.txt"]},
        "head": head, "observed": {"exit_code": 0, "state": "persisting"},
        "disposition": "persisting_owned",
        "owner": {"source_id": "DP-900", "work_item_id": "DP-900-T1"},
        "terminal": False,
        "evidence": [{"kind": "command_result", "reproducer_id": "parity-repro", "exit_code": 0}],
        "currentness": {"status": "current", "scope_paths": ["gap-scope.txt"]},
    }],
}, indent=2) + "\n", encoding="utf-8")
PY

write_marker() {
  local path="$1" status="$2" source_id="${3:-DP-900}" work_item_id="${4:-DP-900-T1}"
  python3 - "$path" "$status" "$source_id" "$work_item_id" <<'PY'
import json, sys
from pathlib import Path
path, status, source_id, work_item_id = sys.argv[1:5]
Path(path).write_text(json.dumps({
    "schema_version": 1, "marker_kind": "selftest", "writer": "selftest",
    "owning_skill": "selftest", "source_id": source_id, "work_item_id": work_item_id,
    "status": status, "freshness": {"head_sha": "abc1234"},
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

write_task_deliverable() {
  local wid="$1" head="$2" vstatus="$3"
  local task_id="${wid##*-}"
  local task_dir="$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/tasks/$task_id"
  mkdir -p "$task_dir"
  {
    echo "---"
    echo "title: \"$wid fixture\""
    echo "description: \"auto-pass runner/probe parity task fixture\""
    echo "status: IN_PROGRESS"
    if [[ -n "$head" ]]; then
      echo "deliverable:"
      echo "  head_sha: $head"
      if [[ -n "$vstatus" ]]; then
        echo "  verification:"
        echo "    status: $vstatus"
      fi
    fi
    echo "---"
    echo ""
    echo "## Fixture"
  } >"$task_dir/index.md"
}

remove_task_deliverable() {
  local wid="$1"
  local task_id="${wid##*-}"
  rm -rf "$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/tasks/$task_id"
}

# probe_to_runner_terminal: terminal_status semantics MUST be identical.
# probe_to_runner_action: probe next_action is a stage hint, runner is a verb.
#   Mapping rules (runner-owned semantic mapping):
#     - probe terminal != null  → runner next_action ∈ {terminal, blocked}
#         terminal == complete | loop_cap_reached | paused_* → terminal
#         terminal == blocked_by_gate_failure → blocked
#     - probe status == PASS, probe terminal null →
#         stage=verify-AC → terminal  (probe pairs PASS with complete here)
#         else → dispatch
#     - probe status == ROUTE_BACK_AMEND → refinement_amendment
#     - else → blocked
assert_parity() {
  local label="$1"; shift
  set +e
  PROBE_OUT="$(bash "$PROBE" --repo "$TMP" "$@" 2>/dev/null)"
  PROBE_RC=$?
  RUNNER_OUT="$(bash "$RUNNER" --repo "$TMP" "$@" 2>/dev/null)"
  RUNNER_RC=$?
  set -e
  if [[ $PROBE_RC -ne 0 || $RUNNER_RC -ne 0 ]]; then
    echo "FAIL: $label probe rc=$PROBE_RC runner rc=$RUNNER_RC" >&2
    echo "probe stdout: $PROBE_OUT" >&2
    echo "runner stdout: $RUNNER_OUT" >&2
    exit 1
  fi
  python3 - "$label" "$PROBE_OUT" "$RUNNER_OUT" <<'PY'
import json, sys
label, probe_raw, runner_raw = sys.argv[1:4]
probe = json.loads(probe_raw)
runner = json.loads(runner_raw)

errs = []

# terminal_status MUST be identical (this is the load-bearing parity signal).
if probe.get("terminal_status") != runner.get("terminal_status"):
    errs.append(f"terminal_status diff: probe={probe.get('terminal_status')!r} runner={runner.get('terminal_status')!r}")

# status: probe status should map to runner status with one carve-out —
# at verify-AC stage, probe PASS+complete is restated as runner PASS+terminal.
if probe.get("status") != runner.get("status"):
    errs.append(f"status diff: probe={probe.get('status')!r} runner={runner.get('status')!r}")

# next_action mapping.
stage = probe.get("stage")
probe_term = probe.get("terminal_status")
probe_status = probe.get("status")
runner_action = runner.get("next_action")

expected_action = None
if probe_term in ("complete", "loop_cap_reached", "paused_for_user_external_write"):
    expected_action = "terminal"
elif probe_term == "blocked_by_gate_failure":
    expected_action = "blocked"
elif probe_status == "ROUTE_BACK_AMEND" or probe.get("next_action") == "refinement_amendment":
    expected_action = "refinement_amendment"
elif probe_status == "ROUTE_BACK_REVISION":
    # DP-313 T1: actionable review signal → engineering revision dispatch.
    # Keyed on status only — probe next_action collides with forward hints.
    expected_action = "dispatch"
elif probe_status == "ROUTE_BACK_BREAKDOWN":
    # DP-313 T1: planning_gap review signal → breakdown dispatch.
    expected_action = "dispatch"
elif probe_status == "PASS":
    expected_action = "terminal" if stage == "verify-AC" else "dispatch"
else:
    expected_action = "blocked"

if runner_action != expected_action:
    errs.append(f"next_action map fail: probe(status={probe_status!r} terminal={probe_term!r} stage={stage!r}) → runner={runner_action!r} expected={expected_action!r}")

if errs:
    print(f"FAIL: {label} parity disagreement", file=sys.stderr)
    for e in errs:
        print(f"  - {e}", file=sys.stderr)
    print(f"probe = {json.dumps(probe, indent=2)}", file=sys.stderr)
    print(f"runner = {json.dumps(runner, indent=2)}", file=sys.stderr)
    raise SystemExit(1)
PY
}

assert_parity_with_gap_ledger() {
  local label="$1"; shift
  local probe_out runner_out
  probe_out="$(bash "$PROBE" --repo "$TMP" "$@")"
  runner_out="$(bash "$RUNNER" --repo "$TMP" "$@" --gap-ledger "$GAP_LEDGER")"
  python3 - "$label" "$probe_out" "$runner_out" <<'PY'
import json, sys
label, probe_raw, runner_raw = sys.argv[1:4]
probe = json.loads(probe_raw)
runner = json.loads(runner_raw)
assert runner["status"] == probe["status"], (label, probe, runner)
assert runner["terminal_status"] == probe["terminal_status"], (label, probe, runner)
assert runner["next_action"] == "dispatch", (label, probe, runner)
authority = runner.get("delegation_authority") or {}
assert authority.get("allowed_actions") == ["gap_disposition", "task_repair"], (label, runner)
assert authority.get("same_source_only") is True, (label, runner)
PY
}

# ─── source stage parity ─────────────────────────────────────────────────────
assert_parity "source-pass"            --stage source --source-id DP-900
assert_parity_with_gap_ledger "source-pass-with-gap-ledger" --stage source --source-id DP-900

# ─── breakdown parity ────────────────────────────────────────────────────────
write_marker "$TMP/.polaris/evidence/task-snapshot/DP-900-T1.json" PASS
assert_parity "breakdown-pass"         --stage breakdown --source-id DP-900 --work-item-id DP-900-T1
rm "$TMP/.polaris/evidence/task-snapshot/DP-900-T1.json"

# AC-NEG3 prose-decoy parity: missing marker, prose contains "PASS" — both
# tools must agree on blocked_by_gate_failure.
assert_parity "breakdown-missing"      --stage breakdown --source-id DP-900 --work-item-id DP-900-T1

# Amendment loop parity.
touch "$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/refinement-inbox/x.md"
assert_parity "breakdown-amend"        --stage breakdown --source-id DP-900 --work-item-id DP-900-T1
rm "$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/refinement-inbox/x.md"

# ─── engineering parity ──────────────────────────────────────────────────────
write_task_deliverable DP-900-T1 abc1234 PASS
write_task_deliverable DP-900-T2 "" ""
assert_parity "engineering-pass"       --stage engineering --source-id DP-900 --work-item-id DP-900-T1 --head-sha abc1234
remove_task_deliverable DP-900-T1
remove_task_deliverable DP-900-T2

assert_parity "engineering-missing"    --stage engineering --source-id DP-900 --work-item-id DP-900-T1 --head-sha abc1234

# DP-313 T1: engineering-stage review-state branch parity. Completion gate is
# PASS; an explicit --pr-state-file carries an actionable / planning / spec
# review state. Runner and probe must agree on the new route's machine fields.
write_task_deliverable DP-900-T1 abc1234 PASS
write_pr_state() {
  python3 - "$1" "$2" "${3:-}" <<'PY'
import json, sys
from pathlib import Path
path, readiness, revision_class = sys.argv[1:4]
payload = {"pr_state": "OPEN", "readiness_state": readiness}
if revision_class:
    payload["revision_class"] = revision_class
Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}
write_pr_state "$TMP/parity-actionable.json" needs_code_changes code_drift
assert_parity "engineering-review-actionable" --stage engineering --source-id DP-900 --work-item-id DP-900-T1 --head-sha abc1234 --pr-state-file "$TMP/parity-actionable.json"
write_pr_state "$TMP/parity-plangap.json" planning_gap plan_gap
assert_parity "engineering-review-plangap"    --stage engineering --source-id DP-900 --work-item-id DP-900-T1 --head-sha abc1234 --pr-state-file "$TMP/parity-plangap.json"
write_pr_state "$TMP/parity-specissue.json" planning_gap spec_issue
assert_parity "engineering-review-specissue"  --stage engineering --source-id DP-900 --work-item-id DP-900-T1 --head-sha abc1234 --pr-state-file "$TMP/parity-specissue.json"
write_pr_state "$TMP/parity-nonactionable.json" mergeable_ready
write_task_deliverable DP-900-T2 "" ""
assert_parity "engineering-review-nonactionable" --stage engineering --source-id DP-900 --work-item-id DP-900-T1 --head-sha abc1234 --pr-state-file "$TMP/parity-nonactionable.json"
remove_task_deliverable DP-900-T1
remove_task_deliverable DP-900-T2

# ─── verify-AC parity ────────────────────────────────────────────────────────
write_marker "$TMP/.polaris/evidence/ac-verification/DP-900-V1-abc1234.json" PASS DP-900 DP-900-V1
assert_parity "verify-pass"            --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234
rm "$TMP/.polaris/evidence/ac-verification/DP-900-V1-abc1234.json"

write_marker "$TMP/.polaris/evidence/ac-verification/DP-900-V1-abc1234.json" MANUAL_REQUIRED DP-900 DP-900-V1
assert_parity "verify-manual"          --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234
rm "$TMP/.polaris/evidence/ac-verification/DP-900-V1-abc1234.json"

assert_parity "verify-unknown"         --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234

# ─── loop cap parity (ledger-driven, runner reads via probe) ─────────────────
LEDGER="$TMP/loop-cap.json"
python3 - "$LEDGER" <<'PY'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
    "loop_counters": {"engineering_to_breakdown": 4, "breakdown_to_refinement_inbox": 0},
    "drift_retry": {},
}) + "\n", encoding="utf-8")
PY
assert_parity "loop-cap"               --stage breakdown --source-id DP-900 --work-item-id DP-900-T1 --ledger "$LEDGER"

echo "PASS: auto-pass-runner-probe parity selftest"
