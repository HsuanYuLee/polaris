#!/usr/bin/env bash
# Purpose: selftest for scripts/selftest-tier-manifest.sh. Proves AC6 — the two-axis
#          (speed × scope) tier marking and the three derived subsets (fast-lint /
#          affected / full-backstop) are explicit and mechanically reproducible (same
#          manifest input + threshold => byte-identical subset output). Uses a SYNTHETIC
#          manifest cache with known wall-clock/scope values; it NEVER measures the real
#          ~319-selftest corpus (that takes ≈2.5h). A tiny 2-selftest fixture exercises
#          the measure→emit roundtrip so measure mode is covered without the full corpus.
# Inputs:  env DEBUG=1 for verbose. Run: bash scripts/selftests/selftest-tier-manifest-selftest.sh
# Outputs: stdout assertions + summary; exit 0 if all pass, exit 1 on any assertion fail.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# REPO_ROOT is the workspace root (the producer's --root contract): it appends
# scripts/ and scripts/selftests/ itself, so pass the repo root, not scripts/.
REPO_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
PRODUCER="$SCRIPTS_DIR/selftest-tier-manifest.sh"
: "${DEBUG:=0}"

PASS=0
FAIL=0

assert_eq() {
  local got="$1" want="$2" label="$3"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1)); [[ "$DEBUG" == "1" ]] && printf '  [ok] %s\n' "$label"
  else
    FAIL=$((FAIL + 1)); printf '  [FAIL] %s\n        want=[%s]\n         got=[%s]\n' "$label" "$want" "$got"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if grep -qF -- "$needle" <<< "$haystack"; then
    PASS=$((PASS + 1)); [[ "$DEBUG" == "1" ]] && printf '  [ok] %s\n' "$label"
  else
    FAIL=$((FAIL + 1)); printf '  [FAIL] %s — needle=%s\n' "$label" "$needle"
  fi
}

assert_exit() {
  local got="$1" want="$2" label="$3"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1)); [[ "$DEBUG" == "1" ]] && printf '  [ok] %s (exit=%s)\n' "$label" "$got"
  else
    FAIL=$((FAIL + 1)); printf '  [FAIL] %s — want exit=%s got=%s\n' "$label" "$want" "$got"
  fi
}

TMP="$(mktemp -d -t selftest-tier-fix-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# --- Synthetic manifest cache -------------------------------------------------
# Four known selftests spanning every (speed,scope) quadrant against a 5000ms threshold:
#   a-fast-narrow   :  100ms / narrow  -> fast-lint + full-backstop
#   b-slow-narrow   : 90000ms / narrow -> full-backstop only
#   c-fast-shared   :  200ms / shared  -> affected + full-backstop
#   d-slow-shared   : 80000ms / shared -> affected + full-backstop
SYNTH="$TMP/synth-manifest.json"
cat >"$SYNTH" <<'JSON'
{
  "count": 4,
  "measured_speed_threshold_ms": 5000,
  "schema_version": 1,
  "selftests": [
    { "last_exit_code": 0, "path": "scripts/selftests/a-fast-narrow-selftest.sh", "scope": "narrow", "wall_clock_ms": 100 },
    { "last_exit_code": 0, "path": "scripts/selftests/b-slow-narrow-selftest.sh", "scope": "narrow", "wall_clock_ms": 90000 },
    { "last_exit_code": 0, "path": "scripts/selftests/c-fast-shared-selftest.sh", "scope": "shared", "wall_clock_ms": 200 },
    { "last_exit_code": 0, "path": "scripts/selftests/d-slow-shared-selftest.sh", "scope": "shared", "wall_clock_ms": 80000 }
  ]
}
JSON

# --- AC6: two-axis subsets are explicit & correct ----------------------------
fast_lint="$(bash "$PRODUCER" --manifest "$SYNTH" --emit fast-lint)"
assert_eq "$fast_lint" "scripts/selftests/a-fast-narrow-selftest.sh" \
  "fast-lint subset = {fast AND narrow}"

affected="$(bash "$PRODUCER" --manifest "$SYNTH" --emit affected)"
affected_want="scripts/selftests/c-fast-shared-selftest.sh
scripts/selftests/d-slow-shared-selftest.sh"
assert_eq "$affected" "$affected_want" "affected subset = {scope=shared} (both fast+slow shared)"

backstop="$(bash "$PRODUCER" --manifest "$SYNTH" --emit full-backstop)"
backstop_want="scripts/selftests/a-fast-narrow-selftest.sh
scripts/selftests/b-slow-narrow-selftest.sh
scripts/selftests/c-fast-shared-selftest.sh
scripts/selftests/d-slow-shared-selftest.sh"
assert_eq "$backstop" "$backstop_want" "full-backstop subset = every selftest"

# Negative axis check: the slow-narrow selftest must NOT leak into fast-lint or affected.
assert_eq "$(printf '%s' "$fast_lint" | grep -c 'b-slow-narrow' || true)" "0" \
  "slow-narrow excluded from fast-lint"
assert_eq "$(printf '%s' "$affected" | grep -c 'a-fast-narrow' || true)" "0" \
  "narrow excluded from affected"

# --- AC6: determinism — same input => byte-identical output ------------------
run1="$(bash "$PRODUCER" --manifest "$SYNTH" --emit full-backstop)"
run2="$(bash "$PRODUCER" --manifest "$SYNTH" --emit full-backstop)"
assert_eq "$run1" "$run2" "full-backstop emit is byte-identical across runs (determinism)"
fl1="$(bash "$PRODUCER" --manifest "$SYNTH" --emit affected)"
fl2="$(bash "$PRODUCER" --manifest "$SYNTH" --emit affected)"
assert_eq "$fl1" "$fl2" "affected emit is byte-identical across runs (determinism)"

# --- Threshold re-bucketing on the SAME cache (no re-measure) -----------------
# Drop the threshold below 200ms: now only the 100ms selftest is "fast", and the 200ms
# c-fast-shared becomes "slow" — but it stays in `affected` (scope-driven), and fast-lint
# still holds exactly a-fast-narrow.
fast_lint_low="$(bash "$PRODUCER" --manifest "$SYNTH" --emit fast-lint --speed-threshold-ms 150)"
assert_eq "$fast_lint_low" "scripts/selftests/a-fast-narrow-selftest.sh" \
  "fast-lint stable when threshold=150 (only <=150ms narrow qualifies)"
# Raise the threshold above the slow-narrow selftest: now b-slow-narrow is fast+narrow
# and joins fast-lint deterministically.
fast_lint_hi="$(bash "$PRODUCER" --manifest "$SYNTH" --emit fast-lint --speed-threshold-ms 100000)"
fast_lint_hi_want="scripts/selftests/a-fast-narrow-selftest.sh
scripts/selftests/b-slow-narrow-selftest.sh"
assert_eq "$fast_lint_hi" "$fast_lint_hi_want" \
  "fast-lint absorbs slow-narrow when threshold raised (two-axis rule re-applied to same cache)"

# --- Fail-closed contract behavior -------------------------------------------
set +e
bash "$PRODUCER" --manifest "$TMP/does-not-exist.json" --emit fast-lint >/dev/null 2>"$TMP/err1"
rc_missing=$?
assert_exit "$rc_missing" "2" "missing manifest fails closed (exit 2)"
assert_contains "$(cat "$TMP/err1")" "POLARIS_SELFTEST_TIER_MANIFEST_MISSING" \
  "missing manifest emits POLARIS_SELFTEST_TIER_MANIFEST_MISSING"

set +e
bash "$PRODUCER" --manifest "$SYNTH" --emit bogus-subset >/dev/null 2>"$TMP/err2"
rc_subset=$?
assert_exit "$rc_subset" "2" "unknown subset fails closed (exit 2)"
assert_contains "$(cat "$TMP/err2")" "POLARIS_SELFTEST_TIER_SUBSET" \
  "unknown subset emits POLARIS_SELFTEST_TIER_SUBSET"

set +e
bash "$PRODUCER" >/dev/null 2>"$TMP/err3"
rc_nomode=$?
assert_exit "$rc_nomode" "2" "no mode flag fails closed (exit 2)"

set +e
bash "$PRODUCER" --manifest "$SYNTH" --emit fast-lint --speed-threshold-ms abc >/dev/null 2>"$TMP/err4"
rc_badthr=$?
assert_exit "$rc_badthr" "2" "non-integer threshold fails closed (exit 2)"

# Malformed manifest body must fail closed, not silently emit nothing.
echo 'not json {{{' >"$TMP/bad.json"
set +e
bash "$PRODUCER" --manifest "$TMP/bad.json" --emit full-backstop >/dev/null 2>"$TMP/err5"
rc_malformed=$?
assert_exit "$rc_malformed" "2" "malformed manifest fails closed (exit 2)"

# --- Real-corpus enumeration: --list sees scripts/*/-selftest.sh, no measuring -
listed="$(bash "$PRODUCER" --root "$REPO_ROOT" --list)"
listed_count="$(printf '%s\n' "$listed" | grep -c '\-selftest\.sh$' || true)"
# Sanity: the live corpus is in the hundreds; assert >= 200 without depending on an
# exact count (corpus grows). This proves enumeration is wired to the real filesystem
# glob WITHOUT running any selftest.
if [[ "$listed_count" -ge 200 ]]; then
  PASS=$((PASS + 1)); [[ "$DEBUG" == "1" ]] && printf '  [ok] --list enumerates live corpus (%s selftests)\n' "$listed_count"
else
  FAIL=$((FAIL + 1)); printf '  [FAIL] --list enumerates live corpus — want >=200 got %s\n' "$listed_count"
fi
# This selftest must be in the enumerated corpus (self-membership).
assert_contains "$listed" "scripts/selftests/selftest-tier-manifest-selftest.sh" \
  "--list includes this selftest itself"

# --- Measure→emit roundtrip on a TINY 2-selftest fixture ----------------------
# Build a throwaway fixture repo with exactly two cheap synthetic selftests + the
# producer, run --measure, then --emit. Proves measure mode actually times + classifies
# + writes a readable manifest, WITHOUT touching the real ~319 corpus.
FIXROOT="$TMP/fixrepo"
mkdir -p "$FIXROOT/scripts/selftests" "$FIXROOT/scripts/lib" "$FIXROOT/.claude/rules"
cp "$PRODUCER" "$FIXROOT/scripts/selftest-tier-manifest.sh"
# narrow-scope selftest: references only its own fixtures (no shared-surface token).
cat >"$FIXROOT/scripts/selftests/tiny-narrow-selftest.sh" <<'EOF'
#!/usr/bin/env bash
# A self-contained selftest with no shared-surface references.
echo "checking local fixture only"
exit 0
EOF
# shared-scope selftest: references a top-level scripts/*.sh and a .claude/rules/ path.
cat >"$FIXROOT/scripts/selftests/tiny-shared-selftest.sh" <<'EOF'
#!/usr/bin/env bash
# Asserts against shared framework surfaces.
grep -q 'x' scripts/some-shared.sh
grep -q 'y' .claude/rules/skill-routing.md
exit 0
EOF

fix_manifest="$FIXROOT/manifest.json"
measure_out="$(bash "$FIXROOT/scripts/selftest-tier-manifest.sh" --root "$FIXROOT" --manifest "$fix_manifest" --measure 2>&1)"
measure_rc=$?
assert_exit "$measure_rc" "0" "measure mode on tiny fixture exits 0"
assert_contains "$measure_out" "POLARIS_SELFTEST_TIER_MEASURED" "measure mode prints measured marker"
if [[ -f "$fix_manifest" ]]; then
  PASS=$((PASS + 1)); [[ "$DEBUG" == "1" ]] && printf '  [ok] measure wrote manifest cache\n'
else
  FAIL=$((FAIL + 1)); printf '  [FAIL] measure did not write manifest cache at %s\n' "$fix_manifest"
fi
# scope classification persisted: shared selftest tagged shared, narrow tagged narrow.
assert_contains "$(cat "$fix_manifest")" '"path": "scripts/selftests/tiny-shared-selftest.sh"' \
  "manifest records the shared fixture selftest"
shared_scope="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
m={e["path"]:e["scope"] for e in d["selftests"]}
print(m.get("scripts/selftests/tiny-shared-selftest.sh","MISSING"))
' "$fix_manifest")"
assert_eq "$shared_scope" "shared" "measure classified shared-surface selftest as scope=shared"
narrow_scope="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
m={e["path"]:e["scope"] for e in d["selftests"]}
print(m.get("scripts/selftests/tiny-narrow-selftest.sh","MISSING"))
' "$fix_manifest")"
assert_eq "$narrow_scope" "narrow" "measure classified self-contained selftest as scope=narrow"

# emit on the freshly-measured tiny manifest: affected = the shared one only.
fix_affected="$(bash "$FIXROOT/scripts/selftest-tier-manifest.sh" --root "$FIXROOT" --manifest "$fix_manifest" --emit affected)"
assert_eq "$fix_affected" "scripts/selftests/tiny-shared-selftest.sh" \
  "emit affected on measured manifest = shared selftest only"

# --- Summary -----------------------------------------------------------------
printf '\nselftest-tier-manifest selftest: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
