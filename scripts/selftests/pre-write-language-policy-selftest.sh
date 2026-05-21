#!/usr/bin/env bash
# pre-write-language-policy-selftest.sh — DP-217 writer-side language policy hook.
#
# Verifies:
#   1. Scope path with English-only body → exit 2 (BLOCKED).
#   2. Scope path with zh-TW body → exit 0 (PASS).
#   3. Out-of-scope path (e.g., random temp file) → exit 0 (no-op).
#   4. Non Write/Edit/MultiEdit tool name → exit 0 (no-op).
#   5. POLARIS_LANGUAGE_POLICY_BYPASS=1 → exit 0 with bypass log.
#   6. POLARIS_PRODUCER=<name> → exit 0 with producer bypass log.
#   7. wall-clock < 500ms per invocation on a small artifact (AC-NF2 budget 200ms;
#      selftest uses 500ms to absorb cold-start + python boot variance on CI).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT_DIR/.claude/hooks/pre-write-language-policy.sh"
WORKDIR="$(mktemp -d -t dp217-pre-write-lang.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

if [[ ! -x "$HOOK" ]]; then
  echo "FAIL: hook is not executable: $HOOK" >&2
  exit 1
fi

run_hook() {
  local payload="$1"
  local expected_exit="$2"
  local label="$3"
  local out_file="$WORKDIR/${label}.out"
  set +e
  printf '%s' "$payload" | "$HOOK" >"$out_file" 2>&1
  local rc=$?
  set -e
  if [[ "$rc" -ne "$expected_exit" ]]; then
    echo "FAIL ($label): expected exit $expected_exit, got $rc" >&2
    cat "$out_file" >&2
    exit 1
  fi
}

# Case 1: in-scope Write with English-only content → block (exit 2).
scope_path_en="$ROOT_DIR/.claude/skills/__dp217_fixture_en__.md"
payload_en=$(python3 -c "
import json,sys
print(json.dumps({
  'tool_name': 'Write',
  'tool_input': {
    'file_path': '$scope_path_en',
    'content': 'Hello world, this is an English-only paragraph that should trigger the gate.\nAnother English sentence.\n'
  }
}))
")
run_hook "$payload_en" 2 case-en-block
grep -q 'BLOCKED by pre-write-language-policy' "$WORKDIR/case-en-block.out"

# Case 2: in-scope Write with zh-TW content → pass (exit 0).
scope_path_zh="$ROOT_DIR/.claude/skills/__dp217_fixture_zh__.md"
payload_zh=$(python3 -c "
import json,sys
print(json.dumps({
  'tool_name': 'Write',
  'tool_input': {
    'file_path': '$scope_path_zh',
    'content': '這是中文內容，用於測試 pre-write language policy hook 不會誤擋 zh-TW 寫入。\n第二行也用中文。\n'
  }
}))
")
run_hook "$payload_zh" 0 case-zh-pass

# Case 3: out-of-scope path → no-op (exit 0).
oos_path="$WORKDIR/out-of-scope.md"
payload_oos=$(python3 -c "
import json,sys
print(json.dumps({
  'tool_name': 'Write',
  'tool_input': {
    'file_path': '$oos_path',
    'content': 'English-only content but this path is outside scope so policy does not run.\n'
  }
}))
")
run_hook "$payload_oos" 0 case-oos-pass

# Case 4: non Write/Edit/MultiEdit tool → no-op.
payload_bash=$(python3 -c "
import json,sys
print(json.dumps({
  'tool_name': 'Bash',
  'tool_input': {
    'command': 'echo hi'
  }
}))
")
run_hook "$payload_bash" 0 case-bash-pass

# Case 5: explicit POLARIS_LANGUAGE_POLICY_BYPASS=1 → bypass (exit 0).
payload_bypass=$(python3 -c "
import json,sys
print(json.dumps({
  'tool_name': 'Write',
  'tool_input': {
    'file_path': '$scope_path_en',
    'content': 'English-only content that would normally block but bypass is set.'
  }
}))
")
payload_bypass_file="$WORKDIR/payload-bypass.json"
printf '%s' "$payload_bypass" >"$payload_bypass_file"
set +e
POLARIS_LANGUAGE_POLICY_BYPASS=1 "$HOOK" <"$payload_bypass_file" >"$WORKDIR/case-explicit-bypass.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL (case-explicit-bypass): expected exit 0, got $rc" >&2
  cat "$WORKDIR/case-explicit-bypass.out" >&2
  exit 1
fi
grep -q 'BYPASS explicit POLARIS_LANGUAGE_POLICY_BYPASS' "$WORKDIR/case-explicit-bypass.out"

# Case 6: POLARIS_PRODUCER=<name> → bypass (exit 0) with producer log.
set +e
POLARIS_PRODUCER=mark-spec-implemented.sh "$HOOK" <"$payload_bypass_file" >"$WORKDIR/case-producer-bypass.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL (case-producer-bypass): expected exit 0, got $rc" >&2
  cat "$WORKDIR/case-producer-bypass.out" >&2
  exit 1
fi
grep -q 'BYPASS producer=mark-spec-implemented.sh' "$WORKDIR/case-producer-bypass.out"

# Case 7: timing budget. Use the zh-TW pass payload so the validator runs the full
# path (read config + scan markdown). Allow 500ms wall-clock per invocation as a
# soft CI budget; the AC-NF2 target is 200ms in steady state.
start_ns=$(python3 -c "import time; print(int(time.monotonic_ns()))")
printf '%s' "$payload_zh" | "$HOOK" >/dev/null 2>&1
end_ns=$(python3 -c "import time; print(int(time.monotonic_ns()))")
elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
if [[ "$elapsed_ms" -gt 500 ]]; then
  echo "FAIL (case-timing): hook wall-clock ${elapsed_ms}ms > 500ms ceiling" >&2
  exit 1
fi

echo "PASS: pre-write-language-policy selftest (timing=${elapsed_ms}ms)"
