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
        "type": "dp",
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

# DP-228 AC14: DP source must not carry jira_status_transition consent or jira_status_consent_record.
DP_JIRA_POLLUTION="$TMP/dp-jira-consent-pollution.json"
cp "$VALID" "$DP_JIRA_POLLUTION"
python3 - "$DP_JIRA_POLLUTION" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["consent_policy"]["jira_status_transition"] = True
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_fail "dp-jira-consent-pollution" "$VALIDATOR" "$DP_JIRA_POLLUTION" --source-container "$SOURCE" --source-id DP-999

DP_JIRA_RECORD_POLLUTION="$TMP/dp-jira-record-pollution.json"
cp "$VALID" "$DP_JIRA_RECORD_POLLUTION"
python3 - "$DP_JIRA_RECORD_POLLUTION" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["jira_status_consent_record"] = {
    "session_id": "ssn-DP-pollution",
    "source_id": "DP-999",
    "granted_at": "2026-05-19T10:00:00+08:00",
    "ttl_seconds": 3600,
}
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_fail "dp-jira-record-pollution" "$VALIDATOR" "$DP_JIRA_RECORD_POLLUTION" --source-container "$SOURCE" --source-id DP-999

# DP-228 AC14 / AC-NEG6: JIRA source ledger fixture.
JIRA_SOURCE="$TMP/docs-manager/src/content/docs/specs/epics/EXAMPLE-999-jira-fixture"
mkdir -p "$JIRA_SOURCE"

cat >"$JIRA_SOURCE/index.md" <<'MD'
---
title: "EXAMPLE-999: JIRA source fixture"
description: "auto-pass ledger selftest JIRA fixture"
status: LOCKED
locked_at: 2026-05-22
---

# EXAMPLE-999 fixture
MD

cat >"$JIRA_SOURCE/refinement.md" <<'MD'
---
title: "EXAMPLE-999 Refinement"
description: "JIRA-backed auto-pass ledger fixture refinement"
---

## Scope

此 fixture 用於驗證 auto-pass ledger 對 JIRA source 的 schema。
MD

python3 - "$JIRA_SOURCE/refinement.json" "$JIRA_SOURCE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
source = Path(sys.argv[2])
payload = {
    "version": "1",
    "created_at": "2026-05-22T10:00:00+08:00",
    "source": {
        "type": "jira",
        "id": "EXAMPLE-999",
        "container": str(source),
        "plan_path": str(source / "index.md"),
        "jira_key": "EXAMPLE-999",
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

JIRA_HASH="$(python3 - "$JIRA_SOURCE" <<'PY'
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

write_jira_ledger() {
  local path="$1"
  local source_id="${2:-EXAMPLE-999}"
  local container="${3:-$JIRA_SOURCE}"
  local hash="${4:-$JIRA_HASH}"
  local include_jira_transition="${5:-true}"
  local include_status_record="${6:-true}"
  local consent_excludes_full="${7:-true}"
  python3 - "$path" "$source_id" "$container" "$hash" "$include_jira_transition" "$include_status_record" "$consent_excludes_full" <<'PY'
import json
import sys
from pathlib import Path

(
    path,
    source_id,
    container,
    ref_hash,
    include_jira_transition,
    include_status_record,
    consent_excludes_full,
) = sys.argv[1:8]

consent_policy = {
    "auto_reestimate": True,
    "auto_resplit": True,
    "auto_task_repair": True,
}
if include_jira_transition == "true":
    consent_policy["jira_status_transition"] = True

consent_excludes = [
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
]
if consent_excludes_full != "true":
    # drop jira_child_write to simulate over-broad consent (AC-NEG6 fail case).
    consent_excludes = [v for v in consent_excludes if v != "jira_child_write"]

payload = {
    "schema_version": "1",
    "source": {
        "type": "jira",
        "id": source_id,
        "container": container,
        "refinement_hash": ref_hash,
    },
    "started_at": "2026-05-22T10:00:00+08:00",
    "resumed_at": None,
    "terminal_status": None,
    "consent_policy": consent_policy,
    "consent_excludes": consent_excludes,
    "task_snapshot": [],
    "stage_events": [],
    "loop_counters": {
        "engineering_to_breakdown": 0,
        "breakdown_to_refinement_inbox": 0,
    },
    "drift_retry": {},
    "pause": None,
}
if include_status_record == "true":
    payload["jira_status_consent_record"] = {
        "session_id": "ssn-jira-fixture",
        "source_id": source_id,
        "granted_at": "2026-05-22T09:55:00+08:00",
        "ttl_seconds": 3600,
    }
Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

# AC14 happy path: JIRA source with jira_status_transition + jira_status_consent_record → PASS.
JIRA_VALID="$TMP/jira-valid-ledger.json"
write_jira_ledger "$JIRA_VALID"
"$VALIDATOR" "$JIRA_VALID" --source-container "$JIRA_SOURCE" --source-id EXAMPLE-999

# AC14 fail: JIRA source missing consent_policy.jira_status_transition.
JIRA_MISSING_FLAG="$TMP/jira-missing-flag.json"
write_jira_ledger "$JIRA_MISSING_FLAG" EXAMPLE-999 "$JIRA_SOURCE" "$JIRA_HASH" "false" "true" "true"
expect_fail "jira-missing-transition-flag" "$VALIDATOR" "$JIRA_MISSING_FLAG" --source-container "$JIRA_SOURCE" --source-id EXAMPLE-999

# AC14 fail: JIRA source missing jira_status_consent_record.
JIRA_MISSING_RECORD="$TMP/jira-missing-record.json"
write_jira_ledger "$JIRA_MISSING_RECORD" EXAMPLE-999 "$JIRA_SOURCE" "$JIRA_HASH" "true" "false" "true"
expect_fail "jira-missing-consent-record" "$VALIDATOR" "$JIRA_MISSING_RECORD" --source-container "$JIRA_SOURCE" --source-id EXAMPLE-999

# AC14 fail: jira_status_consent_record missing required field (session_id).
JIRA_INCOMPLETE_RECORD="$TMP/jira-incomplete-record.json"
write_jira_ledger "$JIRA_INCOMPLETE_RECORD"
python3 - "$JIRA_INCOMPLETE_RECORD" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
del data["jira_status_consent_record"]["session_id"]
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_fail "jira-record-missing-session" "$VALIDATOR" "$JIRA_INCOMPLETE_RECORD" --source-container "$JIRA_SOURCE" --source-id EXAMPLE-999

# AC14 fail: jira_status_consent_record.source_id does not match ledger source.id.
JIRA_MISMATCH_RECORD="$TMP/jira-mismatch-record.json"
write_jira_ledger "$JIRA_MISMATCH_RECORD"
python3 - "$JIRA_MISMATCH_RECORD" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["jira_status_consent_record"]["source_id"] = "EXAMPLE-998"
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_fail "jira-record-source-mismatch" "$VALIDATOR" "$JIRA_MISMATCH_RECORD" --source-container "$JIRA_SOURCE" --source-id EXAMPLE-999

# AC-NEG6: JIRA source ledger must keep consent_excludes complete; dropping jira_child_write fails.
JIRA_OVERBROAD="$TMP/jira-overbroad-consent.json"
write_jira_ledger "$JIRA_OVERBROAD" EXAMPLE-999 "$JIRA_SOURCE" "$JIRA_HASH" "true" "true" "false"
expect_fail "jira-overbroad-consent-excludes" "$VALIDATOR" "$JIRA_OVERBROAD" --source-container "$JIRA_SOURCE" --source-id EXAMPLE-999

# DP-246 T2: loop_counters new object shape {count, evidence_ids[]} is accepted.
OBJECT_COUNTERS="$TMP/object-counters.json"
cp "$VALID" "$OBJECT_COUNTERS"
python3 - "$OBJECT_COUNTERS" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["loop_counters"] = {
    "engineering_to_breakdown": {"count": 1, "evidence_ids": ["DP-999:engineering->breakdown:1"]},
    "breakdown_to_refinement_inbox": {"count": 0, "evidence_ids": []},
}
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
"$VALIDATOR" "$OBJECT_COUNTERS" --source-container "$SOURCE" --source-id DP-999

# DP-246 T2: legacy integer shape is still accepted (backward compat).
LEGACY_INT_COUNTERS="$TMP/legacy-int-counters.json"
cp "$VALID" "$LEGACY_INT_COUNTERS"
python3 - "$LEGACY_INT_COUNTERS" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["loop_counters"] = {
    "engineering_to_breakdown": 1,
    "breakdown_to_refinement_inbox": 0,
}
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
"$VALIDATOR" "$LEGACY_INT_COUNTERS" --source-container "$SOURCE" --source-id DP-999

# DP-246 T2: object shape with invalid count type should fail.
INVALID_OBJECT_COUNT="$TMP/invalid-object-count.json"
cp "$VALID" "$INVALID_OBJECT_COUNT"
python3 - "$INVALID_OBJECT_COUNT" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["loop_counters"] = {
    "engineering_to_breakdown": {"count": "not-an-int", "evidence_ids": []},
}
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_fail "object-counters-invalid-count-type" "$VALIDATOR" "$INVALID_OBJECT_COUNT" --source-container "$SOURCE" --source-id DP-999

# DP-246 T2: object shape with non-string evidence_id entry should fail.
INVALID_EVIDENCE_TYPE="$TMP/invalid-evidence-type.json"
cp "$VALID" "$INVALID_EVIDENCE_TYPE"
python3 - "$INVALID_EVIDENCE_TYPE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["loop_counters"] = {
    "engineering_to_breakdown": {"count": 1, "evidence_ids": [123]},
}
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_fail "object-counters-invalid-evidence-type" "$VALIDATOR" "$INVALID_EVIDENCE_TYPE" --source-container "$SOURCE" --source-id DP-999

# DP-313 T2 / AC4: engineering_revision_rounds counter.
#
# Helper to overwrite loop_counters with an arbitrary engineering_revision_rounds
# value (object or legacy int) and optional terminal_status, then run the validator.
set_revision_counter() {
  local src="$1"
  local dst="$2"
  local counter_json="$3"
  local terminal="${4:-null}"
  cp "$src" "$dst"
  python3 - "$dst" "$counter_json" "$terminal" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
counter = json.loads(sys.argv[2])
terminal = sys.argv[3]
data = json.loads(path.read_text(encoding="utf-8"))
data["loop_counters"] = {
    "engineering_to_breakdown": {"count": 0, "evidence_ids": []},
    "breakdown_to_refinement_inbox": {"count": 0, "evidence_ids": []},
    "engineering_revision_rounds": counter,
}
if terminal != "null":
    data["terminal_status"] = terminal
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

# AC4 — validated-when-present: object shape with count + evidence_ids is accepted.
REVISION_OBJECT="$TMP/revision-rounds-object.json"
set_revision_counter "$VALID" "$REVISION_OBJECT" '{"count": 2, "evidence_ids": ["DP-999:revision:1", "DP-999:revision:2"]}'
"$VALIDATOR" "$REVISION_OBJECT" --source-container "$SOURCE" --source-id DP-999

# AC4 — additive / missing-treated-as-0: a ledger without the key still passes (VALID has no
# engineering_revision_rounds key at all).
"$VALIDATOR" "$VALID" --source-container "$SOURCE" --source-id DP-999

# AC4 — legacy integer shape for the revision counter is accepted (backward compat).
REVISION_LEGACY_INT="$TMP/revision-rounds-legacy-int.json"
set_revision_counter "$VALID" "$REVISION_LEGACY_INT" '1'
"$VALIDATOR" "$REVISION_LEGACY_INT" --source-container "$SOURCE" --source-id DP-999

# AC4 — at-cap (count == cap) is still valid: cap is the inclusive ceiling, only > cap requires
# terminal. evidence_ids mirror the auto-pass-increment-counter idempotent model.
REVISION_AT_CAP="$TMP/revision-rounds-at-cap.json"
set_revision_counter "$VALID" "$REVISION_AT_CAP" '{"count": 3, "evidence_ids": ["DP-999:revision:1", "DP-999:revision:2", "DP-999:revision:3"]}'
"$VALIDATOR" "$REVISION_AT_CAP" --source-container "$SOURCE" --source-id DP-999

# AC4 — cap exceeded without terminal_status=loop_cap_reached must FAIL (counter cannot loop silently).
REVISION_OVER_CAP="$TMP/revision-rounds-over-cap.json"
set_revision_counter "$VALID" "$REVISION_OVER_CAP" '{"count": 4, "evidence_ids": ["DP-999:revision:1", "DP-999:revision:2", "DP-999:revision:3", "DP-999:revision:4"]}'
expect_fail "revision-rounds-over-cap-no-terminal" "$VALIDATOR" "$REVISION_OVER_CAP" --source-container "$SOURCE" --source-id DP-999

# AC4 — cap exceeded WITH terminal_status=loop_cap_reached is the sanctioned terminal and PASSES.
REVISION_OVER_CAP_TERMINAL="$TMP/revision-rounds-over-cap-terminal.json"
set_revision_counter "$VALID" "$REVISION_OVER_CAP_TERMINAL" '{"count": 4, "evidence_ids": ["DP-999:revision:1", "DP-999:revision:2", "DP-999:revision:3", "DP-999:revision:4"]}' "loop_cap_reached"
"$VALIDATOR" "$REVISION_OVER_CAP_TERMINAL" --source-container "$SOURCE" --source-id DP-999

# AC4 — invalid count type on the revision counter must FAIL (validated-when-present, same rigor
# as the other counters).
REVISION_BAD_TYPE="$TMP/revision-rounds-bad-type.json"
set_revision_counter "$VALID" "$REVISION_BAD_TYPE" '{"count": "nope", "evidence_ids": []}'
expect_fail "revision-rounds-invalid-count-type" "$VALIDATOR" "$REVISION_BAD_TYPE" --source-container "$SOURCE" --source-id DP-999

# --- DP-330: contract_evidence read-side fail-closed on gap-assertion friction ---------
# AC4: shape-only gate — a well-shaped, repo-resolvable path:line passes even if the cited
# contract does not "prove" the gap; the validator does not judge semantics.
GAP_WITH_EVIDENCE="$TMP/gap-with-evidence.json"
cp "$VALID" "$GAP_WITH_EVIDENCE"
python3 - "$GAP_WITH_EVIDENCE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["schema_version"] = "2"
data["friction_log"] = [
    {
        "ts": "2026-05-19T10:10:00+08:00",
        "stage": "engineering",
        "friction_kind": "validator_contract_conflict",
        "summary": "fixture gap with evidence",
        "contract_evidence": ["scripts/validate-auto-pass-ledger.sh:1"],
    }
]
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
"$VALIDATOR" "$GAP_WITH_EVIDENCE" --source-container "$SOURCE" --source-id DP-999 >/dev/null

# AC2: strict (schema_version "2") ledger with gap-kind friction but no contract_evidence FAILS.
GAP_WITHOUT_EVIDENCE="$TMP/gap-without-evidence.json"
cp "$GAP_WITH_EVIDENCE" "$GAP_WITHOUT_EVIDENCE"
python3 - "$GAP_WITHOUT_EVIDENCE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["friction_log"][0].pop("contract_evidence", None)
data["friction_log"][0]["friction_kind"] = "deterministic_gap"
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_fail "gap-without-contract-evidence" "$VALIDATOR" "$GAP_WITHOUT_EVIDENCE" --source-container "$SOURCE" --source-id DP-999

# AC2 adversarial: malformed (non path:line) contract_evidence on strict ledger FAILS.
GAP_BAD_EVIDENCE="$TMP/gap-bad-evidence.json"
cp "$GAP_WITH_EVIDENCE" "$GAP_BAD_EVIDENCE"
python3 - "$GAP_BAD_EVIDENCE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["friction_log"][0]["contract_evidence"] = ["not-a-path-line"]
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_fail "gap-bad-contract-evidence" "$VALIDATOR" "$GAP_BAD_EVIDENCE" --source-container "$SOURCE" --source-id DP-999

# AC2 adversarial: out-of-range line on strict ledger FAILS.
GAP_OUT_OF_RANGE_EVIDENCE="$TMP/gap-out-of-range-evidence.json"
cp "$GAP_WITH_EVIDENCE" "$GAP_OUT_OF_RANGE_EVIDENCE"
python3 - "$GAP_OUT_OF_RANGE_EVIDENCE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["friction_log"][0]["contract_evidence"] = ["scripts/validate-auto-pass-ledger.sh:999999"]
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_fail "gap-out-of-range-contract-evidence" "$VALIDATOR" "$GAP_OUT_OF_RANGE_EVIDENCE" --source-container "$SOURCE" --source-id DP-999
grep -q "outside file range" "$TMP/gap-out-of-range-contract-evidence.out"

# AC4: a .md contract surface path:line is also valid evidence (rd_risk mitigation).
GAP_MD_EVIDENCE="$TMP/gap-md-evidence.json"
cp "$GAP_WITH_EVIDENCE" "$GAP_MD_EVIDENCE"
python3 - "$GAP_MD_EVIDENCE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["friction_log"][0]["contract_evidence"] = [
    ".claude/skills/references/friction-capture-contract.md:1"
]
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
"$VALIDATOR" "$GAP_MD_EVIDENCE" --source-container "$SOURCE" --source-id DP-999 >/dev/null

# AC-NEG4: the same evidence-free gap entry on a legacy (schema_version "1") ledger is
# read-compatible — validator warns but does not fail.
LEGACY_GAP_WITHOUT_EVIDENCE="$TMP/legacy-gap-without-evidence.json"
cp "$GAP_WITHOUT_EVIDENCE" "$LEGACY_GAP_WITHOUT_EVIDENCE"
python3 - "$LEGACY_GAP_WITHOUT_EVIDENCE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["schema_version"] = "1"
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
"$VALIDATOR" "$LEGACY_GAP_WITHOUT_EVIDENCE" --source-container "$SOURCE" --source-id DP-999 >/dev/null

echo "PASS: validate-auto-pass-ledger selftest"
