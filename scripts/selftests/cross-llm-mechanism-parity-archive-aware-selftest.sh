#!/usr/bin/env bash
# Purpose: DP-371 T1 (AC1 / AC2 / AC3 / AC-NEG1) real-TDD selftest for the
#          archive-aware parity_exception owning-DP resolution in
#          validate-cross-llm-mechanism-parity.sh. Builds hermetic tmpdir
#          fixtures whose specs-root carries the owning DP plan in either the
#          active design-plans tree or design-plans/archive/, then drives the
#          real validator via POLARIS_SPECS_ROOT to assert:
#            - owning DP only in archive/ + parity reason -> PASS (archive-aware)
#            - genuinely missing (active + archive both absent) -> still FAIL
#              "owning DP plan not found" (no vacuous accept)
#            - archive found but plan lacks "parity" reason -> still FAIL
#              "lacks recorded parity carve-out reason" (reason check not bypassed)
#            - active plan still present -> still PASS (no behavior regression)
# Inputs:  none (hermetic; uses mktemp fixtures, env -u to drop ambient roots,
#          and a stub compiler so only the parity_exception path is exercised).
# Outputs: stdout PASS/FAIL per fixture; exit 0 all-pass, exit 1 any failure.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-cross-llm-mechanism-parity.sh"

FAILS=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAILS=$((FAILS + 1)); }

# Stub compiler so fixture cases isolate the parity_exception owning-DP lookup
# from real generated-target drift.
make_stub_compiler() {
  local path="$1"
  cat >"$path" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$path"
}

# Build a fixture repo whose single active hook carries a
# parity_exception=DP-900:<reason> carve-out, with the adapter infra removed so
# the carve-out short-circuit (and therefore the owning-DP lookup) is the only
# thing under test. The owning DP plan is NOT created here; each fixture decides
# whether to place it under active design-plans/ or design-plans/archive/.
# Returns repo path on stdout.
make_carveout_fixture() {
  local tmp="$1"
  local repo="$tmp/repo"
  mkdir -p "$repo/.claude/hooks" "$repo/.claude/rules" "$repo/.codex" \
    "$repo/scripts/selftests" \
    "$repo/docs-manager/src/content/docs/specs/design-plans"

  # Claude hook referenced by settings (must exist on disk).
  cat >"$repo/.claude/hooks/good-hook.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  # settings.json: one active hook (Write event family) -> good-hook.
  cat >"$repo/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Write", "hooks": [ { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/good-hook.sh\"" } ] }
    ]
  }
}
EOF

  # registry with the good-hook row carrying a parity_exception carve-out.
  # Adapter / fallback / selftest / golden fields are all N/A; a valid carve-out
  # must short-circuit those, so the owning-DP lookup is the sole gate.
  cat >"$repo/.claude/rules/mechanism-registry.md" <<'EOF'
# registry fixture

## Cross-LLM Hook Parity Registry

| hook | runtime | fallback_script | codex_adapter | codex_invocation_point | adapter_selftest | payload_contract | golden_fixture | parity_exception |
|------|---------|-----------------|---------------|------------------------|------------------|------------------|----------------|------------------|
| good-hook.sh | portable | N/A | N/A | N/A | N/A | N/A | N/A | DP-900:dual-platform-parity-bootstrap |

## Next Section
EOF

  printf '%s\n' "$repo"
}

# Write an owning DP plan index.md under <repo>/<rel-design-plans-dir>/DP-900-fixture/.
# Args: <repo> <design-plans-subpath> <body>
write_owning_dp_plan() {
  local repo="$1" subpath="$2" body="$3"
  local dir="$repo/docs-manager/src/content/docs/specs/design-plans/$subpath/DP-900-fixture"
  mkdir -p "$dir"
  printf '%s\n' "$body" >"$dir/index.md"
}

# Drive the real validator hermetically: drop ambient POLARIS_* roots and pin
# specs/repo to the fixture so the live workspace cannot leak in.
run_validator() {
  local repo="$1"
  env -u POLARIS_SPECS_ROOT -u POLARIS_WORKSPACE_ROOT \
    POLARIS_COMPILE_RUNTIME_INSTRUCTIONS_BIN="$repo/scripts/compile-stub.sh" \
    POLARIS_SPECS_ROOT="$repo" \
    bash "$VALIDATOR" --repo "$repo" >"$repo/.out" 2>"$repo/.err"
  echo $?
}

assert_pass() {
  local label="$1" repo="$2"
  local rc; rc="$(run_validator "$repo")"
  if [[ "$rc" == "0" ]]; then pass "$label"; else fail "$label (expected exit 0, got $rc): $(cat "$repo/.err")"; fi
}

# assert_block <label> <repo> <expected-marker-substring>
assert_block() {
  local label="$1" repo="$2" expect="$3"
  local rc; rc="$(run_validator "$repo")"
  if [[ "$rc" == "2" ]] && grep -q 'POLARIS_CROSS_LLM_PARITY_BLOCKED' "$repo/.err" \
      && grep -q "$expect" "$repo/.err"; then
    pass "$label"
  else
    fail "$label (expected exit 2 + marker matching '$expect', got $rc): $(cat "$repo/.err")"
  fi
}

# --- AC1 / AC2: owning DP plan ONLY in archive/ + parity reason -> PASS ---
# This is the RED case before the fix: the active glob finds nothing, so the
# pre-fix validator returns "owning DP plan not found". After the archive-aware
# fix it resolves the plan from design-plans/archive/ and PASSes.
TA="$(mktemp -d)"; RA="$(make_carveout_fixture "$TA")"; make_stub_compiler "$RA/scripts/compile-stub.sh"
write_owning_dp_plan "$RA" "archive" "# DP-900 (archived)
This archived plan records the dual-platform parity carve-out reason."
assert_pass "AC1/AC2 owning DP only in archive/ + parity reason -> PASS" "$RA"

# --- AC-NEG1: genuinely missing (active + archive both absent) -> still FAIL ---
TB="$(mktemp -d)"; RB="$(make_carveout_fixture "$TB")"; make_stub_compiler "$RB/scripts/compile-stub.sh"
# No owning DP plan written anywhere.
assert_block "AC-NEG1 genuinely missing owning DP -> FAIL not found" "$RB" \
  "owning DP plan not found"

# --- AC3: archive found but plan lacks "parity" reason -> still FAIL reason ---
TC="$(mktemp -d)"; RC="$(make_carveout_fixture "$TC")"; make_stub_compiler "$RC/scripts/compile-stub.sh"
write_owning_dp_plan "$RC" "archive" "# DP-900 (archived, no carve word)
This archived plan exists but records no carve-out reason."
assert_block "AC3 archive plan lacks parity reason -> FAIL lacks recorded reason" "$RC" \
  "lacks recorded parity carve-out reason"

# --- AC2 (no regression): active plan still present -> still PASS ---
TD="$(mktemp -d)"; RD="$(make_carveout_fixture "$TD")"; make_stub_compiler "$RD/scripts/compile-stub.sh"
write_owning_dp_plan "$RD" "." "# DP-900 (active)
This active plan records the dual-platform parity carve-out reason."
assert_pass "AC2 active plan still present -> PASS (no regression)" "$RD"

# cleanup
rm -rf "$TA" "$TB" "$TC" "$TD"

if [[ "$FAILS" -gt 0 ]]; then
  echo "cross-llm-mechanism-parity-archive-aware-selftest: $FAILS failure(s)"
  exit 1
fi
echo "cross-llm-mechanism-parity-archive-aware-selftest: all 4 fixtures PASS"
exit 0
