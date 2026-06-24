#!/usr/bin/env bash
# Purpose: produce + read a selftest tier manifest. Enumerate the framework selftest
#          corpus (scripts/selftests/*-selftest.sh + scripts/*-selftest.sh, ~319),
#          and classify every selftest on TWO axes — speed (measured wall-clock) and
#          scope (parsed coverage paths) — then derive three deterministic, mechanically
#          reproducible subsets: fast-lint / affected / full-backstop (AC6). The manifest
#          feeds downstream T-affected / T-precommit / T-backstop selftest sharding.
# Inputs:  --root <repo>        workspace root (default: repo containing this script).
#          --manifest <path>    manifest cache file (default: scripts/selftest-tier-manifest.json).
#          --measure            MEASURE MODE: run every selftest, time wall-clock, parse
#                               scope, write the manifest cache. SLOW (full corpus ≈ 2.5h);
#                               only run during DP-iteration, never on the read hot path.
#          --emit <subset>      EMIT MODE: read the cached manifest and print one subset
#                               (fast-lint | affected | full-backstop), one repo-relative
#                               path per line, deterministically sorted. FAST (no test run).
#          --speed-threshold-ms <n>  speed-axis cutoff (default 5000): wall_clock_ms <= n
#                               is "fast", otherwise "slow". Overridable so the same cached
#                               manifest can be re-bucketed without re-measuring.
#          --list               print the enrolled corpus (repo-relative paths) and exit 0.
# Outputs: --measure  → writes manifest JSON to --manifest path; stdout summary; exit 0,
#                       exit 2 on contract/arg error.
#          --emit     → prints the selected subset to stdout; exit 0, exit 2 on missing
#                       manifest / bad subset / arg error (fail-closed; POLARIS_* markers).
set -euo pipefail

# --- Named constants ---------------------------------------------------------
# Speed-axis default cutoff (ms): a selftest whose measured wall-clock is at or below
# this is "fast", otherwise "slow". 5000ms keeps the fast-lint subset to sub-second-ish
# unit-style selftests and pushes fixture-heavy / spawn-heavy ones to "slow".
readonly DEFAULT_SPEED_THRESHOLD_MS=5000
# Manifest schema version — bump if the JSON shape or tier rules change so a stale
# cache produced by an older shape is detectable by consumers.
readonly MANIFEST_SCHEMA_VERSION=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST_PATH=""
MODE=""
EMIT_SUBSET=""
SPEED_THRESHOLD_MS="$DEFAULT_SPEED_THRESHOLD_MS"

die() {
  printf '%s\n' "$1" >&2
  exit 2
}

# require_tool — fail-stop with a POLARIS_TOOL_MISSING repair hint when a required
# Polaris-runtime binary is absent (no silent install).
# Args: $1 = tool name. Side effects: exit 2 if missing.
require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'POLARIS_TOOL_MISSING:%s — run `mise install` to restore the Polaris runtime toolchain\n' "$tool" >&2
    exit 2
  fi
}

# --- Arg parsing -------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      [[ $# -ge 2 ]] || die "POLARIS_SELFTEST_TIER_ARG: --root requires a value"
      ROOT_DIR="$(cd "$2" && pwd)" || die "POLARIS_SELFTEST_TIER_ARG: --root path not found: $2"
      shift 2
      ;;
    --manifest)
      [[ $# -ge 2 ]] || die "POLARIS_SELFTEST_TIER_ARG: --manifest requires a value"
      MANIFEST_PATH="$2"
      shift 2
      ;;
    --measure)
      MODE="measure"
      shift
      ;;
    --emit)
      [[ $# -ge 2 ]] || die "POLARIS_SELFTEST_TIER_ARG: --emit requires a subset value"
      MODE="emit"
      EMIT_SUBSET="$2"
      shift 2
      ;;
    --speed-threshold-ms)
      [[ $# -ge 2 ]] || die "POLARIS_SELFTEST_TIER_ARG: --speed-threshold-ms requires a value"
      SPEED_THRESHOLD_MS="$2"
      shift 2
      ;;
    --list)
      MODE="list"
      shift
      ;;
    *)
      die "POLARIS_SELFTEST_TIER_ARG: unknown argument: $1"
      ;;
  esac
done

[[ -n "$MODE" ]] || die "POLARIS_SELFTEST_TIER_ARG: one of --measure / --emit <subset> / --list is required"

case "$SPEED_THRESHOLD_MS" in
  '' | *[!0-9]*) die "POLARIS_SELFTEST_TIER_ARG: --speed-threshold-ms must be a non-negative integer, got: $SPEED_THRESHOLD_MS" ;;
esac

if [[ -z "$MANIFEST_PATH" ]]; then
  MANIFEST_PATH="$ROOT_DIR/scripts/selftest-tier-manifest.json"
fi

# enumerate_selftests — print the enrolled selftest corpus (repo-relative paths,
# sorted, deduplicated) to stdout. Source of truth is the filesystem glob, identical to
# scripts/run-aggregate-selftests.sh so the two enumerate the same ~319 set.
# Side effects: none (read-only).
enumerate_selftests() {
  {
    find "$ROOT_DIR/scripts/selftests" -maxdepth 1 -type f -name '*-selftest.sh' 2>/dev/null || true
    find "$ROOT_DIR/scripts" -maxdepth 1 -type f -name '*-selftest.sh' 2>/dev/null || true
  } | sed "s#^$ROOT_DIR/##" | LC_ALL=C sort -u
}

# classify_scope — print "narrow" or "shared" for one selftest, by parsing the
# repo-relative paths it references in its own body. A selftest is "shared" scope when
# it asserts against a shared / framework-wide surface (top-level scripts/*.sh,
# .claude/rules/, .claude/skills/, .claude/hooks/, .claude/instructions/), i.e. a change
# to a shared surface could affect it. It is "narrow" when it only references its own
# fixtures / the scripts/selftests/ subtree (self-contained unit-style selftest).
# Args: $1 = repo-relative selftest path. Side effects: none (read-only).
# This is a deterministic static parse of the file body — same body, same answer.
classify_scope() {
  local rel="$1" abs="$ROOT_DIR/$1"
  [[ -f "$abs" ]] || { printf 'narrow'; return 0; }
  # Shared-surface path tokens. Single-quoted patterns (shell-quoting discipline): the
  # backslash/dot are literal regex, not shell metacharacters to expand.
  if grep -Eq '(^|[^A-Za-z0-9_/])scripts/[A-Za-z0-9._-]+\.(sh|py|mjs|ts)' "$abs" \
    || grep -Eq '\.claude/(rules|skills|hooks|instructions)/' "$abs"; then
    printf 'shared'
    return 0
  fi
  printf 'narrow'
}

# derive_speed — print "fast" or "slow" given a measured wall-clock in ms and the
# active speed threshold. Args: $1 = wall_clock_ms. Side effects: none.
derive_speed() {
  local ms="$1"
  if [[ "$ms" -le "$SPEED_THRESHOLD_MS" ]]; then
    printf 'fast'
  else
    printf 'slow'
  fi
}

# subset_for — print the subset membership rules as a deterministic decision over the
# two axes. Returns 0 if the (speed,scope) pair belongs to the named subset.
#   fast-lint     : speed=fast AND scope=narrow  (cheapest; quick pre-commit lint loop)
#   affected      : scope=shared                 (run when a shared surface changes,
#                                                  regardless of speed)
#   full-backstop : every selftest               (exhaustive corpus; release backstop)
# Args: $1 = subset name, $2 = speed, $3 = scope. Side effects: none.
subset_for() {
  local subset="$1" speed="$2" scope="$3"
  case "$subset" in
    fast-lint) [[ "$speed" == "fast" && "$scope" == "narrow" ]] ;;
    affected) [[ "$scope" == "shared" ]] ;;
    full-backstop) return 0 ;;
    *) return 1 ;;
  esac
}

# --- LIST mode ---------------------------------------------------------------
if [[ "$MODE" == "list" ]]; then
  enumerate_selftests
  exit 0
fi

# --- MEASURE mode ------------------------------------------------------------
# Run each selftest, time it, parse scope, and write a JSON manifest cache. SLOW.
if [[ "$MODE" == "measure" ]]; then
  require_tool python3

  local_corpus=()
  while IFS= read -r _line; do
    [[ -n "$_line" ]] && local_corpus+=("$_line")
  done < <(enumerate_selftests)

  if [[ ${#local_corpus[@]} -eq 0 ]]; then
    die "POLARIS_SELFTEST_TIER_EMPTY: no selftests enumerated under $ROOT_DIR"
  fi

  # Accumulate one TSV record per selftest: path<TAB>wall_clock_ms<TAB>scope<TAB>exit_code
  records=""
  for rel in "${local_corpus[@]}"; do
    abs="$ROOT_DIR/$rel"
    scope="$(classify_scope "$rel")"
    start_ms="$(python3 -c 'import time; print(int(time.monotonic()*1000))')"
    set +e
    bash "$abs" >/dev/null 2>&1
    rc=$?
    set -e
    end_ms="$(python3 -c 'import time; print(int(time.monotonic()*1000))')"
    wall_ms=$((end_ms - start_ms))
    records+="${rel}	${wall_ms}	${scope}	${rc}"$'\n'
  done

  # Serialize to JSON via python3 (structured output, controlled field order). Records
  # are sorted by path so the cache is byte-stable for the same measured inputs. Records
  # go through a temp file (not stdin) because `python3 -` reads the PROGRAM from stdin
  # via the heredoc — piping data to the same stdin would be shadowed by the heredoc.
  records_file="$(mktemp)"
  printf '%s' "$records" >"$records_file"
  python3 - "$MANIFEST_PATH" "$MANIFEST_SCHEMA_VERSION" "$SPEED_THRESHOLD_MS" "$records_file" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
schema_version = int(sys.argv[2])
threshold = int(sys.argv[3])
records_file = Path(sys.argv[4])

entries = []
for line in records_file.read_text(encoding="utf-8").splitlines():
    if not line.strip():
        continue
    rel, wall_ms, scope, rc = line.split("\t")
    entries.append(
        {
            "path": rel,
            "wall_clock_ms": int(wall_ms),
            "scope": scope,
            "last_exit_code": int(rc),
        }
    )

entries.sort(key=lambda e: e["path"])
doc = {
    "schema_version": schema_version,
    "measured_speed_threshold_ms": threshold,
    "count": len(entries),
    "selftests": entries,
}
with open(manifest_path, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
  rm -f "$records_file"

  count="${#local_corpus[@]}"
  printf 'POLARIS_SELFTEST_TIER_MEASURED: wrote %s with %d selftests (threshold=%sms)\n' \
    "$MANIFEST_PATH" "$count" "$SPEED_THRESHOLD_MS"
  exit 0
fi

# --- EMIT mode ---------------------------------------------------------------
# Read the cached manifest and print one subset deterministically. FAST.
if [[ "$MODE" == "emit" ]]; then
  case "$EMIT_SUBSET" in
    fast-lint | affected | full-backstop) ;;
    *) die "POLARIS_SELFTEST_TIER_SUBSET: unknown subset '$EMIT_SUBSET' (expected fast-lint | affected | full-backstop)" ;;
  esac

  [[ -f "$MANIFEST_PATH" ]] || die "POLARIS_SELFTEST_TIER_MANIFEST_MISSING: $MANIFEST_PATH (run --measure first)"
  require_tool python3

  # Parse the manifest into TSV (path<TAB>wall_clock_ms<TAB>scope), fail-closed on a
  # malformed / wrong-shape cache.
  manifest_tsv="$(python3 - "$MANIFEST_PATH" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        doc = json.load(fh)
    entries = doc["selftests"]
except Exception as exc:  # noqa: BLE001 - any malformed manifest is a contract failure
    print(f"POLARIS_SELFTEST_TIER_MANIFEST_MALFORMED:{exc}", file=sys.stderr)
    sys.exit(2)

for e in entries:
    print(f'{e["path"]}\t{e["wall_clock_ms"]}\t{e["scope"]}')
PY
  )" || die "POLARIS_SELFTEST_TIER_MANIFEST_MALFORMED: cannot parse $MANIFEST_PATH"

  # Apply the two-axis subset rule and print members, sorted for byte-identical output.
  selected=""
  while IFS=$'\t' read -r rel wall_ms scope; do
    [[ -n "$rel" ]] || continue
    speed="$(derive_speed "$wall_ms")"
    if subset_for "$EMIT_SUBSET" "$speed" "$scope"; then
      selected+="${rel}"$'\n'
    fi
  done <<<"$manifest_tsv"

  printf '%s' "$selected" | grep -v '^$' | LC_ALL=C sort -u
  exit 0
fi

die "POLARIS_SELFTEST_TIER_ARG: unreachable mode dispatch"
