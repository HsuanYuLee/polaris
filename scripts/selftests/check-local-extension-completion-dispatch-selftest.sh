#!/usr/bin/env bash
set -euo pipefail

# scripts/selftests/check-local-extension-completion-dispatch-selftest.sh
#
# DP-230 D22 / AC18 / AC-NEG11 selftest:
#   check-local-extension-completion.sh must dispatch its completion evidence
#   schema by task_kind frontmatter (V vs T) and fail-stop on unknown task_kind
#   with stderr token POLARIS_COMPLETION_GATE_UNKNOWN_TASK_KIND.
#
# Cases (DP-360 T7: V disposition read from the V-task ac_verification block):
#   1. task_kind=T with valid verify evidence → PASS (rc=0).
#   2. task_kind=V with PASS ac_verification block → PASS (rc=0).
#   3. task_kind=V with FAIL ac_verification block → BLOCK (rc=2).
#   4. Missing task_kind frontmatter (legacy hand-edit) → fail-stop with
#      POLARIS_COMPLETION_GATE_UNKNOWN_TASK_KIND (rc=2).
#   5. task_kind=Z (unknown) → fail-stop with POLARIS_COMPLETION_GATE_UNKNOWN_TASK_KIND (rc=2).
#   6. task_kind=V with no ac_verification block → BLOCK (rc=2)
#      (V schema must not silently fall back to verify-evidence Layer B).
#   7. AC-NEG2: task_kind=V PASS block + stray torn-down ac-verification marker
#      → block authority wins (marker ignored), rc=0.

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/check-local-extension-completion.sh"
TMPROOT="$(mktemp -d -t local-ext-completion-dispatch-XXXXXX)"
PASS=0
TOTAL=0

cleanup() {
  rm -rf "$TMPROOT"
}
trap cleanup EXIT

assert_rc() {
  local label="$1"
  local got="$2"
  local want="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1))
    printf 'ok %s\n' "$label"
  else
    printf 'not ok %s: got rc=%s want rc=%s\n' "$label" "$got" "$want" >&2
  fi
}

assert_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
    printf 'ok %s\n' "$label"
  else
    printf 'not ok %s: missing %q\n' "$label" "$needle" >&2
    printf '  output: %s\n' "$haystack" >&2
  fi
}

assert_not_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$haystack" != *"$needle"* ]]; then
    PASS=$((PASS + 1))
    printf 'ok %s\n' "$label"
  else
    printf 'not ok %s: unexpected %q\n' "$label" "$needle" >&2
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

# write_task <repo_root> <task_md_path> <task_id> <task_kind|"NONE"> <head_sha> <evidence_kind=verify|ac_verification> <evidence_path> <ci_local_path> [ac_block_status]
# DP-360 T7: for V tasks, $9 (ac_block_status) embeds an `ac_verification`
# frontmatter block on the V-task itself (the canonical authority the V dispatcher
# now reads). Empty → no block. The external evidence path is retained only for
# the legacy guard cases (it must be ignored).
write_task() {
  local repo="$1"
  local task_path="$2"
  local task_id="$3"
  local task_kind="$4"
  local head_sha="$5"
  local evidence_kind="$6"
  local evidence_path="$7"
  local ci_local_path="$8"
  local ac_block_status="${9:-}"

  mkdir -p "$(dirname "$task_path")"
  {
    printf -- '---\n'
    printf 'title: "%s fixture"\n' "$task_id"
    printf 'description: "dispatch selftest"\n'
    printf 'draft: true\n'
    printf 'sidebar:\n  hidden: true\n'
    printf 'status: IN_PROGRESS\n'
    if [[ "$task_kind" != "NONE" ]]; then
      printf 'task_kind: %s\n' "$task_kind"
    fi
    if [[ -n "$ac_block_status" ]]; then
      printf 'ac_verification:\n'
      printf '  status: %s\n' "$ac_block_status"
    fi
    printf 'depends_on: []\n'
    printf 'extension_deliverable:\n'
    printf '  endpoint: local_extension\n'
    printf '  extension_id: example-ext\n'
    printf '  task_head_sha: %s\n' "$head_sha"
    printf '  workspace_commit: %s\n' "$head_sha"
    printf '  template_commit: %s\n' "$head_sha"
    printf '  version_tag: N/A\n'
    printf '  release_url: N/A\n'
    printf '  completed_at: 2026-05-25T12:00:00+08:00\n'
    printf '  evidence:\n'
    printf '    ci_local: %s\n' "${ci_local_path:-N/A}"
    if [[ "$evidence_kind" == "verify" ]]; then
      printf '    verify: %s\n' "$evidence_path"
      printf '    ac_verification: N/A\n'
    elif [[ "$evidence_kind" == "ac_verification" ]]; then
      printf '    verify: N/A\n'
      printf '    ac_verification: %s\n' "$evidence_path"
    else
      printf '    verify: N/A\n'
      printf '    ac_verification: N/A\n'
    fi
    printf '    vr: N/A\n'
    printf -- '---\n\n'
    printf '# %s fixture\n' "$task_id"
  } > "$task_path"
}

write_verify_evidence() {
  local path="$1"
  local task_id="$2"
  local head_sha="$3"
  local exit_code="${4:-0}"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
{
  "ticket": "$task_id",
  "head_sha": "$head_sha",
  "writer": "run-verify-command.sh",
  "exit_code": $exit_code,
  "at": "2026-05-25T12:00:00+08:00"
}
EOF
}

REPO="$TMPROOT/repo"
init_repo "$REPO"
HEAD_SHA="$(git -C "$REPO" rev-parse HEAD)"

# ── Case 1: task_kind=T with valid verify evidence → rc=0 ──
TASK_T="$REPO/tasks/T1.md"
EV_T_VERIFY="$TMPROOT/case1-verify.json"
write_verify_evidence "$EV_T_VERIFY" "DP-999-T1" "$HEAD_SHA" 0
write_task "$REPO" "$TASK_T" "DP-999-T1" "T" "$HEAD_SHA" "verify" "$EV_T_VERIFY" ""

set +e
OUTPUT_T="$(
  bash "$SCRIPT_PATH" \
    --repo "$REPO" \
    --task-md "$TASK_T" \
    --task-id "DP-999-T1" \
    --extension-id "example-ext" 2>&1
)"
RC_T=$?
set -e
assert_rc "T-task valid verify evidence rc=0" "$RC_T" 0
assert_contains "T-task PASS message" "$OUTPUT_T" "local extension completion satisfied"

# ── Case 2 (DP-360 T7): task_kind=V with PASS ac_verification block → rc=0 ──
TASK_V="$REPO/tasks/V1.md"
write_task "$REPO" "$TASK_V" "DP-999-V1" "V" "$HEAD_SHA" "ac_verification" "N/A" "" "PASS"

set +e
OUTPUT_V="$(
  bash "$SCRIPT_PATH" \
    --repo "$REPO" \
    --task-md "$TASK_V" \
    --task-id "DP-999-V1" \
    --extension-id "example-ext" 2>&1
)"
RC_V=$?
set -e
assert_rc "V-task valid ac_verification evidence rc=0" "$RC_V" 0
assert_contains "V-task PASS message" "$OUTPUT_V" "local extension completion satisfied"

# ── Case 3 (DP-360 T7): task_kind=V with FAIL ac_verification block → rc=2 ──
TASK_V_FAIL="$REPO/tasks/V2.md"
write_task "$REPO" "$TASK_V_FAIL" "DP-999-V2" "V" "$HEAD_SHA" "ac_verification" "N/A" "" "FAIL"

set +e
OUTPUT_V_FAIL="$(
  bash "$SCRIPT_PATH" \
    --repo "$REPO" \
    --task-md "$TASK_V_FAIL" \
    --task-id "DP-999-V2" \
    --extension-id "example-ext" 2>&1
)"
RC_V_FAIL=$?
set -e
assert_rc "V-task failing ac_verification rc=2" "$RC_V_FAIL" 2

# ── Case 4: missing task_kind (legacy) → fail-stop with token ──
TASK_LEGACY="$REPO/tasks/T-legacy.md"
EV_LEG="$TMPROOT/case4-verify.json"
write_verify_evidence "$EV_LEG" "DP-999-T9" "$HEAD_SHA" 0
write_task "$REPO" "$TASK_LEGACY" "DP-999-T9" "NONE" "$HEAD_SHA" "verify" "$EV_LEG" ""

set +e
OUTPUT_LEGACY="$(
  bash "$SCRIPT_PATH" \
    --repo "$REPO" \
    --task-md "$TASK_LEGACY" \
    --task-id "DP-999-T9" \
    --extension-id "example-ext" 2>&1
)"
RC_LEGACY=$?
set -e
assert_rc "legacy task without task_kind fail-stop rc=2" "$RC_LEGACY" 2
assert_contains "legacy task emits unknown-kind token" "$OUTPUT_LEGACY" "POLARIS_COMPLETION_GATE_UNKNOWN_TASK_KIND"

# ── Case 5: task_kind=Z (unknown value) → fail-stop with token ──
TASK_UNK="$REPO/tasks/T-unknown.md"
EV_UNK="$TMPROOT/case5-verify.json"
write_verify_evidence "$EV_UNK" "DP-999-T10" "$HEAD_SHA" 0
write_task "$REPO" "$TASK_UNK" "DP-999-T10" "Z" "$HEAD_SHA" "verify" "$EV_UNK" ""

set +e
OUTPUT_UNK="$(
  bash "$SCRIPT_PATH" \
    --repo "$REPO" \
    --task-md "$TASK_UNK" \
    --task-id "DP-999-T10" \
    --extension-id "example-ext" 2>&1
)"
RC_UNK=$?
set -e
assert_rc "unknown task_kind value fail-stop rc=2" "$RC_UNK" 2
assert_contains "unknown task_kind emits token" "$OUTPUT_UNK" "POLARIS_COMPLETION_GATE_UNKNOWN_TASK_KIND"
assert_not_contains "unknown task_kind must not silently dispatch to T or V" "$OUTPUT_UNK" "local extension completion satisfied"

# ── Case 6 (DP-360 T7): task_kind=V with NO ac_verification block → rc=2 ──
# The V dispatcher reads the V-task's own ac_verification frontmatter block.
# Absent block → block; it must NOT fall back to a verify-evidence path.
TASK_V_MISS="$REPO/tasks/V3.md"
EV_V_MISS_VERIFY="$TMPROOT/case6-verify.json"
write_verify_evidence "$EV_V_MISS_VERIFY" "DP-999-V3" "$HEAD_SHA" 0
# Point a verify-style evidence path at it (must be ignored) and omit the block.
write_task "$REPO" "$TASK_V_MISS" "DP-999-V3" "V" "$HEAD_SHA" "verify" "$EV_V_MISS_VERIFY" "" ""

set +e
OUTPUT_V_MISS="$(
  bash "$SCRIPT_PATH" \
    --repo "$REPO" \
    --task-md "$TASK_V_MISS" \
    --task-id "DP-999-V3" \
    --extension-id "example-ext" 2>&1
)"
RC_V_MISS=$?
set -e
assert_rc "V-task with no ac_verification block rc=2" "$RC_V_MISS" 2
assert_not_contains "V dispatcher must not fall back to verify schema" "$OUTPUT_V_MISS" "local extension completion satisfied"

# ── Case 7 (DP-360 T7 AC-NEG2): task_kind=V with PASS block but a STRAY torn-down
# ac-verification marker — the block is authority; marker must not influence. ──
TASK_V_STRAY="$REPO/tasks/V4.md"
mkdir -p "$REPO/.polaris/evidence/ac-verification"
cat > "$REPO/.polaris/evidence/ac-verification/DP-999-V4-${HEAD_SHA}.json" <<EOF
{"schema_version":1,"marker_kind":"ac_verification","writer":"verify-AC","work_item_id":"DP-999-V4","status":"FAIL","freshness":{"head_sha":"${HEAD_SHA}"}}
EOF
write_task "$REPO" "$TASK_V_STRAY" "DP-999-V4" "V" "$HEAD_SHA" "ac_verification" "N/A" "" "PASS"

set +e
OUTPUT_V_STRAY="$(
  bash "$SCRIPT_PATH" \
    --repo "$REPO" \
    --task-md "$TASK_V_STRAY" \
    --task-id "DP-999-V4" \
    --extension-id "example-ext" 2>&1
)"
RC_V_STRAY=$?
set -e
assert_rc "V-task PASS block + stray FAIL marker → block authority wins rc=0" "$RC_V_STRAY" 0

printf '\nTOTAL=%d PASS=%d FAIL=%d\n' "$TOTAL" "$PASS" "$((TOTAL - PASS))"
if [[ "$PASS" -ne "$TOTAL" ]]; then
  exit 1
fi
