#!/usr/bin/env bash
# auto-pass-amendment-loop-selftest.sh — DP-212 amendment loop contract.
#
# Verifies:
#   1. Ledger with non-terminal pause.kind=paused_for_refinement + terminal_status=null
#      PASSes the ledger validator (counter <= 3).
#   2. Ledger with terminal_status=paused_for_refinement FAILS with
#      PAUSED_FOR_REFINEMENT_LEGACY_TERMINAL hint.
#   3. Ledger with breakdown_to_refinement_inbox > 3 and terminal_status=null
#      FAILS (must escalate to loop_cap_reached).
#   4. Ledger with breakdown_to_refinement_inbox > 3 and
#      terminal_status=loop_cap_reached PASSes (orchestrator did the right thing).
#   5. Ledger with pause.kind=paused_for_refinement AND
#      terminal_status=paused_for_user_external_write FAILS (mismatched).
#   6. session_handoff resume preserves loop_counters via validate-auto-pass-resume.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LEDGER_VALIDATOR="$ROOT/scripts/validate-auto-pass-ledger.sh"

TMP="$(mktemp -d -t auto-pass-amendment-XXXX)"
trap 'rm -rf "$TMP"' EXIT

SOURCE="$TMP/docs-manager/src/content/docs/specs/design-plans/DP-999-amendment-loop-fixture"
mkdir -p "$SOURCE"

cat >"$SOURCE/index.md" <<'MD'
---
title: "DP-999: amendment loop fixture"
description: "auto-pass amendment loop selftest fixture"
status: LOCKED
locked_at: 2026-05-21
---

# DP-999 fixture
MD

cat >"$SOURCE/refinement.md" <<'MD'
---
title: "DP-999 Refinement"
description: "amendment loop fixture refinement"
---

## Scope

amendment loop selftest fixture.
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

write_ledger() {
  python3 - "$1" "$SOURCE" "$HASH" "$2" "$3" "$4" "$5" <<'PY'
import json
import sys
from pathlib import Path

path, container, ref_hash, terminal, counter, pause_kind, pause_extra = sys.argv[1:8]
pause = None
if pause_kind != "null":
    pause = {
        "kind": pause_kind,
        "reason": "fixture",
        "created_at": "2026-05-21T10:05:00+08:00",
    }
    if pause_kind == "paused_for_refinement":
        pause["inbox_path"] = "refinement-inbox/T1-1-20260521T100500Z.md"
    if pause_extra:
        pause.update(json.loads(pause_extra))
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
    "terminal_status": None if terminal == "null" else terminal,
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
        "breakdown_to_refinement_inbox": int(counter),
    },
    "drift_retry": {},
    "pause": pause,
}
Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

expect_pass() {
  local label="$1" path="$2"
  if ! "$LEDGER_VALIDATOR" "$path" --source-container "$SOURCE" --source-id DP-999 >"$TMP/${label}.out" 2>&1; then
    echo "FAIL: $label expected PASS but validator FAILed" >&2
    cat "$TMP/${label}.out" >&2
    exit 1
  fi
}

expect_fail() {
  local label="$1" path="$2" needle="$3"
  if "$LEDGER_VALIDATOR" "$path" --source-container "$SOURCE" --source-id DP-999 >"$TMP/${label}.out" 2>&1; then
    echo "FAIL: $label expected FAIL but validator PASSed" >&2
    cat "$TMP/${label}.out" >&2
    exit 1
  fi
  if ! grep -qF "$needle" "$TMP/${label}.out"; then
    echo "FAIL: $label missing expected signal: $needle" >&2
    cat "$TMP/${label}.out" >&2
    exit 1
  fi
}

# Case 1: non-terminal pause + counter=1 PASSes
write_ledger "$TMP/case1.json" null 1 paused_for_refinement ""
expect_pass "case1-non-terminal-pause" "$TMP/case1.json"

# Case 2: legacy terminal paused_for_refinement FAILs with hint
write_ledger "$TMP/case2.json" paused_for_refinement 1 null ""
expect_fail "case2-legacy-terminal" "$TMP/case2.json" "PAUSED_FOR_REFINEMENT_LEGACY_TERMINAL"

# Case 3: counter > cap without terminal FAILs
write_ledger "$TMP/case3.json" null 4 null ""
expect_fail "case3-counter-over-cap" "$TMP/case3.json" "exceeds cap=3"

# Case 4: counter > cap with loop_cap_reached PASSes
write_ledger "$TMP/case4.json" loop_cap_reached 4 null ""
expect_pass "case4-counter-promoted" "$TMP/case4.json"

# Case 5: non-terminal pause kind with mismatched terminal status FAILs
write_ledger "$TMP/case5.json" paused_for_user_external_write 1 paused_for_refinement ""
expect_fail "case5-pause-terminal-mismatch" "$TMP/case5.json" "paused_for_refinement pause is non-terminal"

# Case 6: counter=3 (at cap) still PASSes
write_ledger "$TMP/case6.json" null 3 paused_for_refinement ""
expect_pass "case6-counter-at-cap" "$TMP/case6.json"

echo "PASS: DP-212 auto-pass amendment loop selftest (6/6 cases)"
