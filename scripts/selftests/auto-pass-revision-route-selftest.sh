#!/usr/bin/env bash
# Purpose: DP-313 T1 — assert the auto-pass probe/runner engineering-stage
#          review-state branch routes actionable review signals back to the
#          right owning skill, and stays parity with verify-AC when the review
#          state is non-actionable or absent.
# Inputs:  none (self-contained fixtures built under a mktemp source container);
#          exercises scripts/auto-pass-probe.sh and scripts/auto-pass-runner.sh
#          via the explicit --pr-state-file input (no network / no gh).
# Outputs: stdout PASS line on success; exit 1 on any assertion failure,
#          exit 2 on usage error.
#
# The four cases map to AC1 / AC3 / AC-NEG1:
#   (a) needs_code_changes (actionable) → next_skill=engineering (revision)   [AC1]
#   (b) planning_gap                    → next_skill=breakdown                [AC3]
#   (c) spec issue                      → next_skill=refinement (amendment)   [AC3]
#   (d) non-actionable / no review-state → parity: next_skill=verify-AC,
#       terminal_status null                                                  [AC-NEG1]
#
# Fixtures only — never hits real GitHub. The live gh read + head-rebind wiring
# is OUT OF SCOPE for T1 (sibling tasks T2/T3); T1 covers only the
# explicit-input consumption branch + parity.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$ROOT/scripts/auto-pass-runner.sh"
PROBE="$ROOT/scripts/auto-pass-probe.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SOURCE_ID="DP-900"
WORK_ITEM_ID="DP-900-T1"
HEAD_SHA="abc1234"

mkdir -p \
  "$TMP/.polaris/evidence/completion-gate" \
  "$TMP/.polaris/evidence/ac-verification" \
  "$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture"

# Minimal LOCKED source container so the resolver-backed paths stay clean.
cat >"$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/index.md" <<'MD'
---
title: "DP-900 fixture"
description: "revision route fixture"
status: LOCKED
---

fixture body
MD

cat >"$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/refinement.md" <<'MD'
---
title: "DP-900 refinement"
description: "revision route fixture"
---

## Scope
fixture
MD

cat >"$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/refinement.json" <<'JSON'
{"source": {"type": "dp", "id": "DP-900"}, "modules": [], "acceptance_criteria": []}
JSON

# DP-360 T7: the engineering-stage precondition for the review-state branch is a
# task.md `deliverable` block (deliverable.head_sha bound to the probe head +
# deliverable.verification.status == PASS), NOT a head-sha-keyed completion-gate
# marker. The review-state route only fires AFTER that PASS signal. Scaffold a
# real tasks/T1/index.md so resolve-task-md.sh can locate it.
write_task_deliverable() {
  local task_id="${WORK_ITEM_ID##*-}"
  local task_dir="$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/tasks/$task_id"
  mkdir -p "$task_dir"
  {
    echo "---"
    echo "title: \"$WORK_ITEM_ID fixture\""
    echo "description: \"revision route deliverable fixture\""
    echo "status: IN_PROGRESS"
    echo "deliverable:"
    echo "  head_sha: $HEAD_SHA"
    echo "  verification:"
    echo "    status: PASS"
    echo "---"
    echo ""
    echo "## Fixture"
  } >"$task_dir/index.md"
}

# Build an explicit review-state fixture file mirroring pr-action-classifier.sh
# output shape (readiness_state + revision_class). This is the explicit input
# the runner forwards to the probe via --pr-state-file.
write_pr_state_file() {
  local path="$1" readiness="$2" revision_class="${3:-}"
  python3 - "$path" "$readiness" "$revision_class" <<'PY'
import json, sys
from pathlib import Path
path, readiness, revision_class = sys.argv[1:4]
payload = {"pr_state": "OPEN", "readiness_state": readiness}
if revision_class:
    payload["revision_class"] = revision_class
Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

# assert_route: run probe + runner with the given args, assert the runner JSON
# matches the expected next_skill / next_action / terminal_status.
assert_route() {
  local label="$1" exp_next_skill="$2" exp_next_action="$3" exp_terminal="$4"; shift 4
  set +e
  local out rc
  out="$(bash "$RUNNER" --repo "$TMP" "$@" 2>/dev/null)"
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    echo "FAIL: $label runner rc=$rc" >&2
    echo "runner stdout: $out" >&2
    exit 1
  fi
  python3 - "$label" "$out" "$exp_next_skill" "$exp_next_action" "$exp_terminal" <<'PY'
import json, sys
label, raw, exp_skill, exp_action, exp_terminal = sys.argv[1:6]
data = json.loads(raw)
def norm(v):
    return "null" if v is None else str(v)
errs = []
if norm(data.get("next_skill")) != exp_skill:
    errs.append(f"next_skill: got {data.get('next_skill')!r} expected {exp_skill!r}")
if norm(data.get("next_action")) != exp_action:
    errs.append(f"next_action: got {data.get('next_action')!r} expected {exp_action!r}")
if norm(data.get("terminal_status")) != exp_terminal:
    errs.append(f"terminal_status: got {data.get('terminal_status')!r} expected {exp_terminal!r}")
if errs:
    print(f"FAIL: {label}", file=sys.stderr)
    for e in errs:
        print(f"  - {e}", file=sys.stderr)
    print(f"runner = {json.dumps(data, indent=2)}", file=sys.stderr)
    raise SystemExit(1)
PY
}

write_task_deliverable

# ── (a) actionable review signal → engineering revision (AC1) ────────────────
write_pr_state_file "$TMP/state-actionable.json" needs_code_changes code_drift
assert_route "actionable-needs-code-changes" engineering dispatch null \
  --stage engineering --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID" \
  --head-sha "$HEAD_SHA" --pr-state-file "$TMP/state-actionable.json"

# ── (b) planning_gap → breakdown (AC3) ───────────────────────────────────────
write_pr_state_file "$TMP/state-plangap.json" planning_gap plan_gap
assert_route "planning-gap" breakdown dispatch null \
  --stage engineering --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID" \
  --head-sha "$HEAD_SHA" --pr-state-file "$TMP/state-plangap.json"

# ── (c) spec issue → refinement amendment (AC3) ──────────────────────────────
write_pr_state_file "$TMP/state-specissue.json" planning_gap spec_issue
assert_route "spec-issue" refinement refinement_amendment null \
  --stage engineering --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID" \
  --head-sha "$HEAD_SHA" --pr-state-file "$TMP/state-specissue.json"

# ── (d1) non-actionable review-state → parity verify-AC (AC-NEG1) ────────────
for ra in review_required awaiting_re_review mergeable_ready wait_ci; do
  write_pr_state_file "$TMP/state-nonactionable.json" "$ra"
  assert_route "non-actionable-$ra" verify-AC dispatch null \
    --stage engineering --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID" \
    --head-sha "$HEAD_SHA" --pr-state-file "$TMP/state-nonactionable.json"
done

# ── (d2) no review-state input at all → parity verify-AC (AC-NEG1) ───────────
assert_route "no-review-state" verify-AC dispatch null \
  --stage engineering --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID" \
  --head-sha "$HEAD_SHA"

echo "PASS: auto-pass-revision-route selftest"
