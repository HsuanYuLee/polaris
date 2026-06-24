#!/usr/bin/env bash
# Purpose: Hermetic selftest for .claude/hooks/selftest-staleness-eval.sh
#          (DP-360 T5). Covers AC8 — full-corpus staleness advisory:
#          (a) age over workspace-config threshold -> [SELFTEST-STALE] advisory;
#          (b) age under threshold -> silent (no advisory);
#          (c) missing config -> fail-open to built-in defaults + exit 0;
#          (d) missing / corrupt state -> fail-open exit 0 (never-run is treated
#              as stale, but still exit 0 — the hook NEVER blocks the prompt).
#          Also asserts surface=always FRESH dump, surface=on_stale FRESH silence,
#          enabled:false silence, --report mode, no filesystem mutation, and no
#          network/build tokens in the hook source (negative contract).
# Inputs:  None. Builds its own CLAUDE_PROJECT_DIR fixtures under a tmpdir,
#          including a self-contained last-full-corpus-run state file.
# Outputs: Prints per-case PASS lines; exits non-zero with FAIL on any assertion
#          failure (the selftest itself is fail-closed; the hook under test is
#          fail-open). Final line "ALL PASS" on success.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT/.claude/hooks/selftest-staleness-eval.sh"

if [[ ! -f "$HOOK" ]]; then
  echo "FAIL: hook not found at $HOOK" >&2
  exit 1
fi

TMP="$(mktemp -d -t dp360-selftest-staleness.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

PASS_COUNT=0
fail() {
  echo "FAIL: $*" >&2
  exit 1
}
ok() {
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "PASS: $*"
}

# --- Fixture builders -------------------------------------------------------

# Write a last-full-corpus-run state file with an ISO-8601 UTC timestamp.
# Args: $1 project_dir, $2 last_full_corpus_run_ts (empty => omit the file)
make_state() {
  local proj="$1" ts="$2"
  mkdir -p "$proj/.polaris/runtime/selftest-staleness"
  if [[ -n "$ts" ]]; then
    cat > "$proj/.polaris/runtime/selftest-staleness/last-full-corpus-run.json" <<EOF
{"last_full_corpus_run_ts": "$ts"}
EOF
  fi
}

# Write a selftest_staleness config block into workspace-config.yaml.
# Args: $1 project_dir, $2 enabled, $3 max_age_hours, $4 surface
write_config() {
  local proj="$1"
  cat > "$proj/workspace-config.yaml" <<EOF
language: "zh-TW"
defaults:
  selftest_staleness:
    enabled: $2
    max_age_hours: $3
    surface: "$4"
EOF
}

# Recent ISO-8601 UTC timestamp offset by N hours in the past (portable).
ts_hours_ago() {
  local hours="$1"
  date -u -d "-${hours} hours" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || date -u -v-"${hours}"H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null
}

# Invoke the hook with a UserPromptSubmit payload in project $1. Captures stdout
# into global OUT and exit code into global LAST_EXIT. Avoids command
# substitution for the run so LAST_EXIT survives (subshell would lose it).
OUT=""
LAST_EXIT=0
run_hook() {
  local proj="$1"
  local tmpf="$TMP/.run_hook_out"
  printf '{"session_id": "sess-staleness", "hook_event_name": "UserPromptSubmit"}' \
    | CLAUDE_PROJECT_DIR="$proj" bash "$HOOK" > "$tmpf" 2>/dev/null
  LAST_EXIT=$?
  OUT="$(cat "$tmpf")"
}

# === AC8-a: age over threshold -> STALE advisory ============================
P="$TMP/p_over"; make_state "$P" "$(ts_hours_ago 100)"
write_config "$P" true 48 on_stale
run_hook "$P"
[[ "$LAST_EXIT" -eq 0 ]] || fail "AC8-a expected exit 0, got $LAST_EXIT"
printf '%s' "$OUT" | grep -q '\[SELFTEST-STALE\]' || fail "AC8-a expected advisory marker, got: $OUT"
printf '%s' "$OUT" | grep -q 'decision=STALE' || fail "AC8-a expected decision=STALE, got: $OUT"
printf '%s' "$OUT" | grep -q 'full_corpus_age_hours 100/48' || fail "AC8-a expected '100/48', got: $OUT"
ok "AC8-a: age over threshold -> [SELFTEST-STALE] advisory with hours/limit"

# === AC8-b: age under threshold -> silent (no advisory), exit 0 =============
P="$TMP/p_under"; make_state "$P" "$(ts_hours_ago 1)"
write_config "$P" true 48 on_stale
run_hook "$P"
[[ "$LAST_EXIT" -eq 0 ]] || fail "AC8-b expected exit 0, got $LAST_EXIT"
[[ -z "$OUT" ]] || fail "AC8-b expected silent FRESH (empty stdout), got: [$OUT]"
ok "AC8-b: age under threshold + surface=on_stale -> FRESH silent stdout"

# === AC8: config overridable (strict vs loose flips decision on same state) ==
P="$TMP/p_flip"; make_state "$P" "$(ts_hours_ago 24)"
write_config "$P" true 12 on_stale   # strict: 24h age over 12h limit -> STALE
run_hook "$P"
[[ "$LAST_EXIT" -eq 0 ]] || fail "AC8 strict expected exit 0"
printf '%s' "$OUT" | grep -q 'decision=STALE' || fail "AC8 strict expected STALE, got: $OUT"
write_config "$P" true 72 on_stale   # loose: 24h age under 72h limit -> FRESH
run_hook "$P"
[[ "$LAST_EXIT" -eq 0 ]] || fail "AC8 loose expected exit 0"
[[ -z "$OUT" ]] || fail "AC8 loose expected FRESH silent, got: [$OUT]"
ok "AC8: same state flips STALE<->FRESH between strict and loose config (threshold honored)"

# === AC8-c: missing config -> fail-open built-in defaults + exit 0 ==========
# Built-in default max_age_hours is 48. State 12h old -> under default -> FRESH.
P="$TMP/p_noconfig_fresh"; make_state "$P" "$(ts_hours_ago 12)"
run_hook "$P"
[[ "$LAST_EXIT" -eq 0 ]] || fail "AC8-c (no config, fresh) expected exit 0, got $LAST_EXIT"
[[ -z "$OUT" ]] || fail "AC8-c expected FRESH silent under built-in default (48h), got: [$OUT]"
# State 100h old -> over built-in default 48h -> STALE with default limit.
P="$TMP/p_noconfig_stale"; make_state "$P" "$(ts_hours_ago 100)"
run_hook "$P"
[[ "$LAST_EXIT" -eq 0 ]] || fail "AC8-c (no config, stale) expected exit 0"
printf '%s' "$OUT" | grep -q 'full_corpus_age_hours 100/48' || fail "AC8-c expected built-in default 48, got: $OUT"
ok "AC8-c: missing config fails open to built-in default threshold (48h) and exits 0"

# Malformed config -> fail open to defaults + exit 0.
P="$TMP/p_badconfig"; make_state "$P" "$(ts_hours_ago 1)"
printf 'this: is: not: valid: yaml: [[[\n  broken' > "$P/workspace-config.yaml"
run_hook "$P"
[[ "$LAST_EXIT" -eq 0 ]] || fail "AC8-c malformed config expected exit 0, got $LAST_EXIT"
ok "AC8-c: malformed config still exits 0 (built-in defaults)"

# === AC8-d: missing / corrupt state -> fail-open exit 0 =====================
# Absent state file: never-run -> treated as stale (advisory) but STILL exit 0.
P="$TMP/p_nostate"; mkdir -p "$P"
write_config "$P" true 48 on_stale
run_hook "$P"
[[ "$LAST_EXIT" -eq 0 ]] || fail "AC8-d absent state expected exit 0, got $LAST_EXIT"
printf '%s' "$OUT" | grep -q 'decision=STALE' || fail "AC8-d absent state expected never-run STALE advisory, got: $OUT"
printf '%s' "$OUT" | grep -q 'never recorded as run' || fail "AC8-d expected never-run wording, got: $OUT"
ok "AC8-d: absent state file -> never-run STALE advisory, exit 0 (never blocks)"

# Corrupt state file -> fail open, treated as never-run, exit 0.
P="$TMP/p_corruptstate"; mkdir -p "$P/.polaris/runtime/selftest-staleness"
printf '{not valid json' > "$P/.polaris/runtime/selftest-staleness/last-full-corpus-run.json"
write_config "$P" true 48 on_stale
run_hook "$P"
[[ "$LAST_EXIT" -eq 0 ]] || fail "AC8-d corrupt state expected exit 0, got $LAST_EXIT"
ok "AC8-d: corrupt state file -> exit 0 (fail-open)"

# Bare directory (no config, no state, never-run) -> exit 0.
P="$TMP/p_bare"; mkdir -p "$P"
run_hook "$P"
[[ "$LAST_EXIT" -eq 0 ]] || fail "AC8-d bare dir expected exit 0, got $LAST_EXIT"
ok "AC8-d: bare directory (no config, no state) -> exit 0"

# === enabled:false -> silent, exit 0 (even when stale) ======================
P="$TMP/p_disabled"; make_state "$P" "$(ts_hours_ago 100)"
write_config "$P" false 48 on_stale
run_hook "$P"
[[ "$LAST_EXIT" -eq 0 ]] || fail "enabled:false expected exit 0"
[[ -z "$OUT" ]] || fail "enabled:false expected silent stdout even when stale, got: [$OUT]"
ok "enabled:false: silent stdout + exit 0 even over threshold"

# === surface=always: FRESH still emits a marker ============================
P="$TMP/p_always"; make_state "$P" "$(ts_hours_ago 1)"
write_config "$P" true 48 always
run_hook "$P"
[[ "$LAST_EXIT" -eq 0 ]] || fail "surface=always expected exit 0"
printf '%s' "$OUT" | grep -q 'decision=FRESH' || fail "surface=always expected FRESH marker, got: $OUT"
ok "surface=always: FRESH state emits [SELFTEST-STALE] decision=FRESH marker"

# === --report mode: dumps the axis regardless of decision, exit 0 ===========
P="$TMP/p_report"; make_state "$P" "$(ts_hours_ago 1)"
write_config "$P" true 48 on_stale
RPT="$(CLAUDE_PROJECT_DIR="$P" bash "$HOOK" --report 2>/dev/null)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "--report expected exit 0, got $rc"
printf '%s' "$RPT" | grep -q 'full_corpus_age_hours' || fail "--report missing age axis, got: $RPT"
ok "--report: dumps full_corpus_age_hours axis with exit 0"

# === Negative contract: no filesystem mutation (read-only eval) =============
P="$TMP/p_nomutate"; make_state "$P" "$(ts_hours_ago 1)"
write_config "$P" true 48 on_stale
before="$(find "$P" -type f | sort | xargs -I{} sh -c 'printf "%s %s\n" "{}" "$(wc -c < "{}")"' 2>/dev/null | sort)"
run_hook "$P" >/dev/null
after="$(find "$P" -type f | sort | xargs -I{} sh -c 'printf "%s %s\n" "{}" "$(wc -c < "{}")"' 2>/dev/null | sort)"
[[ "$before" == "$after" ]] || fail "negative contract: hook mutated filesystem: $(diff <(printf '%s' "$before") <(printf '%s' "$after"))"
ok "negative contract: hook performs no filesystem mutation (read-only eval)"

# === Negative contract: no env/secret leak into stdout ======================
P="$TMP/p_noenv"; make_state "$P" "$(ts_hours_ago 100)"
write_config "$P" true 48 on_stale
LEAK="$(printf '{"session_id": "sessX"}' \
  | CLAUDE_PROJECT_DIR="$P" SECRET_CANARY="POLARIS_SECRET_CANARY_VALUE_12345" bash "$HOOK" 2>/dev/null)"
printf '%s' "$LEAK" | grep -q 'POLARIS_SECRET_CANARY_VALUE_12345' && fail "negative contract: leaked env value into stdout"
printf '%s' "$LEAK" | grep -Eq '(^|[^A-Za-z_])PATH=' && fail "negative contract: leaked PATH= style env into stdout"
ok "negative contract: hook stdout contains no env/secret values"

# === Negative contract: no network/build tokens in hook source =============
for forbidden in 'curl' 'wget' 'npm ' 'pnpm ' 'yarn ' 'http://' 'https://'; do
  if grep -nE "(^|[^A-Za-z_])${forbidden}" "$HOOK" >/dev/null 2>&1; then
    fail "negative contract: hook source references forbidden network/build token: '$forbidden'"
  fi
done
ok "negative contract: hook source contains no network/build invocations (pure-local)"

# === Negative contract: no EXECUTABLE exit 2 (must not block the prompt) =====
# Strip full-line comments first so the prose "exit 2 ... is forbidden here" in
# the hook's header does not false-positive. We only forbid a runnable exit 2.
if grep -vE '^[[:space:]]*#' "$HOOK" \
   | grep -nE '(^|[^A-Za-z0-9_])exit[[:space:]]+2([^0-9]|$)' >/dev/null 2>&1; then
  fail "negative contract: hook contains an executable 'exit 2' (must never block the prompt)"
fi
ok "negative contract: hook never executes exit 2 (fail-open only)"

echo "ALL PASS ($PASS_COUNT checks)"
