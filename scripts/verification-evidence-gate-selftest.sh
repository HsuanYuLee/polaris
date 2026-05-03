#!/usr/bin/env bash
# scripts/verification-evidence-gate-selftest.sh — DP-032 Wave β D15 selftest
#
# Coverage for verification-evidence-gate.sh (extended in DP-032 D15):
#   - new format (head_sha-bound) found → allow
#   - new format with writer != whitelist → block
#   - new format with invalid JSON → block
#   - new format missing required field → block
#   - new format with exit_code != 0 → block
#   - new format passes WITHOUT 4h stale check (head_sha auto-stale)
#   - old ticket-only evidence file is ignored → block
#   - POLARIS_SKIP_EVIDENCE=1 → allow (existing bypass)
#   - non-task branch (push mode) → allow without evidence
#   - non-Bash tool → allow
#
# Run: bash scripts/verification-evidence-gate-selftest.sh   (DEBUG=1 verbose)
# Exit 0 if all assertions pass.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/verification-evidence-gate.sh"
WORK_DIR="$(mktemp -d -t polaris-veg-selftest-XXXXXX)"
: "${DEBUG:=0}"

PASS=0
FAIL=0

assert_eq() {
  local got="$1" want="$2" label="$3"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1))
    [[ "$DEBUG" == "1" ]] && printf "  [ok] %s (got=%s)\n" "$label" "$got"
  else
    FAIL=$((FAIL + 1))
    printf "  [FAIL] %s — want=%s got=%s\n" "$label" "$want" "$got"
  fi
}

cleanup() {
  rm -rf "$WORK_DIR" 2>/dev/null || true
  rm -f /tmp/polaris-verified-VEG*.json 2>/dev/null || true
  rm -f /tmp/polaris-verified-VEG*-*.json 2>/dev/null || true
}
trap cleanup EXIT

# Build a fake repo so the gate can resolve HEAD
make_fake_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir"
  git -C "$repo_dir" init -q -b main
  git -C "$repo_dir" -c user.email=t@t.t -c user.name=t commit --allow-empty -q -m init
  # Create a task branch so the push filter exercises
  git -C "$repo_dir" checkout -q -b "task/VEG-1-selftest"
  # Create .claude/scripts/ci-local.sh sentinel for push mode (DP-043 path)
  mkdir -p "$repo_dir/.claude/scripts"
  echo '#!/bin/sh' > "$repo_dir/.claude/scripts/ci-local.sh"
  chmod +x "$repo_dir/.claude/scripts/ci-local.sh"
}

# Build PreToolUse JSON input for `gh pr create`
make_pr_create_input() {
  printf '{"tool_name":"Bash","tool_input":{"command":"gh pr create --base main"}}'
}

# Build PreToolUse JSON input for `git push`
make_git_push_input() {
  local repo_dir="$1"
  printf '{"tool_name":"Bash","tool_input":{"command":"git -C %s push origin HEAD"}}' "$repo_dir"
}

# ────────────────────────────────────────────────────────────────────────────
echo "=== non-Bash tool → allow ==="
echo '{"tool_name":"Edit","tool_input":{}}' | "$GATE" >/dev/null 2>&1
assert_eq "$?" "0" "non-Bash tool → allow"

# ────────────────────────────────────────────────────────────────────────────
echo "=== POLARIS_SKIP_EVIDENCE=1 bypass ==="
REPO_S="$WORK_DIR/repo-skip"
make_fake_repo "$REPO_S"
INPUT="$(make_git_push_input "$REPO_S")"
echo "$INPUT" | env POLARIS_SKIP_EVIDENCE=1 "$GATE" >/dev/null 2>&1
assert_eq "$?" "0" "POLARIS_SKIP_EVIDENCE=1 → allow"

# ────────────────────────────────────────────────────────────────────────────
echo "=== non-task branch in push mode → allow ==="
REPO_BRANCH="$WORK_DIR/repo-feat-branch"
make_fake_repo "$REPO_BRANCH"
git -C "$REPO_BRANCH" checkout -q -b feat/cwv-bundle
INPUT="$(make_git_push_input "$REPO_BRANCH")"
echo "$INPUT" | "$GATE" >/dev/null 2>&1
assert_eq "$?" "0" "feat/* push branch → allow without evidence"

# ────────────────────────────────────────────────────────────────────────────
echo "=== new format (head_sha-bound) — happy path ==="
REPO_NEW="$WORK_DIR/repo-new"
make_fake_repo "$REPO_NEW"
HEAD_NEW="$(git -C "$REPO_NEW" rev-parse HEAD)"
EV_NEW="/tmp/polaris-verified-VEG-1-${HEAD_NEW}.json"
cat > "$EV_NEW" <<EOF
{
  "ticket": "VEG-1",
  "head_sha": "${HEAD_NEW}",
  "command": "echo PASS",
  "exit_code": 0,
  "stdout_hash": "abc",
  "writer": "run-verify-command.sh",
  "at": "2026-04-26T12:00:00Z",
  "level": "static",
  "results": [],
  "runtime_contract": {"level": "static"}
}
EOF
INPUT="$(make_git_push_input "$REPO_NEW")"
ERR_OUT="$WORK_DIR/err.txt"
echo "$INPUT" | "$GATE" >/dev/null 2>&1
assert_eq "$?" "0" "new format + writer=run-verify-command.sh + exit 0 → allow"

# ────────────────────────────────────────────────────────────────────────────
echo "=== durable mirror fallback — happy path ==="
EV_MIRROR="${REPO_NEW}/.polaris/evidence/verify/polaris-verified-VEG-1-${HEAD_NEW}.json"
mkdir -p "$(dirname "$EV_MIRROR")"
cp "$EV_NEW" "$EV_MIRROR"
rm -f "$EV_NEW"
echo "$INPUT" | "$GATE" >/dev/null 2>&1
assert_eq "$?" "0" "durable mirror fallback allows when /tmp evidence is absent"
cp "$EV_MIRROR" "$EV_NEW"

# ────────────────────────────────────────────────────────────────────────────
echo "=== new format with writer = polaris-write-evidence.sh → block ==="
cat > "$EV_NEW" <<EOF
{
  "ticket": "VEG-1",
  "head_sha": "${HEAD_NEW}",
  "command": "echo PASS",
  "exit_code": 0,
  "stdout_hash": "abc",
  "writer": "polaris-write-evidence.sh",
  "at": "2026-04-26T12:00:00Z",
  "level": "static"
}
EOF
echo "$INPUT" | "$GATE" >/dev/null 2>"$ERR_OUT"
RC=$?
assert_eq "$RC" "2" "new format + writer=polaris-write-evidence.sh → block"

# ────────────────────────────────────────────────────────────────────────────
echo "=== new format with writer not in whitelist → block ==="
cat > "$EV_NEW" <<EOF
{
  "ticket": "VEG-1",
  "head_sha": "${HEAD_NEW}",
  "command": "echo X",
  "exit_code": 0,
  "stdout_hash": "abc",
  "writer": "evil-writer.sh",
  "at": "2026-04-26T12:00:00Z",
  "level": "static"
}
EOF
echo "$INPUT" | "$GATE" >/dev/null 2>"$ERR_OUT"
RC=$?
assert_eq "$RC" "2" "new format + bad writer → block exit 2"
if grep -q "writer not in whitelist" "$ERR_OUT" 2>/dev/null; then
  PASS=$((PASS + 1))
  [[ "$DEBUG" == "1" ]] && printf "  [ok] writer error message present\n"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] writer error message missing\n    err: %s\n" "$(cat "$ERR_OUT")"
fi

# ────────────────────────────────────────────────────────────────────────────
echo "=== new format with invalid JSON → block ==="
echo "this is not json {" > "$EV_NEW"
echo "$INPUT" | "$GATE" >/dev/null 2>"$ERR_OUT"
RC=$?
assert_eq "$RC" "2" "new format + invalid JSON → block"

# ────────────────────────────────────────────────────────────────────────────
echo "=== new format missing required field (exit_code) → block ==="
cat > "$EV_NEW" <<EOF
{
  "ticket": "VEG-1",
  "head_sha": "${HEAD_NEW}",
  "writer": "run-verify-command.sh",
  "at": "2026-04-26T12:00:00Z",
  "level": "static"
}
EOF
echo "$INPUT" | "$GATE" >/dev/null 2>"$ERR_OUT"
RC=$?
assert_eq "$RC" "2" "new format missing exit_code → block"
if grep -q "missing exit_code" "$ERR_OUT" 2>/dev/null; then
  PASS=$((PASS + 1))
  [[ "$DEBUG" == "1" ]] && printf "  [ok] missing field error message present\n"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] missing field error message wrong\n    err: %s\n" "$(cat "$ERR_OUT")"
fi

# ────────────────────────────────────────────────────────────────────────────
echo "=== new format with exit_code != 0 → block ==="
cat > "$EV_NEW" <<EOF
{
  "ticket": "VEG-1",
  "head_sha": "${HEAD_NEW}",
  "command": "echo FAIL",
  "exit_code": 1,
  "writer": "run-verify-command.sh",
  "at": "2026-04-26T12:00:00Z",
  "level": "static"
}
EOF
echo "$INPUT" | "$GATE" >/dev/null 2>"$ERR_OUT"
RC=$?
assert_eq "$RC" "2" "new format exit_code=1 → block"
if grep -q "verify command FAIL" "$ERR_OUT" 2>/dev/null; then
  PASS=$((PASS + 1))
  [[ "$DEBUG" == "1" ]] && printf "  [ok] exit_code FAIL message present\n"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] exit_code FAIL message wrong\n    err: %s\n" "$(cat "$ERR_OUT")"
fi

# ────────────────────────────────────────────────────────────────────────────
echo "=== new format passes without 4h stale check ==="
# Write evidence with `at` from 1 year ago — should still pass since head_sha
# binds freshness (rebase invalidates filename).
cat > "$EV_NEW" <<EOF
{
  "ticket": "VEG-1",
  "head_sha": "${HEAD_NEW}",
  "command": "echo PASS",
  "exit_code": 0,
  "stdout_hash": "abc",
  "writer": "run-verify-command.sh",
  "at": "2025-01-01T00:00:00Z",
  "level": "static"
}
EOF
echo "$INPUT" | "$GATE" >/dev/null 2>&1
assert_eq "$?" "0" "new format ignores 4h stale check (head_sha self-binds)"

rm -f "$EV_NEW"

# ────────────────────────────────────────────────────────────────────────────
echo "=== old ticket-only evidence file is ignored → block ==="
REPO_LEGACY="$WORK_DIR/repo-legacy"
make_fake_repo "$REPO_LEGACY"
HEAD_LEGACY="$(git -C "$REPO_LEGACY" rev-parse HEAD)"
INPUT_LEGACY="$(make_git_push_input "$REPO_LEGACY")"

EV_LEGACY="/tmp/polaris-verified-VEG-1.json"
cat > "$EV_LEGACY" <<EOF
{
  "ticket": "VEG-1",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "branch": "task/VEG-1-selftest",
  "summary": {"total": 1, "pass": 1, "fail": 0, "skip": 0},
  "results": [{"status": "PASS", "detail": "PASS: legacy"}],
  "runtime_contract": {"level": "static", "runtime_verify_target": "", "runtime_verify_target_host": "", "verify_command": "echo PASS", "verify_command_url": "", "verify_command_url_host": ""}
}
EOF
rm -f "/tmp/polaris-verified-VEG-1-${HEAD_LEGACY}.json"
echo "$INPUT_LEGACY" | "$GATE" >/dev/null 2>"$ERR_OUT"
RC=$?
assert_eq "$RC" "2" "old ticket-only evidence without head_sha filename → block"
if grep -q "No verification evidence" "$ERR_OUT" 2>/dev/null; then
  PASS=$((PASS + 1))
  [[ "$DEBUG" == "1" ]] && printf "  [ok] old-evidence ignored message present\n"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] old-evidence ignored message wrong\n    err: %s\n" "$(cat "$ERR_OUT")"
fi

# ────────────────────────────────────────────────────────────────────────────
echo "=== no evidence file at all → block ==="
rm -f "$EV_LEGACY"
rm -f "/tmp/polaris-verified-VEG-1-${HEAD_LEGACY}.json"
echo "$INPUT_LEGACY" | "$GATE" >/dev/null 2>"$ERR_OUT"
RC=$?
assert_eq "$RC" "2" "no evidence at all → block"
if grep -q "No verification evidence" "$ERR_OUT" 2>/dev/null; then
  PASS=$((PASS + 1))
  [[ "$DEBUG" == "1" ]] && printf "  [ok] no-evidence message present\n"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] no-evidence message wrong\n    err: %s\n" "$(cat "$ERR_OUT")"
fi

# ────────────────────────────────────────────────────────────────────────────
echo "=== new format allows even when old ticket-only evidence also exists ==="
HEAD_PR="$HEAD_NEW"
EV_NEW2="/tmp/polaris-verified-VEG-1-${HEAD_PR}.json"
EV_LEG2="/tmp/polaris-verified-VEG-1.json"
# Valid new format (must reference REPO_NEW's HEAD)
cat > "$EV_NEW2" <<EOF
{
  "ticket": "VEG-1",
  "head_sha": "${HEAD_PR}",
  "command": "echo PASS",
  "exit_code": 0,
  "writer": "run-verify-command.sh",
  "at": "2026-04-26T12:00:00Z",
  "level": "static"
}
EOF
cat > "$EV_LEG2" <<EOF
{
  "ticket": "VEG-1",
  "timestamp": "2025-01-01T00:00:00Z",
  "results": [],
  "runtime_contract": {"level": "static"}
}
EOF
INPUT_NEW="$(make_git_push_input "$REPO_NEW")"
echo "$INPUT_NEW" | "$GATE" >/dev/null 2>&1
assert_eq "$?" "0" "head_sha evidence is the only accepted format"

# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Summary ==="
TOTAL=$((PASS + FAIL))
echo "PASS=$PASS  FAIL=$FAIL  TOTAL=$TOTAL"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
echo "All assertions passed."
exit 0
