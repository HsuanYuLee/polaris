#!/usr/bin/env bash
# Purpose: DP-421 T2 selftest for scripts/backfill-refinement-verification-strategy.sh.
#   Asserts the deterministic verification_strategy corpus backfill (AC2 / AC-NEG2):
#     - three AC2 fixture types infer the correct mode: kind=verification (V) and kind=V both =>
#       source_level_v_required; empty tasks[] => per_task_self_verify; plus a T-task-with-
#       verify_command => per_task_self_verify.
#     - single-key addition (AC-NEG2): jq 'del(.verification_strategy)' equals before vs after.
#     - backfilled provenance present (authority + backfilled_by=DP-421).
#     - a T-only source whose T tasks lack per-task verify_command (and has no V task) is classified
#       needs_review and left UNWRITTEN — the migration never writes a delegate-invalid strategy
#       (it reuses the canonical validate-verification-strategy.sh as the single shape authority).
#     - under the T1 DRAINING-LEDGER-ENROLLMENT model: after draining the mechanically-inferable
#       corpus the T1 gate reports 0 NEW/unenrolled non-conformant (exit 0); a residual un-inferable
#       file is NEW/unenrolled and fail-closes until --seed-baseline enrolls it, after which it is
#       recorded in the draining ledger (remaining>0, target_remaining=0, draining=true,
#       waiver=false, migration_owner) as debt draining toward zero — not a permanent waiver.
# Inputs: none (self-contained fixtures under a temp dir). Outputs: exit 0 all pass, exit 1 any fail.
set -uo pipefail

# Hermetic: fixtures are self-contained; do not inherit a live workspace root.
unset POLARIS_WORKSPACE_ROOT POLARIS_SPECS_ROOT 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BACKFILL="$REPO_ROOT/scripts/backfill-refinement-verification-strategy.sh"
GATE="$REPO_ROOT/scripts/validate-artifact-contract-conformance.sh"
DELEGATE="$REPO_ROOT/scripts/validate-verification-strategy.sh"

PASS=0
FAIL=0
ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SPECS_REL="docs-manager/src/content/docs/specs"

mk_refinement() { # <workspace_root> <rel_container> <tasks_json>
  local wsroot="$1" container="$2" tasks="$3"
  local dir="$wsroot/$SPECS_REL/$container"
  mkdir -p "$dir"
  python3 - "$dir/refinement.json" "$tasks" <<'PY'
import json, sys
path, tasks = sys.argv[1], sys.argv[2]
data = {"epic": "FIX-1", "source": {"type": "dp", "id": "FIX-1"}, "tasks": json.loads(tasks)}
open(path, "w", encoding="utf-8").write(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
PY
}

strategy_of() { python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])).get("verification_strategy")))' "$1"; }
mode_of()     { python3 -c 'import json,sys; s=json.load(open(sys.argv[1])).get("verification_strategy") or {}; print(s.get("mode"))' "$1"; }

# ============================================================================
# Conformable corpus (should all end up conformant + drive the gate green).
# ============================================================================
WS="$TMP/conformable"
mk_refinement "$WS" "design-plans/FIX-A" '[{"id":"V1","kind":"verification"},{"id":"T1","kind":"implementation"}]'   # F1 kind=verification
mk_refinement "$WS" "design-plans/FIX-B" '[{"id":"V1","kind":"V"}]'                                                  # F2 kind=V
mk_refinement "$WS" "design-plans/FIX-C" '[]'                                                                        # F3 empty tasks[]
mk_refinement "$WS" "design-plans/FIX-D" '[{"id":"T1","kind":"implementation","verification":{"verify_command":"echo ok"}}]'  # F4 T + verify_command
mk_refinement "$WS" "design-plans/archive/FIX-E" '[{"id":"V1","kind":"V"}]'                                          # F5 terminal (archive)

F1="$WS/$SPECS_REL/design-plans/FIX-A/refinement.json"
cp "$F1" "$TMP/FIX-A.orig.json"

# --- report mode: no writes, correct inference surfaced ---
REPORT="$(bash "$BACKFILL" --root "$WS" --mode report 2>&1)"
{ grep -q 'applied=5' <<<"$REPORT" && grep -q 'already_ok=0' <<<"$REPORT" && grep -q 'needs_review=0' <<<"$REPORT"; } \
  && ok "report: 5 conformable inferences, 0 needs_review, no writes" \
  || bad "report unexpected counts: $REPORT"
[[ "$(strategy_of "$F1")" == "null" ]] \
  && ok "report mode does not write (verification_strategy still absent)" \
  || bad "report mode wrote verification_strategy"

# --- apply mode ---
APPLY="$(bash "$BACKFILL" --root "$WS" --mode apply 2>&1)"
{ grep -q 'written=5' <<<"$APPLY" && grep -q 'needs_review=0' <<<"$APPLY"; } \
  && ok "apply: wrote 5 files (4 active + 1 archive), 0 needs_review" \
  || bad "apply unexpected: $APPLY"

# --- correct mode inference per AC2 fixture types ---
[[ "$(mode_of "$F1")" == "source_level_v_required" ]] && ok "F1 kind=verification => source_level_v_required" || bad "F1 mode=$(mode_of "$F1")"
[[ "$(mode_of "$WS/$SPECS_REL/design-plans/FIX-B/refinement.json")" == "source_level_v_required" ]] && ok "F2 kind=V => source_level_v_required" || bad "F2 wrong mode"
[[ "$(mode_of "$WS/$SPECS_REL/design-plans/FIX-C/refinement.json")" == "per_task_self_verify" ]] && ok "F3 empty tasks[] => per_task_self_verify" || bad "F3 wrong mode"
[[ "$(mode_of "$WS/$SPECS_REL/design-plans/FIX-D/refinement.json")" == "per_task_self_verify" ]] && ok "F4 T+verify_command => per_task_self_verify" || bad "F4 wrong mode"

# --- AC-NEG2: single-key addition (jq del(.verification_strategy) equal before vs after) ---
before="$(jq -S 'del(.verification_strategy)' "$TMP/FIX-A.orig.json")"
after="$(jq -S 'del(.verification_strategy)' "$F1")"
[[ "$before" == "$after" ]] \
  && ok "AC-NEG2: single-key addition (all other keys byte-equal via jq del)" \
  || bad "AC-NEG2: non-verification_strategy keys changed"

# --- AC-NEG2: provenance present ---
python3 - "$F1" <<'PY' && ok "provenance present (authority + backfilled_by=DP-421 + reason)" || bad "provenance missing"
import json,sys
s=json.load(open(sys.argv[1]))["verification_strategy"]
assert s.get("backfilled_by")=="DP-421", s.get("backfilled_by")
assert isinstance(s.get("authority"),str) and s["authority"].strip()
assert isinstance(s.get("reason"),str) and s["reason"].strip()
PY

# --- written strategies actually pass the canonical delegate (conformant by construction) ---
bash "$DELEGATE" "$F1" >/dev/null 2>&1 \
  && ok "written strategy passes canonical validate-verification-strategy.sh" \
  || bad "written strategy rejected by delegate"

# --- idempotency: re-apply writes nothing more ---
APPLY2="$(bash "$BACKFILL" --root "$WS" --mode apply 2>&1)"
grep -q 'written=0' <<<"$APPLY2" && ok "re-apply idempotent (written=0)" || bad "re-apply not idempotent: $APPLY2"

# ============================================================================
# needs_review: T-only source whose T tasks lack verify_command and has NO V task.
# per_task_self_verify inference is delegate-INVALID => classified needs_review, left unwritten.
# ============================================================================
WR="$TMP/needs_review"
mk_refinement "$WR" "design-plans/FIX-F" '[{"id":"T1","kind":"implementation","verification":{"method":"unit_test","detail":"x"}}]'
FF="$WR/$SPECS_REL/design-plans/FIX-F/refinement.json"
NR="$(bash "$BACKFILL" --root "$WR" --mode apply 2>&1)"
{ grep -q 'needs_review=1' <<<"$NR" && grep -q 'written=0' <<<"$NR"; } \
  && ok "T-only w/o verify_command => needs_review, not written" \
  || bad "needs_review case unexpected: $NR"
[[ "$(strategy_of "$FF")" == "null" ]] \
  && ok "needs_review file left unwritten (no delegate-invalid strategy written)" \
  || bad "needs_review file was written a strategy"
# check mode fails while needs_review remains
if bash "$BACKFILL" --root "$WR" --mode check >/dev/null 2>&1; then
  bad "check mode should exit non-zero while needs_review remains"
else
  ok "check mode exits non-zero while needs_review remains"
fi
# check mode passes on fully-drained conformable corpus
if bash "$BACKFILL" --root "$WS" --mode check >/dev/null 2>&1; then
  ok "check mode passes on fully-drained corpus"
else
  bad "check mode failed on drained corpus"
fi

# ============================================================================
# T1 conformance gate outcome under the DRAINING-LEDGER-ENROLLMENT model (not namespace).
# The T1 gate classifies new-vs-existing by ledger enrollment: --seed-baseline enrolls every
# currently-non-conformant artifact (any namespace) as pre-existing draining debt; thereafter
# enrolled debt passes (draining toward 0) while NEW (unenrolled) non-conformant fail-closed.
# The post-backfill assertion this migration owes is therefore: after draining the mechanically-
# inferable corpus, the T1 gate reports 0 NEW/unenrolled non-conformant (exit 0), and the residual
# files the backfill cannot mechanically infer are ENROLLED in the draining ledger
# (remaining>0, target_remaining=0, draining=true, waiver=false, migration_owner) — recorded debt,
# not a permanent waiver.
# ============================================================================
REG="$TMP/registry.json"
cat > "$REG" <<REGEOF
{
  "schema_version": "1.0",
  "artifact_classes": [
    {
      "class": "refinement-json-verification-strategy",
      "enumerate_glob": "$SPECS_REL/**/refinement.json",
      "required_field": "verification_strategy",
      "required_since": "DP-364",
      "delegate_validator": "$DELEGATE",
      "migration_owner": "DP-421-T2"
    }
  ]
}
REGEOF

# --- Fully-inferable corpus (WS): backfill drains it to zero, so the steady-state gate PASSes with
#     0 new/unenrolled and 0 draining, and creates no ledger (nothing to enroll). ---
LEDGER_WS="$TMP/ledger-ws"
GATE_OUT="$(bash "$GATE" --registry "$REG" --scan-root "$WS" --ledger-dir "$LEDGER_WS" 2>&1)"; GRC=$?
{ [[ $GRC -eq 0 ]] && grep -q '0 new/unenrolled non-conformant' <<<"$GATE_OUT"; } \
  && ok "T1 gate PASS on fully-drained corpus (0 new/unenrolled non-conformant)" \
  || bad "gate not green on drained corpus (rc=$GRC): $GATE_OUT"
[[ ! -f "$LEDGER_WS/refinement-json-verification-strategy.json" ]] \
  && ok "no ledger created when nothing is non-conformant (steady-state does not seed)" \
  || bad "steady-state gate created a ledger on a fully-conformant corpus"

# --- Mixed corpus (MX): mechanically-inferable files + residual un-inferable files, mirroring the
#     real corpus (307 drained + 16 enrolled). backfill drains the inferable; the residual
#     un-inferable (T-only, no verify_command, no V => needs_review, left unwritten) stays
#     non-conformant and must be ENROLLED as draining debt, not fail the gate forever. ---
MX="$TMP/mixed"
mk_refinement "$MX" "design-plans/MX-A" '[{"id":"V1","kind":"V"}]'                                                     # inferable -> source_level_v_required
mk_refinement "$MX" "design-plans/MX-B" '[]'                                                                           # inferable -> per_task_self_verify
mk_refinement "$MX" "design-plans/MX-R" '[{"id":"T1","kind":"implementation","verification":{"method":"unit_test","detail":"x"}}]'  # un-inferable -> needs_review
MXR="$MX/$SPECS_REL/design-plans/MX-R/refinement.json"
bash "$BACKFILL" --root "$MX" --mode apply >/dev/null 2>&1
[[ "$(strategy_of "$MXR")" == "null" ]] \
  && ok "residual un-inferable file left unwritten by backfill (needs_review)" \
  || bad "un-inferable file unexpectedly backfilled"

LEDGER_MX="$TMP/ledger-mx"
# Pre-seed: the residual is NEW/unenrolled => steady-state gate fail-closed (exit 2).
if bash "$GATE" --registry "$REG" --scan-root "$MX" --ledger-dir "$LEDGER_MX" >/dev/null 2>&1; then
  bad "gate should fail-closed on un-inferable residual before baseline enrollment"
else
  ok "T1 gate fail-closed on NEW/unenrolled residual before baseline seed"
fi
[[ ! -f "$LEDGER_MX/refinement-json-verification-strategy.json" ]] \
  && ok "steady-state gate never writes a NEW violation into the ledger" \
  || bad "steady-state gate wrote a ledger entry for a NEW violation"

# Seed baseline: enroll the residual as pre-existing draining debt (the only mode that enrolls).
SEED_OUT="$(bash "$GATE" --registry "$REG" --scan-root "$MX" --ledger-dir "$LEDGER_MX" --seed-baseline 2>&1)"; SRC=$?
{ [[ $SRC -eq 0 ]] && grep -q 'baseline seeded' <<<"$SEED_OUT"; } \
  && ok "--seed-baseline enrolls residual and exits 0" \
  || bad "seed-baseline unexpected (rc=$SRC): $SEED_OUT"

# Post-seed steady-state: enrolled debt passes; gate reports 0 new/unenrolled with draining>0.
GATE_OUT="$(bash "$GATE" --registry "$REG" --scan-root "$MX" --ledger-dir "$LEDGER_MX" 2>&1)"; GRC=$?
{ [[ $GRC -eq 0 ]] && grep -q '0 new/unenrolled non-conformant' <<<"$GATE_OUT"; } \
  && ok "T1 gate PASS after enrollment (0 new/unenrolled; enrolled residual draining)" \
  || bad "gate not green after enrollment (rc=$GRC): $GATE_OUT"

# Ledger shape: enrolled draining debt, target 0, not a permanent waiver.
LF="$LEDGER_MX/refinement-json-verification-strategy.json"
if [[ -f "$LF" ]]; then
  python3 - "$LF" <<'PY' && ok "draining ledger: remaining>0, target=0, draining=true, waiver=false, owner set (recorded debt, not waiver)" || bad "draining ledger shape wrong"
import json, sys
rec = json.load(open(sys.argv[1]))
assert rec.get("remaining", 0) > 0, f"remaining={rec.get('remaining')} (expected >0)"
assert rec.get("target_remaining") == 0, f"target_remaining={rec.get('target_remaining')}"
assert rec.get("draining") is True, f"draining={rec.get('draining')}"
assert rec.get("waiver") is False, f"waiver={rec.get('waiver')}"
assert (rec.get("migration_owner") or "").strip(), "migration_owner empty"
enrolled = rec.get("enrolled_artifacts") or []
assert any(p.endswith("MX-R/refinement.json") for p in enrolled), f"residual not enrolled: {enrolled}"
PY
else
  bad "no draining ledger written after baseline seed of a residual violation"
fi

echo ""
python3 - "$REPO_ROOT/scripts/refinement-consumer-registry.json" <<'PY' \
  && ok "W12 registry binds backfill tasks[] accessors" \
  || bad "W12 registry missing backfill accessor binding"
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
records = {r["path"]: r for r in data.get("consumers", [])}
record = records["scripts/lib/refinement_backfill_verification_strategy.py"]
assert set(record["accessor_vars"]) == {"task"}
assert record["expected_fields"] == {"task": ["id", "kind"]}
PY
echo "backfill-refinement-verification-strategy-selftest: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
