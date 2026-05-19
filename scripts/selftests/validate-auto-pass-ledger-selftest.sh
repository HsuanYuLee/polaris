#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-auto-pass-ledger.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SOURCE="$TMP/docs-manager/src/content/docs/specs/design-plans/DP-999-auto-pass-fixture"
mkdir -p "$SOURCE"

cat >"$SOURCE/index.md" <<'MD'
---
title: "DP-999: auto-pass fixture"
description: "auto-pass ledger selftest fixture"
status: LOCKED
locked_at: 2026-05-19
---

# DP-999 fixture
MD

cat >"$SOURCE/refinement.md" <<'MD'
---
title: "DP-999 Refinement"
description: "auto-pass ledger fixture refinement"
---

## Scope

此 fixture 用於驗證 auto-pass ledger schema。
MD

python3 - "$SOURCE/refinement.json" "$SOURCE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
source = Path(sys.argv[2])
payload = {
    "version": "1",
    "created_at": "2026-05-19T10:00:00+08:00",
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

HASH="$("$VALIDATOR" "$TMP/nonexistent-ledger.json" --print-refinement-hash --source-container "$SOURCE" 2>/dev/null || true)"
if [[ -z "$HASH" ]]; then
  HASH="$(python3 - "$SOURCE" <<'PY'
import hashlib
import sys
from pathlib import Path

source = Path(sys.argv[1])
digest = hashlib.sha256()
for name in ("refinement.md", "refinement.json"):
    path = source / name
    digest.update(name.encode("utf-8"))
    digest.update(b"\0")
    digest.update(path.read_bytes())
    digest.update(b"\0")
print("sha256:" + digest.hexdigest())
PY
)"
fi

write_ledger() {
  local path="$1"
  local source_id="${2:-DP-999}"
  local container="${3:-$SOURCE}"
  local hash="${4:-$HASH}"
  local terminal="${5:-null}"
  python3 - "$path" "$source_id" "$container" "$hash" "$terminal" <<'PY'
import json
import sys
from pathlib import Path

path, source_id, container, ref_hash, terminal = sys.argv[1:6]
payload = {
    "schema_version": "1",
    "source": {
        "id": source_id,
        "container": container,
        "refinement_hash": ref_hash,
    },
    "started_at": "2026-05-19T10:00:00+08:00",
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
        "breakdown_to_refinement_inbox": 0,
    },
    "drift_retry": {},
    "pause": None,
}
Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

expect_fail() {
  local label="$1"
  shift
  if "$@" >"$TMP/${label}.out" 2>&1; then
    echo "FAIL: $label unexpectedly passed" >&2
    cat "$TMP/${label}.out" >&2
    exit 1
  fi
}

VALID="$TMP/valid-ledger.json"
write_ledger "$VALID"
"$VALIDATOR" "$VALID" --source-container "$SOURCE" --source-id DP-999 --task-write-at "2026-05-19T10:05:00+08:00"

pushd "$TMP" >/dev/null
expect_fail "relative-path" "$VALIDATOR" "valid-ledger.json" --source-container "$SOURCE" --source-id DP-999
popd >/dev/null

SOURCE_MISMATCH="$TMP/source-mismatch.json"
write_ledger "$SOURCE_MISMATCH" DP-998
expect_fail "source-mismatch" "$VALIDATOR" "$SOURCE_MISMATCH" --source-container "$SOURCE" --source-id DP-999

MISSING_CONSENT="$TMP/missing-consent.json"
cp "$VALID" "$MISSING_CONSENT"
python3 - "$MISSING_CONSENT" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
del data["consent_policy"]["auto_task_repair"]
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_fail "missing-consent" "$VALIDATOR" "$MISSING_CONSENT" --source-container "$SOURCE" --source-id DP-999

UNKNOWN_TERMINAL="$TMP/unknown-terminal.json"
write_ledger "$UNKNOWN_TERMINAL" DP-999 "$SOURCE" "$HASH" "done"
expect_fail "unknown-terminal" "$VALIDATOR" "$UNKNOWN_TERMINAL" --source-container "$SOURCE" --source-id DP-999

DISCUSSION_SOURCE="$TMP/discussion-ledger.json"
cp "$SOURCE/index.md" "$SOURCE/index.locked.md"
python3 - "$SOURCE/index.md" <<'PY'
from pathlib import Path
path = Path(__import__("sys").argv[1])
path.write_text(path.read_text(encoding="utf-8").replace("status: LOCKED", "status: DISCUSSION"), encoding="utf-8")
PY
write_ledger "$DISCUSSION_SOURCE"
expect_fail "discussion-source" "$VALIDATOR" "$DISCUSSION_SOURCE" --source-container "$SOURCE" --source-id DP-999
mv "$SOURCE/index.locked.md" "$SOURCE/index.md"

STALE_HASH="$TMP/stale-hash.json"
write_ledger "$STALE_HASH" DP-999 "$SOURCE" "sha256:deadbeef"
expect_fail "stale-hash" "$VALIDATOR" "$STALE_HASH" --source-container "$SOURCE" --source-id DP-999

TIMESTAMP_FAIL="$TMP/timestamp-fail.json"
write_ledger "$TIMESTAMP_FAIL"
expect_fail "timestamp-ordering" "$VALIDATOR" "$TIMESTAMP_FAIL" --source-container "$SOURCE" --source-id DP-999 --task-write-at "2026-05-19T09:59:00+08:00"

SUBSET_CONSENT="$TMP/subset-consent.json"
cp "$VALID" "$SUBSET_CONSENT"
python3 - "$SUBSET_CONSENT" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["consent_excludes"] = data["consent_excludes"][:-1]
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_fail "subset-consent-excludes" "$VALIDATOR" "$SUBSET_CONSENT" --source-container "$SOURCE" --source-id DP-999

echo "PASS: validate-auto-pass-ledger selftest"
