#!/usr/bin/env bash
# Purpose: DP-339 T1 — hermetic selftest for scripts/auto-pass-consume-resume.sh.
#          Builds its own tmp LOCKED-source fixtures (mktemp -d, trap cleanup) and
#          asserts AC1 (consume), AC2 (pause==null short-circuit gone), AC3 (resume
#          mismatch fail-closed), AC4 (byte-preserve loop_counters/task_snapshot/
#          drift_retry), AC-NEG1 (wrong pause kind), AC-NEG2 (no-pause idempotent
#          NOOP), AC-NEG3 (tempfile+os.replace shape + post-consume ledger valid).
# Inputs:  none (self-contained fixtures).
# Outputs: PASS line on success; FAIL + exit 1 on any failed assertion. Never
#          touches the live workspace or live ledgers.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONSUMER="$ROOT/scripts/auto-pass-consume-resume.sh"
CONSUMER_IMPL="$ROOT/scripts/lib/auto_pass_auto_pass_consume_resume_2.py"
LEDGER_VALIDATOR="$ROOT/scripts/validate-auto-pass-ledger.sh"
TMP="$(mktemp -d -t dp339-consume-resume.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# build_fixture <dir-suffix> <pause-block-json> -> echoes "<ledger>|<resume>"
# Constructs a LOCKED DP source container + ledger (with the given pause block) +
# matching resume artifact, and computes the refinement_hash the ledger validator
# expects.
build_fixture() {
  local suffix="$1"
  local pause_block="$2"
  local container="$TMP/$suffix/docs-manager/src/content/docs/specs/design-plans/DP-900-consume-fixture"
  mkdir -p "$container/artifacts/auto-pass"
  cat >"$container/index.md" <<'MD'
---
title: "DP-900"
status: LOCKED
---

# DP-900
MD
  cat >"$container/refinement.md" <<'MD'
# Refinement
MD
  cat >"$container/refinement.json" <<'JSON'
{"source":{"id":"DP-900"},"changed_files":["scripts/**"]}
JSON

  local hash
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

  local ledger="$container/artifacts/auto-pass/ledger.json"
  local resume="$container/artifacts/auto-pass/session-handoff.json"
  cat >"$ledger" <<JSON
{
  "schema_version": "1",
  "source": {
    "id": "DP-900",
    "container": "$container",
    "refinement_hash": "$hash"
  },
  "started_at": "2026-06-25T10:00:00+08:00",
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
  "task_snapshot": [
    {"work_item_id": "DP-900-T1", "status": "PASS"}
  ],
  "stage_events": [],
  "loop_counters": {
    "engineering_to_breakdown": 2,
    "breakdown_to_refinement_inbox": 1
  },
  "drift_retry": {"DP-900-T1": 1},
  "pause": $pause_block
}
JSON
  cat >"$resume" <<JSON
{
  "schema_version": 1,
  "source_id": "DP-900",
  "ledger_path": "$ledger",
  "pause_kind": "session_handoff",
  "next_work_item_id": "DP-900-T1",
  "resume_command": "/auto-pass DP-900 resume --ledger $ledger",
  "summary": "Continue from T1.",
  "created_at": "2026-06-25T10:05:00+08:00"
}
JSON

  echo "$ledger|$resume"
}

session_handoff_pause() {
  local resume="$1"
  cat <<JSON
{
    "kind": "session_handoff",
    "reason": "context pressure",
    "created_at": "2026-06-25T10:05:00+08:00",
    "resume_artifact": "$resume",
    "next_work_item_id": "DP-900-T1"
  }
JSON
}

# json_get <file> <python-expr-on-ledger> — extract a value for assertions.
json_get() {
  python3 - "$1" "$2" <<'PY'
import json
import sys
from pathlib import Path
ledger = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
expr = sys.argv[2]
print(json.dumps(eval(expr, {"ledger": ledger})))
PY
}

# ---------------------------------------------------------------------------
# AC1 + AC4 + AC-NEG3: valid session_handoff consume succeeds, pause null,
# resumed_at present (ISO8601), loop_counters/task_snapshot/drift_retry byte-
# preserved, and resulting ledger passes the ledger validator.
# ---------------------------------------------------------------------------
parts="$(build_fixture ac1 "$(session_handoff_pause "$TMP/ac1/docs-manager/src/content/docs/specs/design-plans/DP-900-consume-fixture/artifacts/auto-pass/session-handoff.json")")"
ledger="${parts%%|*}"
resume="${parts##*|}"

# Snapshot the three preserve-target sub-objects before consume.
before_counters="$(json_get "$ledger" 'ledger.get("loop_counters")')"
before_snapshot="$(json_get "$ledger" 'ledger.get("task_snapshot")')"
before_drift="$(json_get "$ledger" 'ledger.get("drift_retry")')"

bash "$CONSUMER" --ledger "$ledger" --resume-artifact "$resume" --source-id DP-900 >"$TMP/ac1.out" 2>&1 \
  || fail "AC1 consume should exit 0 (out: $(cat "$TMP/ac1.out"))"
grep -q '^CONSUMED:' "$TMP/ac1.out" || fail "AC1 expected CONSUMED line, got: $(cat "$TMP/ac1.out")"

[ "$(json_get "$ledger" 'ledger.get("pause")')" = "null" ] || fail "AC2 pause must be null after consume"

resumed="$(json_get "$ledger" 'ledger.get("resumed_at")')"
[ "$resumed" != "null" ] || fail "AC1 resumed_at must be set after consume"
python3 - "$ledger" <<'PY' || fail "AC1 resumed_at must be ISO8601"
import datetime as dt
import json
import sys
from pathlib import Path
v = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["resumed_at"]
t = v[:-1] + "+00:00" if v.endswith("Z") else v
dt.datetime.fromisoformat(t)
PY

# AC4: byte-preserve the three sub-objects.
[ "$(json_get "$ledger" 'ledger.get("loop_counters")')" = "$before_counters" ] || fail "AC4 loop_counters mutated"
[ "$(json_get "$ledger" 'ledger.get("task_snapshot")')" = "$before_snapshot" ] || fail "AC4 task_snapshot mutated"
[ "$(json_get "$ledger" 'ledger.get("drift_retry")')" = "$before_drift" ] || fail "AC4 drift_retry mutated"

# AC-NEG3 / AC1: consumed ledger still passes the ledger contract.
bash "$LEDGER_VALIDATOR" "$ledger" --source-container "$(dirname "$(dirname "$(dirname "$ledger")")")" --source-id DP-900 >/dev/null 2>&1 \
  || fail "AC1 consumed ledger must pass validate-auto-pass-ledger.sh"

# ---------------------------------------------------------------------------
# AC3 mismatch: resume artifact with wrong next_work_item_id -> exit 2,
# POLARIS_* marker, ledger pause UNCHANGED (still session_handoff, no resumed_at).
# ---------------------------------------------------------------------------
parts="$(build_fixture ac3 "$(session_handoff_pause "$TMP/ac3/docs-manager/src/content/docs/specs/design-plans/DP-900-consume-fixture/artifacts/auto-pass/session-handoff.json")")"
ledger="${parts%%|*}"
resume="${parts##*|}"
python3 - "$resume" <<'PY'
import json
import sys
from pathlib import Path
p = Path(sys.argv[1])
d = json.loads(p.read_text())
d["next_work_item_id"] = "DP-900-T9"  # mismatch vs ledger pause next_work_item_id
p.write_text(json.dumps(d) + "\n")
PY
if bash "$CONSUMER" --ledger "$ledger" --resume-artifact "$resume" --source-id DP-900 >"$TMP/ac3.out" 2>&1; then
  fail "AC3 mismatch should exit 2 (out: $(cat "$TMP/ac3.out"))"
fi
grep -q 'POLARIS_AUTO_PASS_CONSUME_RESUME_VALIDATION_FAILED' "$TMP/ac3.out" \
  || fail "AC3 expected VALIDATION_FAILED marker, got: $(cat "$TMP/ac3.out")"
[ "$(json_get "$ledger" 'ledger.get("pause", {}).get("kind")')" = '"session_handoff"' ] \
  || fail "AC3 pause must be unchanged after failed consume"
[ "$(json_get "$ledger" 'ledger.get("resumed_at")')" = "null" ] \
  || fail "AC3 resumed_at must not be written on failed consume"

# ---------------------------------------------------------------------------
# AC-NEG1: pause.kind=paused_for_user_external_write -> exit 2 +
# NOT_SESSION_HANDOFF marker, pause unchanged.
# ---------------------------------------------------------------------------
ext_pause='{
    "kind": "paused_for_user_external_write",
    "reason": "needs user external write",
    "created_at": "2026-06-25T10:05:00+08:00"
  }'
parts="$(build_fixture acneg1 "$ext_pause")"
ledger="${parts%%|*}"
resume="${parts##*|}"
# external-write pause requires terminal_status to match; set it so the fixture is
# self-consistent (consumer must reject on kind before any write regardless).
python3 - "$ledger" <<'PY'
import json
import sys
from pathlib import Path
p = Path(sys.argv[1])
d = json.loads(p.read_text())
d["terminal_status"] = "paused_for_user_external_write"
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n")
PY
if bash "$CONSUMER" --ledger "$ledger" --resume-artifact "$resume" --source-id DP-900 >"$TMP/acneg1.out" 2>&1; then
  fail "AC-NEG1 wrong pause kind should exit 2 (out: $(cat "$TMP/acneg1.out"))"
fi
grep -q 'POLARIS_AUTO_PASS_CONSUME_RESUME_NOT_SESSION_HANDOFF' "$TMP/acneg1.out" \
  || fail "AC-NEG1 expected NOT_SESSION_HANDOFF marker, got: $(cat "$TMP/acneg1.out")"
[ "$(json_get "$ledger" 'ledger.get("pause", {}).get("kind")')" = '"paused_for_user_external_write"' ] \
  || fail "AC-NEG1 pause must be unchanged"

# ---------------------------------------------------------------------------
# AC-NEG2: pause=null -> exit 0 NOOP, no resumed_at added, ledger byte-identical;
# run twice to prove idempotency.
# ---------------------------------------------------------------------------
parts="$(build_fixture acneg2 "null")"
ledger="${parts%%|*}"
resume="${parts##*|}"
before_bytes="$(cat "$ledger")"
bash "$CONSUMER" --ledger "$ledger" --resume-artifact "$resume" --source-id DP-900 >"$TMP/acneg2-1.out" 2>&1 \
  || fail "AC-NEG2 no-pause should exit 0 (out: $(cat "$TMP/acneg2-1.out"))"
grep -q '^NOOP:' "$TMP/acneg2-1.out" || fail "AC-NEG2 expected NOOP line, got: $(cat "$TMP/acneg2-1.out")"
[ "$(cat "$ledger")" = "$before_bytes" ] || fail "AC-NEG2 ledger must be byte-identical after NOOP"
[ "$(json_get "$ledger" 'ledger.get("resumed_at")')" = "null" ] || fail "AC-NEG2 resumed_at must not be added"
# idempotency: second run also NOOP, still byte-identical.
bash "$CONSUMER" --ledger "$ledger" --resume-artifact "$resume" --source-id DP-900 >"$TMP/acneg2-2.out" 2>&1 \
  || fail "AC-NEG2 second run should exit 0"
[ "$(cat "$ledger")" = "$before_bytes" ] || fail "AC-NEG2 ledger must stay byte-identical (idempotent)"

# ---------------------------------------------------------------------------
# AC-NEG3 shape: the consumer body uses tempfile.mkstemp + os.replace.
# ---------------------------------------------------------------------------
grep -q 'tempfile.mkstemp' "$CONSUMER_IMPL" || fail "AC-NEG3 consumer must use tempfile.mkstemp"
grep -q 'os.replace' "$CONSUMER_IMPL" || fail "AC-NEG3 consumer must use os.replace"

echo "PASS: auto-pass consume-resume selftest (7 cases: AC1, AC2, AC3, AC4, AC-NEG1, AC-NEG2, AC-NEG3)"
