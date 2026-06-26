#!/usr/bin/env bash
# Purpose: D43 (DP-343 T1 / AC43 + AC-NEG27) selftest for
#          validate-cross-llm-mechanism-parity.sh. Builds synthetic repo fixtures in
#          tmpdir and asserts the validator PASSes a fully-parity-compliant hook set
#          and fail-stops (exit 2 + POLARIS_CROSS_LLM_PARITY_BLOCKED) on each
#          parity violation class.
# Inputs:  none (hermetic; uses mktemp fixtures and a stubbed compiler).
# Outputs: stdout PASS/FAIL per fixture; exit 0 all-pass, exit 1 any failure.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-cross-llm-mechanism-parity.sh"

FAILS=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAILS=$((FAILS + 1)); }

# Stub compiler that always reports targets in sync, so fixture cases isolate the
# registry/settings/adapter parity logic from real generated-target drift. The
# real compiler --check path is exercised against the live repo in the Verify step.
make_stub_compiler() {
  local path="$1"
  cat >"$path" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$path"
}

# Build a fixture repo. Returns repo path on stdout.
# Usage: make_fixture <tmp>
make_fixture() {
  local tmp="$1"
  local repo="$tmp/repo"
  mkdir -p "$repo/.claude/hooks" "$repo/.claude/rules" "$repo/.codex" \
    "$repo/scripts/selftests" "$repo/.codex/hooks" \
    "$repo/scripts/lib/parity-fixtures" \
    "$repo/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture"

  # Owning DP plan carrying a recorded parity carve-out reason.
  cat >"$repo/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/index.md" <<'EOF'
# DP-900 fixture
This plan records the dual-platform parity carve-out reason for fixture hooks.
EOF

  # A real fallback validator + Claude hook that delegates to it.
  cat >"$repo/scripts/validate-fixture-fallback.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat >"$repo/.claude/hooks/good-hook.sh" <<'EOF'
#!/usr/bin/env bash
# delegates to fallback
bash "$REPO/scripts/validate-fixture-fallback.sh"
EOF
  # Codex adapter (codex_hook style) + selftest + payload contract.
  cat >"$repo/.codex/hooks/good-hook.sh" <<'EOF'
#!/usr/bin/env bash
bash "$REPO/scripts/validate-fixture-fallback.sh"
EOF
  cat >"$repo/scripts/selftests/good-hook-adapter-selftest.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat >"$repo/scripts/lib/parity-fixtures/good-hook.contract.md" <<'EOF'
payload contract: tool_name / matcher / tool_input.path / changed_paths / session_id / transcript / cwd / env_carve_out_token
EOF
  # Golden fixture with matching normalized decision-field digests.
  cat >"$repo/scripts/lib/parity-fixtures/good-hook.golden.json" <<'EOF'
{
  "claude_payload": {"tool_name":"Write","matcher":"Write","tool_input":{"path":"a.txt"},"changed_paths":["a.txt"],"session_id":"s1","transcript":"t","cwd":"/repo","env_carve_out_token":"none"},
  "codex_payload": {"tool_name":"Write","matcher":"Write","tool_input":{"path":"a.txt"},"changed_paths":["a.txt"],"session_id":"s1","transcript":"t","cwd":"/repo","env_carve_out_token":"none","extra_runtime_field":"ignored"},
  "fallback_decision": "PASS"
}
EOF
  # Register the codex_hook adapter in .codex/config.toml.
  cat >"$repo/.codex/config.toml" <<'EOF'
[hooks]
good-hook = ".codex/hooks/good-hook.sh"
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

  # mechanism-registry.md with a fully-compliant Cross-LLM Hook Parity Registry.
  cat >"$repo/.claude/rules/mechanism-registry.md" <<'EOF'
# registry fixture

## Cross-LLM Hook Parity Registry

| hook | runtime | fallback_script | codex_adapter | codex_invocation_point | adapter_selftest | payload_contract | golden_fixture | parity_exception |
|------|---------|-----------------|---------------|------------------------|------------------|------------------|----------------|------------------|
| good-hook.sh | claude-code-only | scripts/validate-fixture-fallback.sh | .codex/hooks/good-hook.sh | codex_hook | scripts/selftests/good-hook-adapter-selftest.sh | scripts/lib/parity-fixtures/good-hook.contract.md | scripts/lib/parity-fixtures/good-hook.golden.json | N/A |

## Next Section
EOF
  printf '%s\n' "$repo"
}

run_validator() {
  local repo="$1"
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

assert_block() {
  local label="$1" repo="$2"
  local rc; rc="$(run_validator "$repo")"
  if [[ "$rc" == "2" ]] && grep -q 'POLARIS_CROSS_LLM_PARITY_BLOCKED' "$repo/.err"; then
    pass "$label"
  else
    fail "$label (expected exit 2 + marker, got $rc): $(cat "$repo/.err")"
  fi
}

# --- Fixture 1: valid active hook (full parity) -> PASS ---
T1="$(mktemp -d)"; R1="$(make_fixture "$T1")"; make_stub_compiler "$R1/scripts/compile-stub.sh"
assert_pass "F1 valid active hook full parity" "$R1"

# --- Fixture 2: settings active hook missing on disk -> block ---
T2="$(mktemp -d)"; R2="$(make_fixture "$T2")"; make_stub_compiler "$R2/scripts/compile-stub.sh"
rm "$R2/.claude/hooks/good-hook.sh"
assert_block "F2 settings active hook missing on disk" "$R2"

# --- Fixture 3: hook missing registry annotation -> block ---
T3="$(mktemp -d)"; R3="$(make_fixture "$T3")"; make_stub_compiler "$R3/scripts/compile-stub.sh"
python3 - "$R3" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1])/".claude/rules/mechanism-registry.md"
t=p.read_text()
# drop the data row for good-hook.sh
t="\n".join(l for l in t.splitlines() if "good-hook.sh |" not in l)
p.write_text(t)
PY
assert_block "F3 hook missing registry annotation" "$R3"

# --- Fixture 4: missing fallback_script on disk -> block ---
T4="$(mktemp -d)"; R4="$(make_fixture "$T4")"; make_stub_compiler "$R4/scripts/compile-stub.sh"
rm "$R4/scripts/validate-fixture-fallback.sh"
assert_block "F4 missing fallback script on disk" "$R4"

# --- Fixture 5: hook does not delegate declared fallback -> block ---
T5="$(mktemp -d)"; R5="$(make_fixture "$T5")"; make_stub_compiler "$R5/scripts/compile-stub.sh"
cat >"$R5/.claude/hooks/good-hook.sh" <<'EOF'
#!/usr/bin/env bash
# inline allow/deny that does NOT call the declared fallback
echo "runtime-specific decision"
EOF
assert_block "F5 hook missing fallback delegation" "$R5"

# --- Fixture 6: missing Codex adapter target -> block ---
T6="$(mktemp -d)"; R6="$(make_fixture "$T6")"; make_stub_compiler "$R6/scripts/compile-stub.sh"
rm "$R6/.codex/hooks/good-hook.sh"
assert_block "F6 missing Codex adapter target" "$R6"

# --- Fixture 7: Codex adapter exists but inactive (not registered) -> block ---
T7="$(mktemp -d)"; R7="$(make_fixture "$T7")"; make_stub_compiler "$R7/scripts/compile-stub.sh"
cat >"$R7/.codex/config.toml" <<'EOF'
[hooks]
EOF
assert_block "F7 Codex adapter exists but inactive" "$R7"

# --- Fixture 8: Stop event-family active hook covered (PASS) ---
T8="$(mktemp -d)"; R8="$(make_fixture "$T8")"; make_stub_compiler "$R8/scripts/compile-stub.sh"
cat >"$R8/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "Stop": [
      { "matcher": "", "hooks": [ { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/good-hook.sh\"" } ] }
    ]
  }
}
EOF
assert_pass "F8 Stop event-family active hook covered" "$R8"

# --- Fixture 9: missing adapter selftest -> block ---
T9="$(mktemp -d)"; R9="$(make_fixture "$T9")"; make_stub_compiler "$R9/scripts/compile-stub.sh"
rm "$R9/scripts/selftests/good-hook-adapter-selftest.sh"
assert_block "F9 missing adapter selftest" "$R9"

# --- Fixture 10: manual invocation point -> block ---
T10="$(mktemp -d)"; R10="$(make_fixture "$T10")"; make_stub_compiler "$R10/scripts/compile-stub.sh"
sed -i.bak 's/| codex_hook |/| manual |/' "$R10/.claude/rules/mechanism-registry.md"
assert_block "F10 manual invocation point" "$R10"

# --- Fixture 11: generated target drift (compiler --check fails) -> block ---
T11="$(mktemp -d)"; R11="$(make_fixture "$T11")"
cat >"$R11/scripts/compile-stub.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$R11/scripts/compile-stub.sh"
assert_block "F11 generated target drift" "$R11"

# --- Fixture 12: parity_exception with valid DP reason -> PASS ---
T12="$(mktemp -d)"; R12="$(make_fixture "$T12")"; make_stub_compiler "$R12/scripts/compile-stub.sh"
# Replace the row with a carve-out; remove adapter infra to prove carve-out short-circuits.
python3 - "$R12" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1])/".claude/rules/mechanism-registry.md"
t=p.read_text()
row="| good-hook.sh | portable | N/A | N/A | N/A | N/A | N/A | N/A | DP-900:dual-platform-parity-bootstrap |"
out=[]
for l in t.splitlines():
    out.append(row if "good-hook.sh |" in l else l)
p.write_text("\n".join(out))
PY
# DP-900 plan must mention "parity"; add it.
echo "parity carve-out recorded" >> "$R12/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/index.md"
rm "$R12/.codex/hooks/good-hook.sh" "$R12/scripts/selftests/good-hook-adapter-selftest.sh"
assert_pass "F12 parity_exception with valid DP reason" "$R12"

# --- Fixture 13: parity_exception but owning DP plan lacks reason -> block ---
T13="$(mktemp -d)"; R13="$(make_fixture "$T13")"; make_stub_compiler "$R13/scripts/compile-stub.sh"
python3 - "$R13" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1])/".claude/rules/mechanism-registry.md"
t=p.read_text()
row="| good-hook.sh | portable | N/A | N/A | N/A | N/A | N/A | N/A | DP-900:missing-reason |"
p.write_text("\n".join(row if "good-hook.sh |" in l else l for l in t.splitlines()))
PY
# strip the word "parity" from the plan so the reason lookup fails
echo "# DP-900 fixture (no carve word)" > "$R13/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/index.md"
assert_block "F13 parity_exception missing owning DP reason" "$R13"

# --- Fixture 14: BYPASS env attempt still blocks ---
T14="$(mktemp -d)"; R14="$(make_fixture "$T14")"; make_stub_compiler "$R14/scripts/compile-stub.sh"
rm "$R14/.claude/hooks/good-hook.sh"  # introduce a real violation
rc=$(POLARIS_CROSS_LLM_PARITY_BYPASS=1 POLARIS_LANGUAGE_POLICY_BYPASS=1 POLARIS_SKILL_BOUNDARY_BYPASS=1 \
  POLARIS_COMPILE_RUNTIME_INSTRUCTIONS_BIN="$R14/scripts/compile-stub.sh" POLARIS_SPECS_ROOT="$R14" \
  bash "$VALIDATOR" --repo "$R14" >"$R14/.out" 2>"$R14/.err"; echo $?)
if [[ "$rc" == "2" ]] && grep -q 'POLARIS_CROSS_LLM_PARITY_BLOCKED' "$R14/.err"; then
  pass "F14 BYPASS env cannot silence gate"
else
  fail "F14 BYPASS env cannot silence gate (got $rc): $(cat "$R14/.err")"
fi

# --- Fixture 15: settings.local hook without parity registration -> block ---
T15="$(mktemp -d)"; R15="$(make_fixture "$T15")"; make_stub_compiler "$R15/scripts/compile-stub.sh"
cp "$R15/.claude/hooks/good-hook.sh" "$R15/.claude/hooks/local-only-hook.sh"
cat >"$R15/.claude/settings.local.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Edit", "hooks": [ { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/local-only-hook.sh\"" } ] }
    ]
  }
}
EOF
assert_block "F15 settings.local hook without parity" "$R15"

# --- Fixture 16: inline / non-canonical hook command -> block ---
T16="$(mktemp -d)"; R16="$(make_fixture "$T16")"; make_stub_compiler "$R16/scripts/compile-stub.sh"
cat >"$R16/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Write", "hooks": [ { "type": "command", "command": "echo hi && bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/good-hook.sh\"" } ] }
    ]
  }
}
EOF
assert_block "F16 inline/chained non-canonical hook command" "$R16"

# --- Fixture 17: adapter normalized payload digest mismatch -> block ---
T17="$(mktemp -d)"; R17="$(make_fixture "$T17")"; make_stub_compiler "$R17/scripts/compile-stub.sh"
cat >"$R17/scripts/lib/parity-fixtures/good-hook.golden.json" <<'EOF'
{
  "claude_payload": {"tool_name":"Write","matcher":"Write","tool_input":{"path":"a.txt"},"changed_paths":["a.txt"],"session_id":"s1","transcript":"t","cwd":"/repo","env_carve_out_token":"none"},
  "codex_payload": {"tool_name":"Write","matcher":"Write","tool_input":{"path":"DIFFERENT.txt"},"changed_paths":["a.txt"],"session_id":"s1","transcript":"t","cwd":"/repo","env_carve_out_token":"none"},
  "fallback_decision": "PASS"
}
EOF
assert_block "F17 adapter normalized payload digest mismatch" "$R17"

# --- Fixture 18: fallback PASS/FAIL mismatch between runtimes -> block ---
T18="$(mktemp -d)"; R18="$(make_fixture "$T18")"; make_stub_compiler "$R18/scripts/compile-stub.sh"
cat >"$R18/scripts/lib/parity-fixtures/good-hook.golden.json" <<'EOF'
{
  "claude_payload": {"tool_name":"Write","matcher":"Write","tool_input":{"path":"a.txt"},"changed_paths":["a.txt"],"session_id":"s1","transcript":"t","cwd":"/repo","env_carve_out_token":"none"},
  "codex_payload": {"tool_name":"Write","matcher":"Write","tool_input":{"path":"a.txt"},"changed_paths":["a.txt"],"session_id":"s1","transcript":"t","cwd":"/repo","env_carve_out_token":"none"},
  "fallback_decision": "PASS",
  "claude_decision": "PASS",
  "codex_decision": "FAIL"
}
EOF
assert_block "F18 fallback PASS/FAIL runtime mismatch" "$R18"

# cleanup
rm -rf "$T1" "$T2" "$T3" "$T4" "$T5" "$T6" "$T7" "$T8" "$T9" "$T10" \
  "$T11" "$T12" "$T13" "$T14" "$T15" "$T16" "$T17" "$T18"

if [[ "$FAILS" -gt 0 ]]; then
  echo "cross-llm-mechanism-parity-selftest: $FAILS failure(s)"
  exit 1
fi
echo "cross-llm-mechanism-parity-selftest: all 18 fixtures PASS"
exit 0
