#!/usr/bin/env bash
# auto-pass-counter-race-recovery-selftest.sh — DP-246 T3 race-recovery selftest.
#
# Verifies AC3, AC-NEG3, and AC-NEG4:
#
#   case 1 (AC3-happy)         : all preconditions pass → new ledger written,
#                                 evidence_ids carried forward, counters reset to actual,
#                                 COUNTER_RACE_RECOVERY entry in stage_events
#   case 2 (AC-NEG3-a)         : terminal_status != loop_cap_reached → exit 1 +
#                                 POLARIS_COUNTER_RECOVERY_PRECONDITION_FAILED
#   case 3 (AC-NEG3-b)         : no stage_retry friction → exit 1 + PRECONDITION_FAILED
#   case 4 (AC-NEG3-c)         : actual back-edge count >= cap → exit 1 +
#                                 PRECONDITION_FAILED
#   case 5 (AC-NEG4-rate-limit): same source 24h rate-limit → exit 1 +
#                                 PRECONDITION_FAILED on second call
#   case 6 (AC-NEG4-forged)    : forged friction entries + actual >= cap → still
#                                 fail-stop (precondition c overrides forged friction)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RECOVERY_HELPER="$ROOT_DIR/scripts/auto-pass-counter-race-recovery.sh"

WORKDIR="$(mktemp -d -t dp246-race-recovery.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

PASS=0
FAIL=0

ok()  { PASS=$((PASS + 1)); printf 'ok  %s\n' "$*"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*" >&2; }

# ------------------------------------------------------------------ mock source builder

CONSENT_EXCLUDES='["base_branch_force_push","force_push_without_lease","history_rewrite","merge","release","deploy","production_write","jira_child_write","jira_comment_write","jira_worklog_write","task_scope_outside_mutation"]'

# setup_mock_source <container_dir> <source_id>
# Creates minimal source artifacts so validate-auto-pass-ledger.sh passes.
setup_mock_source() {
  local container="$1"
  local source_id="$2"
  mkdir -p "$container"

  # index.md with LOCKED status
  cat >"$container/index.md" <<INDEXMD
---
title: "Mock source"
status: LOCKED
---
INDEXMD

  # refinement.md
  cat >"$container/refinement.md" <<REFMD
# Mock refinement
No content.
REFMD

  # refinement.json
  cat >"$container/refinement.json" <<REFJSON
{
  "schema_version": "1",
  "source": {"id": "$source_id"}
}
REFJSON
}

# compute_refinement_hash <container_dir>
compute_refinement_hash() {
  local container="$1"
  python3 - "$container" <<'PY'
import hashlib, sys
from pathlib import Path
container = Path(sys.argv[1])
digest = hashlib.sha256()
for name in ('refinement.md', 'refinement.json'):
    path = container / name
    digest.update(name.encode('utf-8'))
    digest.update(b'\0')
    digest.update(path.read_bytes())
    digest.update(b'\0')
print('sha256:' + digest.hexdigest())
PY
}

# make_ledger <path> <terminal_status> <e2b_count> <friction_count> <stage_events_count> <container> <refinement_hash>
make_ledger() {
  local path="$1"
  local terminal_status="$2"
  local e2b_count="$3"
  local friction_count="$4"
  local stage_events_count="$5"
  local container="$6"
  local refinement_hash="$7"

  python3 - "$path" "$terminal_status" "$e2b_count" "$friction_count" "$stage_events_count" "$container" "$refinement_hash" <<'PY'
import json, sys
from pathlib import Path
import datetime as dt

path             = Path(sys.argv[1])
terminal_status  = sys.argv[2] if sys.argv[2] != "null" else None
e2b_count        = int(sys.argv[3])
friction_count   = int(sys.argv[4])
stage_events_cnt = int(sys.argv[5])
container        = sys.argv[6]
refinement_hash  = sys.argv[7]

CONSENT_EXCLUDES = [
    "base_branch_force_push", "force_push_without_lease", "history_rewrite",
    "merge", "release", "deploy", "production_write", "jira_child_write",
    "jira_comment_write", "jira_worklog_write", "task_scope_outside_mutation"
]

now_iso = dt.datetime.now(tz=dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+00:00")

evidence_ids = [f"DP-246:engineering->breakdown:{i+1}" for i in range(e2b_count)]
friction_log = []
for i in range(friction_count):
    friction_log.append({
        "ts": now_iso,
        "stage": "engineering",
        "friction_kind": "inner_skill_halt_bypass",
        "summary": f"stage retry #{i+1}"
    })

stage_events = []
for i in range(stage_events_cnt):
    stage_events.append({
        "ts": now_iso,
        "stage": "engineering",
        "status": "HALT",
        "transition": "engineering_to_breakdown",
        "kind": "engineering_to_breakdown",
        "work_item_id": "DP-246-T1",
        "evidence_path": None
    })

ledger = {
    "schema_version": "1",
    "source": {
        "type": "dp",
        "id": "DP-246",
        "container": container,
        "refinement_hash": refinement_hash
    },
    "started_at": now_iso,
    "resumed_at": None,
    "terminal_status": terminal_status,
    "consent_policy": {
        "auto_reestimate": True,
        "auto_resplit": True,
        "auto_task_repair": True
    },
    "consent_excludes": CONSENT_EXCLUDES,
    "task_snapshot": [],
    "stage_events": stage_events,
    "loop_counters": {
        "engineering_to_breakdown": {
            "count": e2b_count,
            "evidence_ids": evidence_ids
        },
        "breakdown_to_refinement_inbox": {"count": 0, "evidence_ids": []}
    },
    "drift_retry": {},
    "friction_log": friction_log,
    "pre_dispatch_stash": None,
    "post_dispatch_restore": None,
    "pause": None
}
path.write_text(json.dumps(ledger, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
}

get_counter_count() {
  local ledger="$1"
  local key="$2"
  python3 - "$ledger" "$key" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
v = d.get('loop_counters', {}).get(sys.argv[2])
if v is None:   print(0)
elif isinstance(v, int): print(v)
elif isinstance(v, dict): print(v.get('count', 0))
else: print(-1)
PY
}

get_evidence_ids_count() {
  local ledger="$1"
  local key="$2"
  python3 - "$ledger" "$key" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
v = d.get('loop_counters', {}).get(sys.argv[2])
if isinstance(v, dict): print(len(v.get('evidence_ids', [])))
else: print(0)
PY
}

has_recovery_event() {
  local ledger="$1"
  python3 - "$ledger" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
events = d.get('stage_events', [])
found = any(
    e.get('status') == 'COUNTER_RACE_RECOVERY'
    or e.get('kind') == 'COUNTER_RACE_RECOVERY'
    for e in events if isinstance(e, dict)
)
print('1' if found else '0')
PY
}

get_terminal_status() {
  local ledger="$1"
  python3 - "$ledger" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print(d.get('terminal_status') or 'null')
PY
}

# ------------------------------------------------------------------ case 1: happy path (AC3)

C1_DIR="$WORKDIR/case1"
setup_mock_source "$C1_DIR" "DP-246"
C1_HASH=$(compute_refinement_hash "$C1_DIR")
C1_LEDGER="$C1_DIR/20260527-000000-ledger.json"
# terminal=loop_cap_reached, e2b_count=4 (over cap=3 claimed),
# actual stage_events back-edge = 1 (under cap) — all preconditions pass
make_ledger "$C1_LEDGER" "loop_cap_reached" 4 2 1 "$C1_DIR" "$C1_HASH"

RC1=0
NEW_LEDGER_PATH=""
NEW_LEDGER_PATH=$(bash "$RECOVERY_HELPER" \
  --source-id DP-246 \
  --prior-ledger "$C1_LEDGER" \
  --repo "$ROOT_DIR" 2>/dev/null) || RC1=$?

if [[ "$RC1" == "0" && -n "$NEW_LEDGER_PATH" && -f "$NEW_LEDGER_PATH" ]]; then
  NEW_TERMINAL=$(get_terminal_status "$NEW_LEDGER_PATH")
  NEW_E2B=$(get_counter_count "$NEW_LEDGER_PATH" engineering_to_breakdown)
  NEW_EIDS=$(get_evidence_ids_count "$NEW_LEDGER_PATH" engineering_to_breakdown)
  HAS_AUDIT=$(has_recovery_event "$NEW_LEDGER_PATH")

  if [[ "$NEW_TERMINAL" == "null" && "$NEW_E2B" -lt "3" && "$NEW_EIDS" -gt "0" && "$HAS_AUDIT" == "1" ]]; then
    ok "case 1 (AC3-happy): new ledger written, terminal=null, counters reset, evidence_ids carried, audit event present"
  else
    bad "case 1 (AC3-happy): expected terminal=null, counter<3, eids>0, audit=1; got terminal=$NEW_TERMINAL e2b=$NEW_E2B eids=$NEW_EIDS audit=$HAS_AUDIT"
  fi
else
  bad "case 1 (AC3-happy): expected success exit 0 + new ledger path, got rc=$RC1 path='$NEW_LEDGER_PATH'"
fi

# ------------------------------------------------------------------ case 2: AC-NEG3-a: terminal != loop_cap_reached

C2_DIR="$WORKDIR/case2"
setup_mock_source "$C2_DIR" "DP-246"
C2_HASH=$(compute_refinement_hash "$C2_DIR")
C2_LEDGER="$C2_DIR/20260527-000000-ledger.json"
make_ledger "$C2_LEDGER" "null" 2 1 0 "$C2_DIR" "$C2_HASH"

RC2=0
ERR2=""
ERR2="$(bash "$RECOVERY_HELPER" --source-id DP-246 --prior-ledger "$C2_LEDGER" --repo "$ROOT_DIR" 2>&1)" || RC2=$?
if [[ "$RC2" != "0" && "$ERR2" == *"POLARIS_COUNTER_RECOVERY_PRECONDITION_FAILED"* ]]; then
  ok "case 2 (AC-NEG3-a): terminal != loop_cap_reached → fail-stop + PRECONDITION_FAILED"
else
  bad "case 2 (AC-NEG3-a): expected non-zero + PRECONDITION_FAILED, got rc=$RC2 stderr='$ERR2'"
fi

# ------------------------------------------------------------------ case 3: AC-NEG3-b: no stage_retry friction

C3_DIR="$WORKDIR/case3"
setup_mock_source "$C3_DIR" "DP-246"
C3_HASH=$(compute_refinement_hash "$C3_DIR")
C3_LEDGER="$C3_DIR/20260527-000000-ledger.json"
# terminal=loop_cap_reached but friction_count=0
make_ledger "$C3_LEDGER" "loop_cap_reached" 4 0 1 "$C3_DIR" "$C3_HASH"

RC3=0
ERR3=""
ERR3="$(bash "$RECOVERY_HELPER" --source-id DP-246 --prior-ledger "$C3_LEDGER" --repo "$ROOT_DIR" 2>&1)" || RC3=$?
if [[ "$RC3" != "0" && "$ERR3" == *"POLARIS_COUNTER_RECOVERY_PRECONDITION_FAILED"* ]]; then
  ok "case 3 (AC-NEG3-b): no stage_retry friction → fail-stop + PRECONDITION_FAILED"
else
  bad "case 3 (AC-NEG3-b): expected non-zero + PRECONDITION_FAILED, got rc=$RC3 stderr='$ERR3'"
fi

# ------------------------------------------------------------------ case 4: AC-NEG3-c: actual back-edge count >= cap

C4_DIR="$WORKDIR/case4"
setup_mock_source "$C4_DIR" "DP-246"
C4_HASH=$(compute_refinement_hash "$C4_DIR")
C4_LEDGER="$C4_DIR/20260527-000000-ledger.json"
# terminal=loop_cap_reached, friction present, but stage_events_count=3 (>= cap=3)
make_ledger "$C4_LEDGER" "loop_cap_reached" 4 2 3 "$C4_DIR" "$C4_HASH"

RC4=0
ERR4=""
ERR4="$(bash "$RECOVERY_HELPER" --source-id DP-246 --prior-ledger "$C4_LEDGER" --repo "$ROOT_DIR" 2>&1)" || RC4=$?
if [[ "$RC4" != "0" && "$ERR4" == *"POLARIS_COUNTER_RECOVERY_PRECONDITION_FAILED"* ]]; then
  ok "case 4 (AC-NEG3-c): actual back-edge >= cap → fail-stop + PRECONDITION_FAILED"
else
  bad "case 4 (AC-NEG3-c): expected non-zero + PRECONDITION_FAILED (actual>=cap), got rc=$RC4 stderr='$ERR4'"
fi

# ------------------------------------------------------------------ case 5: AC-NEG4-rate-limit: same source 24h

# Reuse C1_DIR which already has a rate-limit stamp from case 1 run
C5_LEDGER="$C1_DIR/20260527-000001-ledger.json"
make_ledger "$C5_LEDGER" "loop_cap_reached" 4 2 1 "$C1_DIR" "$C1_HASH"

RC5=0
ERR5=""
ERR5="$(bash "$RECOVERY_HELPER" --source-id DP-246 --prior-ledger "$C5_LEDGER" --repo "$ROOT_DIR" 2>&1)" || RC5=$?
if [[ "$RC5" != "0" && "$ERR5" == *"POLARIS_COUNTER_RECOVERY_PRECONDITION_FAILED"* ]]; then
  ok "case 5 (AC-NEG4-rate-limit): same source 24h → fail-stop + PRECONDITION_FAILED"
else
  bad "case 5 (AC-NEG4-rate-limit): expected non-zero + PRECONDITION_FAILED, got rc=$RC5 stderr='$ERR5'"
fi

# ------------------------------------------------------------------ case 6: AC-NEG4-forged: forged friction + actual >= cap

C6_DIR="$WORKDIR/case6"
setup_mock_source "$C6_DIR" "DP-246"
C6_HASH=$(compute_refinement_hash "$C6_DIR")
C6_LEDGER="$C6_DIR/20260527-000000-ledger.json"
# Many forged friction entries but stage_events shows 3 actual back-edges (>= cap)
make_ledger "$C6_LEDGER" "loop_cap_reached" 5 5 3 "$C6_DIR" "$C6_HASH"

RC6=0
ERR6=""
ERR6="$(bash "$RECOVERY_HELPER" --source-id DP-246 --prior-ledger "$C6_LEDGER" --repo "$ROOT_DIR" 2>&1)" || RC6=$?
if [[ "$RC6" != "0" && "$ERR6" == *"POLARIS_COUNTER_RECOVERY_PRECONDITION_FAILED"* ]]; then
  ok "case 6 (AC-NEG4-forged): forged friction + actual>=cap → still fail-stop"
else
  bad "case 6 (AC-NEG4-forged): expected non-zero + PRECONDITION_FAILED, got rc=$RC6 stderr='$ERR6'"
fi

# ------------------------------------------------------------------
echo ""
echo "DP-246 T3 counter race-recovery selftest: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
echo "PASS: auto-pass-counter-race-recovery selftest"
