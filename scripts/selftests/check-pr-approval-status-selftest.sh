#!/usr/bin/env bash
# Purpose: Selftest for .claude/skills/check-pr-approvals/scripts/check-pr-approval-status.sh
#          — the commit_id-based approval-staleness consumer (DP-315 T2,
#          AC3 / AC-NEG1 / AC-NF2). Drives the script end-to-end through a
#          `gh` PATH-shim mock so no real GitHub round-trip is required.
# Inputs:  none (installs a mock `gh` on PATH and pipes synthetic PR JSON on
#          stdin to the script under test).
# Outputs: stdout PASS/FAIL lines; exit 0 = all pass, exit 1 = any failure.
#
# Contract under test (DP-315 T2):
#   AC3     — valid_approvals / has_stale / per-reviewer is_stale are driven by
#             review.commit_id == pr.head.sha (routed through the shared helper
#             scripts/lib/approval-staleness.sh), NOT by submitted_at < pushed_at.
#   AC-NEG1 — shared-repo false positive: a reviewer approves AT the current head,
#             then an UNRELATED branch push bumps head.repo.pushed_at. Under the
#             old timestamp rule the approval would flip to stale; under the
#             commit_id rule it stays VALID. Asserts valid_approvals counts the
#             head-matching approval (not all-stale).
#   AC-NF2  — no NEW gh api round-trip: the script must add only --jq projection
#             changes. Asserts the mock observed exactly the same two endpoints
#             (.../reviews and the PR object) and no extra `gh api` call.
set -euo pipefail

# shellcheck source=../lib/selftest-bootstrap.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/selftest-bootstrap.sh"
init_ROOT_DIR "${BASH_SOURCE[0]}"

SCRIPT_UNDER_TEST="$ROOT_DIR/.claude/skills/check-pr-approvals/scripts/check-pr-approval-status.sh"

FAIL=0

assert_eq() {
  # Args: <label> <expected> <actual>
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    printf 'PASS: %s (got %s)\n' "$label" "$actual"
  else
    printf 'FAIL: %s — expected %s, got %s\n' "$label" "$expected" "$actual" >&2
    FAIL=1
  fi
}

# Head commit SHA the PR currently points at.
HEAD_SHA="aaaa111headsha"

# install_mock_gh writes a `gh` shim into $1 (a dir prepended to PATH).
# The shim:
#   * appends one line per invocation to $GH_CALL_LOG so the test can assert
#     the exact set/count of `gh api` round-trips (AC-NF2);
#   * serves the reviews endpoint with a commit_id-bearing projection;
#   * serves the PR object endpoint with a head.sha projection.
# It deliberately refuses any extra endpoint so an accidental new round-trip
# would surface as a hard failure rather than silently passing.
install_mock_gh() {
  local mockbin="$1"
  mkdir -p "$mockbin"
  cat > "$mockbin/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

# Record the raw argv of every gh call for AC-NF2 round-trip accounting.
printf '%s\n' "\$*" >> "$GH_CALL_LOG"

# Only \`gh api <path> --jq <expr>\` is supported by this mock.
if [[ "\${1:-}" != "api" ]]; then
  echo "mock gh: unsupported subcommand: \${1:-}" >&2
  exit 1
fi

api_path="\${2:-}"

case "\$api_path" in
  */pulls/*/reviews)
    # Reviewer "approver" approved AT the current head commit.
    # Reviewer "stale-approver" approved at an OLD commit (force-pushed away).
    printf '%s\n' '[{"user":"approver","state":"APPROVED","commit_id":"$HEAD_SHA"},{"user":"stale-approver","state":"APPROVED","commit_id":"oldcommit999"}]'
    ;;
  */pulls/*)
    # PR object: head.sha is the canonical current head.
    printf '%s\n' '$HEAD_SHA'
    ;;
  *)
    echo "mock gh: unexpected api path: \$api_path" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "$mockbin/gh"
}

run_script() {
  # Args: <pr_json_on_stdin via heredoc caller>; reads stdin, returns enriched JSON on stdout.
  ORG="exampleco" PATH="$MOCKBIN:$PATH" bash "$SCRIPT_UNDER_TEST" --threshold 2 2>/dev/null
}

# --- Setup -------------------------------------------------------------------

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
MOCKBIN="$WORKDIR/bin"
GH_CALL_LOG="$WORKDIR/gh-calls.log"
: > "$GH_CALL_LOG"
install_mock_gh "$MOCKBIN"

PR_JSON='[{"repo":"exampleco-web","number":42}]'

OUT="$(printf '%s' "$PR_JSON" | run_script)"

# --- AC3 / AC-NEG1: commit_id-driven valid/stale -----------------------------

# AC-NEG1 core: one reviewer approved at head (commit_id == head.sha) and one at
# an old commit. valid_approvals MUST be 1 (the head-matching approval), NOT 0.
# A 0 here means the unrelated pushed_at bump (old rule) wrongly invalidated the
# head approval — the shared-repo false positive this DP eliminates.
valid_approvals="$(printf '%s' "$OUT" | jq -r '.[0].valid_approvals')"
assert_eq "AC-NEG1: head-matching approval counts as valid (not all-stale)" "1" "$valid_approvals"

total_approvals="$(printf '%s' "$OUT" | jq -r '.[0].total_approvals')"
assert_eq "AC3: total_approvals counts both APPROVED reviews" "2" "$total_approvals"

has_stale="$(printf '%s' "$OUT" | jq -r '.[0].has_stale')"
assert_eq "AC3: has_stale true when one approval is at an old commit" "true" "$has_stale"

approver_is_stale="$(printf '%s' "$OUT" | jq -r '.[0].reviewers[] | select(.user=="approver") | .is_stale')"
assert_eq "AC3: head-matching reviewer is_stale=false" "false" "$approver_is_stale"

stale_is_stale="$(printf '%s' "$OUT" | jq -r '.[0].reviewers[] | select(.user=="stale-approver") | .is_stale')"
assert_eq "AC3: old-commit reviewer is_stale=true" "true" "$stale_is_stale"

# --- AC-NF2: no new gh api round-trip ----------------------------------------

# The script must hit exactly two endpoints per PR: the reviews list and the PR
# object. Both already existed before this change (the PR object previously
# fetched head.repo.pushed_at); only the --jq projection changed. Therefore the
# total gh call count for one PR must be exactly 2 — a third call would mean a
# new round-trip was introduced.
gh_call_count="$(wc -l < "$GH_CALL_LOG" | tr -d ' ')"
assert_eq "AC-NF2: exactly 2 gh api calls per PR (no new round-trip)" "2" "$gh_call_count"

reviews_calls="$(grep -c 'pulls/[^ ]*/reviews' "$GH_CALL_LOG" || true)"
assert_eq "AC-NF2: exactly 1 reviews-endpoint call" "1" "$reviews_calls"

# PR-object call (the .../pulls/<n> without /reviews suffix). Count gh api calls
# to a pulls path that is NOT the reviews endpoint.
pr_object_calls="$(grep 'pulls/' "$GH_CALL_LOG" | grep -vc '/reviews' || true)"
assert_eq "AC-NF2: exactly 1 PR-object call (reused, not added)" "1" "$pr_object_calls"

# Adversarial guard: the script must NOT project head.repo.pushed_at anymore.
# Source-level assertion complements the runtime behaviour above (AC3 removal).
if grep -q 'pushed_at' "$SCRIPT_UNDER_TEST"; then
  printf 'FAIL: AC3 — check-pr-approval-status.sh still references pushed_at\n' >&2
  FAIL=1
else
  printf 'PASS: AC3 — check-pr-approval-status.sh no longer references pushed_at\n'
fi

# Adversarial guard: the staleness decision must be routed through the shared
# helper, not reimplemented inline (AC2/AC-NF1 single writer path).
if grep -q 'approval-staleness.sh' "$SCRIPT_UNDER_TEST"; then
  printf 'PASS: AC3 — staleness routed through shared helper approval-staleness.sh\n'
else
  printf 'FAIL: AC3 — check-pr-approval-status.sh does not source the shared helper\n' >&2
  FAIL=1
fi

if [[ "$FAIL" -eq 0 ]]; then
  printf '\nAll check-pr-approval-status selftests PASSED.\n'
  exit 0
fi

printf '\ncheck-pr-approval-status selftest FAILED.\n' >&2
exit 1
