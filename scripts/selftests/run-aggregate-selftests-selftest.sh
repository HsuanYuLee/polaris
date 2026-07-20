#!/usr/bin/env bash
# Purpose: selftest for run-aggregate-selftests.sh + validate-selftest-enrollment.sh.
#          Builds synthetic git fixtures and asserts: head-only red selftests
#          fail-closed, base-red selftests are reported as tracked debt, the
#          runner uses filesystem enrollment, and no embedded static skip list
#          remains.
# Inputs:  env DEBUG=1 for verbose. Run: bash scripts/selftests/run-aggregate-selftests-selftest.sh
# Outputs: stdout assertions + summary; exit 0 if all pass, exit 1 on assertion fail.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$ROOT_DIR/run-aggregate-selftests.sh"
ENROLL="$ROOT_DIR/validate-selftest-enrollment.sh"
ENROLL_MODULE="$ROOT_DIR/lib/validate_selftest_enrollment_1.py"
: "${DEBUG:=0}"

PASS=0
FAIL=0

assert_eq() {
  local got="$1" want="$2" label="$3"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1)); [[ "$DEBUG" == "1" ]] && printf '  [ok] %s (got=%s)\n' "$label" "$got"
  else
    FAIL=$((FAIL + 1)); printf '  [FAIL] %s - want=%s got=%s\n' "$label" "$want" "$got"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if grep -qF -- "$needle" <<< "$haystack"; then
    PASS=$((PASS + 1)); [[ "$DEBUG" == "1" ]] && printf '  [ok] %s\n' "$label"
  else
    FAIL=$((FAIL + 1)); printf '  [FAIL] %s - needle=%s\n' "$label" "$needle"
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" label="$3"
  if grep -qF -- "$needle" <<< "$haystack"; then
    FAIL=$((FAIL + 1)); printf '  [FAIL] %s - unexpected needle=%s\n' "$label" "$needle"
  else
    PASS=$((PASS + 1)); [[ "$DEBUG" == "1" ]] && printf '  [ok] %s\n' "$label"
  fi
}

FIX="$(mktemp -d -t aggregate-selftest-fix-XXXXXX)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/scripts/lib" "$FIX/scripts/selftests"
cp "$RUNNER" "$FIX/scripts/run-aggregate-selftests.sh"
cp "$ENROLL" "$FIX/scripts/validate-selftest-enrollment.sh"
cp "$ENROLL_MODULE" "$FIX/scripts/lib/validate_selftest_enrollment_1.py"

git -C "$FIX" init -q
git -C "$FIX" config user.email selftest@example.com
git -C "$FIX" config user.name "aggregate selftest"

cat >"$FIX/scripts/selftests/alpha-green-selftest.sh" <<'EOF'
#!/usr/bin/env bash
echo "alpha green ok"; exit 0
EOF
cat >"$FIX/scripts/selftests/beta-base-red-selftest.sh" <<'EOF'
#!/usr/bin/env bash
echo "beta red on base"; exit 1
EOF
cat >"$FIX/scripts/root-green-selftest.sh" <<'EOF'
#!/usr/bin/env bash
echo "root green ok"; exit 0
EOF
chmod +x "$FIX"/scripts/selftests/*.sh "$FIX"/scripts/root-green-selftest.sh "$FIX/scripts/run-aggregate-selftests.sh"

git -C "$FIX" add -A
git -C "$FIX" -c commit.gpgsign=false commit -q -m "base"
BASE_SHA="$(git -C "$FIX" rev-parse HEAD)"

cat >"$FIX/scripts/selftests/delta-head-red-selftest.sh" <<'EOF'
#!/usr/bin/env bash
echo "delta red on head only"; exit 1
EOF
chmod +x "$FIX/scripts/selftests/delta-head-red-selftest.sh"
git -C "$FIX" add -A
git -C "$FIX" -c commit.gpgsign=false commit -q -m "head red"

echo "=== AC1: head-only red selftest => exit 1 + red logged ==="
out="$(bash "$FIX/scripts/run-aggregate-selftests.sh" --root "$FIX" --base-ref "$BASE_SHA" 2>&1)"; rc=$?
assert_eq "$rc" "1" "head-only red => exit 1"
assert_contains "$out" "RED        scripts/selftests/delta-head-red-selftest.sh" "head-only red logged"
assert_contains "$out" "POLARIS_AGGREGATE_SELFTEST_RED" "structured red marker"
assert_contains "$out" "TRACKED_DEBT scripts/selftests/beta-base-red-selftest.sh" "base-red tracked debt logged"
assert_contains "$out" "tracked_debt=1" "tracked debt counted"
assert_contains "$out" "red=1" "head-only red counted"

echo "=== AC3: base-red only => exit 0 but tracked debt remains visible ==="
rm "$FIX/scripts/selftests/delta-head-red-selftest.sh"
git -C "$FIX" add -A
git -C "$FIX" -c commit.gpgsign=false commit -q -m "remove head red"
out2="$(bash "$FIX/scripts/run-aggregate-selftests.sh" --root "$FIX" --base-ref "$BASE_SHA" 2>&1)"; rc2=$?
assert_eq "$rc2" "0" "base-red only => exit 0"
assert_contains "$out2" "TRACKED_DEBT scripts/selftests/beta-base-red-selftest.sh" "tracked debt still logged"
assert_contains "$out2" "red=0" "no blocking reds"

echo "=== AC2: enrollment gate PASS when every fs selftest enrolled ==="
ge="$(bash "$FIX/scripts/validate-selftest-enrollment.sh" --root "$FIX" 2>&1)"; gerc=$?
assert_eq "$gerc" "0" "enrollment PASS exit 0"
assert_contains "$ge" "PASS: selftest enrollment" "enrollment PASS line"

echo "=== AC2 adversarial: a selftest the runner cannot enumerate => enrollment fail-closed ==="
DRIFT="$FIX/scripts/run-aggregate-selftests.sh"
cp "$DRIFT" "$DRIFT.bak"
cat >"$DRIFT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for a in "$@"; do [[ "$a" == "--root" ]] && shift && ROOT_DIR="$(cd "$1" && pwd)" && shift; done 2>/dev/null || true
find "$ROOT_DIR/scripts/selftests" -maxdepth 1 -type f -name '*-selftest.sh' | sed "s#^$ROOT_DIR/##" | sort
EOF
chmod +x "$DRIFT"
go="$(bash "$FIX/scripts/validate-selftest-enrollment.sh" --root "$FIX" 2>&1)"; gorc=$?
assert_eq "$gorc" "2" "enrollment gap => exit 2"
assert_contains "$go" "POLARIS_SELFTEST_ENROLLMENT_GAP" "structured enrollment-gap marker"
assert_contains "$go" "scripts/root-green-selftest.sh" "names unenrolled selftest"
mv "$DRIFT.bak" "$DRIFT"

echo "=== AC-NF1: missing-input fail-closed ==="
mo="$(bash "$FIX/scripts/run-aggregate-selftests.sh" --root /nonexistent-dir-xyz 2>&1)"; morc=$?
assert_eq "$morc" "2" "no scripts/ root => exit 2"
assert_contains "$mo" "POLARIS_AGGREGATE_SELFTEST_NO_ROOT" "missing-root marker"

ao="$(bash "$FIX/scripts/run-aggregate-selftests.sh" --bogus-flag 2>&1)"; aorc=$?
assert_eq "$aorc" "2" "unknown arg => exit 2"
assert_contains "$ao" "POLARIS_AGGREGATE_SELFTEST_ARG" "unknown-arg marker"

echo "=== AC-NEG2: no embedded static skip list remains ==="
runner_body="$(sed '/^usage()/,$d' "$RUNNER")"
assert_not_contains "$runner_body" "QUARANTINE=(" "no embedded QUARANTINE array"
assert_not_contains "$runner_body" "QUARANTINE_OVERRIDE" "no static skip override hook"

echo ""
echo "=== Summary ==="
printf 'PASS=%s  FAIL=%s  TOTAL=%s\n' "$PASS" "$FAIL" "$((PASS + FAIL))"
if [[ "$FAIL" -gt 0 ]]; then
  echo "run-aggregate-selftests-selftest FAILED"
  exit 1
fi
echo "All assertions passed."
exit 0
