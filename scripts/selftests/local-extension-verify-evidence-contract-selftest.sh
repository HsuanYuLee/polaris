#!/usr/bin/env bash
set -euo pipefail

# scripts/selftests/local-extension-verify-evidence-contract-selftest.sh
#
# Purpose: DP-293 T3 / AC4 — prove the Layer B verify-evidence skip contract is
#   end-to-end consistent across the producer gate (scripts/gates/gate-evidence.sh)
#   and the consumer gate (scripts/check-local-extension-completion.sh) for a
#   framework `task_kind: T` task that legitimately has no Layer B verify marker.
#   Both ends must honor POLARIS_SKIP_EVIDENCE=1, eliminating the Gap 3 mutual
#   exclusion where the producer skips the marker but the consumer hard-blocks.
# Inputs:  none (hermetic; builds a throwaway git repo + fixture task.md in tmp).
# Outputs: prints ok/not-ok lines + TOTAL/PASS/FAIL; exit 0 on full pass, 1 otherwise.
# Exit code: 0 PASS, 1 contract failure.
#
# Cases:
#   1. consumer, task_kind=T, no verify marker, POLARIS_SKIP_EVIDENCE=1
#        → rc=0 + bypass message (the fix: consumer honors the skip flag).
#   2. consumer, task_kind=T, no verify marker, flag UNSET
#        → rc=2 block (the fix does not blanket-disable the gate).
#   3. consumer, task_kind=T, VALID verify marker, POLARIS_SKIP_EVIDENCE=1
#        → rc=0 (skip flag is harmless on the happy path; no regression).
#   4. producer gate-evidence.sh, POLARIS_SKIP_EVIDENCE=1
#        → rc=0 + bypass message (same flag → producer skips too).
#   Parity: case 1 (consumer skip) + case 4 (producer skip) under the SAME flag
#   prove both ends share one skip contract; case 2 proves the consumer still
#   requires the marker when not skipping.

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONSUMER="$SCRIPTS_DIR/check-local-extension-completion.sh"
PRODUCER="$SCRIPTS_DIR/gates/gate-evidence.sh"
TMPROOT="$(mktemp -d -t local-ext-verify-evidence-contract-XXXXXX)"
PASS=0
TOTAL=0

cleanup() {
  rm -rf "$TMPROOT"
}
trap cleanup EXIT

for f in "$CONSUMER" "$PRODUCER"; do
  [[ -f "$f" ]] || { echo "FAIL: missing script under test: $f" >&2; exit 1; }
done

assert_rc() {
  local label="$1" got="$2" want="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1))
    printf 'ok %s\n' "$label"
  else
    printf 'not ok %s: got rc=%s want rc=%s\n' "$label" "$got" "$want" >&2
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
    printf 'ok %s\n' "$label"
  else
    printf 'not ok %s: missing %q\n' "$label" "$needle" >&2
    printf '  output: %s\n' "$haystack" >&2
  fi
}

init_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git -c init.defaultBranch=main init --quiet "$repo"
  git -C "$repo" config user.email "selftest@example.com"
  git -C "$repo" config user.name "selftest"
  : > "$repo/.gitignore"
  git -C "$repo" add .gitignore
  git -C "$repo" commit --quiet -m "init"
}

# write_task <repo_root> <task_md_path> <task_id> <head_sha> <verify_path|"N/A">
write_task() {
  local repo="$1" task_path="$2" task_id="$3" head_sha="$4" verify_path="$5"
  mkdir -p "$(dirname "$task_path")"
  {
    printf -- '---\n'
    printf 'title: "%s fixture"\n' "$task_id"
    printf 'description: "verify-evidence skip contract selftest"\n'
    printf 'draft: true\n'
    printf 'sidebar:\n  hidden: true\n'
    printf 'status: IN_PROGRESS\n'
    printf 'task_kind: T\n'
    printf 'depends_on: []\n'
    printf 'extension_deliverable:\n'
    printf '  endpoint: local_extension\n'
    printf '  extension_id: example-ext\n'
    printf '  task_head_sha: %s\n' "$head_sha"
    printf '  workspace_commit: %s\n' "$head_sha"
    printf '  template_commit: %s\n' "$head_sha"
    printf '  version_tag: N/A\n'
    printf '  release_url: N/A\n'
    printf '  completed_at: 2026-06-07T12:00:00+08:00\n'
    printf '  evidence:\n'
    printf '    ci_local: N/A\n'
    printf '    verify: %s\n' "$verify_path"
    printf '    ac_verification: N/A\n'
    printf '    vr: N/A\n'
    printf -- '---\n\n'
    printf '# %s fixture\n' "$task_id"
  } > "$task_path"
}

write_verify_evidence() {
  local path="$1" task_id="$2" head_sha="$3"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
{
  "ticket": "$task_id",
  "head_sha": "$head_sha",
  "writer": "run-verify-command.sh",
  "exit_code": 0,
  "at": "2026-06-07T12:00:00+08:00"
}
EOF
}

run_consumer() {
  local repo="$1" task_md="$2" task_id="$3"
  bash "$CONSUMER" \
    --repo "$repo" \
    --task-md "$task_md" \
    --task-id "$task_id" \
    --extension-id "example-ext" 2>&1
}

REPO="$TMPROOT/repo"
init_repo "$REPO"
HEAD_SHA="$(git -C "$REPO" rev-parse HEAD)"

# ── Case 1: consumer, task_kind=T, no verify marker, skip flag set → rc=0 (fix) ──
TASK_NO_MARKER="$REPO/tasks/T1.md"
write_task "$REPO" "$TASK_NO_MARKER" "DP-293-T1" "$HEAD_SHA" "N/A"

set +e
OUT_SKIP="$(POLARIS_SKIP_EVIDENCE=1 run_consumer "$REPO" "$TASK_NO_MARKER" "DP-293-T1")"
RC_SKIP=$?
set -e
assert_rc "consumer T-task no-marker + skip flag rc=0" "$RC_SKIP" 0
assert_contains "consumer announces POLARIS_SKIP_EVIDENCE bypass" "$OUT_SKIP" "POLARIS_SKIP_EVIDENCE=1"
assert_contains "consumer still reaches completion-satisfied" "$OUT_SKIP" "local extension completion satisfied"

# ── Case 2: consumer, task_kind=T, no verify marker, flag UNSET → rc=2 block ──
set +e
OUT_NOSKIP="$(unset POLARIS_SKIP_EVIDENCE; run_consumer "$REPO" "$TASK_NO_MARKER" "DP-293-T1")"
RC_NOSKIP=$?
set -e
assert_rc "consumer T-task no-marker + no flag rc=2 (gate still enforces)" "$RC_NOSKIP" 2
assert_contains "consumer blocks on missing verify evidence" "$OUT_NOSKIP" "verify evidence"

# ── Case 3: consumer, task_kind=T, VALID marker, skip flag set → rc=0 (no regression) ──
TASK_WITH_MARKER="$REPO/tasks/T2.md"
EV_VERIFY="$TMPROOT/t2-verify.json"
write_verify_evidence "$EV_VERIFY" "DP-293-T2" "$HEAD_SHA"
write_task "$REPO" "$TASK_WITH_MARKER" "DP-293-T2" "$HEAD_SHA" "$EV_VERIFY"

set +e
OUT_HAPPY="$(POLARIS_SKIP_EVIDENCE=1 run_consumer "$REPO" "$TASK_WITH_MARKER" "DP-293-T2")"
RC_HAPPY=$?
set -e
assert_rc "consumer T-task valid marker + skip flag rc=0 (happy path intact)" "$RC_HAPPY" 0
assert_contains "consumer happy path reaches completion-satisfied" "$OUT_HAPPY" "local extension completion satisfied"

# ── Case 4: producer gate-evidence.sh, skip flag set → rc=0 (same flag, same skip) ──
set +e
OUT_PROD="$(POLARIS_SKIP_EVIDENCE=1 bash "$PRODUCER" --repo "$REPO" 2>&1)"
RC_PROD=$?
set -e
assert_rc "producer gate-evidence skip flag rc=0" "$RC_PROD" 0
assert_contains "producer announces POLARIS_SKIP_EVIDENCE bypass" "$OUT_PROD" "POLARIS_SKIP_EVIDENCE=1"

printf '\nTOTAL=%d PASS=%d FAIL=%d\n' "$TOTAL" "$PASS" "$((TOTAL - PASS))"
if [[ "$PASS" -ne "$TOTAL" ]]; then
  exit 1
fi
