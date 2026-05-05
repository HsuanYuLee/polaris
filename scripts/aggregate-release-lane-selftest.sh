#!/usr/bin/env bash
# Fixture coverage for framework aggregate release PR base gate.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/gates/gate-base-check.sh"
TMP_DIR="$(mktemp -d -t polaris-aggregate-release-lane-XXXXXX)"
PASS=0
FAIL=0

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

assert_pass() {
  local label="$1"
  shift
  if "$@" >/tmp/polaris-aggregate-release-lane.out 2>&1; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf '[FAIL] %s expected pass\n' "$label" >&2
    cat /tmp/polaris-aggregate-release-lane.out >&2
  fi
}

assert_fail() {
  local label="$1"
  shift
  if "$@" >/tmp/polaris-aggregate-release-lane.out 2>&1; then
    FAIL=$((FAIL + 1))
    printf '[FAIL] %s expected fail\n' "$label" >&2
    cat /tmp/polaris-aggregate-release-lane.out >&2
  else
    PASS=$((PASS + 1))
  fi
}

REPO="$TMP_DIR/repo"
TASK_MD="$TMP_DIR/specs/DP-105/tasks/T1.md"

git init -q -b main "$REPO"
git -C "$REPO" config user.email "selftest@example.com"
git -C "$REPO" config user.name "selftest"
printf 'init\n' >"$REPO/file.txt"
git -C "$REPO" add file.txt
git -C "$REPO" commit -q -m init
git -C "$REPO" checkout -q -b task/DP-105-T0-upstream
printf 'upstream\n' >>"$REPO/file.txt"
git -C "$REPO" commit -q -am upstream
git -C "$REPO" checkout -q -b task/DP-105-T1-aggregate-release-lane-hotfix
printf 'task\n' >>"$REPO/file.txt"
git -C "$REPO" commit -q -am task

mkdir -p "$REPO/scripts" "$(dirname "$TASK_MD")"
cat >"$REPO/scripts/resolve-task-md-by-branch.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$TASK_MD"
EOF
cat >"$REPO/scripts/resolve-task-base.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "task/DP-105-T0-upstream"
EOF
cat >"$REPO/scripts/resolve-branch-chain.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "main"
printf '%s\n' "task/DP-105-T0-upstream"
printf '%s\n' "task/DP-105-T1-aggregate-release-lane-hotfix"
EOF
chmod +x "$REPO"/scripts/*.sh

cat >"$TASK_MD" <<'EOF'
---
status: READY
---

# T1: aggregate release lane selftest

## Operational Context

| 欄位 | 值 |
|------|-----|
| Base branch | task/DP-105-T0-upstream |
| Branch chain | main -> task/DP-105-T0-upstream -> task/DP-105-T1-aggregate-release-lane-hotfix |
| Task branch | task/DP-105-T1-aggregate-release-lane-hotfix |
EOF

pushd "$REPO" >/dev/null
assert_fail "base-main-without-opt-in" bash "$GATE" --repo "$REPO" --base main
assert_pass "base-main-with-aggregate-opt-in" bash "$GATE" --repo "$REPO" --base main --aggregate-release
assert_fail "aggregate-base-not-main" bash "$GATE" --repo "$REPO" --base develop --aggregate-release
assert_pass "normal-expected-base" bash "$GATE" --repo "$REPO" --base task/DP-105-T0-upstream
popd >/dev/null

TOTAL=$((PASS + FAIL))
printf 'aggregate-release-lane selftest: %d/%d PASS\n' "$PASS" "$TOTAL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
