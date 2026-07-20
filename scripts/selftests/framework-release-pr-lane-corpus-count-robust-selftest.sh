#!/usr/bin/env bash
set -euo pipefail

# Purpose: Prove framework-release-pr-lane.sh's selftest-corpus presence probe is
#          SIGPIPE-free (DP-352 Bug #4). The legacy `find ... | head -1 | wc -l`
#          assignment leaks find's SIGPIPE rc=141 under `set -o pipefail` once the
#          corpus has >1 file (head closes the pipe early). The fix replaces it
#          with release_lane_corpus_present() using `find -print -quit` (no head
#          pipe). This selftest reproduces the real multi-file corpus state (not a
#          toy single-file fixture) so the rc=141 leak actually triggers, then
#          verifies the new helper is present, correct, and leak-free.
# Inputs:  none (builds its own fixture corpus under a temp dir).
# Outputs: PASS / FAIL lines to stdout; exit 0 all-pass, exit 1 on any failure.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_SCRIPT="${TARGET_SCRIPT:-${REPO_ROOT}/scripts/framework-release-pr-lane.sh}"
BACKSTOPS_LIB="${REPO_ROOT}/scripts/lib/release-gate-backstops.sh"

fail_count=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  printf 'FAIL: %s\n' "$1"
  fail_count=$((fail_count + 1))
}

# Build a potent fixture: a scripts dir with enough *-selftest.sh files that the
# total `find` output exceeds the OS pipe buffer. Then `find ... | head -1` makes
# find BLOCK on write (buffer full) until head reads one line and closes the read
# end — guaranteeing find takes SIGPIPE (rc=141) rather than finishing first. A
# small fixture (output < pipe buffer) would let find complete before head closes
# and would NOT reproduce the bug, so the corpus is intentionally large.
FIXTURE_DIR="$(mktemp -d)"
EMPTY_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR" "$EMPTY_DIR"' EXIT
FIXTURE_SCRIPTS="${FIXTURE_DIR}/scripts"
mkdir -p "${FIXTURE_SCRIPTS}/selftests"
mkdir -p "${EMPTY_DIR}/scripts"

# ~110+ bytes per emitted path × CORPUS_SIZE must exceed the pipe buffer
# (commonly 16KB-64KB on darwin/linux); 4000 long-named files yield >400KB.
NAME_PAD="padding-to-make-each-emitted-find-line-comfortably-long"
CORPUS_SIZE=4000
for i in $(seq 1 "$CORPUS_SIZE"); do
  : >"${FIXTURE_SCRIPTS}/selftests/fixture-${i}-${NAME_PAD}-selftest.sh"
done

# ---------------------------------------------------------------------------
# Test 1 — Fixture potency / characterization of the legacy bug.
# Run the EXACT legacy pipeline against the populated fixture under pipefail and
# assert it leaks a NON-ZERO exit. When head closes the read end, find's blocked
# write fails: rc=141 if SIGPIPE is delivered (interactive shells), or rc=1 from
# EPIPE if SIGPIPE is ignored (e.g. under run-verify-command.sh). Both are the
# same bug — a non-zero status leaking from the corpus probe. A clean corpus
# (output < pipe buffer) would let find finish first and yield rc=0, so a
# non-zero here proves (a) the fixture is potent and (b) the pattern is buggy.
# ---------------------------------------------------------------------------
legacy_rc=0
(
  set -o pipefail
  find "${FIXTURE_SCRIPTS}" -maxdepth 2 -type f -name '*-selftest.sh' 2>/dev/null \
    | head -1 | wc -l >/dev/null
) || legacy_rc=$?
if [[ "$legacy_rc" -ne 0 ]]; then
  pass "fixture potency: legacy 'find | head -1 | wc -l' leaks non-zero rc=${legacy_rc} under pipefail (real bug reproduced)"
else
  fail "fixture potency: expected legacy pipeline to leak non-zero, got rc=0 (fixture not potent — cannot prove the bug)"
fi

# ---------------------------------------------------------------------------
# Probe sourceability in a SUBSHELL first. With the source-guard the CLI exec
# flow is skipped, so the subshell source returns 0. Without the guard the exec
# flow runs (and dies on missing args), so the subshell exits non-zero — and we
# must NOT source into the current shell (that would `exit` the selftest). This
# keeps an unguarded target producing clean FAILs instead of killing the run.
# ---------------------------------------------------------------------------
source_ok=1
# shellcheck disable=SC1090
( source "$TARGET_SCRIPT" ) >/dev/null 2>&1 || source_ok=0
if [[ "$source_ok" -eq 1 ]]; then
  pass "target script is source-guarded (sourcing does not run the release-lane CLI flow)"
  # shellcheck disable=SC1090
  source "$TARGET_SCRIPT" >/dev/null 2>&1
else
  fail "sourcing target script ran the CLI exec flow / errored (missing BASH_SOURCE source-guard)"
fi

# ---------------------------------------------------------------------------
# Test 2 — the SIGPIPE-free helper exists.
# ---------------------------------------------------------------------------
if declare -F release_lane_corpus_present >/dev/null 2>&1; then
  pass "release_lane_corpus_present helper is defined"
else
  fail "release_lane_corpus_present helper is NOT defined (fix not applied)"
fi

# ---------------------------------------------------------------------------
# Test 3 — helper returns 0 for a populated corpus, with NO rc=141 leak even
# under pipefail (the functional fix).
# ---------------------------------------------------------------------------
if declare -F release_lane_corpus_present >/dev/null 2>&1; then
  present_rc=0
  (
    set -o pipefail
    release_lane_corpus_present "${FIXTURE_SCRIPTS}"
  ) || present_rc=$?
  if [[ "$present_rc" -eq 0 ]]; then
    pass "release_lane_corpus_present returns 0 for populated corpus with no SIGPIPE leak"
  else
    fail "release_lane_corpus_present should return 0 for populated corpus, got rc=${present_rc}"
  fi

  # ---------------------------------------------------------------------------
  # Test 4 — helper returns 1 (absent) for an empty corpus (zero-file value still
  # correct), no leak.
  # ---------------------------------------------------------------------------
  absent_rc=0
  (
    set -o pipefail
    release_lane_corpus_present "${EMPTY_DIR}/scripts"
  ) || absent_rc=$?
  if [[ "$absent_rc" -eq 1 ]]; then
    pass "release_lane_corpus_present returns 1 for empty corpus (no false positive)"
  else
    fail "release_lane_corpus_present should return 1 for empty corpus, got rc=${absent_rc}"
  fi
else
  fail "skipping helper behavior tests: helper undefined"
  fail "skipping empty-corpus test: helper undefined"
fi

# ---------------------------------------------------------------------------
# Test 5 — the real script no longer carries the leaky pipeline and does carry
# the SIGPIPE-free existence test.
# ---------------------------------------------------------------------------
if grep -Eq 'head -1[[:space:]]*\|[[:space:]]*wc -l' "$TARGET_SCRIPT"; then
  fail "target script still contains the leaky 'head -1 | wc -l' corpus pipeline"
else
  pass "target script no longer contains the leaky 'head -1 | wc -l' corpus pipeline"
fi
if grep -q -- '-print -quit' "$TARGET_SCRIPT" "$BACKSTOPS_LIB"; then
  pass "release lane or its sourced backstop uses 'find -print -quit' existence probe"
else
  fail "release lane and sourced backstop do not use 'find -print -quit' existence probe"
fi

if [[ "$fail_count" -eq 0 ]]; then
  printf '\nALL PASS: framework-release-pr-lane corpus-count is SIGPIPE-free\n'
  exit 0
fi
printf '\n%d FAILURE(S)\n' "$fail_count"
exit 1
