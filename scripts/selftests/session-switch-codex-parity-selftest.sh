#!/usr/bin/env bash
# Purpose: Cross-runtime (Codex) parity selftest for the DP-291 per-response
#          session-switch mechanism (session-switch-eval + session-pressure-tick).
#          AC7 coverage: the mechanism-registry Runtime Annotation Registry carries
#          rows for both session-switch hooks; the session-switch-advisory rule
#          documents the four-lane cross-runtime taxonomy (claude-code-native /
#          codex-native-candidate / codex-wrapper-guaranteed / copilot-fallback);
#          a Codex-equivalent UserPromptSubmit payload yields the same single
#          deterministic [SESSION-SWITCH] marker (native probe), and that marker is
#          a single deterministic line an app-server / SDK wrapper lane can
#          deterministically prepend before a turn (wrapper probe).
#          AC-NEG2 coverage: neither hook auto-switches the session, mutates state
#          beyond .polaris/runtime/session-pressure, nor dumps env/secrets to stdout.
# Inputs:  None (builds its own hermetic tmp project as CLAUDE_PROJECT_DIR).
# Outputs: Prints PASS on success; exits non-zero with FAIL on any assertion.
# Side effects: none beyond its own mktemp dir (removed on exit).

# Not using `set -e`: assertions branch on captured exit codes; a stray non-zero
# from grep -c (no match) must not abort the run before its assertion is checked.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGISTRY="$ROOT/.claude/rules/mechanism-registry.md"
ADVISORY="$ROOT/.claude/rules/session-switch-advisory.md"
EVAL_HOOK="$ROOT/.claude/hooks/session-switch-eval.sh"
TICK_HOOK="$ROOT/.claude/hooks/session-pressure-tick.sh"

EVAL_HOOK_REL=".claude/hooks/session-switch-eval.sh"
TICK_HOOK_REL=".claude/hooks/session-pressure-tick.sh"

CHECKS=0
fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; CHECKS=$((CHECKS + 1)); }

[[ -f "$REGISTRY" ]]  || fail "mechanism-registry not found: $REGISTRY"
[[ -x "$EVAL_HOOK" ]] || fail "session-switch-eval hook not found/executable: $EVAL_HOOK"
[[ -x "$TICK_HOOK" ]] || fail "session-pressure-tick hook not found/executable: $TICK_HOOK"

# registry_row_for <hook-rel-path> — echo the Runtime Annotation Registry table
# row (a single `| ... |` line) that annotates the given hook path, or empty.
registry_row_for() {
  local hook_rel="$1"
  awk -v hook="$hook_rel" '
    $0 == "## Runtime Annotation Registry" { cap = 1; next }
    cap && /^## / { exit }
    cap && /^\|/ && index($0, hook) { print; exit }
  ' "$REGISTRY"
}

# ---- AC7.1: Runtime Annotation Registry rows for both session-switch hooks ----
for hook_rel in "$EVAL_HOOK_REL" "$TICK_HOOK_REL"; do
  row="$(registry_row_for "$hook_rel")"
  [[ -n "$row" ]] || fail "AC7: Runtime Annotation Registry has no row for $hook_rel"
  # Cells: | mechanism | path | kind | runtime | fallback_script | governance_role |
  kind="$(printf '%s' "$row" | awk -F'|' '{gsub(/^[ \t`]+|[ \t`]+$/,"",$4); print $4}')"
  runtime="$(printf '%s' "$row" | awk -F'|' '{gsub(/^[ \t`]+|[ \t`]+$/,"",$5); print $5}')"
  [[ "$kind" == "hook" ]] || fail "AC7: $hook_rel row kind must be 'hook' (got '$kind')"
  case "$runtime" in
    portable | claude-code-only) ;;
    *) fail "AC7: $hook_rel row runtime must be portable|claude-code-only (got '$runtime')" ;;
  esac
done
pass "AC7: runtime annotation rows present for both session-switch hooks"

# ---- AC7.2: advisory rule documents the four-lane cross-runtime taxonomy ----
[[ -f "$ADVISORY" ]] || fail "AC7: session-switch-advisory rule missing: $ADVISORY"
for token in claude-code-native codex-native-candidate codex-wrapper-guaranteed copilot-fallback; do
  grep -qF "$token" "$ADVISORY" || fail "AC7: advisory rule missing cross-runtime taxonomy token: $token"
done
pass "AC7: advisory rule documents the four-lane cross-runtime taxonomy"

# ---- Hermetic SWITCH-state fixture (low limits + saturated state force SWITCH) ----
TMP="$(mktemp -d -t dp291-codex-parity.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
PROJECT="$TMP/project"
STATE_DIR="$PROJECT/.polaris/runtime/session-pressure"
mkdir -p "$STATE_DIR"
cat > "$PROJECT/workspace-config.yaml" <<'YAML'
defaults:
  session_switch:
    enabled: true
    tool_call_limit: 2
    turn_limit: 2
    elapsed_minutes_limit: 1
    minutes_since_checkpoint_limit: 1
    surface: on_switch
YAML
SID="codex-parity-session"
cat > "$STATE_DIR/$SID.json" <<JSON
{"tool_call_count": 50, "turn_count": 50, "first_seen_ts": "2000-01-01T00:00:00Z"}
JSON

# run_eval — feed a Codex-equivalent UserPromptSubmit payload to the eval hook.
run_eval() {
  printf '{"session_id":"%s","prompt":"hi"}' "$SID" \
    | CLAUDE_PROJECT_DIR="$PROJECT" bash "$EVAL_HOOK" 2>/dev/null
}

# ---- AC7.3: Codex-native probe — equivalent payload yields a SWITCH marker ----
set +e
out1="$(run_eval)"; rc=$?
set -e 2>/dev/null || true
[[ "$rc" -eq 0 ]] || fail "AC7 native probe: eval hook exited $rc (must exit 0, never block)"
printf '%s\n' "$out1" | grep -q '^\[SESSION-SWITCH\] decision=SWITCH' \
  || fail "AC7 native probe: expected [SESSION-SWITCH] decision=SWITCH marker, got: $out1"
pass "AC7: Codex-native probe — equivalent UserPromptSubmit payload yields SWITCH marker"

# ---- AC7.4: wrapper probe — marker is a single deterministic prependable line ----
out2="$(run_eval)"
[[ "$out1" == "$out2" ]] || fail "AC7 wrapper probe: marker not deterministic across runs"
marker_lines="$(printf '%s\n' "$out1" | grep -c '.')"
[[ "$marker_lines" -eq 1 ]] \
  || fail "AC7 wrapper probe: marker must be a single line a wrapper can prepend (got $marker_lines)"
pass "AC7: wrapper probe — marker is a single deterministic line for app-server/SDK prepend"

# ---- AC-NEG2: no env/secret dump; mutations confined to session-pressure state ----
snapshot() { ( cd "$PROJECT" && find . -type f | sort ); }
before="$(snapshot)"
eval_out="$(run_eval)"
tick_out="$(printf '{"session_id":"%s","tool_name":"Bash","tool_input":{},"tool_response":{}}' "$SID" \
  | CLAUDE_PROJECT_DIR="$PROJECT" bash "$TICK_HOOK" 2>/dev/null)"
after="$(snapshot)"

for blob in "$eval_out" "$tick_out"; do
  # An env/secret dump surfaces as an UPPERCASE NAME=value assignment at line
  # start, or a well-known secret token. The marker line starts with '[' and uses
  # a lowercase `decision=` key, so it never matches.
  if printf '%s\n' "$blob" | grep -Eq '^[A-Z][A-Z0-9_]*='; then
    fail "AC-NEG2: hook stdout contains an env-variable assignment line"
  fi
  if printf '%s\n' "$blob" | grep -Eq '(SECRET|TOKEN|PASSWORD|API_KEY|AWS_SECRET|PRIVATE_KEY)'; then
    fail "AC-NEG2: hook stdout contains a secret-like token"
  fi
done

newfiles="$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after"))"
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  case "$f" in
    ./.polaris/runtime/session-pressure/*) ;;
    *) fail "AC-NEG2: unexpected mutation outside session-pressure state: $f" ;;
  esac
done <<< "$newfiles"
pass "AC-NEG2: no env/secret dump; mutations confined to .polaris/runtime/session-pressure"

echo "PASS: session-switch-codex-parity-selftest ($CHECKS checks)"
