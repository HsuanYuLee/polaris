#!/usr/bin/env bash
# Verify auto-pass complete reports require parent lifecycle closeout.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-auto-pass-report.sh"
TMP="$(mktemp -d -t auto-pass-terminal-lifecycle.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

HEAD_SHA="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
EVIDENCE_ROOT="$TMP/evidence"
SPECS_ROOT="$TMP/specs"
DESIGN_PLANS="$SPECS_ROOT/design-plans"
mkdir -p "$DESIGN_PLANS/DP-777-selftest/tasks/V1" "$DESIGN_PLANS/archive"

cat >"$DESIGN_PLANS/DP-777-selftest/tasks/V1/index.md" <<MD
---
title: "V1"
status: IMPLEMENTED
task_kind: V
work_item_id: DP-777-V1
ac_verification:
  status: PASS
---

# V1

> Source: DP-777 | Task: DP-777-V1 | JIRA: N/A | Repo: polaris-framework
MD

mkdir -p "$DESIGN_PLANS/DP-777-selftest/tasks/T1"
cat >"$DESIGN_PLANS/DP-777-selftest/tasks/T1/index.md" <<MD
---
task_kind: T
deliverable:
  head_sha: ${HEAD_SHA}
---

# T1

> Source: DP-777 | Task: DP-777-T1 | JIRA: N/A | Repo: polaris-framework
MD

mkdir -p "$EVIDENCE_ROOT/docs-manager/src/content/docs/specs"
ln -s "$DESIGN_PLANS" "$EVIDENCE_ROOT/docs-manager/src/content/docs/specs/design-plans"

ledger="$TMP/ledger.json"
cat >"$ledger" <<'JSON'
{"schema_version":"1","terminal_status":"complete","pause":null,"friction_log":[]}
JSON

write_report() {
  local path="$1"
  python3 - "$path" "$ledger" "$HEAD_SHA" <<'PY'
import json
import sys
from pathlib import Path

path, ledger, head = sys.argv[1:4]
payload = {
    "schema_version": 1,
    "source_id": "DP-777",
    "terminal_status": "complete",
    "created_at": "2026-07-05T00:00:00Z",
    "ledger_path": ledger,
    "required_prs": [{"task_id": "DP-777-T1", "head_sha": head}],
    "verification": {"status": "PASS", "work_item_id": "DP-777-V1", "head_sha": head},
    "issues": [],
    "blockers": [],
    "manual_items": [],
    "follow_ups": [],
    "overlap_disposition": [],
    "follow_up_dp_seed": None,
}
Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

report="$TMP/report.json"
write_report "$report"

cat >"$DESIGN_PLANS/DP-777-selftest/index.md" <<'MD'
---
title: "DP-777"
description: "Active selftest fixture."
status: LOCKED
---

# DP-777
MD

if POLARIS_WORKSPACE_ROOT="$EVIDENCE_ROOT" POLARIS_SPECS_ROOT="$SPECS_ROOT" "$VALIDATOR" "$report" >"$TMP/locked.out" 2>&1; then
  cat "$TMP/locked.out" >&2
  echo "FAIL: complete report with active LOCKED parent should fail" >&2
  exit 1
fi
grep -q "POLARIS_AUTO_PASS_TERMINAL_PARENT_NOT_ARCHIVED" "$TMP/locked.out"

mkdir -p "$DESIGN_PLANS/archive/DP-777-selftest/tasks"
mv "$DESIGN_PLANS/DP-777-selftest/tasks/V1" "$DESIGN_PLANS/archive/DP-777-selftest/tasks/V1"
mv "$DESIGN_PLANS/DP-777-selftest/tasks/T1" "$DESIGN_PLANS/archive/DP-777-selftest/tasks/T1"
cat >"$DESIGN_PLANS/archive/DP-777-selftest/index.md" <<'MD'
---
title: "DP-777"
description: "Archived selftest fixture."
status: IMPLEMENTED
---

# DP-777
MD
rm -rf "$DESIGN_PLANS/DP-777-selftest"

POLARIS_WORKSPACE_ROOT="$EVIDENCE_ROOT" POLARIS_SPECS_ROOT="$SPECS_ROOT" "$VALIDATOR" "$report" >"$TMP/archived.out"
grep -q "PASS: auto-pass report validation" "$TMP/archived.out"

echo "PASS: auto-pass terminal lifecycle fixed point selftest"
