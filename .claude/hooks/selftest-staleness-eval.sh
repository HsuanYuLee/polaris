#!/usr/bin/env bash
# Purpose: UserPromptSubmit eval hook (DP-360 T5) — full-corpus selftest
#          staleness advisory. Clones the session-switch-eval (DP-291 D9) pattern:
#          reads the last-full-corpus-run state file and the workspace-config.yaml
#          defaults.selftest_staleness threshold, computes hours-since-last-run,
#          and applies a single-axis over-limit check (age >= max_age_hours ->
#          STALE, else FRESH). On STALE (surface=on_stale) injects a single-line
#          [SELFTEST-STALE] advisory carrying the raw hours/limit + percentage so
#          the user can decide whether to run the full corpus. FRESH under
#          surface=on_stale is silent (empty stdout) to avoid per-turn noise.
# Inputs:  stdin = UserPromptSubmit hook JSON payload (unused fields tolerated).
#          CLAUDE_PROJECT_DIR (project root); --report flag dumps the axis state.
#          Threshold: workspace-config.yaml -> defaults.selftest_staleness.
#          State: .polaris/runtime/selftest-staleness/last-full-corpus-run.json
#          (JSON field last_full_corpus_run_ts, ISO-8601 UTC).
# Outputs: stdout = [SELFTEST-STALE] advisory on STALE (or --report dump),
#          empty on silent FRESH. ALWAYS exit 0 — never blocks the prompt (AC8).
# Side effects: none beyond reading files (no state mutation, no network, no
#          build, no env/secrets dump). exit 2 would block the prompt and is
#          forbidden here; every error branch fails open with exit 0.

# Intentionally NOT using `set -e`: AC8 requires exit 0 on every branch,
# including corrupt state / missing config / non-git directory. A stray non-zero
# from an intermediate command must never propagate into a prompt block.
set -uo pipefail 2>/dev/null || set -u

# --- Built-in fail-open defaults (used when config is missing/unreadable) ---
# The single pressure axis is wall-clock age (hours) since the last recorded
# full-corpus selftest run. Name encodes purpose; unit noted inline.
DEFAULT_ENABLED="true"
DEFAULT_MAX_AGE_HOURS=48            # hours since last full-corpus run before STALE
DEFAULT_SURFACE="on_stale"         # on_stale (silent FRESH) | always

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
REPORT_MODE="false"
[[ "${1:-}" == "--report" ]] && REPORT_MODE="true"

# --- Read stdin payload (best-effort; never fatal) ---
if [[ "$REPORT_MODE" == "false" ]]; then
  # Drain stdin so the hook does not block, but we do not need any field from it.
  cat >/dev/null 2>&1 || true
fi

# --- Resolve threshold from workspace-config.yaml (fail-open to defaults) ---
MAX_AGE_HOURS="$DEFAULT_MAX_AGE_HOURS"
SURFACE="$DEFAULT_SURFACE"
ENABLED="$DEFAULT_ENABLED"

config_file="$PROJECT_DIR/workspace-config.yaml"
if [[ -r "$config_file" ]]; then
  # Parse defaults.selftest_staleness with python3 stdlib only (no PyYAML
  # dependency): a minimal indentation-aware reader for the single nested block
  # we own. Mirrors session-switch-eval.sh's parser shape.
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


# Find `defaults:` at column 0, then `selftest_staleness:` under it, then keys.
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
        if not in_block:
            in_defaults = False
        if in_block and ci <= (block_indent if block_indent is not None else 0):
            break
    if not in_block:
        if stripped.rstrip() == "selftest_staleness:" and ci > defaults_indent:
            in_block = True
            block_indent = None
        continue
    # inside selftest_staleness block
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
      enabled)        ENABLED="$v" ;;
      max_age_hours)  MAX_AGE_HOURS="$v" ;;
      surface)        SURFACE="$v" ;;
    esac
  done <<< "$cfg"
fi

# Validate numeric limit; any non-integer falls back to its built-in default so
# a malformed config still fails open rather than poisoning arithmetic.
ensure_int() {
  local val="$1" fallback="$2"
  [[ "$val" =~ ^[0-9]+$ ]] && { printf '%s' "$val"; return; }
  printf '%s' "$fallback"
}
MAX_AGE_HOURS="$(ensure_int "$MAX_AGE_HOURS" "$DEFAULT_MAX_AGE_HOURS")"

# --- Read last-full-corpus-run state (fail-open: absent/corrupt -> no run) ---
state_file="$PROJECT_DIR/.polaris/runtime/selftest-staleness/last-full-corpus-run.json"
last_run_ts=""
if [[ -r "$state_file" ]]; then
  last_run_ts="$(python3 - "$state_file" <<'PY' 2>/dev/null || true
import sys, json
try:
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        d = json.load(fh)
    ts = d.get("last_full_corpus_run_ts", "")
    sys.stdout.write(str(ts) if ts is not None else "")
except Exception:
    pass
PY
)"
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

# --- Compute age axis ---
# No state / unparseable timestamp -> NEVER_RUN: treat as maximally stale so the
# advisory fires (the corpus has never been recorded as run). This still exits 0.
never_run="false"
last_run_epoch="$(iso_to_epoch "$last_run_ts")"
if [[ -z "$last_run_epoch" || ! "$last_run_epoch" =~ ^[0-9]+$ ]]; then
  never_run="true"
  age_hours="$MAX_AGE_HOURS"
else
  age_hours=$(( (now_epoch - last_run_epoch) / 3600 ))
  (( age_hours < 0 )) && age_hours=0
fi

# --- Over-limit evaluation (single axis) ---
# pct hours/limit, guarding divide-by-zero (limit 0 -> treat as 0%).
pct() {
  local n="$1" limit="$2"
  if [[ "$limit" -le 0 ]]; then printf '0'; return; fi
  printf '%s' $(( n * 100 / limit ))
}

decision="FRESH"
if (( age_hours >= MAX_AGE_HOURS )); then
  decision="STALE"
fi

# --- --report mode: dump the axis regardless of decision ---
if [[ "$REPORT_MODE" == "true" ]]; then
  printf '[SELFTEST-STALE report] decision=%s\n' "$decision"
  if [[ "$never_run" == "true" ]]; then
    printf '  full_corpus_age_hours: never-run (treated as >= limit)\n'
  fi
  printf '  full_corpus_age_hours: %s/%s = %s%%\n' "$age_hours" "$MAX_AGE_HOURS" "$(pct "$age_hours" "$MAX_AGE_HOURS")"
  exit 0
fi

# Disabled -> silent, no advisory.
if [[ "$ENABLED" != "true" ]]; then
  exit 0
fi

# --- Surface the decision ---
if [[ "$decision" == "STALE" ]]; then
  if [[ "$never_run" == "true" ]]; then
    printf '[SELFTEST-STALE] decision=STALE; full corpus never recorded as run; consider running the full selftest corpus\n'
  else
    printf '[SELFTEST-STALE] decision=STALE; full_corpus_age_hours %s/%s = %s%%; consider running the full selftest corpus\n' \
      "$age_hours" "$MAX_AGE_HOURS" "$(pct "$age_hours" "$MAX_AGE_HOURS")"
  fi
elif [[ "$SURFACE" == "always" ]]; then
  printf '[SELFTEST-STALE] decision=FRESH; full_corpus_age_hours %s/%s = %s%%\n' \
    "$age_hours" "$MAX_AGE_HOURS" "$(pct "$age_hours" "$MAX_AGE_HOURS")"
fi
# surface=on_stale + FRESH -> empty stdout (silent CONTINUE equivalent).

exit 0
