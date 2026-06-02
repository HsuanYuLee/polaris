#!/usr/bin/env bash
# Purpose: selftest for the DP-269 breakdown blocker-marker emitter + runner/probe
#          mapping (AC3).
# Inputs:  none (uses a tmpdir as a synthetic repo).
# Outputs: PASS line on success; non-zero exit + FAIL line on contract regression.
#
# Covers (DP-269 AC3): emitting a validation_fail / missing_v_task durable marker
# makes auto-pass-probe.sh AND auto-pass-runner.sh report
# terminal_status=blocked_by_gate_failure with the marker's specific reason
# (NOT the generic "breakdown PASS marker missing" / "marker missing").

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EMITTER="$ROOT_DIR/scripts/breakdown-emit-blocker-marker.sh"
PROBE="$ROOT_DIR/scripts/auto-pass-probe.sh"
RUNNER="$ROOT_DIR/scripts/auto-pass-runner.sh"

for f in "$EMITTER" "$PROBE" "$RUNNER"; do
  [[ -f "$f" ]] || { echo "FAIL: missing script: $f" >&2; exit 1; }
done

tmpdir="$(mktemp -d -t blocker-marker.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir"

SOURCE_ID="DP-999"
WORK_ITEM_ID="DP-999-T1"

# --- Case 1 (AC3): validation_fail marker → probe blocked_by_gate_failure + reason. ---
validation_reason="task DP-999-T1 derived task.md failed validate-task-md.sh: missing Allowed Files"
bash "$EMITTER" \
  --source-id "$SOURCE_ID" \
  --work-item-id "$WORK_ITEM_ID" \
  --marker-kind validation_fail \
  --reason "$validation_reason" \
  --out "$tmpdir/.polaris/evidence/validation-fail/${WORK_ITEM_ID}.json" >/dev/null

probe_out="$(bash "$PROBE" --repo "$tmpdir" --stage breakdown --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID" 2>/dev/null)"
probe_terminal="$(printf '%s' "$probe_out" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("terminal_status"))')"
probe_reason="$(printf '%s' "$probe_out" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("reason"))')"
if [[ "$probe_terminal" != "blocked_by_gate_failure" ]]; then
  echo "FAIL [case 1 / AC3]: probe terminal_status='$probe_terminal' (expected blocked_by_gate_failure)" >&2
  printf '%s\n' "$probe_out" >&2
  exit 1
fi
if [[ "$probe_reason" != "$validation_reason" ]]; then
  echo "FAIL [case 1 / AC3]: probe reason did not surface the marker's specific cause" >&2
  echo "  got:      $probe_reason" >&2
  echo "  expected: $validation_reason" >&2
  exit 1
fi
if printf '%s' "$probe_reason" | grep -qiE 'marker missing|PASS marker missing'; then
  echo "FAIL [case 1 / AC3]: probe reason is the generic 'marker missing' message" >&2
  exit 1
fi

# --- Case 2 (AC3): runner forwards the same specific reason. ---
runner_out="$(bash "$RUNNER" --repo "$tmpdir" --stage breakdown --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID" 2>/dev/null)"
runner_terminal="$(printf '%s' "$runner_out" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("terminal_status"))')"
runner_reason="$(printf '%s' "$runner_out" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("reason"))')"
if [[ "$runner_terminal" != "blocked_by_gate_failure" ]]; then
  echo "FAIL [case 2 / AC3]: runner terminal_status='$runner_terminal' (expected blocked_by_gate_failure)" >&2
  printf '%s\n' "$runner_out" >&2
  exit 1
fi
if [[ "$runner_reason" != "$validation_reason" ]]; then
  echo "FAIL [case 2 / AC3]: runner reason did not forward the marker's specific cause" >&2
  echo "  got:      $runner_reason" >&2
  echo "  expected: $validation_reason" >&2
  exit 1
fi

# --- Case 3 (AC3): missing_v_task marker → blocked_by_gate_failure + specific reason. ---
mvt_tmp="$(mktemp -d -t blocker-marker-mvt.XXXXXX)"
mvt_reason="source DP-999 task set has no V verification task; framework DP-backed source requires >=1 V*.md"
bash "$EMITTER" \
  --source-id "$SOURCE_ID" \
  --work-item-id "$WORK_ITEM_ID" \
  --marker-kind missing_v_task \
  --reason "$mvt_reason" \
  --out "$mvt_tmp/.polaris/evidence/missing-v-task/${WORK_ITEM_ID}.json" >/dev/null
mvt_probe="$(bash "$PROBE" --repo "$mvt_tmp" --stage breakdown --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID" 2>/dev/null)"
mvt_terminal="$(printf '%s' "$mvt_probe" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("terminal_status"))')"
mvt_reason_got="$(printf '%s' "$mvt_probe" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("reason"))')"
rm -rf "$mvt_tmp"
if [[ "$mvt_terminal" != "blocked_by_gate_failure" ]]; then
  echo "FAIL [case 3 / AC3]: missing_v_task probe terminal_status='$mvt_terminal'" >&2
  printf '%s\n' "$mvt_probe" >&2
  exit 1
fi
if [[ "$mvt_reason_got" != "$mvt_reason" ]]; then
  echo "FAIL [case 3 / AC3]: missing_v_task reason did not surface the marker cause" >&2
  echo "  got:      $mvt_reason_got" >&2
  echo "  expected: $mvt_reason" >&2
  exit 1
fi

# --- Case 4: emitter rejects an invalid marker kind. ---
if bash "$EMITTER" --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID" \
     --marker-kind not_a_kind --reason "x" >/dev/null 2>"$tmpdir/badkind.stderr"; then
  echo "FAIL [case 4]: emitter accepted an invalid --marker-kind" >&2
  exit 1
fi

echo "PASS: breakdown-emit-blocker-marker selftest"
