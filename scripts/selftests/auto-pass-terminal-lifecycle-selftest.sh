#!/usr/bin/env bash
# Purpose: DP-406 terminal lifecycle parity selftest.
#
# 固定 auto-pass terminal_status 的 canonical set：
# complete / paused_for_user_external_write / loop_cap_reached /
# blocked_by_gate_failure / user_aborted。paused_for_refinement 與
# paused_for_session_handoff 不可作為 report terminal_status；session_handoff 只能作為
# ledger non-terminal pause.kind。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORT_VALIDATOR="$ROOT/scripts/validate-auto-pass-report.sh"
LEDGER_VALIDATOR="$ROOT/scripts/validate-auto-pass-ledger.sh"
TMP="$(mktemp -d -t auto-pass-terminal-lifecycle.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

export POLARIS_WORKSPACE_ROOT="$TMP"
export POLARIS_SPECS_ROOT="$TMP/docs-manager/src/content/docs/specs"

mkdir -p "$POLARIS_SPECS_ROOT/design-plans/DP-406-selftest/tasks/V1"
SOURCE_CONTAINER="$POLARIS_SPECS_ROOT/design-plans/DP-406-selftest"

cat >"$SOURCE_CONTAINER/index.md" <<'EOF'
---
title: "DP-406 Selftest"
status: LOCKED
---

# DP-406 Selftest
EOF

cat >"$SOURCE_CONTAINER/refinement.md" <<'EOF'
---
title: "DP-406 Selftest Refinement"
status: LOCKED
---

# DP-406 Selftest Refinement
EOF

cat >"$SOURCE_CONTAINER/refinement.json" <<'EOF'
{
  "source": {
    "id": "DP-406"
  }
}
EOF

set_source_status() {
  local status="$1"
  python3 - "$SOURCE_CONTAINER/index.md" "$status" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
status = sys.argv[2]
text = path.read_text(encoding="utf-8")
text = re.sub(r"^status: .*$", f"status: {status}", text, count=1, flags=re.MULTILINE)
path.write_text(text, encoding="utf-8")
PY
}

write_v_task() {
  local status="$1"
  cat >"$POLARIS_SPECS_ROOT/design-plans/DP-406-selftest/tasks/V1/index.md" <<EOF
---
title: "V1"
status: IN_PROGRESS
task_kind: V
work_item_id: DP-406-V1
ac_verification:
  status: ${status}
---

# V1

> Source: DP-406 | Task: DP-406-V1 | JIRA: N/A | Repo: polaris-framework
EOF
}

write_t_task() {
  mkdir -p "$POLARIS_SPECS_ROOT/design-plans/DP-406-selftest/tasks/T1"
  cat >"$POLARIS_SPECS_ROOT/design-plans/DP-406-selftest/tasks/T1/index.md" <<'EOF'
---
task_kind: T
deliverable:
  head_sha: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
---

# T1

> Source: DP-406 | Task: DP-406-T1 | JIRA: N/A | Repo: polaris-framework
EOF
}

write_ledger() {
  local path="$1" terminal_json="$2" pause_json="$3"
  python3 - "$SOURCE_CONTAINER" "$path" "$terminal_json" "$pause_json" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

container = Path(sys.argv[1])
path = Path(sys.argv[2])
terminal_status = json.loads(sys.argv[3])
pause = json.loads(sys.argv[4])

digest = hashlib.sha256()
for name in ("refinement.md", "refinement.json"):
    artifact = container / name
    digest.update(name.encode("utf-8"))
    digest.update(b"\0")
    digest.update(artifact.read_bytes())
    digest.update(b"\0")

payload = {
    "schema_version": "1",
    "source": {
        "type": "dp",
        "id": "DP-406",
        "container": str(container),
        "refinement_hash": "sha256:" + digest.hexdigest(),
    },
    "started_at": "2026-07-06T16:00:00+08:00",
    "terminal_status": terminal_status,
    "pause": pause,
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
    "loop_counters": {
        "engineering_to_breakdown": {"count": 0, "evidence_ids": []},
        "breakdown_to_refinement_inbox": {"count": 0, "evidence_ids": []},
        "engineering_revision_rounds": {"count": 0, "evidence_ids": []},
    },
    "friction_log": [],
}
path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
}

write_report() {
  local path="$1" terminal="$2" ledger="$3"
  cat >"$path" <<EOF
{
  "schema_version": 1,
  "source_id": "DP-406",
  "terminal_status": "${terminal}",
  "created_at": "2026-07-06T16:00:00+08:00",
  "ledger_path": "${ledger}",
  "required_prs": [
    {
      "task_id": "DP-406-T1",
      "head_sha": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    }
  ],
  "verification": {
    "status": "PASS",
    "work_item_id": "DP-406-V1",
    "head_sha": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  },
  "issues": [],
  "blockers": [],
  "manual_items": [],
  "follow_ups": [],
  "overlap_disposition": [],
  "follow_up_dp_seed": null,
  "framework_release_tail": {
    "trigger": "framework-release DP-406",
    "allowed": true,
    "reason": "selftest"
  }
}
EOF
}

expect_fail_contains() {
  local label="$1" needle="$2"
  shift 2
  if "$@" >"$TMP/$label.out" 2>&1; then
    echo "FAIL: $label unexpectedly passed" >&2
    cat "$TMP/$label.out" >&2
    exit 1
  fi
  grep -q "$needle" "$TMP/$label.out" || {
    echo "FAIL: $label did not mention $needle" >&2
    cat "$TMP/$label.out" >&2
    exit 1
  }
}

write_v_task PASS
write_t_task
set_source_status IMPLEMENTED
COMPLETE_LEDGER="$TMP/complete-ledger.json"
write_ledger "$COMPLETE_LEDGER" '"complete"' 'null'
COMPLETE_REPORT="$TMP/complete-report.json"
write_report "$COMPLETE_REPORT" complete "$COMPLETE_LEDGER"
"$REPORT_VALIDATOR" "$COMPLETE_REPORT" >/dev/null

ELIGIBLE_LEDGER="$TMP/eligible-ledger.json"
write_ledger "$ELIGIBLE_LEDGER" 'null' 'null'
ELIGIBLE_REPORT="$TMP/eligible-report.json"
write_report "$ELIGIBLE_REPORT" complete "$ELIGIBLE_LEDGER"
"$REPORT_VALIDATOR" "$ELIGIBLE_REPORT" >/dev/null

BAD_REFINEMENT_REPORT="$TMP/bad-refinement-report.json"
write_report "$BAD_REFINEMENT_REPORT" paused_for_refinement "$ELIGIBLE_LEDGER"
expect_fail_contains report-paused-refinement "invalid terminal_status" \
  "$REPORT_VALIDATOR" "$BAD_REFINEMENT_REPORT"

BAD_HANDOFF_REPORT="$TMP/bad-handoff-report.json"
write_report "$BAD_HANDOFF_REPORT" paused_for_session_handoff "$ELIGIBLE_LEDGER"
expect_fail_contains report-session-handoff "invalid terminal_status" \
  "$REPORT_VALIDATOR" "$BAD_HANDOFF_REPORT"

set_source_status LOCKED
LEGACY_LEDGER="$TMP/legacy-paused-refinement-ledger.json"
write_ledger "$LEGACY_LEDGER" '"paused_for_refinement"' 'null'
expect_fail_contains ledger-paused-refinement "PAUSED_FOR_REFINEMENT_LEGACY_TERMINAL" \
  "$LEDGER_VALIDATOR" "$LEGACY_LEDGER"

SESSION_LEDGER="$TMP/session-handoff-ledger.json"
write_ledger "$SESSION_LEDGER" 'null' '{"kind":"session_handoff","reason":"selftest","created_at":"2026-07-06T16:00:00+08:00","resume_artifact":"/tmp/session-resume.json","next_work_item_id":"DP-406-T1"}'
"$LEDGER_VALIDATOR" "$SESSION_LEDGER" >/dev/null

echo "PASS: auto-pass terminal lifecycle selftest"
