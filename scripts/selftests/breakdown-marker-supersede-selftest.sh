#!/usr/bin/env bash
# Purpose: selftest for DP-325 T3 (B) — breakdown-emit-task-snapshot.sh, when it
#          successfully emits a PASS task_snapshot, supersedes the same
#          work-item's stale validation-fail / missing-v-task blocker markers so
#          auto-pass-probe.sh (stage breakdown) lets the re-packaged work item
#          through instead of being pinned on a stale blocker.
# Inputs:  none (builds a synthetic .polaris/evidence/ tree + source/ledger in tmpdir).
# Outputs: PASS line on success; non-zero exit + FAIL line on contract regression.
#
# Covers (DP-325):
#   AC7     : old validation-fail / missing-v-task blocker marker + a new PASS
#             task_snapshot → blocker markers superseded → probe stage breakdown
#             returns PASS (next_action engineering), not blocked_by_gate_failure.
#   AC-NF1  : the supersede path is deterministic; without it the probe fails
#             closed on the stale blocker (the pre-fix behaviour the test pins).
#   AC-NEG3 : ships a deterministic script + this selftest (no prose-only fix).
#   AC7-attack (adversarial pass): supersede is scoped to the SAME work-item only
#             — a different work-item's blocker marker MUST survive the emit.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EMITTER="$ROOT/scripts/breakdown-emit-task-snapshot.sh"
BLOCKER_EMITTER="$ROOT/scripts/breakdown-emit-blocker-marker.sh"
PROBE="$ROOT/scripts/auto-pass-probe.sh"

for f in "$EMITTER" "$BLOCKER_EMITTER" "$PROBE"; do
  [[ -f "$f" ]] || { echo "FAIL: missing script: $f" >&2; exit 1; }
done

TMP="$(mktemp -d -t dp325-marker-supersede.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

SOURCE_ID="DP-998"
WORK_ITEM_ID="DP-998-T1"
OTHER_WORK_ITEM_ID="DP-998-T2"

# --- Synthetic source container (LOCKED) so auto-pass-probe can resolve it. ---
SOURCE="$TMP/docs-manager/src/content/docs/specs/design-plans/DP-998-fixture"
mkdir -p "$SOURCE"

cat >"$SOURCE/index.md" <<'MD'
---
title: "DP-998: marker supersede fixture"
description: "DP-325 T3 selftest fixture"
status: LOCKED
locked_at: 2026-06-15
---

# DP-998 fixture
MD

cat >"$SOURCE/refinement.md" <<'MD'
---
title: "DP-998 Refinement"
description: "DP-325 T3 fixture refinement"
---

## Scope

此 fixture 用於驗證 task_snapshot 成功 emit 時 supersede 舊 blocker marker。
MD

python3 - "$SOURCE/refinement.json" "$SOURCE" "$SOURCE_ID" <<'PY'
import json
import sys
from pathlib import Path

path, source, source_id = sys.argv[1:4]
source = Path(source)
payload = {
    "version": "1",
    "created_at": "2026-06-15T10:00:00+08:00",
    "source": {
        "type": "dp",
        "id": source_id,
        "container": str(source),
        "plan_path": str(source / "index.md"),
        "jira_key": None,
    },
    "modules": [{"path": ".claude/skills/auto-pass/SKILL.md", "action": "modify"}],
    "acceptance_criteria": [
        {"id": "AC1", "text": "fixture", "category": "functional", "negative": False,
         "verification": {"method": "unit_test", "detail": "fixture"}}
    ],
    "dependencies": [],
    "edge_cases": [],
    "predecessor_audit": [],
}
Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

# --- A repo root with a synthetic .polaris/evidence/ tree the probe will read. ---
# The probe resolves the source via spec-source-resolver against the repo's own
# docs-manager specs root, so the synthetic source lives under REPO.
REPO="$TMP"
EVIDENCE="$REPO/.polaris/evidence"
TASK_SNAPSHOT="$EVIDENCE/task-snapshot/${WORK_ITEM_ID}.json"
VALIDATION_FAIL="$EVIDENCE/validation-fail/${WORK_ITEM_ID}.json"
MISSING_V="$EVIDENCE/missing-v-task/${WORK_ITEM_ID}.json"
OTHER_VALIDATION_FAIL="$EVIDENCE/validation-fail/${OTHER_WORK_ITEM_ID}.json"

TASK_MD="$TMP/task.md"
cat >"$TASK_MD" <<'MD'
---
title: "DP-998 T1"
status: IN_PROGRESS
---

# T1 fixture task
MD

# --- Stage stale blocker markers for BOTH work items (an earlier failed
#     breakdown run wrote them). ---
bash "$BLOCKER_EMITTER" \
  --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID" \
  --marker-kind validation_fail --reason "earlier validation failure" \
  --out "$VALIDATION_FAIL" >/dev/null
bash "$BLOCKER_EMITTER" \
  --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID" \
  --marker-kind missing_v_task --reason "earlier missing V task" \
  --out "$MISSING_V" >/dev/null
bash "$BLOCKER_EMITTER" \
  --source-id "$SOURCE_ID" --work-item-id "$OTHER_WORK_ITEM_ID" \
  --marker-kind validation_fail --reason "sibling still blocked" \
  --out "$OTHER_VALIDATION_FAIL" >/dev/null

for f in "$VALIDATION_FAIL" "$MISSING_V" "$OTHER_VALIDATION_FAIL"; do
  [[ -f "$f" ]] || { echo "FAIL [setup]: blocker marker not written: $f" >&2; exit 1; }
done

# --- Sanity: BEFORE the supersede emit, the probe is pinned on the stale
#     validation-fail blocker (this is the pre-fix bug). ---
set +e
before_json="$(bash "$PROBE" --stage breakdown \
  --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID" --repo "$REPO" 2>"$TMP/before.err")"
before_exit=$?
set -e
if [[ "$before_exit" -ne 0 ]]; then
  echo "FAIL [pre-emit probe]: probe exited $before_exit (expected 0 emit)" >&2
  cat "$TMP/before.err" >&2
  exit 1
fi
before_terminal="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1]).get("terminal_status") or "")' "$before_json")"
if [[ "$before_terminal" != "blocked_by_gate_failure" ]]; then
  echo "FAIL [pre-emit probe]: expected stale blocker to pin probe at blocked_by_gate_failure, got terminal=$before_terminal" >&2
  echo "$before_json" >&2
  exit 1
fi

# --- ACT: emit a PASS task_snapshot for WORK_ITEM_ID. This must supersede the
#     same work-item's validation-fail + missing-v-task blocker markers. ---
bash "$EMITTER" \
  --source-id "$SOURCE_ID" \
  --work-item-id "$WORK_ITEM_ID" \
  --task-md "$TASK_MD" \
  --status PASS \
  --out "$TASK_SNAPSHOT" >/dev/null

# --- AC7: the same work-item's blocker markers are gone. ---
if [[ -f "$VALIDATION_FAIL" ]]; then
  echo "FAIL [AC7]: validation-fail blocker for $WORK_ITEM_ID survived a PASS task_snapshot emit" >&2
  exit 1
fi
if [[ -f "$MISSING_V" ]]; then
  echo "FAIL [AC7]: missing-v-task blocker for $WORK_ITEM_ID survived a PASS task_snapshot emit" >&2
  exit 1
fi

# --- AC7-attack: a DIFFERENT work-item's blocker must still be present. ---
if [[ ! -f "$OTHER_VALIDATION_FAIL" ]]; then
  echo "FAIL [AC7-attack]: supersede wrongly removed a different work-item ($OTHER_WORK_ITEM_ID) blocker" >&2
  exit 1
fi

# --- AC7 / AC-NF1: probe stage breakdown now lets the work item through. ---
set +e
after_json="$(bash "$PROBE" --stage breakdown \
  --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID" --repo "$REPO" 2>"$TMP/after.err")"
after_exit=$?
set -e
if [[ "$after_exit" -ne 0 ]]; then
  echo "FAIL [post-emit probe]: probe exited $after_exit (expected 0 emit)" >&2
  cat "$TMP/after.err" >&2
  exit 1
fi
after_status="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1]).get("status") or "")' "$after_json")"
after_terminal="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1]).get("terminal_status") or "")' "$after_json")"
after_action="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1]).get("next_action") or "")' "$after_json")"
if [[ "$after_status" != "PASS" || -n "$after_terminal" || "$after_action" != "engineering" ]]; then
  echo "FAIL [AC7]: post-supersede probe did not let the work item through" >&2
  echo "  status=$after_status terminal=$after_terminal next_action=$after_action" >&2
  echo "$after_json" >&2
  exit 1
fi

# --- AC7 idempotency / no-blocker case: re-emitting with no blockers present is
#     a no-op (does not error). ---
bash "$EMITTER" \
  --source-id "$SOURCE_ID" \
  --work-item-id "$WORK_ITEM_ID" \
  --task-md "$TASK_MD" \
  --status PASS \
  --out "$TASK_SNAPSHOT" >/dev/null

# --- AC7-attack (non-PASS): a non-PASS emit must NOT supersede blockers (only a
#     successful PASS re-package clears them). ---
NONPASS_WORK_ITEM="DP-998-T3"
NONPASS_BLOCKER="$EVIDENCE/validation-fail/${NONPASS_WORK_ITEM}.json"
NONPASS_SNAPSHOT="$EVIDENCE/task-snapshot/${NONPASS_WORK_ITEM}.json"
bash "$BLOCKER_EMITTER" \
  --source-id "$SOURCE_ID" --work-item-id "$NONPASS_WORK_ITEM" \
  --marker-kind validation_fail --reason "still failing" \
  --out "$NONPASS_BLOCKER" >/dev/null
bash "$EMITTER" \
  --source-id "$SOURCE_ID" \
  --work-item-id "$NONPASS_WORK_ITEM" \
  --task-md "$TASK_MD" \
  --status BLOCKED \
  --out "$NONPASS_SNAPSHOT" >/dev/null
if [[ ! -f "$NONPASS_BLOCKER" ]]; then
  echo "FAIL [AC7-attack non-PASS]: a non-PASS task_snapshot emit wrongly superseded the blocker" >&2
  exit 1
fi

echo "PASS: breakdown-marker-supersede selftest (AC7, AC-NF1, AC-NEG3, AC7-attack)"
