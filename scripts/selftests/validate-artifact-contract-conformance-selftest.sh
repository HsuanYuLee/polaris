#!/usr/bin/env bash
# Purpose: DP-421 T1 selftest for scripts/validate-artifact-contract-conformance.sh.
#   Asserts the generic, registry-driven artifact-contract-conformance gate whose new-vs-existing
#   classification is DRAINING-LEDGER-ENROLLMENT based (NOT namespace based) — because
#   docs-manager/**/specs/** is gitignored so git base-diff cannot distinguish new from existing:
#     - conformant corpus => PASS, and the registry-declared delegate validator IS invoked
#       (proves registry-driven delegation, not a hardcoded classifier).
#     - unenrolled non-conformant (missing required field OR delegate shape-drift) => fail-closed
#       (exit 2 + POLARIS_ARTIFACT_CONTRACT_NON_CONFORMANT, enumerating every violation). A
#       non-conformant artifact that is NOT enrolled in the draining ledger is treated as NEW.
#     - --seed-baseline enrolls EVERY currently-non-conformant artifact (regardless of active vs
#       archive namespace) into the draining ledger as known pre-existing debt (draining=true,
#       waiver=false, target_remaining=0, migration_owner).
#     - enrolled non-conformant (incl. ACTIVE namespace) => OK/draining: the gate does NOT fail on
#       it (this is the DP-421-T1 revision correction — active-namespace pre-existing debt no longer
#       fail-closes just because it is not under /archive/).
#     - AC-NEG1: a NEW (unenrolled) active non-conformant beside enrolled debt still fail-closes and
#       is never laundered into the ledger as a permanent waiver.
#     - draining: when an enrolled artifact later becomes conformant it is removed from the ledger
#       and remaining decreases toward 0 (not a permanent grandfather).
#     - no-second-classifier: the gate neither re-implements an existing per-contract validator's
#       vocabulary nor classifies by /archive/ namespace; it delegates SHAPE to the registry-named
#       validator and classifies new-vs-existing purely by ledger enrollment.
# Inputs: none (self-contained fixtures under a temp dir). Outputs: exit 0 all pass, exit 1 any fail.
set -uo pipefail

# Hermetic: fixtures are self-contained; do not inherit a live workspace root.
unset POLARIS_WORKSPACE_ROOT POLARIS_SPECS_ROOT 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE="$REPO_ROOT/scripts/validate-artifact-contract-conformance.sh"
REGISTRY="$REPO_ROOT/scripts/lib/artifact-contract-registry.json"

PASS=0
FAIL=0
ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- Build a self-contained fixture workspace with a synthetic "test-contract" class. ---
# A stub delegate validator: appends the artifact path to $DELEGATE_LOG (proves the gate invoked
# the registry-declared validator) and exits 2 only when the artifact carries "drift": true
# (simulates shape drift for a field that IS present).
mk_stub_validator() { # <scan_root>
  cat > "$1/stub-validator.sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[[ -n "${DELEGATE_LOG:-}" ]] && printf '%s\n' "$1" >> "$DELEGATE_LOG"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(2 if d.get("drift") else 0)' "$1"
STUB
  chmod +x "$1/stub-validator.sh"
}

# Registry fixture: enrollment model — NO terminal_when namespace rule.
mk_registry() { # <scan_root>
  cat > "$1/registry.json" <<'REG'
{
  "schema_version": "1.0",
  "artifact_classes": [
    {
      "class": "test-contract",
      "description": "selftest synthetic contract",
      "enumerate_glob": "corpus/**/*.json",
      "required_field": "test_field",
      "required_since": "DP-TEST",
      "delegate_validator": "stub-validator.sh",
      "migration_owner": "DP-421-T2"
    }
  ]
}
REG
}

mk_artifact() { # <path> <json>
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" > "$1"
}

run_gate() { OUT="$(bash "$GATE" "$@" 2>&1)"; RC=$?; }

ledger_has() { # <ledger-file> <relpath-substring> -> exit 0 if enrolled_artifacts contains it
  python3 - "$1" "$2" <<'PY'
import json,sys
try:
    d=json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
needle=sys.argv[2]
sys.exit(0 if any(needle in a for a in d.get("enrolled_artifacts",[])) else 1)
PY
}

ledger_remaining() { # <ledger-file> -> prints remaining (or empty)
  python3 - "$1" <<'PY'
import json,sys
try:
    d=json.load(open(sys.argv[1]))
    print(d.get("remaining",""))
except Exception:
    pass
PY
}

# ============================================================================
# Case 1: conformant-only corpus => PASS + delegate invoked (registry-driven delegation).
# ============================================================================
R1="$TMP/case1"; mkdir -p "$R1"
mk_stub_validator "$R1"; mk_registry "$R1"
mk_artifact "$R1/corpus/active/ok.json" '{"test_field": "present"}'
DELEGATE_LOG="$R1/delegate.log" run_gate --registry "$R1/registry.json" --scan-root "$R1" --ledger-dir "$R1/ledger"
{ [[ $RC -eq 0 ]] && grep -q 'PASS' <<<"$OUT"; } \
  && ok "conformant corpus => PASS" || bad "conformant expected 0/PASS got $RC: $OUT"
{ [[ -f "$R1/delegate.log" ]] && grep -q 'ok.json' "$R1/delegate.log"; } \
  && ok "gate invoked registry-declared delegate validator (registry-driven)" \
  || bad "delegate not invoked; log missing ok.json"

# ============================================================================
# Case 2: unenrolled non-conformant (missing required field, no ledger) => fail-closed (NEW).
# ============================================================================
R2="$TMP/case2"; mkdir -p "$R2"
mk_stub_validator "$R2"; mk_registry "$R2"
mk_artifact "$R2/corpus/active/missing.json" '{"other": "x"}'
run_gate --registry "$R2/registry.json" --scan-root "$R2" --ledger-dir "$R2/ledger"
{ [[ $RC -eq 2 ]] && grep -q 'POLARIS_ARTIFACT_CONTRACT_NON_CONFORMANT' <<<"$OUT" \
    && grep -q 'missing.json' <<<"$OUT"; } \
  && ok "unenrolled missing-field (NEW) => exit 2 + marker + enumerate" \
  || bad "unenrolled missing expected exit2+marker got $RC: $OUT"

# ============================================================================
# Case 3: unenrolled shape-drift (field present, delegate exits 2, no ledger) => fail-closed (NEW).
# ============================================================================
R3="$TMP/case3"; mkdir -p "$R3"
mk_stub_validator "$R3"; mk_registry "$R3"
mk_artifact "$R3/corpus/active/drift.json" '{"test_field": "present", "drift": true}'
run_gate --registry "$R3/registry.json" --scan-root "$R3" --ledger-dir "$R3/ledger"
{ [[ $RC -eq 2 ]] && grep -q 'POLARIS_ARTIFACT_CONTRACT_NON_CONFORMANT' <<<"$OUT" \
    && grep -q 'drift.json' <<<"$OUT"; } \
  && ok "unenrolled shape-drift (NEW) => exit 2 + marker" \
  || bad "unenrolled drift expected exit2 got $RC: $OUT"

# ============================================================================
# Case 4: --seed-baseline enrolls EVERY non-conformant (active + archive namespace) as
#   pre-existing debt; a subsequent steady-state run then PASSes (all enrolled => draining).
# ============================================================================
R4="$TMP/case4"; mkdir -p "$R4"
mk_stub_validator "$R4"; mk_registry "$R4"
mk_artifact "$R4/corpus/active/old-active.json" '{"other": "x"}'   # ACTIVE-namespace pre-existing debt
mk_artifact "$R4/corpus/archive/old-arch.json" '{"other": "x"}'    # archive-namespace pre-existing debt
run_gate --seed-baseline --registry "$R4/registry.json" --scan-root "$R4" --ledger-dir "$R4/ledger"
L4="$R4/ledger/test-contract.json"
{ [[ $RC -eq 0 ]] && [[ -f "$L4" ]]; } \
  && ok "--seed-baseline => exit 0 + ledger written" \
  || bad "seed-baseline expected 0 + ledger got $RC (exists=$([[ -f "$L4" ]] && echo y || echo n)): $OUT"
if [[ -f "$L4" ]]; then
  python3 - "$L4" <<'PY' && ok "seed ledger is draining (remaining>=2, waiver=false, target_remaining=0, migration_owner)" \
    || bad "seed ledger not a draining migration record"
import json,sys
d=json.load(open(sys.argv[1]))
assert d.get("remaining",0) >= 2, "remaining must be >=2"
assert d.get("waiver") is False, "waiver must be false (not a permanent waiver)"
assert d.get("draining") is True, "draining must be true"
assert d.get("target_remaining") == 0, "target_remaining must be 0 (drains to zero)"
assert d.get("migration_owner"), "migration_owner required"
PY
  ledger_has "$L4" "old-active.json" \
    && ok "seed enrolled ACTIVE-namespace debt (not just archive)" \
    || bad "seed failed to enroll active-namespace old-active.json"
  ledger_has "$L4" "old-arch.json" \
    && ok "seed enrolled archive-namespace debt" \
    || bad "seed failed to enroll archive-namespace old-arch.json"
fi
# steady-state run over the same enrolled corpus => PASS (all enrolled => draining, none NEW).
run_gate --registry "$R4/registry.json" --scan-root "$R4" --ledger-dir "$R4/ledger"
{ [[ $RC -eq 0 ]] && grep -q 'PASS' <<<"$OUT"; } \
  && ok "steady-state over enrolled debt => PASS (0 NEW)" \
  || bad "steady-state over enrolled expected 0/PASS got $RC: $OUT"

# ============================================================================
# Case 5 (revision correction): an ACTIVE-namespace non-conformant that IS enrolled in the ledger
#   must NOT fail-closed (old namespace classifier would have failed it because it is not /archive/).
# ============================================================================
R5="$TMP/case5"; mkdir -p "$R5"
mk_stub_validator "$R5"; mk_registry "$R5"
mk_artifact "$R5/corpus/active/enrolled-active.json" '{"other": "x"}'
run_gate --seed-baseline --registry "$R5/registry.json" --scan-root "$R5" --ledger-dir "$R5/ledger"
run_gate --registry "$R5/registry.json" --scan-root "$R5" --ledger-dir "$R5/ledger"
{ [[ $RC -eq 0 ]] && grep -q 'PASS' <<<"$OUT"; } \
  && ok "enrolled ACTIVE-namespace debt => OK/draining (not fail-closed)" \
  || bad "enrolled active debt expected 0/PASS got $RC: $OUT"

# ============================================================================
# Case 6 (AC-NEG1): a NEW (unenrolled) active non-conformant beside enrolled debt => still
#   fail-closed, and the NEW artifact is NEVER laundered into the ledger as a permanent waiver.
# ============================================================================
R6="$TMP/case6"; mkdir -p "$R6"
mk_stub_validator "$R6"; mk_registry "$R6"
mk_artifact "$R6/corpus/active/old.json" '{"other": "x"}'          # pre-existing debt
run_gate --seed-baseline --registry "$R6/registry.json" --scan-root "$R6" --ledger-dir "$R6/ledger"
mk_artifact "$R6/corpus/active/new-bad.json" '{"other": "x"}'      # NEW, created AFTER baseline
run_gate --registry "$R6/registry.json" --scan-root "$R6" --ledger-dir "$R6/ledger"
{ [[ $RC -eq 2 ]] && grep -q 'new-bad.json' <<<"$OUT"; } \
  && ok "AC-NEG1: NEW unenrolled violation beside enrolled debt still fail-closes" \
  || bad "AC-NEG1 expected exit2 naming new-bad got $RC: $OUT"
! grep -q 'old.json' <<<"$OUT" \
  && ok "AC-NEG1: enrolled debt (old.json) not reported as violation" \
  || bad "AC-NEG1: enrolled old.json wrongly reported as violation: $OUT"
L6="$R6/ledger/test-contract.json"
if ledger_has "$L6" "new-bad.json"; then
  bad "AC-NEG1: NEW violation laundered into ledger as permanent waiver"
else
  ok "AC-NEG1: NEW violation not written into ledger (no permanent waiver)"
fi

# ============================================================================
# Case 7 (draining decreases remaining): enrolled A + B; fix A => steady-state PASS and the
#   ledger removes A, remaining decreases toward 0.
# ============================================================================
R7="$TMP/case7"; mkdir -p "$R7"
mk_stub_validator "$R7"; mk_registry "$R7"
mk_artifact "$R7/corpus/active/a.json" '{"other": "x"}'
mk_artifact "$R7/corpus/active/b.json" '{"other": "x"}'
run_gate --seed-baseline --registry "$R7/registry.json" --scan-root "$R7" --ledger-dir "$R7/ledger"
L7="$R7/ledger/test-contract.json"
[[ "$(ledger_remaining "$L7")" == "2" ]] \
  && ok "draining: baseline remaining=2" || bad "draining: baseline remaining expected 2 got '$(ledger_remaining "$L7")'"
mk_artifact "$R7/corpus/active/a.json" '{"test_field": "now-present"}'   # A becomes conformant
run_gate --registry "$R7/registry.json" --scan-root "$R7" --ledger-dir "$R7/ledger"
{ [[ $RC -eq 0 ]] && grep -q 'PASS' <<<"$OUT"; } \
  && ok "draining: fixing an enrolled artifact => PASS" || bad "draining: expected 0/PASS got $RC: $OUT"
[[ "$(ledger_remaining "$L7")" == "1" ]] \
  && ok "draining: remaining decreased 2 -> 1" || bad "draining: remaining expected 1 got '$(ledger_remaining "$L7")'"
{ ledger_has "$L7" "b.json" && ! ledger_has "$L7" "a.json"; } \
  && ok "draining: drained artifact removed from ledger, remaining debt kept" \
  || bad "draining: expected b.json kept and a.json removed from ledger"

# ============================================================================
# Case 8 (no-second-classifier + no namespace classification, static): the gate must not
#   re-implement an existing per-contract validator's vocabulary, must not classify by /archive/
#   namespace, and must consume the registry delegate_validator + ledger enrollment.
# ============================================================================
if grep -q 'per_task_self_verify' "$GATE" || grep -q 'POLARIS_VERIFICATION_STRATEGY' "$GATE"; then
  bad "no-second-classifier: gate re-implements verification_strategy vocabulary"
else
  ok "no-second-classifier: gate holds no per-contract validator vocabulary"
fi
if grep -q '/archive/' "$GATE" || grep -q 'terminal_when' "$GATE" || grep -q 'path_contains' "$GATE"; then
  bad "namespace classification: gate still classifies new-vs-existing by /archive/ namespace"
else
  ok "gate does not classify by /archive/ namespace (enrollment-based)"
fi
if grep -q 'delegate_validator' "$GATE"; then
  ok "gate consumes registry delegate_validator (registry-driven delegation)"
else
  bad "gate does not reference registry delegate_validator"
fi
if grep -q 'enrolled' "$GATE"; then
  ok "gate classifies new-vs-existing by draining-ledger enrollment"
else
  bad "gate does not reference ledger enrollment"
fi

# ============================================================================
# Case 9: the shipped registry is valid, wires verification_strategy to the EXISTING
#   validate-verification-strategy.sh (canonical shape, no parallel classifier), carries a
#   migration_owner, and no longer declares a terminal_when namespace rule.
# ============================================================================
if [[ -f "$REGISTRY" ]]; then
  python3 - "$REGISTRY" <<'PY' && ok "shipped registry wires verification_strategy => validate-verification-strategy.sh (no terminal_when)" \
    || bad "shipped registry missing verification_strategy delegate wiring or still declares terminal_when"
import json,sys
d=json.load(open(sys.argv[1]))
classes=d.get("artifact_classes") or []
vs=[c for c in classes if c.get("required_field")=="verification_strategy"]
assert vs, "no verification_strategy class in shipped registry"
c=vs[0]
assert c.get("delegate_validator")=="scripts/validate-verification-strategy.sh", \
    f"delegate must be scripts/validate-verification-strategy.sh (got {c.get('delegate_validator')})"
assert c.get("required_since"), "required_since required"
assert c.get("migration_owner"), "migration_owner required"
assert "terminal_when" not in c, "terminal_when namespace rule must be removed (enrollment model)"
PY
else
  bad "shipped registry not found: $REGISTRY"
fi

echo ""
echo "validate-artifact-contract-conformance-selftest: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
