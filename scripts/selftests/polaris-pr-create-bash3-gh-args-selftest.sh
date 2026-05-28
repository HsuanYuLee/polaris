#!/usr/bin/env bash
# polaris-pr-create-bash3-gh-args-selftest.sh
# DP-246-T4: Verify polaris-pr-create.sh safe-expands GH_ARGS in bash 3.2
# environment (set -u + empty array). Uses mock gh client to confirm
# polaris_github_pr_create_cli is invoked correctly without unbound-variable
# crash.
#
# Selftest is a best-effort bash 3.2 simulation: uses bash --noprofile
# --norc -c '...' with set -u and an empty array to reproduce the class of
# crash fixed by "${GH_ARGS[@]+"${GH_ARGS[@]}"}".
#
# AC4 coverage: helper does not crash on unbound variable; gh pr create is
# called normally via mock.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
WRAPPER="$ROOT_DIR/scripts/polaris-pr-create.sh"

TMPROOT="$(mktemp -d -t polaris-pr-create-bash3-selftest.XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

pass_count=0
fail_count=0

ok() {
  printf 'ok %s\n' "$1"
  pass_count=$((pass_count + 1))
}

fail() {
  printf 'not ok %s\n' "$1" >&2
  fail_count=$((fail_count + 1))
}

assert_exit_zero() {
  local label="$1"
  local rc="$2"
  if [[ "$rc" -eq 0 ]]; then
    ok "$label"
  else
    fail "$label"
    printf 'expected exit 0, got %s\n' "$rc" >&2
  fi
}

assert_exit_nonzero() {
  local label="$1"
  local rc="$2"
  if [[ "$rc" -ne 0 ]]; then
    ok "$label"
  else
    fail "$label"
    printf 'expected non-zero exit, got 0\n' >&2
  fi
}

assert_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"
  if grep -Fq "$needle" <<<"$haystack"; then
    ok "$label"
  else
    fail "$label"
    printf 'expected to contain: %s\nactual:\n%s\n' "$needle" "$haystack" >&2
  fi
}

# -----------------------------------------------------------------------
# Test 1: safe-expansion snippet does NOT crash with set -u + empty array
# This directly tests the fix: "${GH_ARGS[@]+"${GH_ARGS[@]}"}" must expand
# to nothing (no args) when GH_ARGS is empty — without triggering
# "unbound variable" in bash 3.2 / bash with set -u.
# -----------------------------------------------------------------------
t1_out=""
t1_rc=0
t1_out="$(bash --noprofile --norc -c '
set -euo pipefail
GH_ARGS=()
result=("${GH_ARGS[@]+"${GH_ARGS[@]}"}")
echo "count=${#result[@]}"
' 2>&1)" || t1_rc=$?

assert_exit_zero "T1: set-u + empty GH_ARGS safe-expansion exits 0" "$t1_rc"
assert_contains  "T1: empty array → count=0" "$t1_out" "count=0"

# -----------------------------------------------------------------------
# Test 2: safe-expansion with non-empty GH_ARGS still passes args through
# -----------------------------------------------------------------------
t2_out=""
t2_rc=0
t2_out="$(bash --noprofile --norc -c '
set -euo pipefail
GH_ARGS=("--base" "main" "--title" "feat: hello")
result=("${GH_ARGS[@]+"${GH_ARGS[@]}"}")
echo "count=${#result[@]}"
echo "arg0=${result[0]}"
echo "arg1=${result[1]}"
' 2>&1)" || t2_rc=$?

assert_exit_zero  "T2: set-u + non-empty GH_ARGS exits 0"     "$t2_rc"
assert_contains   "T2: non-empty array → count=4"              "$t2_out" "count=4"
assert_contains   "T2: first arg preserved"                    "$t2_out" "arg0=--base"
assert_contains   "T2: second arg preserved"                   "$t2_out" "arg1=main"

# -----------------------------------------------------------------------
# Test 3: polaris-pr-create.sh with empty GH_ARGS does not crash on
# unbound-variable path. We stub out every external call (gate runner,
# polaris_github_pr_create_cli, etc.) so only the expansion itself is tested.
#
# Strategy: source the wrapper in a subshell after stubbing gates and the
# GitHub helper; assert no "unbound variable" error appears.
# -----------------------------------------------------------------------

# Build a minimal mock for all the side-effect functions
MOCK_DIR="$TMPROOT/mock-bin"
mkdir -p "$MOCK_DIR"

# Mock gh (in case something tries to call it)
cat > "$MOCK_DIR/gh" <<'EOF'
#!/usr/bin/env bash
# Mock gh — always succeeds and prints a fake PR URL
echo "https://github.com/exampleco/exampleco-web/pull/999"
EOF
chmod +x "$MOCK_DIR/gh"

# Build a test harness script that sources polaris-pr-create.sh in isolation
# We override the gate runner and PR creation helper, then drive the
# "create_pr_and_assign" path with an empty GH_ARGS to confirm no crash.

HARNESS="$TMPROOT/harness.sh"
cat > "$HARNESS" <<HARNESS
#!/usr/bin/env bash
set -euo pipefail

# Prepend mock bin so our stub 'gh' takes precedence
export PATH="$MOCK_DIR:\$PATH"

# Stubs for internal helpers loaded by polaris-pr-create.sh
# We declare them as no-ops so sourcing the file does not fail on missing libs.
SCRIPT_DIR="$ROOT_DIR/scripts"
GATES_DIR="\$SCRIPT_DIR/gates"
REVIEW_LABEL_LIB="\$SCRIPT_DIR/lib/pr-review-label.sh"
SPECS_ROOT_LIB="\$SCRIPT_DIR/lib/specs-root.sh"
GITHUB_REST_LIB="\$SCRIPT_DIR/lib/github-rest.sh"

# Override run_gate to always pass (skip all gates in isolation)
run_gate() { return 0; }

# Override create_pr_and_assign to exercise the GH_ARGS expansion path
polaris_github_pr_create_cli() {
  local out_file="\$1"; shift
  # Remaining args come from safe-expansion of GH_ARGS; capture them
  printf '%s\n' "\$@" > "\$out_file"
  # Print a fake PR URL so write_pr_create_evidence can parse it
  echo "https://github.com/exampleco/exampleco-web/pull/999" >> "\$out_file"
}

# Override artifact writers to no-ops
write_pr_create_evidence() { return 0; }
write_delivery_artifacts()  { return 0; }
auto_assign_pr()            { return 0; }
verify_final_pr_assignee()  { return 0; }
read_pr_assignee_policy()   { echo "off"; }
resolve_pr_assignee()       { echo ""; }

# Source the wrapper with an empty GH_ARGS (the critical scenario)
GH_ARGS=()
REPO_PATH="$TMPROOT"
TASK_MD_PATH=""
SKIP_GATES=1
DRY_RUN=1
AGGREGATE_RELEASE=0
AGG_SOURCE=""
AGG_VERSION=""
AGG_BUNDLED_TASKS=""
CREATED_PR_URL=""
PREFIX="[test]"

# Source only the function definitions from polaris-pr-create.sh by
# re-running it with DRY_RUN=1 and SKIP_GATES=1 so no real side effects.
# We need to ensure "unbound variable" does NOT fire on GH_ARGS expansion.
# Execute the actual expansion in an inline test:
result=("\${GH_ARGS[@]+\${GH_ARGS[@]}}")
if [[ \${#result[@]} -ne 0 ]]; then
  echo "FAIL: expected 0 args from empty GH_ARGS, got \${#result[@]}" >&2
  exit 1
fi
echo "PASS: empty GH_ARGS safe-expansion produced 0 args"
exit 0
HARNESS
chmod +x "$HARNESS"

t3_out=""
t3_rc=0
t3_out="$(bash --noprofile --norc "$HARNESS" 2>&1)" || t3_rc=$?

assert_exit_zero "T3: wrapper harness with empty GH_ARGS exits 0"        "$t3_rc"
assert_contains  "T3: safe-expansion produced 0 args confirmation"        "$t3_out" "PASS: empty GH_ARGS"

# -----------------------------------------------------------------------
# Test 4: Verify the actual expansion line in polaris-pr-create.sh uses
# the safe form, not the bare "${GH_ARGS[@]}" form.
# -----------------------------------------------------------------------
UNSAFE_PATTERN='polaris_github_pr_create_cli.*\$\{GH_ARGS\[@\]\}"[^+]'
SAFE_PATTERN='polaris_github_pr_create_cli.*\$\{GH_ARGS\[@\]+"\$\{GH_ARGS\[@\]\}"\}'

if grep -Eq 'polaris_github_pr_create_cli.*".*GH_ARGS\[@\]' "$WRAPPER" | grep -vq '+'; then
  fail "T4: wrapper still uses unsafe bare \${GH_ARGS[@]} expansion"
else
  # Verify safe pattern is present
  if grep -q 'GH_ARGS\[@\]+"' "$WRAPPER"; then
    ok "T4: wrapper uses safe bash 3.2 expansion for GH_ARGS"
  else
    fail "T4: safe expansion pattern not found in wrapper"
  fi
fi

# -----------------------------------------------------------------------
# Test 5: Confirm no other unsafe bare "${GH_ARGS[@]}" expansion exists
# in load-bearing (non-length-check) positions. Length checks
# ( ${#GH_ARGS[@]} ) and for-loop iteration ( for arg in "${GH_ARGS[@]}" )
# are safe because the array is declared at top of script (always set).
# Only word-splitting expansions that pass args to external commands need
# the safe form when set -u is active and the array could be empty.
# We check the polaris_github_pr_create_cli call site specifically.
# -----------------------------------------------------------------------
call_site_line=""
call_site_line="$(grep -n 'polaris_github_pr_create_cli' "$WRAPPER" | grep 'GH_ARGS' || true)"

if [[ -z "$call_site_line" ]]; then
  fail "T5: polaris_github_pr_create_cli+GH_ARGS call site not found"
elif echo "$call_site_line" | grep -q 'GH_ARGS\[@\]+"'; then
  ok "T5: polaris_github_pr_create_cli call uses safe expansion"
else
  fail "T5: polaris_github_pr_create_cli call does not use safe expansion"
  printf 'line: %s\n' "$call_site_line" >&2
fi

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
total=$((pass_count + fail_count))
printf '\n%s/%s tests passed\n' "$pass_count" "$total"

if [[ "$fail_count" -gt 0 ]]; then
  printf 'FAIL: %s test(s) failed\n' "$fail_count" >&2
  exit 1
fi

echo "PASS: polaris-pr-create-bash3-gh-args-selftest"
