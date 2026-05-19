#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="$ROOT/scripts/auto-pass-probe.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p \
  "$TMP/.polaris/evidence/task-snapshot" \
  "$TMP/.polaris/evidence/validation-fail" \
  "$TMP/.polaris/evidence/missing-v-task" \
  "$TMP/.polaris/evidence/completion-gate" \
  "$TMP/.polaris/evidence/blocked-conflict" \
  "$TMP/.polaris/evidence/unsupported-mutation" \
  "$TMP/.polaris/evidence/ac-verification" \
  "$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/refinement-inbox"

write_marker() {
  local path="$1"
  local kind="$2"
  local status="$3"
  python3 - "$path" "$kind" "$status" <<'PY'
import json
import sys
from pathlib import Path

path, kind, status = sys.argv[1:4]
payload = {
    "schema_version": 1,
    "marker_kind": kind,
    "writer": "selftest",
    "owning_skill": "selftest",
    "source_id": "DP-900",
    "work_item_id": "DP-900-T1",
    "status": status,
    "freshness": {"head_sha": "abc1234"},
}
Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

probe_field() {
  local field="$1"
  shift
  "$PROBE" --repo "$TMP" "$@" | python3 -c "import json,sys; print(json.load(sys.stdin).get('$field'))"
}

assert_field() {
  local label="$1"
  local expected="$2"
  shift 2
  local actual
  actual="$(probe_field "$@")"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $label expected $expected got $actual" >&2
    exit 1
  fi
}

write_marker "$TMP/.polaris/evidence/task-snapshot/DP-900-T1.json" task_snapshot PASS
assert_field "breakdown-pass" "engineering" next_action --stage breakdown --source-id DP-900 --work-item-id DP-900-T1

rm -f "$TMP/.polaris/evidence/task-snapshot/DP-900-T1.json"
write_marker "$TMP/.polaris/evidence/validation-fail/DP-900-T1.json" validation_fail FAIL
assert_field "breakdown-validation-fail" "blocked_by_gate_failure" terminal_status --stage breakdown --source-id DP-900 --work-item-id DP-900-T1
rm -f "$TMP/.polaris/evidence/validation-fail/DP-900-T1.json"

touch "$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/refinement-inbox/needs-refinement.md"
assert_field "breakdown-refinement-inbox" "paused_for_refinement" terminal_status --stage breakdown --source-id DP-900 --work-item-id DP-900-T1
rm -f "$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/refinement-inbox/needs-refinement.md"

assert_field "breakdown-unknown" "blocked_by_gate_failure" terminal_status --stage breakdown --source-id DP-900 --work-item-id DP-900-T1

write_marker "$TMP/.polaris/evidence/completion-gate/DP-900-T1-abc1234.json" completion_gate PASS
assert_field "engineering-pass" "verify-AC" next_action --stage engineering --source-id DP-900 --work-item-id DP-900-T1 --head-sha abc1234
rm -f "$TMP/.polaris/evidence/completion-gate/DP-900-T1-abc1234.json"

write_marker "$TMP/.polaris/evidence/blocked-conflict/DP-900-T1-abc1234.json" blocked_conflict BLOCKED
assert_field "engineering-blocked-conflict" "blocked_by_gate_failure" terminal_status --stage engineering --source-id DP-900 --work-item-id DP-900-T1 --head-sha abc1234
rm -f "$TMP/.polaris/evidence/blocked-conflict/DP-900-T1-abc1234.json"

write_marker "$TMP/.polaris/evidence/ac-verification/DP-900-V1-abc1234.json" ac_verification PASS
assert_field "verify-pass" "complete" terminal_status --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234
rm -f "$TMP/.polaris/evidence/ac-verification/DP-900-V1-abc1234.json"

write_marker "$TMP/.polaris/evidence/ac-verification/spec-issue-DP-900-V1-abc1234.json" spec_issue ROUTE_BACK
assert_field "verify-spec-issue" "paused_for_refinement" terminal_status --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234
rm -f "$TMP/.polaris/evidence/ac-verification/spec-issue-DP-900-V1-abc1234.json"

write_marker "$TMP/.polaris/evidence/ac-verification/DP-900-V1-abc1234.json" ac_verification MANUAL_REQUIRED
assert_field "verify-manual" "paused_for_user_external_write" terminal_status --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234
rm -f "$TMP/.polaris/evidence/ac-verification/DP-900-V1-abc1234.json"

assert_field "verify-unknown" "blocked_by_gate_failure" terminal_status --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234

LEDGER="$TMP/ledger.json"
python3 - "$LEDGER" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = {
    "loop_counters": {"engineering_to_breakdown": 3, "breakdown_to_refinement_inbox": 0},
    "drift_retry": {"DP-900-V1": 0},
}
path.write_text(json.dumps(payload) + "\n", encoding="utf-8")
PY
assert_field "loop-cap" "loop_cap_reached" terminal_status --stage breakdown --source-id DP-900 --work-item-id DP-900-T1 --ledger "$LEDGER"

python3 - "$LEDGER" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = {
    "loop_counters": {"engineering_to_breakdown": 0, "breakdown_to_refinement_inbox": 0},
    "drift_retry": {"DP-900-V1": 3},
}
path.write_text(json.dumps(payload) + "\n", encoding="utf-8")
PY
assert_field "drift-cap" "blocked_by_gate_failure" terminal_status --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234 --ledger "$LEDGER"

echo "PASS: auto-pass probe selftest"
