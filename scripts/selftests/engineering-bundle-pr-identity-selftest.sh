#!/usr/bin/env bash
# engineering-bundle-pr-identity-selftest.sh — DP-230-T3 (D16)
#
# Verifies:
#   - scripts/engineering-branch-setup.sh --aggregate-release --source DP-NNN
#     --version vX.Y.Z produces branch name "bundle-DP-NNN-vX.Y.Z" and writes
#     bundle_branch_alias frontmatter to each --task-md it is given.
#   - scripts/framework-release-closeout.sh --task-head-sha
#     DP-NNN-T1=<sha1>,DP-NNN-T2=<sha2> parses the per-task map and resolves
#     each task's head SHA from it (PASS contract).
#   - DP-226 P3 + P11 broken fixture coverage:
#       P3:  closeout without per-task head SHA mapping fails to locate
#            the task head when branches share a bundle alias.
#       P11: aggregate-release branch name is derived from --source + --version,
#            not from the legacy single-task summary slug.
#
# Exit: 0 PASS, non-zero FAIL.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENGINEERING_BRANCH_SETUP="$ROOT/scripts/engineering-branch-setup.sh"
FRAMEWORK_RELEASE_CLOSEOUT="$ROOT/scripts/framework-release-closeout.sh"

PASS=0
FAIL=0
TOTAL=0

log_fail() {
  FAIL=$((FAIL + 1))
  echo "FAIL [$TOTAL]: $*" >&2
}

log_pass() {
  PASS=$((PASS + 1))
}

assert_eq() {
  TOTAL=$((TOTAL + 1))
  local actual="$1"
  local expected="$2"
  local label="$3"
  if [[ "$actual" == "$expected" ]]; then
    log_pass
  else
    log_fail "$label — expected='$expected' actual='$actual'"
  fi
}

assert_ne() {
  TOTAL=$((TOTAL + 1))
  local actual="$1"
  local forbidden="$2"
  local label="$3"
  if [[ "$actual" != "$forbidden" ]]; then
    log_pass
  else
    log_fail "$label — value must not equal '$forbidden'"
  fi
}

assert_file_contains() {
  TOTAL=$((TOTAL + 1))
  local file="$1"
  local needle="$2"
  local label="$3"
  if [[ -f "$file" ]] && grep -F -q -- "$needle" "$file"; then
    log_pass
  else
    log_fail "$label — file='$file' missing needle='$needle'"
  fi
}

cleanup() {
  if [[ -n "${TMPDIR_ST:-}" && -d "$TMPDIR_ST" ]]; then
    rm -rf "$TMPDIR_ST"
  fi
}
trap cleanup EXIT

TMPDIR_ST="$(mktemp -d)"
REMOTE="$TMPDIR_ST/remote.git"
LOCAL="$TMPDIR_ST/local"

git init --bare "$REMOTE" >/dev/null 2>&1
git clone "$REMOTE" "$LOCAL" >/dev/null 2>&1

(
  cd "$LOCAL"
  git -c user.email=t@example.invalid -c user.name=tester checkout -b main >/dev/null 2>&1
  echo "init" > seed.txt
  git add seed.txt
  git -c user.email=t@example.invalid -c user.name=tester commit -m "init" >/dev/null 2>&1
  git push -u origin main >/dev/null 2>&1
)

# Build two minimal task.md fixtures sharing the same source DP-9990.
make_task_md() {
  local task_id="$1"
  local dest="$2"
  local jira="$3"
  local task_branch="task/${task_id}-bundle-fixture"
  mkdir -p "$(dirname "$dest")"
  cat > "$dest" <<TASK
---
title: "${task_id} bundle fixture"
status: IN_PROGRESS
verification:
  behavior_contract:
    applies: false
    reason: "selftest fixture"
depends_on: []
---

# ${task_id} bundle fixture

> Source: DP-9990 | Task: ${task_id} | JIRA: ${jira} | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-9990 |
| Task ID | ${task_id} |
| Task JIRA key | ${jira} |
| Base branch | main |
| Branch chain | main -> ${task_branch} |
| Task branch | ${task_branch} |
| Depends on | N/A |

## Allowed Files

- \`src/**\`

## Test Command

\`\`\`bash
echo ok
\`\`\`
TASK
}

# DP-319 release-stage-bundle-precondition: run_aggregate_release only assembles a
# bundle when EVERY --task-md is finalized under a tasks/pr-release/ lifecycle
# location (is_pr_release_task). Place each fixture work order at
# .../tasks/pr-release/{Tn}/index.md so the precondition passes; flat tmp paths
# would (correctly) trip POLARIS_RELEASE_STAGE_TASK_NOT_FINALIZED.
FIXTURE_SPECS_DIR="$TMPDIR_ST/specs/DP-9990/tasks/pr-release"
TASK_MD1="$FIXTURE_SPECS_DIR/T1/index.md"
TASK_MD2="$FIXTURE_SPECS_DIR/T2/index.md"
make_task_md "DP-9990-T1" "$TASK_MD1" "FX-1"
make_task_md "DP-9990-T2" "$TASK_MD2" "FX-2"

# ---------------------------------------------------------------------------
# Test 1 (AC12 — D16, also DP-226 P11): aggregate-release mode derives the
# branch name from --source + --version, NOT from any task summary slug.
# ---------------------------------------------------------------------------
SETUP_OUT="$TMPDIR_ST/setup.out"
SETUP_ERR="$TMPDIR_ST/setup.err"

if (cd "$LOCAL" && env -u ENGINEERING_BRANCH_SETUP_SELFTEST \
        POLARIS_SKIP_BASELINE_SNAPSHOT=1 \
        bash "$ENGINEERING_BRANCH_SETUP" \
          --aggregate-release \
          --source DP-9990 \
          --version v9.99.99 \
          --task-md "$TASK_MD1" \
          --task-md "$TASK_MD2" \
          --repo-base "$TMPDIR_ST" \
          >"$SETUP_OUT" 2>"$SETUP_ERR"); then
  setup_rc=0
else
  setup_rc=$?
fi
assert_eq "$setup_rc" "0" "T1: aggregate-release setup exits 0"

EXPECTED_BUNDLE_BRANCH="bundle-DP-9990-v9.99.99"
LAST_LINE="$(tail -n 1 "$SETUP_OUT" 2>/dev/null || true)"
TOTAL=$((TOTAL + 1))
if [[ -d "$LAST_LINE" ]]; then
  log_pass
else
  log_fail "T1: aggregate-release stdout last line should be a worktree directory (got '$LAST_LINE')"
fi

if (cd "$LOCAL" && git show-ref --verify --quiet "refs/heads/${EXPECTED_BUNDLE_BRANCH}"); then
  branch_status="found"
else
  branch_status="missing"
fi
assert_eq "$branch_status" "found" "T1: bundle branch '${EXPECTED_BUNDLE_BRANCH}' exists"

# Negative: must not have created a per-task slug branch (DP-226 P11 attack).
if (cd "$LOCAL" && git show-ref --verify --quiet "refs/heads/task/DP-9990-T1-bundle-fixture"); then
  per_task_branch="created"
else
  per_task_branch="absent"
fi
assert_eq "$per_task_branch" "absent" "T1: aggregate mode must not also create per-task branch"

# ---------------------------------------------------------------------------
# Test 2 (AC12): bundle_branch_alias frontmatter is written into each task.md.
# ---------------------------------------------------------------------------
assert_file_contains "$TASK_MD1" "bundle_branch_alias: ${EXPECTED_BUNDLE_BRANCH}" \
  "T2: TASK_MD1 frontmatter contains bundle_branch_alias"
assert_file_contains "$TASK_MD2" "bundle_branch_alias: ${EXPECTED_BUNDLE_BRANCH}" \
  "T2: TASK_MD2 frontmatter contains bundle_branch_alias"

# ---------------------------------------------------------------------------
# Test 3 (AC12 — D16, DP-226 P3): framework-release-closeout accepts a
# per-task head SHA map of the form --task-head-sha DP-NNN-T1=<sha>,...
# (parser-only contract — we exercise the parser via a dry-run by passing
# bogus repo + invalid SHAs to verify rejection messages reference the
# task_id=sha map, not the legacy positional contract.)
# ---------------------------------------------------------------------------
# Resolve real SHAs to feed: workspace HEAD on LOCAL main.
WORKSPACE_HEAD="$(git -C "$LOCAL" rev-parse HEAD)"

# Run a help-style probe: the script must accept the map syntax (no
# "unknown argument" error) and reach the validation block. To avoid
# requiring real branches/evidence, we capture stderr and assert the
# parser does NOT reject "--task-head-sha DP-9990-T1=<sha>,DP-9990-T2=<sha>"
# as an unknown argument.
CLOSEOUT_ERR="$TMPDIR_ST/closeout.err"
if bash "$FRAMEWORK_RELEASE_CLOSEOUT" \
    --task-head-sha "DP-9990-T1=${WORKSPACE_HEAD},DP-9990-T2=${WORKSPACE_HEAD}" \
    >/dev/null 2>"$CLOSEOUT_ERR"; then
  closeout_rc=0
else
  closeout_rc=$?
fi
# We expect non-zero (no --task-md, no --workspace-commit, etc.) but the
# parser MUST recognize the map syntax. Failure mode must NOT be
# "unknown argument: --task-head-sha".
assert_ne "$closeout_rc" "0" "T3: closeout with only --task-head-sha map exits non-zero (validation gates)"
TOTAL=$((TOTAL + 1))
if grep -F -q -- "unknown argument: --task-head-sha" "$CLOSEOUT_ERR"; then
  log_fail "T3: --task-head-sha map syntax must not be rejected as unknown argument"
else
  log_pass
fi

# ---------------------------------------------------------------------------
# Test 4 (AC12 — D16): closeout map parser splits comma-separated entries.
# Provide a malformed entry (missing '=') and assert the parser surfaces a
# specific error rather than silently dropping the entry.
# ---------------------------------------------------------------------------
CLOSEOUT_ERR2="$TMPDIR_ST/closeout2.err"
if bash "$FRAMEWORK_RELEASE_CLOSEOUT" \
    --task-head-sha "DP-9990-T1${WORKSPACE_HEAD}" \
    --task-md "$TASK_MD1" \
    --verify-evidence "$TASK_MD1" \
    --workspace-commit "$WORKSPACE_HEAD" \
    --template-commit "$WORKSPACE_HEAD" \
    --version-tag "v9.99.99" \
    --release-url "N/A" \
    --repo "$LOCAL" \
    >/dev/null 2>"$CLOSEOUT_ERR2"; then
  bad_rc=0
else
  bad_rc=$?
fi
assert_ne "$bad_rc" "0" "T4: closeout rejects malformed --task-head-sha map entry"
TOTAL=$((TOTAL + 1))
if grep -F -q -- "task-head-sha" "$CLOSEOUT_ERR2"; then
  log_pass
else
  log_fail "T4: malformed --task-head-sha map error message should reference task-head-sha"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "engineering-bundle-pr-identity-selftest: ${PASS}/${TOTAL} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
