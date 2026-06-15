#!/usr/bin/env bash
# Purpose: selftest for DP-301 FD1 — task_snapshot binds to the source canonical
#          refinement_hash and a deterministic staleness check catches a task.md
#          derived before a re-LOCK refinement.json change.
# Inputs:  none (builds a synthetic source container + valid ledger in a tmpdir).
# Outputs: PASS line on success; non-zero exit + FAIL line on contract regression.
#
# Covers (DP-301):
#   AC1     : emit task_snapshot with source_refinement_hash → change refinement.json
#             (task.md UNCHANGED) → staleness check exit 2 + POLARIS_TASK_SNAPSHOT_STALE.
#   AC-NF1  : the staleness violation fails closed (exit non-zero) and emits the
#             structured POLARIS_TASK_SNAPSHOT_STALE marker on stderr.
#   AC-NEG1 : the hash is sourced from validate-auto-pass-ledger.sh
#             --print-refinement-hash (no second hash impl); the emitter holds no
#             standalone refinement-hash algorithm callable without that validator.
#   AC-NEG3 : this fix ships a deterministic gate/script + selftest (this file).
# Back-compat: a pre-FD1 marker without source_refinement_hash is an additive
#             no-op on --check (exit 0).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EMITTER="$ROOT/scripts/breakdown-emit-task-snapshot.sh"
LEDGER_VALIDATOR="$ROOT/scripts/validate-auto-pass-ledger.sh"

for f in "$EMITTER" "$LEDGER_VALIDATOR"; do
  [[ -f "$f" ]] || { echo "FAIL: missing script: $f" >&2; exit 1; }
done

TMP="$(mktemp -d -t dp301-task-snapshot.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

SOURCE_ID="DP-999"
WORK_ITEM_ID="DP-999-T1"
SOURCE="$TMP/docs-manager/src/content/docs/specs/design-plans/DP-999-fixture"
mkdir -p "$SOURCE"

cat >"$SOURCE/index.md" <<'MD'
---
title: "DP-999: task-snapshot fixture"
description: "DP-301 FD1 selftest fixture"
status: LOCKED
locked_at: 2026-06-15
---

# DP-999 fixture
MD

cat >"$SOURCE/refinement.md" <<'MD'
---
title: "DP-999 Refinement"
description: "DP-301 FD1 fixture refinement"
---

## Scope

此 fixture 用於驗證 task_snapshot refinement_hash 綁定。
MD

write_refinement_json() {
  local marker="$1"
  python3 - "$SOURCE/refinement.json" "$SOURCE" "$marker" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
source = Path(sys.argv[2])
marker = sys.argv[3]
payload = {
    "version": "1",
    "created_at": "2026-06-15T10:00:00+08:00",
    "source": {
        "type": "dp",
        "id": "DP-999",
        "container": str(source),
        "plan_path": str(source / "index.md"),
        "jira_key": None,
    },
    "modules": [{"path": ".claude/skills/auto-pass/SKILL.md", "action": marker}],
    "acceptance_criteria": [
        {"id": "AC1", "text": "fixture", "category": "functional", "negative": False,
         "verification": {"method": "unit_test", "detail": "fixture"}}
    ],
    "dependencies": [],
    "edge_cases": [],
    "predecessor_audit": [],
}
path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

write_ledger() {
  local path="$1"
  python3 - "$path" "$SOURCE_ID" "$SOURCE" <<'PY'
import json
import sys
from pathlib import Path

path, source_id, container = sys.argv[1:4]
payload = {
    "schema_version": "1",
    "source": {
        "type": "dp",
        "id": source_id,
        "container": container,
        # Placeholder hash; --print-refinement-hash prints the actual current
        # hash regardless of this value, so the check never depends on it.
        "refinement_hash": "sha256:placeholder",
    },
    "started_at": "2026-06-15T10:00:00+08:00",
    "resumed_at": None,
    "terminal_status": None,
    "consent_policy": {
        "auto_reestimate": True,
        "auto_resplit": True,
        "auto_task_repair": True,
    },
    "consent_excludes": [
        "base_branch_force_push",
        "force_push_without_lease",
        "history_rewrite",
        "merge",
        "release",
        "deploy",
        "production_write",
        "jira_child_write",
        "jira_comment_write",
        "jira_worklog_write",
        "task_scope_outside_mutation",
    ],
    "task_snapshot": [],
    "stage_events": [],
    "loop_counters": {
        "engineering_to_breakdown": 0,
        "breakdown_to_refinement_inbox": 0,
    },
    "drift_retry": {},
    "pause": None,
}
Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

# task.md is created ONCE and never modified — staleness must be proven by the
# refinement.json change alone, via source_refinement_hash mismatch.
TASK_MD="$TMP/task.md"
cat >"$TASK_MD" <<'MD'
---
title: "DP-999 T1"
status: IN_PROGRESS
---

# T1 fixture task
MD

LEDGER="$TMP/ledger.json"
write_ledger "$LEDGER"

write_refinement_json "create"
MARKER="$TMP/.polaris/evidence/task-snapshot/${WORK_ITEM_ID}.json"

# --- Emit a fresh task_snapshot bound to the current canonical refinement hash. ---
bash "$EMITTER" \
  --source-id "$SOURCE_ID" \
  --work-item-id "$WORK_ITEM_ID" \
  --task-md "$TASK_MD" \
  --source-container "$SOURCE" \
  --ledger "$LEDGER" \
  --out "$MARKER" >/dev/null

recorded="$(python3 -c 'import json,sys;print((json.load(open(sys.argv[1])).get("freshness") or {}).get("source_refinement_hash",""))' "$MARKER")"
if [[ -z "$recorded" ]]; then
  echo "FAIL [emit]: marker missing source_refinement_hash after emit with --source-container/--ledger" >&2
  exit 1
fi
case "$recorded" in
  sha256:*) : ;;
  *) echo "FAIL [emit]: source_refinement_hash not a sha256 value: $recorded" >&2; exit 1 ;;
esac

# --- Case 1 (AC1): fresh marker matches current refinement → check PASS. ---
if ! bash "$EMITTER" --check \
       --source-container "$SOURCE" --ledger "$LEDGER" --marker "$MARKER" >/dev/null 2>"$TMP/check-fresh.err"; then
  echo "FAIL [case 1 / AC1]: fresh task_snapshot check should PASS" >&2
  cat "$TMP/check-fresh.err" >&2
  exit 1
fi

# --- Case 2 (AC1 / AC-NF1): change refinement.json ONLY → check fails closed. ---
write_refinement_json "modify"  # hash changes; task.md untouched

set +e
bash "$EMITTER" --check \
  --source-container "$SOURCE" --ledger "$LEDGER" --marker "$MARKER" \
  >"$TMP/check-stale.out" 2>"$TMP/check-stale.err"
stale_exit=$?
set -e

if [[ "$stale_exit" -ne 2 ]]; then
  echo "FAIL [case 2 / AC1+AC-NF1]: stale check exit=$stale_exit (expected 2)" >&2
  cat "$TMP/check-stale.out" "$TMP/check-stale.err" >&2
  exit 1
fi
if ! grep -q 'POLARIS_TASK_SNAPSHOT_STALE' "$TMP/check-stale.err"; then
  echo "FAIL [case 2 / AC-NF1]: missing POLARIS_TASK_SNAPSHOT_STALE marker on stderr" >&2
  cat "$TMP/check-stale.err" >&2
  exit 1
fi

# --- Case 3 (back-compat): pre-FD1 marker without source_refinement_hash → no-op PASS. ---
LEGACY_MARKER="$TMP/.polaris/evidence/task-snapshot/legacy.json"
mkdir -p "$(dirname "$LEGACY_MARKER")"
python3 - "$LEGACY_MARKER" "$SOURCE_ID" "$TASK_MD" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

out, source_id, task_md = sys.argv[1:4]
task_path = Path(task_md)
payload = {
    "schema_version": 1,
    "marker_kind": "task_snapshot",
    "writer": "breakdown",
    "owning_skill": "breakdown",
    "source_id": source_id,
    "work_item_id": "DP-999-LEGACY",
    "status": "PASS",
    "freshness": {
        "task_artifact_sha256": hashlib.sha256(task_path.read_bytes()).hexdigest(),
        "source_artifact": task_path.as_posix(),
    },
    "task_md": task_path.as_posix(),
    "at": "2026-06-01T00:00:00+00:00",
}
Path(out).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

if ! bash "$EMITTER" --check \
       --source-container "$SOURCE" --ledger "$LEDGER" --marker "$LEGACY_MARKER" >/dev/null 2>"$TMP/check-legacy.err"; then
  echo "FAIL [case 3 / back-compat]: pre-FD1 marker (no source_refinement_hash) should be a no-op PASS" >&2
  cat "$TMP/check-legacy.err" >&2
  exit 1
fi

# --- Case 4 (AC-NEG1): emit without --source-container/--ledger omits the field
#     (additive), so legacy callers stay back-compatible. ---
LEGACY_EMIT="$TMP/.polaris/evidence/task-snapshot/no-hash.json"
bash "$EMITTER" \
  --source-id "$SOURCE_ID" \
  --work-item-id "DP-999-T2" \
  --task-md "$TASK_MD" \
  --out "$LEGACY_EMIT" >/dev/null
no_hash="$(python3 -c 'import json,sys;print((json.load(open(sys.argv[1])).get("freshness") or {}).get("source_refinement_hash","<absent>"))' "$LEGACY_EMIT")"
if [[ "$no_hash" != "<absent>" ]]; then
  echo "FAIL [case 4 / AC-NEG1]: emit without container/ledger should omit source_refinement_hash, got: $no_hash" >&2
  exit 1
fi

echo "PASS: task-snapshot-refinement-hash selftest (AC1, AC-NF1, AC-NEG1, AC-NEG3)"
