#!/usr/bin/env bash
# scripts/cross-session-warm-scan-selftest.sh
#
# Selftest for .claude/hooks/cross-session-warm-scan.sh — UserPromptSubmit
# hook that surfaces memory matches when the user types `繼續 X` / `continue X`.
#
# Coverage:
#   - zero-input forms ("繼續", "繼續\n", "下一步") → silent (no output)
#   - "繼續 polaris" → matches polaris-framework Warm folder + flat root files
#   - "繼續 DP-015" → matches DP-015 file in flat root
#   - "繼續 GT-478" → matches Warm topic folder file (cwv-epics/)
#   - "繼續做 KB2CW-3711" → strips leading verb, matches KB2CW key
#   - "continue dp-015" (lowercase / English trigger) → still matches
#   - prompt with no trigger ("hello world") → silent
#   - JSON with no user_prompt field → silent
#   - JSON with empty prompt → silent
#   - matches in archive/ Cold tier still surfaced
#   - top-level MEMORY.md (the index itself) is excluded
#
# Run: bash scripts/cross-session-warm-scan-selftest.sh   (DEBUG=1 verbose)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../.claude/hooks/cross-session-warm-scan.sh"
WORK_DIR="$(mktemp -d -t polaris-warm-scan-selftest-XXXXXX)"
: "${DEBUG:=0}"

PASS=0
FAIL=0

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    PASS=$((PASS + 1))
    [[ "$DEBUG" == "1" ]] && printf "  [ok] %s (found '%s')\n" "$label" "$needle"
  else
    FAIL=$((FAIL + 1))
    printf "  [FAIL] %s — missing '%s'\n     in output: %s\n" "$label" "$needle" "${haystack:0:200}"
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" label="$3"
  if ! printf '%s' "$haystack" | grep -qF -- "$needle"; then
    PASS=$((PASS + 1))
    [[ "$DEBUG" == "1" ]] && printf "  [ok] %s (no '%s')\n" "$label" "$needle"
  else
    FAIL=$((FAIL + 1))
    printf "  [FAIL] %s — should not contain '%s'\n     in output: %s\n" "$label" "$needle" "${haystack:0:200}"
  fi
}

assert_silent() {
  local haystack="$1" label="$2"
  if [[ -z "$haystack" ]]; then
    PASS=$((PASS + 1))
    [[ "$DEBUG" == "1" ]] && printf "  [ok] %s (silent)\n" "$label"
  else
    FAIL=$((FAIL + 1))
    printf "  [FAIL] %s — expected silent, got: %s\n" "$label" "${haystack:0:200}"
  fi
}

cleanup() { rm -rf "$WORK_DIR" 2>/dev/null || true; }
trap cleanup EXIT

# --- Build fake memory tree ---
MEM="$WORK_DIR/memory"
mkdir -p "$MEM"
mkdir -p "$MEM/polaris-framework"
mkdir -p "$MEM/cwv-epics"
mkdir -p "$MEM/session-management"
mkdir -p "$MEM/archive"

# Hot flat root
: > "$MEM/MEMORY.md"
: > "$MEM/project_polaris_next_session.md"
: > "$MEM/project_dp015_polaris_context_efficiency.md"
: > "$MEM/feedback_random_unrelated.md"

# Warm folders
: > "$MEM/polaris-framework/index.md"
: > "$MEM/polaris-framework/project_polaris_framework_iteration.md"
: > "$MEM/polaris-framework/project_dp032_engineering.md"

: > "$MEM/cwv-epics/index.md"
: > "$MEM/cwv-epics/project_gt478_t3_rescope.md"
: > "$MEM/cwv-epics/project_gt478_t1_done.md"

: > "$MEM/session-management/index.md"
: > "$MEM/session-management/feedback_cross_session_warm.md"

# Cold archive
: > "$MEM/archive/old_dp015_artifact.md"

# --- Helper: invoke hook with JSON prompt ---
run_hook() {
  local prompt="$1"
  # Build proper JSON
  local json
  json=$(printf '%s' "$prompt" | python3 -c 'import json,sys; print(json.dumps({"user_prompt": sys.stdin.read()}))')
  POLARIS_MEMORY_DIR="$MEM" bash "$HOOK" <<<"$json"
}

run_hook_raw() {
  POLARIS_MEMORY_DIR="$MEM" bash "$HOOK" <<<"$1"
}

# --- Test cases ---

# 1. Zero-input forms → silent
out=$(run_hook "繼續")
assert_silent "$out" "[1] 繼續 alone → silent"

out=$(run_hook "繼續。")
assert_silent "$out" "[2] 繼續 with punctuation only → silent"

out=$(run_hook "下一步")
assert_silent "$out" "[3] 下一步 (different trigger word) → silent"

out=$(run_hook "next")
assert_silent "$out" "[4] next (no continue prefix) → silent"

# 5. No trigger at all → silent
out=$(run_hook "hello world, what's the weather?")
assert_silent "$out" "[5] no trigger → silent"

# 6. 繼續 polaris → matches polaris-framework folder + flat files
out=$(run_hook "繼續 polaris")
assert_contains "$out" "[繼續]" "[6a] polaris → emits header"
assert_contains "$out" "polaris-framework/" "[6b] polaris → finds Warm folder file"
assert_contains "$out" "project_polaris_next_session.md" "[6c] polaris → finds flat root file"
assert_not_contains "$out" "MEMORY.md" "[6d] polaris → top-level MEMORY.md excluded"

# 7. 繼續 DP-015 → matches DP-015 file (flat) + dp015 in polaris-framework if any
out=$(run_hook "繼續 DP-015")
assert_contains "$out" "project_dp015_polaris_context_efficiency.md" "[7a] DP-015 → flat file"

# 8. 繼續 GT-478 → matches cwv-epics Warm folder
out=$(run_hook "繼續 GT-478")
assert_contains "$out" "cwv-epics/project_gt478_t3_rescope.md" "[8a] GT-478 → Warm folder file"
assert_contains "$out" "cwv-epics/project_gt478_t1_done.md" "[8b] GT-478 → second match"

# 9. 繼續做 KB2CW-3711 → strip 做, match KB2CW key (no file in fake tree, so silent OK)
# Add a file to verify the key works
: > "$MEM/cwv-epics/project_kb2cw3711_done.md"
out=$(run_hook "繼續做 KB2CW-3711")
assert_contains "$out" "kb2cw3711" "[9a] 繼續做 strips verb, matches KB2CW key"

# 10. continue dp-015 (English trigger, lowercase keyword)
out=$(run_hook "continue dp-015")
assert_contains "$out" "dp015_polaris_context_efficiency" "[10a] English trigger, lowercase match"

# 11. JSON with no user_prompt field → silent
out=$(run_hook_raw '{"session_id":"abc"}')
assert_silent "$out" "[11] no user_prompt field → silent"

# 12. JSON with empty prompt → silent
out=$(run_hook_raw '{"user_prompt":""}')
assert_silent "$out" "[12] empty user_prompt → silent"

# 13. JSON malformed → silent
out=$(run_hook_raw 'not json at all')
assert_silent "$out" "[13] malformed JSON → silent"

# 14. Cold archive matches surfaced
out=$(run_hook "繼續 dp015")
assert_contains "$out" "archive/old_dp015_artifact.md" "[14] archive/ Cold matches surfaced"

# 15. Multi-keyword prompt → captures multiple, capped at 3
out=$(run_hook "繼續 polaris GT-478 DP-015 extra-token-four")
# Should match polaris and GT-478 (first two of the three considered)
assert_contains "$out" "polaris-framework" "[15a] multi-keyword: polaris matches"
assert_contains "$out" "cwv-epics" "[15b] multi-keyword: GT-478 matches"

# 16. prompt that mentions 繼續 but inline / mid-sentence
out=$(run_hook "今天我想繼續 polaris 的工作")
assert_contains "$out" "[繼續]" "[16] mid-sentence trigger still detected"

# 17. fallback "prompt" field (alternate JSON shape)
out=$(run_hook_raw '{"prompt":"繼續 polaris"}')
assert_contains "$out" "polaris-framework" "[17] fallback prompt field works"

# 18. memory dir absent → silent (skip, don't crash)
NONE_DIR="$WORK_DIR/does-not-exist"
out=$(POLARIS_MEMORY_DIR="$NONE_DIR" bash "$HOOK" <<<'{"user_prompt":"繼續 polaris"}')
assert_silent "$out" "[18] missing memory dir → silent"

# --- Summary ---
echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "✅ cross-session-warm-scan-selftest: $PASS/$((PASS + FAIL)) PASS"
  exit 0
else
  echo "❌ cross-session-warm-scan-selftest: $PASS PASS, $FAIL FAIL"
  exit 1
fi
