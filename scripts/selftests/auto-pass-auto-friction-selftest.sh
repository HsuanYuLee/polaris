#!/usr/bin/env bash
# auto-pass-auto-friction-selftest.sh — DP-220 deterministic auto-friction triggers.
#
# Verifies the 5 friction triggers introduced by DP-220 plus the NOOP boundary:
#
#   case 1  (AC1)     : gate-hook-adapter exit 2 -> deterministic_gap friction appended
#   case 2  (AC2)     : pre-write-language-policy BYPASS=1 -> env_bypass friction appended
#   case 3  (AC2-neg) : pre-write-language-policy POLARIS_PRODUCER -> NO friction (carve-out)
#   case 4  (AC3)     : auto-pass-probe UNKNOWN -> deterministic_gap friction appended
#   case 5  (AC3-neg) : auto-pass-probe PASS -> NO friction (only UNKNOWN triggers)
#   case 6  (AC4)     : auto-pass-increment-counter 1->2 -> inner_skill_halt_bypass appended
#   case 7  (AC4-a)   : auto-pass-increment-counter 0->1 -> counter updated, NO friction
#   case 8  (AC4-b)   : auto-pass-increment-counter 2->3 -> counter updated, NO additional friction
#   case 9  (AC-NF1)  : AUTO_PASS_LEDGER_PATH unset -> all triggers NOOP silently
#   case 10 (AC-NF2)  : AUTO_PASS_LEDGER_PATH set but ledger missing -> NOOP silently
#   case 11 (AC-NEG1) : corrupt ledger JSON -> helper exit 1 (validation works)
#   case 12 (AC-NF3)  : full selftest wall-clock < 10s

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FRICTION_HELPER="$ROOT_DIR/scripts/append-auto-pass-friction.sh"
COUNTER_HELPER="$ROOT_DIR/scripts/auto-pass-increment-counter.sh"
PROBE="$ROOT_DIR/scripts/auto-pass-probe.sh"
GATE_ADAPTER="$ROOT_DIR/scripts/gate-hook-adapter.sh"
LANGUAGE_HOOK="$ROOT_DIR/.claude/hooks/pre-write-language-policy.sh"

WORKDIR="$(mktemp -d -t dp220-auto-friction.XXXXXX)"
WORKDIR="$(cd "$WORKDIR" && pwd -P)"
trap 'rm -rf "$WORKDIR"' EXIT

START_TS=$(date +%s)
PASS=0
FAIL=0

note() { printf '  - %s\n' "$*"; }
ok()   { PASS=$((PASS + 1)); printf '✓ %s\n' "$*"; }
bad()  { FAIL=$((FAIL + 1)); printf '✗ %s\n' "$*" >&2; }

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

count_friction() {
  local ledger="$1"
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(len(d.get('friction_log',[])))" "$ledger"
}

last_kind() {
  local ledger="$1"
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); fl=d.get('friction_log',[]); print(fl[-1]['friction_kind'] if fl else 'NONE')" "$ledger"
}

get_counter() {
  local ledger="$1"
  local key="$2"
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('loop_counters',{}).get(sys.argv[2],0))" "$ledger" "$key"
}

# ------------------------------------------------------------------
# case 1: gate-hook-adapter exit 2 -> deterministic_gap friction
# ------------------------------------------------------------------
LEDGER1="$WORKDIR/case1-ledger.json"
new_ledger "$LEDGER1"
FAKE_GATE="$WORKDIR/fake-gate-exit2.sh"
cat >"$FAKE_GATE" <<'GATE'
#!/usr/bin/env bash
echo "fake gate failure" >&2
exit 2
GATE
chmod +x "$FAKE_GATE"

FAKE_REPO="$WORKDIR/case1-repo"
mkdir -p "$FAKE_REPO"
git -C "$FAKE_REPO" init -q
git -C "$FAKE_REPO" config user.email selftest@example.com
git -C "$FAKE_REPO" config user.name selftest
echo init >"$FAKE_REPO/README.md"
git -C "$FAKE_REPO" add -A
git -C "$FAKE_REPO" -c commit.gpgsign=false commit -q -m init

AUTO_PASS_LEDGER_PATH="$LEDGER1" POLARIS_TASK_ID="DP-999-T1" GATE_PROJECT_DIR="$FAKE_REPO" \
  POLARIS_GATE_FAILURE_LEDGER_DIR="$WORKDIR/case1-failures" \
  bash "$GATE_ADAPTER" "$FAKE_GATE" "dummy command" >/dev/null 2>&1 || true

C1_KIND=$(last_kind "$LEDGER1")
C1_COUNT=$(count_friction "$LEDGER1")
if [[ "$C1_KIND" == "deterministic_gap" && "$C1_COUNT" == "1" ]]; then
  ok "case 1: gate-hook-adapter exit 2 appended deterministic_gap (count=1)"
else
  bad "case 1: expected deterministic_gap/count=1, got kind=$C1_KIND count=$C1_COUNT"
fi

# ------------------------------------------------------------------
# case 2: pre-write-language-policy BYPASS=1 -> env_bypass friction
# ------------------------------------------------------------------
LEDGER2="$WORKDIR/case2-ledger.json"
new_ledger "$LEDGER2"
PAYLOAD2='{"tool_name":"Write","tool_input":{"file_path":"docs-manager/src/content/docs/specs/example.md","content":"hello"}}'
AUTO_PASS_LEDGER_PATH="$LEDGER2" POLARIS_LANGUAGE_POLICY_BYPASS=1 \
  bash -c "printf '%s' '$PAYLOAD2' | bash \"$LANGUAGE_HOOK\"" >/dev/null 2>&1 || true
C2_KIND=$(last_kind "$LEDGER2")
C2_COUNT=$(count_friction "$LEDGER2")
if [[ "$C2_KIND" == "env_bypass" && "$C2_COUNT" == "1" ]]; then
  ok "case 2: language-policy BYPASS=1 appended env_bypass (count=1)"
else
  bad "case 2: expected env_bypass/count=1, got kind=$C2_KIND count=$C2_COUNT"
fi

# ------------------------------------------------------------------
# case 3: POLARIS_PRODUCER -> NO friction (producer carve-out exits before bypass branch)
# ------------------------------------------------------------------
LEDGER3="$WORKDIR/case3-ledger.json"
new_ledger "$LEDGER3"
AUTO_PASS_LEDGER_PATH="$LEDGER3" POLARIS_PRODUCER="auto-pass" \
  bash -c "printf '%s' '$PAYLOAD2' | bash \"$LANGUAGE_HOOK\"" >/dev/null 2>&1 || true
C3_COUNT=$(count_friction "$LEDGER3")
if [[ "$C3_COUNT" == "0" ]]; then
  ok "case 3: POLARIS_PRODUCER carve-out emitted NO friction"
else
  bad "case 3: expected count=0 (producer carve-out), got count=$C3_COUNT"
fi

# ------------------------------------------------------------------
# case 4: auto-pass-probe UNKNOWN -> deterministic_gap friction
# ------------------------------------------------------------------
LEDGER4="$WORKDIR/case4-ledger.json"
new_ledger "$LEDGER4"
# DP-229 D27: spec-source-resolver source_kind enum 通用化後，非 DP key 回 BLOCKED
# 而非 UNKNOWN（BLOCKED 不觸發 friction，由 case 5 涵蓋）。改用 engineering 階段
# 缺 --head-sha 的 deterministic UNKNOWN 路徑作 fixture：probe 一律輸出
# status=UNKNOWN reason="engineering probe requires --head-sha"，進而觸發
# deterministic_gap friction。
AUTO_PASS_LEDGER_PATH="$LEDGER4" \
  bash "$PROBE" --repo "$ROOT_DIR" --stage engineering --source-id "ANY" \
  --work-item-id "TASK-1" --ledger "$LEDGER4" >/dev/null 2>&1 || true
C4_KIND=$(last_kind "$LEDGER4")
C4_COUNT=$(count_friction "$LEDGER4")
if [[ "$C4_KIND" == "deterministic_gap" && "$C4_COUNT" == "1" ]]; then
  ok "case 4: probe UNKNOWN appended deterministic_gap (count=1)"
else
  bad "case 4: expected deterministic_gap/count=1, got kind=$C4_KIND count=$C4_COUNT"
fi

# ------------------------------------------------------------------
# case 5: auto-pass-probe PASS -> NO friction
# ------------------------------------------------------------------
LEDGER5="$WORKDIR/case5-ledger.json"
new_ledger "$LEDGER5"
# Use a known LOCKED DP container if available; otherwise just confirm that
# probing a missing container emits BLOCKED (not UNKNOWN) and does NOT trigger
# the friction helper. BLOCKED is distinct from UNKNOWN and must not emit.
AUTO_PASS_LEDGER_PATH="$LEDGER5" \
  bash "$PROBE" --repo "$ROOT_DIR" --stage source --source-id "DP-99999" \
  --ledger "$LEDGER5" >/dev/null 2>&1 || true
C5_COUNT=$(count_friction "$LEDGER5")
if [[ "$C5_COUNT" == "0" ]]; then
  ok "case 5: probe BLOCKED (non-UNKNOWN) emitted NO friction"
else
  bad "case 5: expected count=0 for BLOCKED probe, got count=$C5_COUNT"
fi

# ------------------------------------------------------------------
# case 6: counter 1->2 transition -> inner_skill_halt_bypass friction
# ------------------------------------------------------------------
LEDGER6="$WORKDIR/case6-ledger.json"
new_ledger "$LEDGER6"
bash "$COUNTER_HELPER" "$LEDGER6" --transition engineering_to_breakdown --stage engineering >/dev/null
bash "$COUNTER_HELPER" "$LEDGER6" --transition engineering_to_breakdown --stage engineering >/dev/null
C6_KIND=$(last_kind "$LEDGER6")
C6_COUNT=$(count_friction "$LEDGER6")
C6_CTR=$(get_counter "$LEDGER6" engineering_to_breakdown)
if [[ "$C6_KIND" == "inner_skill_halt_bypass" && "$C6_COUNT" == "1" && "$C6_CTR" == "2" ]]; then
  ok "case 6: counter 1->2 appended inner_skill_halt_bypass (counter=2, friction=1)"
else
  bad "case 6: expected kind=inner_skill_halt_bypass count=1 counter=2, got kind=$C6_KIND count=$C6_COUNT counter=$C6_CTR"
fi

# ------------------------------------------------------------------
# case 7: counter 0->1 -> NO friction yet (only 1->2 emits)
# ------------------------------------------------------------------
LEDGER7="$WORKDIR/case7-ledger.json"
new_ledger "$LEDGER7"
bash "$COUNTER_HELPER" "$LEDGER7" --transition breakdown_to_refinement_inbox --stage breakdown >/dev/null
C7_COUNT=$(count_friction "$LEDGER7")
C7_CTR=$(get_counter "$LEDGER7" breakdown_to_refinement_inbox)
if [[ "$C7_COUNT" == "0" && "$C7_CTR" == "1" ]]; then
  ok "case 7: counter 0->1 updated counter only (no friction)"
else
  bad "case 7: expected count=0 counter=1, got count=$C7_COUNT counter=$C7_CTR"
fi

# ------------------------------------------------------------------
# case 8: counter 2->3 -> still 1 friction total (only one 1->2 transition)
# ------------------------------------------------------------------
LEDGER8="$WORKDIR/case8-ledger.json"
new_ledger "$LEDGER8"
bash "$COUNTER_HELPER" "$LEDGER8" --transition engineering_to_breakdown --stage engineering >/dev/null  # 0->1
bash "$COUNTER_HELPER" "$LEDGER8" --transition engineering_to_breakdown --stage engineering >/dev/null  # 1->2 (emits)
bash "$COUNTER_HELPER" "$LEDGER8" --transition engineering_to_breakdown --stage engineering >/dev/null  # 2->3 (no emit)
C8_COUNT=$(count_friction "$LEDGER8")
C8_CTR=$(get_counter "$LEDGER8" engineering_to_breakdown)
if [[ "$C8_COUNT" == "1" && "$C8_CTR" == "3" ]]; then
  ok "case 8: counter 2->3 did not append additional friction (counter=3, friction=1)"
else
  bad "case 8: expected count=1 counter=3, got count=$C8_COUNT counter=$C8_CTR"
fi

# ------------------------------------------------------------------
# case 9: AUTO_PASS_LEDGER_PATH unset -> NOOP everywhere
# ------------------------------------------------------------------
unset AUTO_PASS_LEDGER_PATH || true
SET9=$(env | grep -c '^AUTO_PASS_LEDGER_PATH=' || true)
RC9=0
bash -c "printf '%s' '$PAYLOAD2' | POLARIS_LANGUAGE_POLICY_BYPASS=1 bash \"$LANGUAGE_HOOK\"" >/dev/null 2>&1 || RC9=$?
bash "$PROBE" --repo "$ROOT_DIR" --stage source --source-id "ZZ-8888" >/dev/null 2>&1 || true
if [[ "$SET9" == "0" && "$RC9" == "0" ]]; then
  ok "case 9: AUTO_PASS_LEDGER_PATH unset -> triggers NOOP (no error)"
else
  bad "case 9: AUTO_PASS_LEDGER_PATH unset NOOP path failed (set=$SET9 rc=$RC9)"
fi

# ------------------------------------------------------------------
# case 10: AUTO_PASS_LEDGER_PATH set but ledger missing -> NOOP
# ------------------------------------------------------------------
MISSING="$WORKDIR/does-not-exist.json"
RC10=0
AUTO_PASS_LEDGER_PATH="$MISSING" bash "$FRICTION_HELPER" "$MISSING" \
  --stage engineering --kind other --summary "test missing ledger" >/dev/null 2>&1 || RC10=$?
if [[ "$RC10" == "0" && ! -f "$MISSING" ]]; then
  ok "case 10: missing ledger -> helper exit 0 NOOP, did not create file"
else
  bad "case 10: expected NOOP exit 0 + no file, got rc=$RC10 file_exists=$([[ -f "$MISSING" ]] && echo yes || echo no)"
fi

# ------------------------------------------------------------------
# case 11: corrupt ledger JSON -> helper exit non-zero (validation works)
# ------------------------------------------------------------------
LEDGER11="$WORKDIR/case11-ledger.json"
echo "not json {" >"$LEDGER11"
RC11=0
bash "$FRICTION_HELPER" "$LEDGER11" --stage engineering --kind other --summary "corrupt" >/dev/null 2>&1 || RC11=$?
if [[ "$RC11" != "0" ]]; then
  ok "case 11: corrupt ledger JSON -> helper exit $RC11 (validation works)"
else
  bad "case 11: expected non-zero exit for corrupt ledger, got rc=$RC11"
fi

# ------------------------------------------------------------------
# case 12: wall-clock < 10s
# ------------------------------------------------------------------
END_TS=$(date +%s)
ELAPSED=$((END_TS - START_TS))
if [[ "$ELAPSED" -lt 10 ]]; then
  ok "case 12: wall-clock ${ELAPSED}s < 10s"
else
  bad "case 12: wall-clock ${ELAPSED}s >= 10s (too slow)"
fi

# ------------------------------------------------------------------
echo ""
echo "DP-220 auto-friction selftest: $PASS passed, $FAIL failed (elapsed ${ELAPSED}s)"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
