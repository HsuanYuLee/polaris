#!/usr/bin/env bash
# Purpose: Hermetic selftest for scripts/update-active-thread.sh.
#          DP-290 coverage: AC2 (overwrite, no append residue, byte-idempotent for
#          identical input) and AC3 (>10k input truncates tail, preserves「下一步」
#          head, emits truncation notice, total length <= 10000).
#          DP-300 T3 coverage: AC4 per-thread-key upsert — writing a second thread
#          key does NOT clobber the first; rewriting the same key with identical
#          content is byte-idempotent; --done / --remove drops a key's section;
#          and the legacy keyless single-thread path stays byte-identical (regression).
# Inputs:  None (builds its own tmp git repo as CLAUDE_PROJECT_DIR).
# Outputs: Prints PASS on success; exits non-zero with FAIL on any assertion failure.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRITER="$ROOT/scripts/update-active-thread.sh"
TMP="$(mktemp -d -t dp290-update-active-thread.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

PROJECT="$TMP/project"
mkdir -p "$PROJECT"
git -C "$PROJECT" init -q
git -C "$PROJECT" config user.email test@example.com
git -C "$PROJECT" config user.name "Active Thread Test"

ANCHOR="$PROJECT/.claude/active-thread.md"
export CLAUDE_PROJECT_DIR="$PROJECT"
export POLARIS_ACTIVE_THREAD_STAMP="2026-06-06T00:00:00Z"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# ---- AC2: overwrite (no append residue) ----
FIRST=$'# 下一步\n\nFIRST RUN content alpha unique-marker-AAA'
SECOND=$'# 下一步\n\nSECOND RUN content beta unique-marker-BBB'

printf '%s' "$FIRST" | bash "$WRITER" >/dev/null
[[ -f "$ANCHOR" ]] || fail "anchor file not created on first run"
grep -q 'unique-marker-AAA' "$ANCHOR" || fail "first-run content missing"

printf '%s' "$SECOND" | bash "$WRITER" >/dev/null
grep -q 'unique-marker-BBB' "$ANCHOR" || fail "second-run content missing"
if grep -q 'unique-marker-AAA' "$ANCHOR"; then
  fail "AC2: append residue detected — first-run content survived overwrite"
fi

# Final file must equal a fresh compose of the SECOND input (byte-exact).
EXPECTED="$TMP/expected.md"
printf '%s\n\n%s\n' "last-updated: $POLARIS_ACTIVE_THREAD_STAMP" "$SECOND" >"$EXPECTED"
if ! diff -q "$EXPECTED" "$ANCHOR" >/dev/null; then
  echo "--- expected ---" >&2; cat "$EXPECTED" >&2
  echo "--- actual ---" >&2; cat "$ANCHOR" >&2
  fail "AC2: final anchor does not byte-match second input compose"
fi

# ---- AC2: idempotency (identical input twice => byte-identical file) ----
printf '%s' "$SECOND" | bash "$WRITER" >/dev/null
HASH_A="$(shasum "$ANCHOR" | awk '{print $1}')"
printf '%s' "$SECOND" | bash "$WRITER" >/dev/null
HASH_B="$(shasum "$ANCHOR" | awk '{print $1}')"
[[ "$HASH_A" == "$HASH_B" ]] || fail "AC2: identical input produced different files (not idempotent)"

# ---- AC3: >10k input truncates tail, preserves head + emits notice ----
HEAD_MARKER='# 下一步: deterministic-handoff-head-MARKER'
# Build a body whose head carries the marker and whose tail is filler exceeding 10k.
BIG_BODY="$TMP/big.txt"
{
  printf '%s\n\n' "$HEAD_MARKER"
  # ~12000 chars of tail filler
  for _ in $(seq 1 240); do
    printf 'TAILFILLER-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx-%s\n' "$_"
  done
} >"$BIG_BODY"

[[ "$(wc -c <"$BIG_BODY")" -gt 10000 ]] || fail "AC3 fixture not >10k chars"

bash "$WRITER" --content "$(cat "$BIG_BODY")" >/dev/null

CHARS="$(wc -m <"$ANCHOR" | tr -d ' ')"
[[ "$CHARS" -le 10000 ]] || fail "AC3: truncated anchor exceeds 10000 chars (got $CHARS)"
grep -qF "$HEAD_MARKER" "$ANCHOR" || fail "AC3: head「下一步」marker was truncated away"
grep -q 'truncated by update-active-thread.sh' "$ANCHOR" || fail "AC3: truncation notice line missing"
if grep -q 'TAILFILLER-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx-240' "$ANCHOR"; then
  fail "AC3: tail filler末段 should have been truncated"
fi

# ============================================================================
# DP-300 T3 — per-thread-key upsert (AC4) + legacy regression
# ============================================================================
# Use a fresh project so DP-290 fixtures above don't bleed into the multi-thread
# assertions.
MT="$TMP/multithread"
mkdir -p "$MT"
git -C "$MT" init -q
git -C "$MT" config user.email test@example.com
git -C "$MT" config user.name "Multithread Test"
MT_ANCHOR="$MT/.claude/active-thread.md"
export CLAUDE_PROJECT_DIR="$MT"

# ---- AC4: write key A, then key B — both coexist (no clobber) ----
A_BODY=$'# 下一步: DP-298\n\nResume /auto-pass DP-298 verify-AC next.'
B_BODY=$'# 下一步: review-inbox\n\nFinish review-inbox thread parking.'

bash "$WRITER" --key DP-298 --content "$A_BODY" >/dev/null
[[ -f "$MT_ANCHOR" ]] || fail "AC4: anchor not created on first keyed write"
grep -q '<!-- thread:DP-298 -->' "$MT_ANCHOR" || fail "AC4: key A section marker missing"
grep -q 'Resume /auto-pass DP-298' "$MT_ANCHOR" || fail "AC4: key A body missing"

bash "$WRITER" --key review-inbox --content "$B_BODY" >/dev/null
# After the second write, BOTH threads must be present (no clobber).
grep -q '<!-- thread:DP-298 -->' "$MT_ANCHOR" || fail "AC4: key A was clobbered by key B write"
grep -q 'Resume /auto-pass DP-298' "$MT_ANCHOR" || fail "AC4: key A body lost after key B write"
grep -q '<!-- thread:review-inbox -->' "$MT_ANCHOR" || fail "AC4: key B section marker missing"
grep -q 'Finish review-inbox thread parking' "$MT_ANCHOR" || fail "AC4: key B body missing"

# ---- AC4: idempotency — rewrite key A with identical content => file unchanged ----
HASH_BEFORE="$(shasum "$MT_ANCHOR" | awk '{print $1}')"
bash "$WRITER" --key DP-298 --content "$A_BODY" >/dev/null
HASH_AFTER="$(shasum "$MT_ANCHOR" | awk '{print $1}')"
[[ "$HASH_BEFORE" == "$HASH_AFTER" ]] \
  || fail "AC4: rewriting key DP-298 with identical content changed the file (not idempotent)"
# Both threads still present after the idempotent rewrite.
grep -q '<!-- thread:review-inbox -->' "$MT_ANCHOR" || fail "AC4: key B lost after idempotent key A rewrite"

# ---- AC4: same-key rewrite with NEW content updates only that section ----
A_BODY2=$'# 下一步: DP-298\n\nDP-298 moved to engineering — resume there.'
bash "$WRITER" --key DP-298 --content "$A_BODY2" >/dev/null
grep -q 'moved to engineering' "$MT_ANCHOR" || fail "AC4: key A update did not take effect"
if grep -q 'Resume /auto-pass DP-298 verify-AC next' "$MT_ANCHOR"; then
  fail "AC4: old key A body survived an update (upsert should replace the section body)"
fi
grep -q 'Finish review-inbox thread parking' "$MT_ANCHOR" || fail "AC4: key B clobbered by key A update"

# ---- AC4: --done removes a key's section, leaving others ----
bash "$WRITER" --key DP-298 --done >/dev/null
if grep -q '<!-- thread:DP-298 -->' "$MT_ANCHOR"; then
  fail "AC4: --done did not remove key DP-298 section"
fi
grep -q '<!-- thread:review-inbox -->' "$MT_ANCHOR" || fail "AC4: --done dropped an unrelated key (review-inbox)"

# ---- AC4: --remove is an alias of --done ----
bash "$WRITER" --key review-inbox --remove >/dev/null
if grep -q '<!-- thread:review-inbox -->' "$MT_ANCHOR"; then
  fail "AC4: --remove did not remove key review-inbox section"
fi

# ---- AC4 regression: legacy keyless path stays flat (no delimiters) ----
LEG="$TMP/legacy"
mkdir -p "$LEG"
git -C "$LEG" init -q
git -C "$LEG" config user.email test@example.com
git -C "$LEG" config user.name "Legacy Test"
LEG_ANCHOR="$LEG/.claude/active-thread.md"
CLAUDE_PROJECT_DIR="$LEG" bash "$WRITER" --content $'# 下一步\n\nlegacy single thread' >/dev/null
if grep -q '<!-- thread:' "$LEG_ANCHOR"; then
  fail "AC4 regression: keyless write introduced thread delimiters (legacy must stay flat)"
fi
LEG_EXPECTED="$TMP/legacy_expected.md"
printf '%s\n\n%s\n' "last-updated: $POLARIS_ACTIVE_THREAD_STAMP" $'# 下一步\n\nlegacy single thread' >"$LEG_EXPECTED"
if ! diff -q "$LEG_EXPECTED" "$LEG_ANCHOR" >/dev/null; then
  echo "--- expected ---" >&2; cat "$LEG_EXPECTED" >&2
  echo "--- actual ---" >&2; cat "$LEG_ANCHOR" >&2
  fail "AC4 regression: legacy keyless anchor is not byte-identical to pre-DP-300 flat form"
fi

echo "PASS: update-active-thread selftest (AC2 overwrite/idempotent, AC3 10k truncation, AC4 multi-thread upsert/done + legacy regression)"
