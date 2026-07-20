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

# Keep the source non-terminal while T1 head binding is exercised. Without a
# pending sibling, the current full-source completion invariant legitimately
# archives the fixture after the first PASS and destroys the later rebind case.
mkdir -p "$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/tasks/T2"
cat >"$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/tasks/T2/index.md" <<'MD'
---
title: "DP-900-T2 pending sibling"
description: "keeps the source active during T1 head-rebind assertions"
status: IN_PROGRESS
---

## Fixture
MD

# DP-360 T7: head-rebind is now expressed via the task.md `deliverable` block
# (deliverable.head_sha bound to the probe head + deliverable.verification.status),
# NOT a head-sha-keyed completion-gate / ac-verification marker filename. The
# engineering stage's head_bound check IS the rebind: an old delivered head does
# not satisfy a probe keyed on the new head, and vice versa. write_task_deliverable
# scaffolds a real tasks/T1/index.md so resolve-task-md.sh can locate it.
#   $1 = delivered head_sha (empty string omits the deliverable block entirely)
#   $2 = verification status (empty string omits the verification sub-block)
write_task_deliverable() {
  local head="$1" vstatus="$2"
  local task_id="${WORK_ITEM_ID##*-}"
  local task_dir="$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/tasks/$task_id"
  mkdir -p "$task_dir"
  {
    echo "---"
    echo "title: \"$WORK_ITEM_ID fixture\""
    echo "description: \"head rebind deliverable fixture\""
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

# ── AC2 head rebind (DP-360 T7: engineering-stage deliverable head binding) ───
# After a revision the delivered head moves OLD → NEW. The task.md deliverable
# block records exactly one delivered head. The engineering probe's head_bound
# check is the rebind: a probe keyed on a head other than the recorded
# deliverable.head_sha must NOT pass.

# (a) deliverable bound to the OLD head; probe keyed on the NEW head must NOT
#     inherit the stale OLD-head delivery → blocked (head not bound).
write_task_deliverable "$OLD_HEAD" PASS
run_runner --stage engineering --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID" --head-sha "$NEW_HEAD"
assert_runner_json "ac2-new-head-no-stale-delivery" UNKNOWN blocked_by_gate_failure blocked

# (b) the same deliverable (bound to the OLD head) keyed on the OLD head still
#     resolves → PASS. Proves the deliverable head binding is head-scoped, not
#     head-agnostic (the rebind is real).
run_runner --stage engineering --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID" --head-sha "$OLD_HEAD"
assert_runner_json "ac2-old-head-resolves-old-delivery" PASS null dispatch

# (c) after the revision the deliverable block rebinds to the NEW head; the NEW
#     head now passes (and the OLD head no longer does — covered by symmetry).
write_task_deliverable "$NEW_HEAD" PASS
run_runner --stage engineering --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID" --head-sha "$NEW_HEAD"
assert_runner_json "ac2-new-head-passes-after-rebind" PASS null dispatch

# ── AC-NEG2 gh fail-closed ───────────────────────────────────────────────────
# Engineering stage on the NEW head with a PASS deliverable block. When the
# orchestrator requested a review-state read (--pr-state-file) but the state is
# unavailable, the runner must stay blocked and re-surface POLARIS_TOOL_MISSING.
# (deliverable already rebound to NEW_HEAD by case (c) above.)
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
