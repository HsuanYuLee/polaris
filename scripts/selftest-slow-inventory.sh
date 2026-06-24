#!/usr/bin/env bash
# Purpose: pathological-slow selftest inventory + affected push-time baseline record
#          (DP-360 T-backstop / AC-NF1). Reads the T1 tier manifest cache produced by
#          selftest-tier-manifest.sh --measure (REUSE; this script never re-measures the
#          full corpus) and prints the "slow" tier — the selftests whose measured
#          wall-clock exceeds the speed threshold. The slow list is the precondition for
#          the DP-iteration/release full-corpus backstop to actually run (DP-349 de-rot
#          dependency); it is consumed for de-rot prioritisation, not as a gate.
#          Also emits the recorded affected push-time baseline (NF1 budget) so the
#          three-layer split (commit fast-lint / push affected-scoped / DP-iteration
#          full-corpus backstop) has a durable baseline artifact.
# Inputs:  --manifest <path>  tier manifest cache (default: scripts/selftest-tier-manifest.json).
#          --root <repo>      workspace root (default: repo containing this script).
#          --speed-threshold-ms <n>  slow cutoff (default 5000): wall_clock_ms > n is slow.
#          --format <text|json>  output format (default text).
#          --baseline-only    print only the affected push-time baseline block and exit 0.
# Outputs: stdout slow inventory (one selftest per line in text mode, or JSON) + a
#          baseline block; exit 0 on success, exit 2 on missing manifest / bad arg /
#          malformed cache (fail-closed; POLARIS_SLOW_INVENTORY_* markers).
set -euo pipefail

# Speed-axis default cutoff (ms): mirrors selftest-tier-manifest.sh so "slow" here means
# the same selftests the manifest pushes out of the fast-lint subset. Overridable so the
# same cached manifest can be re-bucketed without re-measuring.
DEFAULT_SPEED_THRESHOLD_MS=5000
# Affected push-time budget class (NF1): the push hot path runs only the affected-scoped
# subset (T3 affected-runner), targeting a tens-of-seconds wall-clock — NOT the full
# corpus. Full corpus is hour-scale (319 selftests; sampled 20 → 602s linear
# extrapolation per refinement risk row), hence backstop-only.
AFFECTED_PUSH_TIME_BUDGET_CLASS="tens-of-seconds"
FULL_CORPUS_SELFTEST_COUNT=319
FULL_CORPUS_SCALE="hour-scale (sampled 20 selftests = 602s, linear extrapolation)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST_PATH=""
SPEED_THRESHOLD_MS="$DEFAULT_SPEED_THRESHOLD_MS"
FORMAT="text"
BASELINE_ONLY="false"

die() {
  printf '%s\n' "$1" >&2
  exit 2
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || die "POLARIS_TOOL_MISSING:$1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      [[ $# -ge 2 ]] || die "POLARIS_SLOW_INVENTORY_ARG: --root requires a value"
      ROOT_DIR="$(cd "$2" && pwd)" || die "POLARIS_SLOW_INVENTORY_ARG: --root path not found: $2"
      shift 2
      ;;
    --manifest)
      [[ $# -ge 2 ]] || die "POLARIS_SLOW_INVENTORY_ARG: --manifest requires a value"
      MANIFEST_PATH="$2"
      shift 2
      ;;
    --speed-threshold-ms)
      [[ $# -ge 2 ]] || die "POLARIS_SLOW_INVENTORY_ARG: --speed-threshold-ms requires a value"
      SPEED_THRESHOLD_MS="$2"
      shift 2
      ;;
    --format)
      [[ $# -ge 2 ]] || die "POLARIS_SLOW_INVENTORY_ARG: --format requires a value"
      FORMAT="$2"
      shift 2
      ;;
    --baseline-only)
      BASELINE_ONLY="true"
      shift
      ;;
    *)
      die "POLARIS_SLOW_INVENTORY_ARG: unknown argument: $1"
      ;;
  esac
done

case "$SPEED_THRESHOLD_MS" in
  '' | *[!0-9]*) die "POLARIS_SLOW_INVENTORY_ARG: --speed-threshold-ms must be a non-negative integer, got: $SPEED_THRESHOLD_MS" ;;
esac
case "$FORMAT" in
  text | json) ;;
  *) die "POLARIS_SLOW_INVENTORY_ARG: --format must be text|json, got: $FORMAT" ;;
esac

[[ -n "$MANIFEST_PATH" ]] || MANIFEST_PATH="$ROOT_DIR/scripts/selftest-tier-manifest.json"

# emit_baseline — print the affected push-time baseline block (NF1 budget record).
# Args: $1 = format (text|json). Side effects: none (read-only constants).
emit_baseline() {
  local fmt="$1"
  if [[ "$fmt" == "json" ]]; then
    printf '{"affected_push_time_budget_class":"%s","full_corpus_selftest_count":%d,"full_corpus_scale":"%s","backstop_lanes":["dp-iteration","release"],"hot_path_excluded":["pre-commit","pre-push"]}\n' \
      "$AFFECTED_PUSH_TIME_BUDGET_CLASS" "$FULL_CORPUS_SELFTEST_COUNT" "$FULL_CORPUS_SCALE"
    return 0
  fi
  printf 'AFFECTED_PUSH_TIME_BASELINE:\n'
  printf '  affected_push_time_budget_class=%s\n' "$AFFECTED_PUSH_TIME_BUDGET_CLASS"
  printf '  full_corpus_selftest_count=%d\n' "$FULL_CORPUS_SELFTEST_COUNT"
  printf '  full_corpus_scale=%s\n' "$FULL_CORPUS_SCALE"
  printf '  backstop_lanes=dp-iteration,release\n'
  printf '  hot_path_excluded=pre-commit,pre-push\n'
}

if [[ "$BASELINE_ONLY" == "true" ]]; then
  emit_baseline "$FORMAT"
  exit 0
fi

[[ -f "$MANIFEST_PATH" ]] || die "POLARIS_SLOW_INVENTORY_MANIFEST_MISSING: $MANIFEST_PATH (run scripts/selftest-tier-manifest.sh --measure first; this script reuses that cache and never re-measures)"
require_tool python3

# Parse the manifest into TSV (path<TAB>wall_clock_ms), fail-closed on a malformed cache.
manifest_tsv="$(python3 - "$MANIFEST_PATH" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        doc = json.load(fh)
    entries = doc["selftests"]
except Exception as exc:  # noqa: BLE001 - any malformed manifest is a contract failure
    print(f"POLARIS_SLOW_INVENTORY_MANIFEST_MALFORMED:{exc}", file=sys.stderr)
    sys.exit(2)

for e in entries:
    print(f'{e["path"]}\t{e["wall_clock_ms"]}')
PY
)" || die "POLARIS_SLOW_INVENTORY_MANIFEST_MALFORMED: cannot parse $MANIFEST_PATH"

# Collect slow selftests: wall_clock_ms > threshold. Sorted slowest-first for triage.
slow_records=""
while IFS=$'\t' read -r rel wall_ms; do
  [[ -n "$rel" ]] || continue
  if (( wall_ms > SPEED_THRESHOLD_MS )); then
    slow_records+="${wall_ms}	${rel}"$'\n'
  fi
done <<<"$manifest_tsv"

# Numeric-descending sort by wall_clock so the slowest (most pathological) lead.
slow_sorted="$(printf '%s' "$slow_records" | grep -v '^$' | LC_ALL=C sort -t$'\t' -k1,1nr || true)"
slow_count="$(printf '%s' "$slow_sorted" | grep -c '.' || true)"

if [[ "$FORMAT" == "json" ]]; then
  python3 - "$SPEED_THRESHOLD_MS" "$AFFECTED_PUSH_TIME_BUDGET_CLASS" \
    "$FULL_CORPUS_SELFTEST_COUNT" "$FULL_CORPUS_SCALE" <<PY
import json
import sys

threshold = int(sys.argv[1])
budget_class = sys.argv[2]
corpus_count = int(sys.argv[3])
corpus_scale = sys.argv[4]
raw = """$slow_sorted"""
slow = []
for line in raw.splitlines():
    if not line.strip():
        continue
    wall_ms, path = line.split("\t", 1)
    slow.append({"path": path, "wall_clock_ms": int(wall_ms)})

doc = {
    "slow_speed_threshold_ms": threshold,
    "slow_count": len(slow),
    "slow_selftests": slow,
    "affected_push_time_baseline": {
        "affected_push_time_budget_class": budget_class,
        "full_corpus_selftest_count": corpus_count,
        "full_corpus_scale": corpus_scale,
        "backstop_lanes": ["dp-iteration", "release"],
        "hot_path_excluded": ["pre-commit", "pre-push"],
    },
}
json.dump(doc, sys.stdout, indent=2, sort_keys=True)
sys.stdout.write("\n")
PY
  exit 0
fi

printf 'SLOW_SELFTEST_INVENTORY: threshold=%sms count=%s (source manifest: %s)\n' \
  "$SPEED_THRESHOLD_MS" "$slow_count" "$MANIFEST_PATH"
if [[ -n "$slow_sorted" ]]; then
  printf '%s\n' "$slow_sorted" | while IFS=$'\t' read -r wall_ms rel; do
    [[ -n "$rel" ]] || continue
    printf '  %sms\t%s\n' "$wall_ms" "$rel"
  done
fi
emit_baseline text
