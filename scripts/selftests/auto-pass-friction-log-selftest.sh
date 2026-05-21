#!/usr/bin/env bash
# auto-pass-friction-log-selftest.sh — DP-214 friction_log[] artifact contract.
#
# Verifies:
#   - append helper writes a valid friction_log entry (atomic, enum-checked).
#   - helper rejects unknown stage / kind (exit 1).
#   - helper warns on summary > 280 chars but does NOT truncate (AC-NEG3).
#   - ledger validator accepts well-formed friction_log[] and rejects malformed.
#   - report validator computes friction_log_summary from the ledger.
#   - report validator fails when declared friction_log_summary mismatches ledger.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LEDGER_VALIDATOR="$ROOT/scripts/validate-auto-pass-ledger.sh"
REPORT_VALIDATOR="$ROOT/scripts/validate-auto-pass-report.sh"
APPEND_HELPER="$ROOT/scripts/append-auto-pass-friction.sh"

TMP="$(mktemp -d -t auto-pass-friction-XXXX)"
trap 'rm -rf "$TMP"' EXIT

SOURCE="$TMP/docs-manager/src/content/docs/specs/design-plans/DP-999-friction-log-fixture"
mkdir -p "$SOURCE"

cat >"$SOURCE/index.md" <<'MD'
---
title: "DP-999: friction log fixture"
description: "auto-pass friction log selftest fixture"
status: LOCKED
locked_at: 2026-05-21
---

# DP-999 fixture
MD

cat >"$SOURCE/refinement.md" <<'MD'
---
title: "DP-999 Refinement"
description: "friction log fixture refinement"
---

## Scope

friction log selftest fixture refinement body.
MD

python3 - "$SOURCE/refinement.json" "$SOURCE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
source = Path(sys.argv[2])
payload = {
    "version": "1",
    "created_at": "2026-05-21T10:00:00+08:00",
    "source": {
        "type": "dp",
        "id": "DP-999",
        "container": str(source),
        "plan_path": str(source / "index.md"),
        "jira_key": None,
    },
    "modules": [{"path": ".claude/skills/auto-pass/SKILL.md", "action": "create"}],
    "acceptance_criteria": [
        {"id": "AC1", "text": "fixture", "category": "functional", "negative": False, "verification": {"method": "unit_test", "detail": "fixture"}}
    ],
    "dependencies": [],
    "edge_cases": [],
    "predecessor_audit": [],
}
path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

HASH="$(python3 - "$SOURCE" <<'PY'
import hashlib
import sys
from pathlib import Path

source = Path(sys.argv[1])
digest = hashlib.sha256()
for name in ("refinement.md", "refinement.json"):
    p = source / name
    digest.update(name.encode("utf-8"))
    digest.update(b"\0")
    digest.update(p.read_bytes())
    digest.update(b"\0")
print("sha256:" + digest.hexdigest())
PY
)"

LEDGER="$TMP/ledger.json"
python3 - "$LEDGER" "$SOURCE" "$HASH" <<'PY'
import json
import sys
from pathlib import Path

path, container, ref_hash = sys.argv[1:4]
payload = {
    "schema_version": "1",
    "source": {
        "type": "dp",
        "id": "DP-999",
        "container": container,
        "refinement_hash": ref_hash,
    },
    "started_at": "2026-05-21T10:00:00+08:00",
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

# AC1 + AC2: helper appends a valid entry with enum + required fields.
"$APPEND_HELPER" "$LEDGER" \
  --stage breakdown \
  --kind manual_artifact_patch \
  --summary "fixture: 補 V-task implementation_tasks 欄位才能 PASS validator" \
  --ts "2026-05-21T10:05:00+08:00" >/dev/null

"$APPEND_HELPER" "$LEDGER" \
  --stage engineering \
  --kind deterministic_gap \
  --summary "fixture: validator 無法判斷 PR freshness，需手動 rebind head_sha" \
  --ts "2026-05-21T10:10:00+08:00" >/dev/null

"$APPEND_HELPER" "$LEDGER" \
  --stage engineering \
  --kind manual_artifact_patch \
  --summary "fixture: 第二筆 manual patch entry，用來測 by_kind 聚合" \
  --ts "2026-05-21T10:15:00+08:00" >/dev/null

count="$(python3 -c "import json; print(len(json.load(open('$LEDGER'))['friction_log']))")"
if [[ "$count" != "3" ]]; then
  echo "FAIL: expected 3 friction_log entries after append, got $count" >&2
  exit 1
fi

# AC1: ledger validator accepts well-formed friction_log[]
"$LEDGER_VALIDATOR" "$LEDGER" --source-container "$SOURCE" --source-id DP-999 >/dev/null

# AC-NEG1: helper rejects unknown enum values
if "$APPEND_HELPER" "$LEDGER" \
    --stage unknown-stage \
    --kind manual_artifact_patch \
    --summary "bad stage" >"$TMP/bad-stage.out" 2>&1; then
  echo "FAIL: helper accepted unknown stage" >&2
  exit 1
fi

if "$APPEND_HELPER" "$LEDGER" \
    --stage breakdown \
    --kind unknown-kind \
    --summary "bad kind" >"$TMP/bad-kind.out" 2>&1; then
  echo "FAIL: helper accepted unknown friction_kind" >&2
  exit 1
fi

# AC-NEG2: helper rejects empty summary
if "$APPEND_HELPER" "$LEDGER" \
    --stage breakdown \
    --kind other \
    --summary "" >"$TMP/empty-summary.out" 2>&1; then
  echo "FAIL: helper accepted empty summary" >&2
  exit 1
fi

# AC-NEG3: helper warns on summary > 280 chars but does NOT truncate.
LONG_SUMMARY="$(python3 -c "print('長' * 300)")"
LONG_OUT="$TMP/long-summary.out"
"$APPEND_HELPER" "$LEDGER" \
  --stage engineering \
  --kind language_drift_repair \
  --summary "$LONG_SUMMARY" \
  --ts "2026-05-21T10:20:00+08:00" >"$LONG_OUT" 2>&1

if ! grep -q "WARNING: summary length" "$LONG_OUT"; then
  echo "FAIL: helper did not emit soft-limit WARNING" >&2
  cat "$LONG_OUT" >&2
  exit 1
fi

stored_len="$(python3 -c "import json; print(len(json.load(open('$LEDGER'))['friction_log'][-1]['summary']))")"
if [[ "$stored_len" != "300" ]]; then
  echo "FAIL: helper truncated summary (expected 300 chars, got $stored_len)" >&2
  exit 1
fi

# Now we have 4 entries: breakdown=1, engineering=3 (deterministic_gap, manual, language_drift)
total="$(python3 -c "import json; print(len(json.load(open('$LEDGER'))['friction_log']))")"
if [[ "$total" != "4" ]]; then
  echo "FAIL: expected 4 friction_log entries, got $total" >&2
  exit 1
fi

# AC4: report validator computes friction_log_summary from ledger and accepts matching snapshot.
REPORT="$TMP/report.json"
python3 - "$REPORT" "$LEDGER" <<'PY'
import json
import sys
from pathlib import Path

report_path, ledger_path = sys.argv[1], sys.argv[2]
ledger = json.loads(Path(ledger_path).read_text(encoding="utf-8"))
friction = ledger.get("friction_log", [])
summary = {"total": 0, "by_stage": {}, "by_kind": {}}
for entry in friction:
    summary["total"] += 1
    s = entry["stage"]
    k = entry["friction_kind"]
    summary["by_stage"][s] = summary["by_stage"].get(s, 0) + 1
    summary["by_kind"][k] = summary["by_kind"].get(k, 0) + 1

payload = {
    "schema_version": 1,
    "source_id": "DP-999",
    "terminal_status": "complete",
    "created_at": "2026-05-21T11:00:00+08:00",
    "ledger_path": ledger_path,
    "required_prs": [],
    "verification": {"status": "PASS", "work_item_id": "DP-999-V1"},
    "issues": [],
    "blockers": [],
    "manual_items": [],
    "follow_ups": [
        {"reason": "friction-log non-empty", "next_step": "open follow-up DP for friction"}
    ],
    "overlap_disposition": [],
    "follow_up_dp_seed": {
        "path": "docs-manager/src/content/docs/specs/design-plans/DP-999-follow-up/index.md",
        "reason": "friction_log non-empty",
        "source_report": report_path,
    },
    "framework_release_tail": None,
    "friction_log_summary": summary,
}
Path(report_path).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

"$REPORT_VALIDATOR" "$REPORT" >/dev/null

# AC-NEG4: mismatched friction_log_summary must fail.
BAD_REPORT="$TMP/report-mismatch.json"
python3 - "$REPORT" "$BAD_REPORT" <<'PY'
import json
import sys
from pathlib import Path

src, dst = sys.argv[1], sys.argv[2]
data = json.loads(Path(src).read_text(encoding="utf-8"))
data["friction_log_summary"]["total"] = 999
Path(dst).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

if "$REPORT_VALIDATOR" "$BAD_REPORT" >"$TMP/bad-report.out" 2>&1; then
  echo "FAIL: report validator accepted mismatched friction_log_summary" >&2
  cat "$TMP/bad-report.out" >&2
  exit 1
fi

# AC-NEG5: malformed friction_log entry must fail ledger validator.
BAD_LEDGER="$TMP/bad-ledger.json"
python3 - "$LEDGER" "$BAD_LEDGER" <<'PY'
import json
import sys
from pathlib import Path

src, dst = sys.argv[1], sys.argv[2]
data = json.loads(Path(src).read_text(encoding="utf-8"))
data["friction_log"].append({"ts": "2026-05-21T11:00:00+08:00", "stage": "engineering"})  # missing kind+summary
Path(dst).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

if "$LEDGER_VALIDATOR" "$BAD_LEDGER" --source-container "$SOURCE" --source-id DP-999 >"$TMP/bad-ledger.out" 2>&1; then
  echo "FAIL: ledger validator accepted malformed friction_log entry" >&2
  cat "$TMP/bad-ledger.out" >&2
  exit 1
fi

echo "PASS: DP-214 auto-pass friction-log selftest (entries=4, helper warns, validators consistent)"
