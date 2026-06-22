#!/usr/bin/env bash
# Purpose: UserPromptSubmit eval hook — per-response deterministic session-switch
#          recommendation. Reads the session-keyed pressure state file, the
#          workspace-config.yaml session_switch thresholds, and the newest
#          checkpoint mtime, computes four pressure axes, and applies
#          OR-of-limits (any axis over its limit -> SWITCH, else CONTINUE).
#          On SWITCH (surface=on_switch) injects a single-line [SESSION-SWITCH]
#          marker carrying the decision, the over-limit trigger axes and their
#          raw n/limit + percentage so the user can calibrate. CONTINUE under
#          surface=on_switch is silent (empty stdout) to avoid per-turn noise.
# Inputs:  stdin = UserPromptSubmit hook JSON payload (uses session_id).
#          CLAUDE_PROJECT_DIR (project root); --report flag dumps all four axes.
#          Thresholds: workspace-config.yaml -> defaults.session_switch.
# Outputs: stdout = [SESSION-SWITCH] marker on SWITCH (or --report dump),
#          empty on silent CONTINUE. ALWAYS exit 0 — never blocks the prompt.
# Side effects: none beyond reading files (no session mutation, no network,
#          no build, no env/secrets dump). exit 2 would block the prompt and is
#          forbidden here; every error branch fails open with exit 0.

# Intentionally NOT using `set -e`: AC-NEG1 requires exit 0 on every branch,
# including corrupt state / missing config / non-git directory. A stray non-zero
# from an intermediate command must never propagate into a prompt block.
set -uo pipefail 2>/dev/null || set -u

# --- Built-in fail-open defaults (used when config is missing/unreadable) ---
# Each limit is the OR-of-limits threshold for its pressure axis. Names encode
# purpose; units noted inline.
DEFAULT_ENABLED="true"
DEFAULT_TOOL_CALL_LIMIT=40          # tool calls accumulated this session
DEFAULT_TURN_LIMIT=30               # user prompts (turns) this session
DEFAULT_ELAPSED_MINUTES_LIMIT=120   # wall-clock minutes since session first seen
DEFAULT_MINUTES_SINCE_CHECKPOINT_LIMIT=45  # minutes since newest checkpoint mtime
DEFAULT_SURFACE="on_switch"         # on_switch (silent CONTINUE) | always

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
REPORT_MODE="false"
[[ "${1:-}" == "--report" ]] && REPORT_MODE="true"

# --- Read stdin payload (best-effort; never fatal) ---
payload=""
if [[ "$REPORT_MODE" == "false" ]]; then
  payload="$(cat 2>/dev/null || true)"
fi

# Extract a JSON string field via python3 (stdlib only). Empty on any failure.
json_field() {
  local raw="$1" key="$2"
  printf '%s' "$raw" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    v = d.get('$key', '')
    sys.stdout.write(str(v) if v is not None else '')
except Exception:
    pass
" 2>/dev/null || true
}

session_id=""
[[ -n "$payload" ]] && session_id="$(json_field "$payload" session_id)"
# Sanitize session_id to a safe filename token; fall back to a fixed key so a
# missing/odd session_id still resolves to a readable (possibly absent) state file.
session_id="$(printf '%s' "$session_id" | tr -cd 'A-Za-z0-9._-')"
[[ -z "$session_id" ]] && session_id="unknown-session"

# --- Resolve thresholds from workspace-config.yaml (fail-open to defaults) ---
TOOL_CALL_LIMIT="$DEFAULT_TOOL_CALL_LIMIT"
TURN_LIMIT="$DEFAULT_TURN_LIMIT"
ELAPSED_MINUTES_LIMIT="$DEFAULT_ELAPSED_MINUTES_LIMIT"
MINUTES_SINCE_CHECKPOINT_LIMIT="$DEFAULT_MINUTES_SINCE_CHECKPOINT_LIMIT"
SURFACE="$DEFAULT_SURFACE"
ENABLED="$DEFAULT_ENABLED"

config_file="$PROJECT_DIR/workspace-config.yaml"
if [[ -r "$config_file" ]]; then
  # Parse defaults.session_switch with python3 stdlib only (no PyYAML dependency):
  # a minimal indentation-aware reader for the single nested block we own.
  cfg="$(python3 - "$config_file" <<'PY' 2>/dev/null || true
import sys

path = sys.argv[1]
out = {}
try:
    with open(path, "r", encoding="utf-8") as fh:
        lines = fh.readlines()
except Exception:
    sys.exit(0)


def indent(s):
    return len(s) - len(s.lstrip(" "))


# Find `defaults:` at column 0, then `session_switch:` under it, then its keys.
in_defaults = False
defaults_indent = None
in_block = False
block_indent = None
for raw in lines:
    line = raw.rstrip("\n")
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    ci = indent(line)
    stripped = line.strip()
    if not in_defaults:
        if stripped == "defaults:" and ci == 0:
            in_defaults = True
            defaults_indent = ci
        continue
    # inside defaults
    if ci <= defaults_indent and stripped != "defaults:":
        # dedented out of defaults entirely
        if not in_block:
            in_defaults = False
        # if we were in the block and dedent to <= defaults, block ends too
        if in_block and ci <= (block_indent if block_indent is not None else 0):
            break
    if not in_block:
        if stripped.rstrip() == "session_switch:" and ci > defaults_indent:
            in_block = True
            block_indent = None
        continue
    # inside session_switch block
    if block_indent is None:
        block_indent = ci
    if ci < block_indent:
        break
    if ci == block_indent and ":" in stripped:
        k, _, v = stripped.partition(":")
        k = k.strip()
        v = v.strip().strip('"').strip("'")
        if k and v != "":
            out[k] = v

for k, v in out.items():
    print(f"{k}={v}")
PY
)"
  # Apply parsed values (only override when present & non-empty).
  while IFS='=' read -r k v; do
    [[ -z "$k" ]] && continue
    case "$k" in
      enabled)                          ENABLED="$v" ;;
      tool_call_limit)                  TOOL_CALL_LIMIT="$v" ;;
      turn_limit)                       TURN_LIMIT="$v" ;;
      elapsed_minutes_limit)            ELAPSED_MINUTES_LIMIT="$v" ;;
      minutes_since_checkpoint_limit)   MINUTES_SINCE_CHECKPOINT_LIMIT="$v" ;;
      surface)                          SURFACE="$v" ;;
    esac
  done <<< "$cfg"
fi

# Validate numeric limits; any non-integer falls back to its built-in default so
# a malformed config still fails open rather than poisoning arithmetic.
ensure_int() {
  local val="$1" fallback="$2"
  [[ "$val" =~ ^[0-9]+$ ]] && { printf '%s' "$val"; return; }
  printf '%s' "$fallback"
}
TOOL_CALL_LIMIT="$(ensure_int "$TOOL_CALL_LIMIT" "$DEFAULT_TOOL_CALL_LIMIT")"
TURN_LIMIT="$(ensure_int "$TURN_LIMIT" "$DEFAULT_TURN_LIMIT")"
ELAPSED_MINUTES_LIMIT="$(ensure_int "$ELAPSED_MINUTES_LIMIT" "$DEFAULT_ELAPSED_MINUTES_LIMIT")"
MINUTES_SINCE_CHECKPOINT_LIMIT="$(ensure_int "$MINUTES_SINCE_CHECKPOINT_LIMIT" "$DEFAULT_MINUTES_SINCE_CHECKPOINT_LIMIT")"

# --- Read session-keyed state (fail-open: absent/corrupt -> zeros) ---
state_file="$PROJECT_DIR/.polaris/runtime/session-pressure/${session_id}.json"
tool_call_count=0
turn_count=0
first_seen_ts=""
if [[ -r "$state_file" ]]; then
  state_kv="$(python3 - "$state_file" <<'PY' 2>/dev/null || true
import sys, json
try:
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        d = json.load(fh)
    print("tool_call_count=%s" % int(d.get("tool_call_count", 0) or 0))
    print("turn_count=%s" % int(d.get("turn_count", 0) or 0))
    fs = d.get("first_seen_ts", "")
    print("first_seen_ts=%s" % (fs if fs is not None else ""))
except Exception:
    pass
PY
)"
  while IFS='=' read -r k v; do
    case "$k" in
      tool_call_count) [[ "$v" =~ ^[0-9]+$ ]] && tool_call_count="$v" ;;
      turn_count)      [[ "$v" =~ ^[0-9]+$ ]] && turn_count="$v" ;;
      first_seen_ts)   first_seen_ts="$v" ;;
    esac
  done <<< "$state_kv"
fi

now_epoch="$(date -u +%s 2>/dev/null || printf '0')"

# Convert an ISO-8601 UTC timestamp to epoch seconds (portable; GNU & BSD date).
iso_to_epoch() {
  local ts="$1" e=""
  [[ -z "$ts" ]] && { printf ''; return; }
  e="$(date -u -d "$ts" +%s 2>/dev/null || true)"
  [[ -z "$e" ]] && e="$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null || true)"
  printf '%s' "$e"
}

first_seen_epoch="$(iso_to_epoch "$first_seen_ts")"
# No state / unparseable first_seen -> treat session as just started (0 elapsed).
[[ -z "$first_seen_epoch" || ! "$first_seen_epoch" =~ ^[0-9]+$ ]] && first_seen_epoch="$now_epoch"

elapsed_minutes=$(( (now_epoch - first_seen_epoch) / 60 ))
(( elapsed_minutes < 0 )) && elapsed_minutes=0

# --- Newest checkpoint mtime -> minutes_since_checkpoint ---
# No checkpoint yet: anchor to session first_seen so we never report a bogus
# huge value (edge case in refinement.json).
checkpoint_dir="$PROJECT_DIR/.claude/checkpoints"
newest_ckpt_epoch=""
if [[ -d "$checkpoint_dir" ]]; then
  # Largest mtime among checkpoint files (portable stat for GNU & BSD).
  for f in "$checkpoint_dir"/*; do
    [[ -f "$f" ]] || continue
    m="$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || true)"
    [[ "$m" =~ ^[0-9]+$ ]] || continue
    if [[ -z "$newest_ckpt_epoch" || "$m" -gt "$newest_ckpt_epoch" ]]; then
      newest_ckpt_epoch="$m"
    fi
  done
fi
[[ -z "$newest_ckpt_epoch" ]] && newest_ckpt_epoch="$first_seen_epoch"
minutes_since_checkpoint=$(( (now_epoch - newest_ckpt_epoch) / 60 ))
(( minutes_since_checkpoint < 0 )) && minutes_since_checkpoint=0

# --- OR-of-limits evaluation ---
# pct n/limit, guarding divide-by-zero (limit 0 -> treat as 0%).
pct() {
  local n="$1" limit="$2"
  if [[ "$limit" -le 0 ]]; then printf '0'; return; fi
  printf '%s' $(( n * 100 / limit ))
}

triggers=""   # space-joined "axis n/limit pct%" fragments for over-limit axes
add_trigger() {
  local name="$1" n="$2" limit="$3"
  if (( n >= limit )); then
    local p; p="$(pct "$n" "$limit")"
    local frag="${name} ${n}/${limit} = ${p}%"
    if [[ -z "$triggers" ]]; then triggers="$frag"; else triggers="${triggers}; ${frag}"; fi
  fi
}

add_trigger "tool_calls" "$tool_call_count" "$TOOL_CALL_LIMIT"
add_trigger "turns" "$turn_count" "$TURN_LIMIT"
add_trigger "elapsed_minutes" "$elapsed_minutes" "$ELAPSED_MINUTES_LIMIT"
add_trigger "minutes_since_checkpoint" "$minutes_since_checkpoint" "$MINUTES_SINCE_CHECKPOINT_LIMIT"

decision="CONTINUE"
[[ -n "$triggers" ]] && decision="SWITCH"

# --- --report mode: dump all four axes regardless of decision ---
if [[ "$REPORT_MODE" == "true" ]]; then
  printf '[SESSION-SWITCH report] decision=%s\n' "$decision"
  printf '  tool_calls: %s/%s = %s%%\n' "$tool_call_count" "$TOOL_CALL_LIMIT" "$(pct "$tool_call_count" "$TOOL_CALL_LIMIT")"
  printf '  turns: %s/%s = %s%%\n' "$turn_count" "$TURN_LIMIT" "$(pct "$turn_count" "$TURN_LIMIT")"
  printf '  elapsed_minutes: %s/%s = %s%%\n' "$elapsed_minutes" "$ELAPSED_MINUTES_LIMIT" "$(pct "$elapsed_minutes" "$ELAPSED_MINUTES_LIMIT")"
  printf '  minutes_since_checkpoint: %s/%s = %s%%\n' "$minutes_since_checkpoint" "$MINUTES_SINCE_CHECKPOINT_LIMIT" "$(pct "$minutes_since_checkpoint" "$MINUTES_SINCE_CHECKPOINT_LIMIT")"
  exit 0
fi

# Disabled -> silent, no marker.
if [[ "$ENABLED" != "true" ]]; then
  exit 0
fi

# --- Surface the decision ---
if [[ "$decision" == "SWITCH" ]]; then
  printf '[SESSION-SWITCH] decision=SWITCH; triggered: %s\n' "$triggers"
elif [[ "$SURFACE" == "always" ]]; then
  printf '[SESSION-SWITCH] decision=CONTINUE; all axes under limit\n'
fi
# surface=on_switch + CONTINUE -> empty stdout (AC-NEG3).

exit 0
