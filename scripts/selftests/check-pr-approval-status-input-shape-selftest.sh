#!/usr/bin/env bash
# Purpose: Selftest for .claude/skills/check-pr-approvals/scripts/check-pr-approval-status.sh
#          input-shape guard + gh api fail-closed contract (DP-324 T2,
#          AC3 / AC4 / AC-NEG2 / AC-NF1 / AC-NF2).
# Inputs:  none (drives the script under test with a hermetic gh PATH shim).
# Outputs: stdout PASS/FAIL lines; exit 0 = all pass, exit 1 = any failure.
#
# Contract under test (DP-324 T2):
#   AC3  — org-prefixed repo input ("owner/repo") fail-closes:
#          exit 2 + POLARIS_APPROVAL_INPUT_SHAPE (before any gh consumption).
#   AC4  — gh api non-zero exit (e.g. 404) fail-closes:
#          exit 2 + POLARIS_APPROVAL_API_ERROR (no silent `|| echo []`).
#   AC-NEG2 — genuine 0-review PR (gh succeeds, returns []) still flows through
#             normally: exit 0, valid output, NO POLARIS_APPROVAL_API_ERROR.
#   AC-NF1 — the gh shim is the only external surface; no network is touched.
#   AC-NF2 — markers are emitted on stderr so the orchestrator can grep them.
set -euo pipefail

SCRIPT_UNDER_TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.claude/skills/check-pr-approvals/scripts/check-pr-approval-status.sh"

FAIL=0

# Build a hermetic gh PATH shim. The shim's behavior is selected per-case via
# the GH_SHIM_MODE env var so a single script can serve all three cases without
# touching the network (AC-NF1).
SHIM_DIR="$(mktemp -d)"
trap 'rm -rf "$SHIM_DIR"' EXIT

cat > "$SHIM_DIR/gh" <<'SHIM'
#!/usr/bin/env bash
# Hermetic gh stub: never touches the network.
#   GH_SHIM_MODE=empty   — reviews endpoint returns [], head endpoint returns a sha.
#   GH_SHIM_MODE=apierror — every gh api call exits non-zero (simulates 404).
case "${GH_SHIM_MODE:-empty}" in
  apierror)
    echo "gh: HTTP 404 Not Found" >&2
    exit 1
    ;;
  empty|*)
    # Distinguish the reviews call from the head.sha call by argument shape.
    for arg in "$@"; do
      case "$arg" in
        */reviews) echo "[]"; exit 0 ;;
        repos/*/pulls/*) echo "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"; exit 0 ;;
      esac
    done
    echo "[]"
    exit 0
    ;;
esac
SHIM
chmod +x "$SHIM_DIR/gh"

# run_case <label> <gh_shim_mode> <repo_value> -> captures exit code + stderr.
# Echoes "exit=<code>" then the captured stderr into globals OUT_CODE / OUT_ERR.
run_case() {
  local mode="$1" repo="$2"
  local prs err
  prs="$(printf '[{"repo":"%s","number":1}]' "$repo")"
  set +e
  err="$(
    PATH="$SHIM_DIR:$PATH" \
    GH_SHIM_MODE="$mode" \
    ORG="example-org" \
      bash "$SCRIPT_UNDER_TEST" <<<"$prs" 2>&1 >/dev/null
  )"
  OUT_CODE=$?
  set -e
  OUT_ERR="$err"
}

# run_case_stdout: like run_case but also keeps stdout for the genuine-empty case.
run_case_stdout() {
  local mode="$1" repo="$2"
  local prs combined
  prs="$(printf '[{"repo":"%s","number":1}]' "$repo")"
  set +e
  combined="$(
    PATH="$SHIM_DIR:$PATH" \
    GH_SHIM_MODE="$mode" \
    ORG="example-org" \
      bash "$SCRIPT_UNDER_TEST" <<<"$prs" 2>&1
  )"
  OUT_CODE=$?
  set -e
  OUT_ALL="$combined"
}

assert_code() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    printf 'PASS: %s (exit %s)\n' "$label" "$actual"
  else
    printf 'FAIL: %s — expected exit %s, got %s\n' "$label" "$expected" "$actual" >&2
    FAIL=1
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if grep -q "$needle" <<< "$haystack"; then
    printf 'PASS: %s\n' "$label"
  else
    printf 'FAIL: %s — missing %s\n' "$label" "$needle" >&2
    FAIL=1
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if grep -q "$needle" <<< "$haystack"; then
    printf 'FAIL: %s — unexpectedly found %s\n' "$label" "$needle" >&2
    FAIL=1
  else
    printf 'PASS: %s\n' "$label"
  fi
}

# --- Case 1: org-prefixed repo input (AC3) -----------------------------------
# repo="owner/repo" is the wrong shape; the script must fail-close before any
# gh consumption with exit 2 + POLARIS_APPROVAL_INPUT_SHAPE.
run_case "empty" "owner/repo"
assert_code "org-prefixed repo => exit 2" "2" "$OUT_CODE"
assert_contains "org-prefixed repo => POLARIS_APPROVAL_INPUT_SHAPE" 'POLARIS_APPROVAL_INPUT_SHAPE' "$OUT_ERR"

# --- Case 2: gh api error / 404 (AC4) ----------------------------------------
# gh exits non-zero; the script must fail-close with exit 2 +
# POLARIS_APPROVAL_API_ERROR instead of silently swallowing into [].
run_case "apierror" "good-repo"
assert_code "gh api error => exit 2" "2" "$OUT_CODE"
assert_contains "gh api error => POLARIS_APPROVAL_API_ERROR" 'POLARIS_APPROVAL_API_ERROR' "$OUT_ERR"

# --- Case 3: genuine empty (gh succeeds, []) (AC-NEG2) ------------------------
# A real 0-review PR must flow through normally: exit 0, no API_ERROR marker.
run_case_stdout "empty" "good-repo"
assert_code "genuine empty => exit 0" "0" "$OUT_CODE"
assert_not_contains "genuine empty => no POLARIS_APPROVAL_API_ERROR" 'POLARIS_APPROVAL_API_ERROR' "$OUT_ALL"

if [[ "$FAIL" -ne 0 ]]; then
  printf '\nRESULT: FAIL\n' >&2
  exit 1
fi
printf '\nRESULT: PASS\n'
