#!/usr/bin/env bash
# Purpose: Selftest for scripts/review-inbox-discovery-probe.sh. Asserts the four-state
#          fail-closed classification (source-unavailable / format-mismatch / stale /
#          legitimate-empty) plus the AC-NEG1 false-positive guard (a genuinely empty but
#          fresh inbox must exit 0 and never be misreported as a degraded state).
# Inputs:  none (builds fixtures in a tmpdir)
# Outputs: PASS=<n> FAIL=<n> on stdout; exit 0 all pass, exit 1 any failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE="$SCRIPT_DIR/review-inbox-discovery-probe.sh"
TMPDIR="$(mktemp -d -t polaris-discovery-probe-XXXXXX)"
PASS=0
FAIL=0

cleanup() {
  rm -rf "$TMPDIR" 2>/dev/null || true
}
trap cleanup EXIT

# A stable "now" so freshness math is deterministic. Messages at NOW-100s are fresh
# against the default 86400s threshold; messages at NOW-200000s are stale.
NOW=2000000000
FRESH_TS="$((NOW - 100))"          # 100s old -> fresh
STALE_TS="$((NOW - 200000))"       # ~55h old -> stale vs 86400 default

assert_rc() {
  local got="$1" want="$2" label="$3"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf '[FAIL] %s: want rc=%s got=%s\n' "$label" "$want" "$got"
  fi
}

assert_marker() {
  local out_file="$1" want_marker="$2" label="$3"
  if grep -q "$want_marker" "$out_file"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf '[FAIL] %s: marker %s not found in output:\n%s\n' "$label" "$want_marker" "$(cat "$out_file")"
  fi
}

assert_no_marker() {
  local out_file="$1" bad_marker="$2" label="$3"
  if grep -q "$bad_marker" "$out_file"; then
    FAIL=$((FAIL + 1))
    printf '[FAIL] %s: unexpected marker %s present in output:\n%s\n' "$label" "$bad_marker" "$(cat "$out_file")"
  else
    PASS=$((PASS + 1))
  fi
}

# Build a raw detailed dump with one message header + TS, using a generic placeholder
# author/UID and an exampleco PR URL (template-facing: no live company slug).
make_raw_with_message() {
  local out="$1" ts="$2" body="$3"
  cat > "$out" <<RAW
=== Message from Reviewer Bot (U0EXAMPLE1) at 2033-05-18 10:00:00 CST ===
Message TS: ${ts}.000100
${body}
RAW
}

# ---------------------------------------------------------------------------------------
# Case AC4: source-unavailable via --source-available 0
# ---------------------------------------------------------------------------------------
RAW1="$TMPDIR/raw1.txt"
CAND1="$TMPDIR/cand1.txt"
make_raw_with_message "$RAW1" "$FRESH_TS" "please review https://github.com/exampleco/exampleco-web/pull/100"
printf 'https://github.com/exampleco/exampleco-web/pull/100\n' > "$CAND1"
OUT="$TMPDIR/out1.txt"
"$PROBE" --raw-dump "$RAW1" --candidates "$CAND1" --now-epoch "$NOW" --source-available 0 >"$OUT" 2>&1
assert_rc "$?" "2" "AC4 source-available=0 exits 2"
assert_marker "$OUT" "POLARIS_DISCOVERY_SOURCE_UNAVAILABLE" "AC4 source-available=0 marker"

# ---------------------------------------------------------------------------------------
# Case AC4: source-unavailable via unparseable raw (no headers, no TS)
# ---------------------------------------------------------------------------------------
RAW2="$TMPDIR/raw2.txt"
CAND2="$TMPDIR/cand2.txt"
printf 'some concise non-detailed blob with no headers at all\n' > "$RAW2"
: > "$CAND2"
OUT="$TMPDIR/out2.txt"
"$PROBE" --raw-dump "$RAW2" --candidates "$CAND2" --now-epoch "$NOW" >"$OUT" 2>&1
assert_rc "$?" "2" "AC4 unparseable detailed header exits 2"
assert_marker "$OUT" "POLARIS_DISCOVERY_SOURCE_UNAVAILABLE" "AC4 unparseable header marker"

# ---------------------------------------------------------------------------------------
# Case AC2: format-mismatch (raw channel advertises a PR URL but parser produced 0).
# This reproduces the incident: the raw detailed dump still carries a github pull URL,
# yet the parser (keyed on the wrong header format) returned 0 candidates. The probe must
# detect the disagreement and fail loud instead of treating it as an empty inbox.
# ---------------------------------------------------------------------------------------
RAW3="$TMPDIR/raw3.txt"
CAND3="$TMPDIR/cand3.txt"
make_raw_with_message "$RAW3" "$FRESH_TS" "please review https://github.com/exampleco/exampleco-web/pull/999 thanks"
: > "$CAND3"   # parser returned 0 URLs despite the channel advertising one
OUT="$TMPDIR/out3.txt"
"$PROBE" --raw-dump "$RAW3" --candidates "$CAND3" --now-epoch "$NOW" >"$OUT" 2>&1
assert_rc "$?" "2" "AC2 format-mismatch exits 2"
assert_marker "$OUT" "POLARIS_DISCOVERY_FORMAT_MISMATCH" "AC2 format-mismatch marker"
assert_no_marker "$OUT" "POLARIS_DISCOVERY_LEGITIMATE_EMPTY" "AC2 format-mismatch not misreported as legitimate-empty"

# ---------------------------------------------------------------------------------------
# Case AC3: stale (newest message older than threshold)
# ---------------------------------------------------------------------------------------
RAW4="$TMPDIR/raw4.txt"
CAND4="$TMPDIR/cand4.txt"
make_raw_with_message "$RAW4" "$STALE_TS" "please review https://github.com/exampleco/exampleco-web/pull/200"
printf 'https://github.com/exampleco/exampleco-web/pull/200\n' > "$CAND4"
OUT="$TMPDIR/out4.txt"
"$PROBE" --raw-dump "$RAW4" --candidates "$CAND4" --now-epoch "$NOW" >"$OUT" 2>&1
assert_rc "$?" "2" "AC3 stale exits 2"
assert_marker "$OUT" "POLARIS_DISCOVERY_STALE" "AC3 stale marker"

# ---------------------------------------------------------------------------------------
# Case AC5 / AC-NEG1: legitimate-empty (fresh, parseable, genuinely 0 review PRs)
# ---------------------------------------------------------------------------------------
RAW5="$TMPDIR/raw5.txt"
CAND5="$TMPDIR/cand5.txt"
# A fresh message that simply carries no PR URL (e.g. a standup note). The channel really
# is empty of review PRs; this must NOT be a degraded state.
make_raw_with_message "$RAW5" "$FRESH_TS" "morning standup posted, no PRs pending today"
: > "$CAND5"
OUT="$TMPDIR/out5.txt"
"$PROBE" --raw-dump "$RAW5" --candidates "$CAND5" --now-epoch "$NOW" >"$OUT" 2>&1
RC=$?
# AC-NEG1 hard guard: legitimate empty inbox is NOT format-mismatch because there is no
# parser disagreement signal here other than 0 URLs. The probe distinguishes mismatch
# from empty by message-header presence, so this case requires a header with a URL-less
# body whose 0-URL outcome is the truth. To keep that distinction honest, a body that
# genuinely advertises no review PR must reach legitimate-empty.
assert_rc "$RC" "0" "AC5 legitimate-empty exits 0"
assert_marker "$OUT" "POLARIS_DISCOVERY_LEGITIMATE_EMPTY" "AC5 legitimate-empty marker"
assert_no_marker "$OUT" "POLARIS_DISCOVERY_STALE" "AC-NEG1 legitimate-empty not misreported STALE"
assert_no_marker "$OUT" "POLARIS_DISCOVERY_SOURCE_UNAVAILABLE" "AC-NEG1 legitimate-empty not misreported SOURCE_UNAVAILABLE"

# ---------------------------------------------------------------------------------------
# Case non-empty healthy (fresh + candidates) exits 0 with OK marker
# ---------------------------------------------------------------------------------------
RAW6="$TMPDIR/raw6.txt"
CAND6="$TMPDIR/cand6.txt"
make_raw_with_message "$RAW6" "$FRESH_TS" "please review https://github.com/exampleco/exampleco-web/pull/300"
printf 'https://github.com/exampleco/exampleco-web/pull/300\n' > "$CAND6"
OUT="$TMPDIR/out6.txt"
"$PROBE" --raw-dump "$RAW6" --candidates "$CAND6" --now-epoch "$NOW" >"$OUT" 2>&1
assert_rc "$?" "0" "non-empty healthy exits 0"
assert_marker "$OUT" "POLARIS_DISCOVERY_OK" "non-empty healthy OK marker"

# ---------------------------------------------------------------------------------------
# Case decision-order: source-unavailable wins over format-mismatch
# (--source-available 0 even with message headers present and 0 URLs)
# ---------------------------------------------------------------------------------------
OUT="$TMPDIR/out7.txt"
"$PROBE" --raw-dump "$RAW3" --candidates "$CAND3" --now-epoch "$NOW" --source-available 0 >"$OUT" 2>&1
assert_rc "$?" "2" "decision-order source-unavailable precedes format-mismatch"
assert_marker "$OUT" "POLARIS_DISCOVERY_SOURCE_UNAVAILABLE" "decision-order source-unavailable marker"
assert_no_marker "$OUT" "POLARIS_DISCOVERY_FORMAT_MISMATCH" "decision-order does not emit format-mismatch when source down"

# ---------------------------------------------------------------------------------------
# Case usage error: missing required arg exits 1
# ---------------------------------------------------------------------------------------
OUT="$TMPDIR/out8.txt"
"$PROBE" --candidates "$CAND6" --now-epoch "$NOW" >"$OUT" 2>&1
assert_rc "$?" "1" "missing --raw-dump exits 1"

printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
