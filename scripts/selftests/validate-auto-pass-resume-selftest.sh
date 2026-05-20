#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-auto-pass-resume.sh"
LEDGER_VALIDATOR="$ROOT/scripts/validate-auto-pass-ledger.sh"
TMP="$(mktemp -d -t dp207-auto-pass-resume.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

container="$TMP/docs-manager/src/content/docs/specs/design-plans/DP-999-resume-fixture"
mkdir -p "$container/artifacts/auto-pass"
cat >"$container/index.md" <<'MD'
---
title: "DP-999"
status: LOCKED
---

# DP-999
MD
cat >"$container/refinement.md" <<'MD'
# Refinement
MD
cat >"$container/refinement.json" <<'JSON'
{"source":{"id":"DP-999"},"changed_files":["scripts/**"]}
JSON

hash=$(python3 - "$container" <<'PY'
import hashlib
import sys
from pathlib import Path
container = Path(sys.argv[1])
digest = hashlib.sha256()
for name in ("refinement.md", "refinement.json"):
    digest.update(name.encode("utf-8"))
    digest.update(b"\0")
    digest.update((container / name).read_bytes())
    digest.update(b"\0")
print("sha256:" + digest.hexdigest())
PY
)

ledger="$container/artifacts/auto-pass/ledger.json"
resume="$container/artifacts/auto-pass/session-handoff.json"
cat >"$ledger" <<JSON
{
  "schema_version": "1",
  "source": {
    "id": "DP-999",
    "container": "$container",
    "refinement_hash": "$hash"
  },
  "started_at": "2026-05-20T10:00:00+08:00",
  "resumed_at": null,
  "terminal_status": null,
  "consent_policy": {
    "auto_reestimate": true,
    "auto_resplit": true,
    "auto_task_repair": true
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
    "task_scope_outside_mutation"
  ],
  "task_snapshot": [],
  "stage_events": [],
  "loop_counters": {
    "engineering_to_breakdown": 0,
    "breakdown_to_refinement_inbox": 0
  },
  "drift_retry": {},
  "pause": {
    "kind": "session_handoff",
    "reason": "context pressure",
    "created_at": "2026-05-20T10:05:00+08:00",
    "resume_artifact": "$resume",
    "next_work_item_id": "DP-999-T2"
  }
}
JSON
cat >"$resume" <<JSON
{
  "schema_version": 1,
  "source_id": "DP-999",
  "ledger_path": "$ledger",
  "pause_kind": "session_handoff",
  "next_work_item_id": "DP-999-T2",
  "resume_command": "/auto-pass DP-999 resume --ledger $ledger",
  "summary": "Continue from T2.",
  "created_at": "2026-05-20T10:05:00+08:00"
}
JSON

bash "$LEDGER_VALIDATOR" "$ledger" --source-container "$container" --source-id DP-999 >/tmp/dp207-ledger-session-handoff.out
bash "$VALIDATOR" --ledger "$ledger" --resume-artifact "$resume" --source-id DP-999 >/tmp/dp207-resume-pass.out

bad_source="$TMP/bad-source.json"
cp "$resume" "$bad_source"
python3 - "$bad_source" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text())
data["source_id"] = "DP-998"
path.write_text(json.dumps(data) + "\n")
PY
if bash "$VALIDATOR" --ledger "$ledger" --resume-artifact "$bad_source" --source-id DP-999 >/tmp/dp207-resume-bad-source.out 2>&1; then
  echo "FAIL: bad source resume should fail" >&2
  exit 1
fi
rg -n 'source_id does not match' /tmp/dp207-resume-bad-source.out >/dev/null

missing="$TMP/missing.json"
if bash "$VALIDATOR" --ledger "$ledger" --resume-artifact "$missing" --source-id DP-999 >/tmp/dp207-resume-missing.out 2>&1; then
  echo "FAIL: missing resume artifact should fail" >&2
  exit 1
fi
rg -n 'resume artifact not found' /tmp/dp207-resume-missing.out >/dev/null

echo "PASS: validate auto-pass resume selftest"
