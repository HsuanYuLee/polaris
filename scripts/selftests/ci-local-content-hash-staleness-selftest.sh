#!/usr/bin/env bash
# Purpose: Assert ci-local.sh staleness guard uses content-hash, not mtime (DP-338 D3).
# Inputs:  none (builds throwaway git fixtures under a temp dir).
# Outputs: PASS/FAIL summary to stdout; exit 0 when all assertions pass, 1 otherwise.
# Side effects: creates/removes a temp directory; writes generated ci-local.sh inside it.
#
# Why: worktree checkout rewrites source-file mtime without changing content, which made
# the old mtime-based staleness guard fire a false-positive "CI config changed" error.
# The guard must instead compare each source file's content hash captured at generation
# time. touch (mtime-only) must NOT trip staleness; a real content edit MUST trip it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GENERATE="$SCRIPT_DIR/ci-local-generate.sh"
TMPROOT="$(mktemp -d -t ci-local-content-hash-staleness-XXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf "  ✓ %s\n" "$1"; }
fail() { FAIL=$((FAIL + 1)); printf "  ✗ %s\n" "$1" >&2; }

# Build a minimal git fixture with a single fast CI source file.
make_fixture() {
  local fix="$1"
  mkdir -p "$fix/.github/workflows"
  cat > "$fix/.github/workflows/ci.yml" <<'YML'
name: CI
on: [pull_request]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: 'true'
YML
  git -C "$fix" init -q
  git -C "$fix" -c user.email=t@t -c user.name=t add -A
  git -C "$fix" -c user.email=t@t -c user.name=t commit -qm init
}

# Run the generated ci-local.sh and report whether the staleness guard fired.
# Echoes "STALE" if the "CI config changed" error appears, "FRESH" otherwise.
# Staleness runs before the cache/check section, so the overall exit code (which
# depends on the trivial checks) is irrelevant here — only the message matters.
staleness_state() {
  local out_script="$1" repo="$2" combined
  combined="$(bash "$out_script" --repo "$repo" 2>&1 || true)"
  if grep -q 'CI config changed' <<< "$combined"; then
    printf 'STALE'
  else
    printf 'FRESH'
  fi
}

FIX="$TMPROOT/repo"
make_fixture "$FIX"
OUT="$FIX/ci-local.sh"

POLARIS_WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)" \
  bash "$GENERATE" --repo "$FIX" --out "$OUT" --force >/dev/null 2>&1

# Case 1: immediately after generation, content is identical → must be FRESH.
# (The old mtime guard could already false-positive here on sub-second generation.)
state="$(staleness_state "$OUT" "$FIX")"
if [[ "$state" == "FRESH" ]]; then
  pass "clean run right after generation is FRESH"
else
  fail "clean run right after generation should be FRESH, got $state"
fi

# Case 2: touch source (mtime newer, content identical) → must be FRESH.
# This is the worktree-checkout false-positive the content-hash guard must fix.
sleep 1
touch "$FIX/.github/workflows/ci.yml"
state="$(staleness_state "$OUT" "$FIX")"
if [[ "$state" == "FRESH" ]]; then
  pass "touch (mtime-only change, content identical) stays FRESH"
else
  fail "touch (mtime-only) should stay FRESH, got $state"
fi

# Case 3: real content edit → must be STALE (regression guard for detection).
printf '\n# content change\n' >> "$FIX/.github/workflows/ci.yml"
state="$(staleness_state "$OUT" "$FIX")"
if [[ "$state" == "STALE" ]]; then
  pass "content edit is detected as STALE"
else
  fail "content edit should be STALE, got $state"
fi

# Case 4: missing source file → must be STALE.
make_fixture "$TMPROOT/repo2"
FIX2="$TMPROOT/repo2"
OUT2="$FIX2/ci-local.sh"
POLARIS_WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)" \
  bash "$GENERATE" --repo "$FIX2" --out "$OUT2" --force >/dev/null 2>&1
rm -f "$FIX2/.github/workflows/ci.yml"
state="$(staleness_state "$OUT2" "$FIX2")"
if [[ "$state" == "STALE" ]]; then
  pass "missing source file is detected as STALE"
else
  fail "missing source file should be STALE, got $state"
fi

# Case 5: generated script must not emit the old mtime comparison logic.
if grep -q '_src_mtime' "$OUT"; then
  fail "generated script still contains mtime comparison (_src_mtime)"
else
  pass "generated script no longer uses mtime comparison"
fi

echo "ci-local-content-hash-staleness-selftest: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
