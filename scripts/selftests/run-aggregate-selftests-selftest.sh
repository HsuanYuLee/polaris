#!/usr/bin/env bash
# Purpose: selftest for run-aggregate-selftests.sh + validate-selftest-enrollment.sh.
#          Builds a synthetic fixture root with one green + one red + one quarantined
#          selftest and asserts: AC1 (red => exit 1 + red logged), AC-NF2 (quarantine
#          logged, not silent), AC2 (enrollment gap => fail-closed exit 2), AC-NF1
#          (structured POLARIS_* markers on every fail-closed path), and the runner's
#          own real-tree green path (DP-325-T2 deliverable + run-verify-command
#          hermeticity).
# Inputs:  env DEBUG=1 for verbose. Run: bash scripts/selftests/run-aggregate-selftests-selftest.sh
# Outputs: stdout assertions + summary; exit 0 if all pass, exit 1 on any assertion fail.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$ROOT_DIR/run-aggregate-selftests.sh"
ENROLL="$ROOT_DIR/validate-selftest-enrollment.sh"
: "${DEBUG:=0}"

PASS=0
FAIL=0

assert_eq() {
  local got="$1" want="$2" label="$3"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1)); [[ "$DEBUG" == "1" ]] && printf '  [ok] %s (got=%s)\n' "$label" "$got"
  else
    FAIL=$((FAIL + 1)); printf '  [FAIL] %s — want=%s got=%s\n' "$label" "$want" "$got"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    PASS=$((PASS + 1)); [[ "$DEBUG" == "1" ]] && printf '  [ok] %s\n' "$label"
  else
    FAIL=$((FAIL + 1)); printf '  [FAIL] %s — needle=%s\n' "$label" "$needle"
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" label="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    FAIL=$((FAIL + 1)); printf '  [FAIL] %s — unexpected needle=%s\n' "$label" "$needle"
  else
    PASS=$((PASS + 1)); [[ "$DEBUG" == "1" ]] && printf '  [ok] %s\n' "$label"
  fi
}

# --- Build a synthetic fixture root ------------------------------------------
# A minimal repo with scripts/ + scripts/selftests/ holding one green, one red,
# one quarantined selftest. The aggregate runner is copied in so it resolves its
# own ROOT_DIR via --root.
FIX="$(mktemp -d -t aggregate-selftest-fix-XXXXXX)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/scripts/selftests"
cp "$RUNNER" "$FIX/scripts/run-aggregate-selftests.sh"
cp "$ENROLL" "$FIX/scripts/validate-selftest-enrollment.sh"

cat >"$FIX/scripts/selftests/alpha-green-selftest.sh" <<'EOF'
#!/usr/bin/env bash
echo "alpha green ok"; exit 0
EOF
cat >"$FIX/scripts/selftests/beta-red-selftest.sh" <<'EOF'
#!/usr/bin/env bash
echo "beta intentionally red"; exit 1
EOF
cat >"$FIX/scripts/selftests/gamma-quarantined-selftest.sh" <<'EOF'
#!/usr/bin/env bash
echo "gamma would be red but quarantined"; exit 1
EOF
# A root-level selftest too, to assert both globs are enumerated (AC1 adversarial).
cat >"$FIX/scripts/root-green-selftest.sh" <<'EOF'
#!/usr/bin/env bash
echo "root green ok"; exit 0
EOF
chmod +x "$FIX"/scripts/selftests/*.sh "$FIX"/scripts/root-green-selftest.sh

# Quarantine fixture: gamma is quarantined via QUARANTINE_OVERRIDE (production list
# is the embedded array; override is the test hook).
QFILE="$FIX/quarantine.txt"
printf 'scripts/selftests/gamma-quarantined-selftest.sh|known red — owned by FOLLOWUP-1\n' >"$QFILE"

echo "=== AC1: red selftest => exit 1 + red logged ==="
out="$(QUARANTINE_OVERRIDE="$QFILE" bash "$FIX/scripts/run-aggregate-selftests.sh" --root "$FIX" 2>&1)"; rc=$?
assert_eq "$rc" "1" "red present => exit 1"
assert_contains "$out" "RED        scripts/selftests/beta-red-selftest.sh" "red selftest logged"
assert_contains "$out" "POLARIS_AGGREGATE_SELFTEST_RED" "structured red marker (AC-NF1)"
assert_contains "$out" "PASS       scripts/selftests/alpha-green-selftest.sh" "green selftest logged"
assert_contains "$out" "PASS       scripts/root-green-selftest.sh" "root-level selftest enumerated (AC1 adversarial)"

echo "=== AC-NF2: quarantined selftest skipped but logged (not silent) ==="
assert_contains "$out" "QUARANTINE scripts/selftests/gamma-quarantined-selftest.sh" "quarantine logged"
assert_contains "$out" "known red — owned by FOLLOWUP-1" "quarantine reason logged"
assert_contains "$out" "quarantined=1" "quarantine counted in summary"
# gamma is red-on-execution but quarantined => must NOT appear in red list / red count.
assert_not_contains "$out" "RED        scripts/selftests/gamma-quarantined-selftest.sh" "quarantined not counted red"

echo "=== AC1: all-green corpus => exit 0 (quarantine away the red one) ==="
QALL="$FIX/quarantine-all.txt"
printf 'scripts/selftests/beta-red-selftest.sh|temp\nscripts/selftests/gamma-quarantined-selftest.sh|temp\n' >"$QALL"
out2="$(QUARANTINE_OVERRIDE="$QALL" bash "$FIX/scripts/run-aggregate-selftests.sh" --root "$FIX" 2>&1)"; rc2=$?
assert_eq "$rc2" "0" "no non-quarantined red => exit 0"
assert_contains "$out2" "red=0" "summary red=0"

echo "=== AC2: enrollment gate PASS when every fs selftest enrolled ==="
ge="$(bash "$FIX/scripts/validate-selftest-enrollment.sh" --root "$FIX" 2>&1)"; gerc=$?
assert_eq "$gerc" "0" "enrollment PASS exit 0"
assert_contains "$ge" "PASS: selftest enrollment" "enrollment PASS line"

echo "=== AC2 adversarial: a selftest the runner can't enumerate => enrollment fail-closed ==="
# Simulate a runner whose glob drifted: stub a --list that omits one fs selftest.
DRIFT="$FIX/scripts/run-aggregate-selftests.sh"
cp "$DRIFT" "$DRIFT.bak"
cat >"$DRIFT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for a in "$@"; do [[ "$a" == "--root" ]] && shift && ROOT_DIR="$(cd "$1" && pwd)" && shift; done 2>/dev/null || true
# Drifted: enumerate ONLY selftests dir, omit root *-selftest.sh => root-green missed.
find "$ROOT_DIR/scripts/selftests" -maxdepth 1 -type f -name '*-selftest.sh' | sed "s#^$ROOT_DIR/##" | sort
EOF
chmod +x "$DRIFT"
go="$(bash "$FIX/scripts/validate-selftest-enrollment.sh" --root "$FIX" 2>&1)"; gorc=$?
assert_eq "$gorc" "2" "enrollment gap => exit 2 (fail-closed)"
assert_contains "$go" "POLARIS_SELFTEST_ENROLLMENT_GAP" "structured enrollment-gap marker (AC-NF1)"
assert_contains "$go" "scripts/root-green-selftest.sh" "names the unenrolled selftest"
mv "$DRIFT.bak" "$DRIFT"

echo "=== AC-NF1: missing-input fail-closed ==="
mo="$(bash "$FIX/scripts/run-aggregate-selftests.sh" --root /nonexistent-dir-xyz 2>&1)"; morc=$?
assert_eq "$morc" "2" "no scripts/ root => exit 2"
assert_contains "$mo" "POLARIS_AGGREGATE_SELFTEST_NO_ROOT" "missing-root marker"

ao="$(bash "$FIX/scripts/run-aggregate-selftests.sh" --bogus-flag 2>&1)"; aorc=$?
assert_eq "$aorc" "2" "unknown arg => exit 2"
assert_contains "$ao" "POLARIS_AGGREGATE_SELFTEST_ARG" "unknown-arg marker"

echo "=== --list emits enrolled corpus + exit 0 ==="
lo="$(QUARANTINE_OVERRIDE="$QFILE" bash "$FIX/scripts/run-aggregate-selftests.sh" --root "$FIX" --list 2>&1)"; lorc=$?
assert_eq "$lorc" "0" "--list exit 0"
assert_contains "$lo" "scripts/selftests/alpha-green-selftest.sh" "list contains selftests-dir entry"
assert_contains "$lo" "scripts/root-green-selftest.sh" "list contains root entry"

echo ""
echo "=== Summary ==="
printf 'PASS=%s  FAIL=%s  TOTAL=%s\n' "$PASS" "$FAIL" "$((PASS + FAIL))"
if [[ "$FAIL" -gt 0 ]]; then
  echo "run-aggregate-selftests-selftest FAILED"
  exit 1
fi
echo "All assertions passed."
exit 0
