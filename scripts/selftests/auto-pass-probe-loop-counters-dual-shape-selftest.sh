#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="$ROOT/scripts/auto-pass-probe.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

write_ledger() {
  local path="$1"
  local loops_json="$2"
  local drift_json="$3"
  python3 - "$path" "$loops_json" "$drift_json" <<'PY'
import json
import sys
from pathlib import Path

path, loops_raw, drift_raw = sys.argv[1:4]
payload = {
    "schema_version": "1",
    "source": {
        "type": "dp",
        "id": "DP-958",
        "container": "/tmp/DP-958",
        "refinement_hash": "sha256:fixture",
    },
    "started_at": "2026-05-28T00:00:00+08:00",
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
    "loop_counters": json.loads(loops_raw),
    "drift_retry": json.loads(drift_raw),
    "pre_dispatch_stash": None,
    "post_dispatch_restore": None,
    "pause": None,
}
Path(path).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

probe_terminal() {
  "$PROBE" --repo "$TMP" --stage breakdown --source-id DP-958 --work-item-id DP-958-T1 --ledger "$1" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("terminal_status"))'
}

legacy="$TMP/legacy-int-ledger.json"
write_ledger "$legacy" '{"engineering_to_breakdown": 3, "breakdown_to_refinement_inbox": 0}' '{}'
if [[ "$(probe_terminal "$legacy")" != "loop_cap_reached" ]]; then
  echo "FAIL: legacy int loop counter did not trigger loop cap" >&2
  exit 1
fi

dict="$TMP/dict-ledger.json"
write_ledger "$dict" '{"engineering_to_breakdown": {"count": 0, "evidence_ids": []}, "breakdown_to_refinement_inbox": {"count": 3, "evidence_ids": ["x"]}}' '{}'
if [[ "$(probe_terminal "$dict")" != "loop_cap_reached" ]]; then
  echo "FAIL: dict loop counter did not trigger loop cap" >&2
  exit 1
fi

drift="$TMP/drift-ledger.json"
write_ledger "$drift" '{"engineering_to_breakdown": {"count": 0, "evidence_ids": []}, "breakdown_to_refinement_inbox": {"count": 0, "evidence_ids": []}}' '{"DP-958-T1": {"count": 3, "evidence_ids": ["d1"]}}'
if [[ "$(probe_terminal "$drift")" != "blocked_by_gate_failure" ]]; then
  echo "FAIL: dict drift_retry counter did not trigger blocked terminal" >&2
  exit 1
fi

echo "PASS: auto-pass probe loop counters dual-shape"
