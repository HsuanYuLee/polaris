#!/usr/bin/env bash
# auto-pass-increment-counter-idempotency-selftest.sh — DP-246 T2 idempotency selftest.
#
# Verifies AC2 (happy path + idempotency) and AC-NEG2 (missing --evidence-id fail-stop):
#
#   case 1 (AC2-happy)     : first call increments counter, adds evidence_id
#   case 2 (AC2-duplicate) : same evidence-id -> silent exit 0, counter unchanged
#   case 3 (AC2-diff-id)   : different evidence-id for same transition -> counter increments
#   case 4 (AC-NEG2)       : missing --evidence-id -> exit 1 + stderr POLARIS_COUNTER_EVIDENCE_ID_REQUIRED
#   case 5 (AC-NEG2-env)   : POLARIS_COUNTER_BYPASS=1 does NOT bypass --evidence-id requirement
#   case 6 (AC2-legacy-compat): legacy integer counter shape migrated to object on first call
#   case 7 (AC2-friction)  : 1->2 transition still appends inner_skill_halt_bypass friction
#   case 8 (AC2-duplicate-no-friction): duplicate id on 1->2 transition does NOT double-append friction

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COUNTER_HELPER="$ROOT_DIR/scripts/auto-pass-increment-counter.sh"

WORKDIR="$(mktemp -d -t dp246-counter-idempotency.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); printf 'ok  %s\n' "$*"; }
bad()  { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*" >&2; }

new_ledger() {
  local path="$1"
  cat >"$path" <<JSON
{
  "schema_version": 1,
  "source": {"id": "DP-999", "refinement_hash": "sha256:placeholder"},
  "loop_counters": {},
  "friction_log": []
}
JSON
}

get_counter_count() {
  local ledger="$1"
  local key="$2"
  python3 - "$ledger" "$key" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
v = d.get('loop_counters', {}).get(sys.argv[2])
if v is None:
    print(0)
elif isinstance(v, int):
    print(v)
elif isinstance(v, dict):
    print(v.get('count', 0))
else:
    print(-1)
PY
}

get_evidence_ids() {
  local ledger="$1"
  local key="$2"
  python3 - "$ledger" "$key" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
v = d.get('loop_counters', {}).get(sys.argv[2])
if isinstance(v, dict):
    print(','.join(v.get('evidence_ids', [])))
else:
    print('')
PY
}

count_friction() {
  local ledger="$1"
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(len(d.get('friction_log',[])))" "$ledger"
}

# ------------------------------------------------------------------
# case 1: happy path — first call increments counter, adds evidence_id
# ------------------------------------------------------------------
L1="$WORKDIR/case1.json"
new_ledger "$L1"
bash "$COUNTER_HELPER" "$L1" --transition engineering_to_breakdown \
  --evidence-id "DP-999:engineering->breakdown:1" --stage engineering
C1_CTR=$(get_counter_count "$L1" engineering_to_breakdown)
C1_IDS=$(get_evidence_ids "$L1" engineering_to_breakdown)
if [[ "$C1_CTR" == "1" && "$C1_IDS" == "DP-999:engineering->breakdown:1" ]]; then
  ok "case 1: first call incremented counter=1, evidence_id recorded"
else
  bad "case 1: expected count=1 id='DP-999:engineering->breakdown:1', got count=$C1_CTR ids='$C1_IDS'"
fi

# ------------------------------------------------------------------
# case 2: duplicate evidence-id -> silent exit 0, counter unchanged
# ------------------------------------------------------------------
L2="$WORKDIR/case2.json"
new_ledger "$L2"
bash "$COUNTER_HELPER" "$L2" --transition engineering_to_breakdown \
  --evidence-id "DP-999:engineering->breakdown:1"
# second call with same id — must be idempotent
bash "$COUNTER_HELPER" "$L2" --transition engineering_to_breakdown \
  --evidence-id "DP-999:engineering->breakdown:1"
C2_CTR=$(get_counter_count "$L2" engineering_to_breakdown)
C2_IDS=$(get_evidence_ids "$L2" engineering_to_breakdown)
if [[ "$C2_CTR" == "1" && "$C2_IDS" == "DP-999:engineering->breakdown:1" ]]; then
  ok "case 2: duplicate evidence-id -> silent no-op, counter stays 1"
else
  bad "case 2: expected count=1 ids single entry, got count=$C2_CTR ids='$C2_IDS'"
fi

# ------------------------------------------------------------------
# case 3: different evidence-id -> counter increments
# ------------------------------------------------------------------
L3="$WORKDIR/case3.json"
new_ledger "$L3"
bash "$COUNTER_HELPER" "$L3" --transition engineering_to_breakdown \
  --evidence-id "DP-999:engineering->breakdown:1"
bash "$COUNTER_HELPER" "$L3" --transition engineering_to_breakdown \
  --evidence-id "DP-999:engineering->breakdown:2"
C3_CTR=$(get_counter_count "$L3" engineering_to_breakdown)
if [[ "$C3_CTR" == "2" ]]; then
  ok "case 3: two different evidence-ids -> counter=2"
else
  bad "case 3: expected count=2, got count=$C3_CTR"
fi

# ------------------------------------------------------------------
# case 4: missing --evidence-id -> exit 1 + POLARIS_COUNTER_EVIDENCE_ID_REQUIRED
# ------------------------------------------------------------------
L4="$WORKDIR/case4.json"
new_ledger "$L4"
RC4=0
ERR4=""
ERR4="$(bash "$COUNTER_HELPER" "$L4" --transition engineering_to_breakdown 2>&1)" || RC4=$?
if [[ "$RC4" != "0" && "$ERR4" == *"POLARIS_COUNTER_EVIDENCE_ID_REQUIRED"* ]]; then
  ok "case 4: missing --evidence-id -> exit $RC4 + POLARIS_COUNTER_EVIDENCE_ID_REQUIRED"
else
  bad "case 4: expected non-zero exit + POLARIS_COUNTER_EVIDENCE_ID_REQUIRED, got rc=$RC4 stderr='$ERR4'"
fi

# ------------------------------------------------------------------
# case 5: POLARIS_COUNTER_BYPASS=1 does NOT bypass --evidence-id requirement
# ------------------------------------------------------------------
L5="$WORKDIR/case5.json"
new_ledger "$L5"
RC5=0
ERR5=""
ERR5="$(POLARIS_COUNTER_BYPASS=1 bash "$COUNTER_HELPER" "$L5" \
  --transition engineering_to_breakdown 2>&1)" || RC5=$?
if [[ "$RC5" != "0" && "$ERR5" == *"POLARIS_COUNTER_EVIDENCE_ID_REQUIRED"* ]]; then
  ok "case 5: POLARIS_COUNTER_BYPASS=1 does NOT bypass missing --evidence-id"
else
  bad "case 5: expected fail-stop even with bypass env, got rc=$RC5 stderr='$ERR5'"
fi

# ------------------------------------------------------------------
# case 6: legacy integer counter shape migrated on first call
# ------------------------------------------------------------------
L6="$WORKDIR/case6.json"
python3 - "$L6" <<'PY'
import json, sys
from pathlib import Path
ledger = {
    'schema_version': 1,
    'source': {'id': 'DP-999', 'refinement_hash': 'sha256:placeholder'},
    'loop_counters': {'engineering_to_breakdown': 1},
    'friction_log': []
}
Path(sys.argv[1]).write_text(json.dumps(ledger, indent=2) + '\n', encoding='utf-8')
PY
bash "$COUNTER_HELPER" "$L6" --transition engineering_to_breakdown \
  --evidence-id "DP-999:engineering->breakdown:migrated"
C6_CTR=$(get_counter_count "$L6" engineering_to_breakdown)
C6_IDS=$(get_evidence_ids "$L6" engineering_to_breakdown)
if [[ "$C6_CTR" == "2" && "$C6_IDS" == "DP-999:engineering->breakdown:migrated" ]]; then
  ok "case 6: legacy int=1 migrated to object, counter incremented to 2"
else
  bad "case 6: expected count=2 ids='DP-999:engineering->breakdown:migrated', got count=$C6_CTR ids='$C6_IDS'"
fi

# ------------------------------------------------------------------
# case 7: 1->2 transition still appends inner_skill_halt_bypass friction
# ------------------------------------------------------------------
L7="$WORKDIR/case7.json"
new_ledger "$L7"
bash "$COUNTER_HELPER" "$L7" --transition engineering_to_breakdown \
  --evidence-id "DP-999:engineering->breakdown:1" --stage engineering
bash "$COUNTER_HELPER" "$L7" --transition engineering_to_breakdown \
  --evidence-id "DP-999:engineering->breakdown:2" --stage engineering
C7_CTR=$(get_counter_count "$L7" engineering_to_breakdown)
C7_FRICTION=$(count_friction "$L7")
if [[ "$C7_CTR" == "2" && "$C7_FRICTION" == "1" ]]; then
  ok "case 7: 1->2 transition appended inner_skill_halt_bypass (counter=2, friction=1)"
else
  bad "case 7: expected count=2 friction=1, got count=$C7_CTR friction=$C7_FRICTION"
fi

# ------------------------------------------------------------------
# case 8: duplicate id on 1->2 boundary does NOT double-append friction
# ------------------------------------------------------------------
L8="$WORKDIR/case8.json"
new_ledger "$L8"
bash "$COUNTER_HELPER" "$L8" --transition engineering_to_breakdown \
  --evidence-id "DP-999:engineering->breakdown:1" --stage engineering
bash "$COUNTER_HELPER" "$L8" --transition engineering_to_breakdown \
  --evidence-id "DP-999:engineering->breakdown:2" --stage engineering
# Duplicate id that was already at count=2 boundary — must not increment or append friction
bash "$COUNTER_HELPER" "$L8" --transition engineering_to_breakdown \
  --evidence-id "DP-999:engineering->breakdown:2" --stage engineering
C8_CTR=$(get_counter_count "$L8" engineering_to_breakdown)
C8_FRICTION=$(count_friction "$L8")
if [[ "$C8_CTR" == "2" && "$C8_FRICTION" == "1" ]]; then
  ok "case 8: duplicate id on 1->2 boundary does not double-append friction (count=2, friction=1)"
else
  bad "case 8: expected count=2 friction=1 after duplicate, got count=$C8_CTR friction=$C8_FRICTION"
fi

# ------------------------------------------------------------------
echo ""
echo "DP-246 T2 counter idempotency selftest: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
echo "PASS: auto-pass-increment-counter-idempotency selftest"
