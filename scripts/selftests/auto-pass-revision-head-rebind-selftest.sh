#!/usr/bin/env bash
# Purpose: DP-313 T3 — assert the auto-pass runner/probe rebind to the NEW head
#          after a revision, and fail closed when a review-state read was
#          requested but the PR state is unavailable (gh missing / unreadable).
# Inputs:  none (self-contained fixtures under a mktemp source container);
#          exercises scripts/auto-pass-runner.sh and scripts/auto-pass-probe.sh
#          via head-scoped evidence markers and the explicit --pr-state-file
#          input (no network / no gh).
# Outputs: stdout PASS line on success; exit 1 on any assertion failure,
#          exit 2 on usage error.
#
# Cases map to AC2 / AC-NEG2:
#   AC2 (head rebind) — both old-head and new-head completion-gate markers exist;
#     the old head also has an ac-verification PASS marker, the new head does not
#     (yet). The verify-AC stage keyed on the NEW head must NOT treat the stale
#     old-head ac-verification PASS as current → blocked_by_gate_failure, while
#     the same stage keyed on the OLD head still resolves the old marker (proving
#     markers are head-scoped). After the revision verification reruns and writes
#     the NEW-head ac-verification PASS marker, the NEW head completes.
#   AC-NEG2 (gh fail-closed) — at the engineering stage with a PASS completion
#     gate, supplying --pr-state-file that points at a missing / tool_missing /
#     contentless review-state file fails closed: the probe exits 3 with
#     POLARIS_TOOL_MISSING on stderr and the runner stays
#     blocked_by_gate_failure (never silently complete). Omitting --pr-state-file
#     entirely stays at parity (continue to verify-AC).
#
# Fixtures only — never hits real GitHub. Head-scoped markers + explicit
# review-state input are the whole surface under test.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$ROOT/scripts/auto-pass-runner.sh"
PROBE="$ROOT/scripts/auto-pass-probe.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SOURCE_ID="DP-900"
WORK_ITEM_ID="DP-900-T1"
OLD_HEAD="oldhead1"
NEW_HEAD="newhead2"

mkdir -p \
  "$TMP/.polaris/evidence/completion-gate" \
  "$TMP/.polaris/evidence/ac-verification" \
  "$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture"

# Minimal LOCKED source container so the resolver-backed paths stay clean.
cat >"$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/index.md" <<'MD'
---
title: "DP-900 fixture"
description: "head rebind fixture"
status: LOCKED
---

fixture body
MD

cat >"$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/refinement.md" <<'MD'
---
title: "DP-900 refinement"
description: "head rebind fixture"
---

## Scope
fixture
MD

cat >"$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/refinement.json" <<'JSON'
{"source": {"type": "dp", "id": "DP-900"}, "modules": [], "acceptance_criteria": []}
JSON

# write_marker: emit a head-scoped evidence marker under a given evidence subdir.
write_marker() {
  local subdir="$1" head="$2" status="$3"
  python3 - "$TMP/.polaris/evidence/$subdir/${WORK_ITEM_ID}-${head}.json" "$status" "$head" <<'PY'
import json, sys
from pathlib import Path
path, status, head = sys.argv[1:4]
Path(path).write_text(json.dumps({
    "schema_version": 1, "marker_kind": "selftest", "writer": "selftest",
    "owning_skill": "selftest", "source_id": "DP-900", "work_item_id": "DP-900-T1",
    "status": status, "freshness": {"head_sha": head},
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

# run_runner: invoke the runner, capture stdout (JSON) and stderr separately.
RUNNER_OUT=""
RUNNER_ERR=""
RUNNER_RC=0
run_runner() {
  local errfile; errfile="$(mktemp)"
  set +e
  RUNNER_OUT="$(bash "$RUNNER" --repo "$TMP" "$@" 2>"$errfile")"
  RUNNER_RC=$?
  set -e
  RUNNER_ERR="$(cat "$errfile")"
  rm -f "$errfile"
}

# assert_runner_json: assert the runner JSON status / terminal / next_action.
assert_runner_json() {
  local label="$1" exp_status="$2" exp_terminal="$3" exp_next_action="$4"
  python3 - "$label" "$RUNNER_OUT" "$exp_status" "$exp_terminal" "$exp_next_action" <<'PY'
import json, sys
label, raw, exp_status, exp_terminal, exp_action = sys.argv[1:6]
try:
    data = json.loads(raw)
except Exception as exc:
    print(f"FAIL: {label}: runner stdout not JSON: {exc}", file=sys.stderr)
    print(f"stdout = {raw!r}", file=sys.stderr)
    raise SystemExit(1)
def norm(v):
    return "null" if v is None else str(v)
errs = []
if norm(data.get("status")) != exp_status:
    errs.append(f"status: got {data.get('status')!r} expected {exp_status!r}")
if norm(data.get("terminal_status")) != exp_terminal:
    errs.append(f"terminal_status: got {data.get('terminal_status')!r} expected {exp_terminal!r}")
if norm(data.get("next_action")) != exp_action:
    errs.append(f"next_action: got {data.get('next_action')!r} expected {exp_action!r}")
if errs:
    print(f"FAIL: {label}", file=sys.stderr)
    for e in errs:
        print(f"  - {e}", file=sys.stderr)
    print(f"runner = {json.dumps(data, indent=2)}", file=sys.stderr)
    raise SystemExit(1)
PY
}

# ── AC2 head rebind ──────────────────────────────────────────────────────────
# Both heads carry a PASS completion gate (the revision produced a new head, the
# old head's engineering evidence is still on disk). Only the OLD head carries an
# ac-verification PASS marker.
write_marker completion-gate "$OLD_HEAD" PASS
write_marker completion-gate "$NEW_HEAD" PASS
write_marker ac-verification "$OLD_HEAD" PASS

# (a) verify-AC keyed on the NEW head must NOT inherit the OLD head's stale
#     ac-verification PASS — it sees no current marker and stays blocked.
run_runner --stage verify-AC --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID" --head-sha "$NEW_HEAD"
assert_runner_json "ac2-new-head-no-stale-verification" UNKNOWN blocked_by_gate_failure blocked

# (b) verify-AC keyed on the OLD head still resolves the old marker → complete.
#     Proves markers are head-scoped, not head-agnostic (the rebind is real).
run_runner --stage verify-AC --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID" --head-sha "$OLD_HEAD"
assert_runner_json "ac2-old-head-resolves-old-marker" PASS complete terminal

# (c) after the revision verification reruns on the NEW head and writes the
#     NEW-head ac-verification PASS marker, the NEW head completes.
write_marker ac-verification "$NEW_HEAD" PASS
run_runner --stage verify-AC --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID" --head-sha "$NEW_HEAD"
assert_runner_json "ac2-new-head-completes-after-rebind" PASS complete terminal

# ── AC-NEG2 gh fail-closed ───────────────────────────────────────────────────
# Engineering stage on the NEW head with a PASS completion gate. When the
# orchestrator requested a review-state read (--pr-state-file) but the state is
# unavailable, the runner must stay blocked and re-surface POLARIS_TOOL_MISSING.
assert_tool_missing() {
  local label="$1"
  if [[ "$RUNNER_ERR" != *"POLARIS_TOOL_MISSING"* ]]; then
    echo "FAIL: $label: runner stderr missing POLARIS_TOOL_MISSING" >&2
    echo "stderr = $RUNNER_ERR" >&2
    exit 1
  fi
}

# (d1) --pr-state-file points at a missing file → fail closed.
run_runner --stage engineering --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID" \
  --head-sha "$NEW_HEAD" --pr-state-file "$TMP/does-not-exist.json"
assert_runner_json "acneg2-missing-state-file" UNKNOWN blocked_by_gate_failure blocked
assert_tool_missing "acneg2-missing-state-file"

# (d2) --pr-state-file with an explicit tool_missing sentinel → fail closed.
printf '{"pr_state":"UNKNOWN","tool_missing":true}\n' >"$TMP/tool-missing.json"
run_runner --stage engineering --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID" \
  --head-sha "$NEW_HEAD" --pr-state-file "$TMP/tool-missing.json"
assert_runner_json "acneg2-tool-missing-sentinel" UNKNOWN blocked_by_gate_failure blocked
assert_tool_missing "acneg2-tool-missing-sentinel"

# (d3) --pr-state-file present but carrying no usable readiness/revision class
#      (e.g. pr_state UNKNOWN, no classification) → fail closed.
printf '{"pr_state":"UNKNOWN"}\n' >"$TMP/contentless.json"
run_runner --stage engineering --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID" \
  --head-sha "$NEW_HEAD" --pr-state-file "$TMP/contentless.json"
assert_runner_json "acneg2-contentless-state-file" UNKNOWN blocked_by_gate_failure blocked
assert_tool_missing "acneg2-contentless-state-file"

# (d4) NO --pr-state-file at all → parity: no review-state requested, continue to
#      verify-AC (must NOT fail closed; POLARIS_TOOL_MISSING must be absent).
run_runner --stage engineering --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID" \
  --head-sha "$NEW_HEAD"
assert_runner_json "acneg2-no-state-file-parity" PASS null dispatch
if [[ "$RUNNER_ERR" == *"POLARIS_TOOL_MISSING"* ]]; then
  echo "FAIL: acneg2-no-state-file-parity: parity case wrongly failed closed" >&2
  echo "stderr = $RUNNER_ERR" >&2
  exit 1
fi

echo "PASS: auto-pass-revision-head-rebind selftest"
