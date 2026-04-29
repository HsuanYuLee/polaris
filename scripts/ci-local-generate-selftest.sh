#!/usr/bin/env bash
# ci-local-generate-selftest.sh — Self-test harness for ci-local-generate.sh.
#
# Builds throw-away fixture repos (Woodpecker / GitHub Actions / GitLab CI / husky+pre-commit
# / NO_CHECKS) under a tmp dir, runs the generator against each, and asserts
# the produced ci-local.sh contains the expected commands and skips the right ones.
#
# Behavioral execution of the generated scripts is NOT covered here — that requires
# real toolchains (pnpm, vitest, etc.). This harness validates GENERATION only.
#
# Usage: scripts/ci-local-generate-selftest.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GEN="$SCRIPT_DIR/ci-local-generate.sh"
TMPROOT="$(mktemp -d -t ci-local-selftest-XXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0
ASSERTIONS=0

assert() {
  local desc="$1" cond="$2"
  ASSERTIONS=$((ASSERTIONS+1))
  if [ "$cond" = "1" ]; then
    PASS=$((PASS+1))
    printf "  ✓ %s\n" "$desc"
  else
    FAIL=$((FAIL+1))
    printf "  ✗ %s\n" "$desc" >&2
  fi
}

assert_contains() {
  local desc="$1" file="$2" needle="$3"
  if grep -qF -- "$needle" "$file"; then assert "$desc" 1; else assert "$desc" 0; fi
}

assert_not_contains() {
  local desc="$1" file="$2" needle="$3"
  if grep -qF -- "$needle" "$file"; then assert "$desc" 0; else assert "$desc" 1; fi
}

init_git_repo() {
  local d="$1"
  (
    cd "$d"
    git init -q
    git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init >/dev/null 2>&1
  )
}

# ============================================================================
echo "== Test 1: Woodpecker (folder mode) + husky + codecov =="
# ============================================================================
T1="$TMPROOT/woodpecker-repo"
mkdir -p "$T1/.woodpecker" "$T1/.husky"
cat > "$T1/.woodpecker/lint.yml" <<'YAML'
pipeline:
  format-check:
    image: node:22
    commands:
      - corepack enable
      - pnpm install --frozen-lockfile
      - pnpm prettier --check "**/*.ts"
    when:
      event: pull_request
YAML
cat > "$T1/.woodpecker/test.yml" <<'YAML'
pipeline:
  test-and-coverage:
    image: node:22
    commands:
      - pnpm install
      - pnpm vitest run --coverage
      - curl -Os https://uploader.codecov.io/latest/alpine/codecov
      - chmod +x codecov
      - ./codecov -t $CODECOV_TOKEN -f coverage/lcov.info -F unit
    secrets:
      - source: codecov_token
        target: CODECOV_TOKEN
    when:
      event: pull_request
YAML
cat > "$T1/.woodpecker/release.yml" <<'YAML'
pipeline:
  release:
    image: node:22
    commands:
      - apk add --no-cache git
      - PR_NUMBER=$(echo $CI_COMMIT_REF | sed -n 's#refs/pull/\([0-9]*\)/head#\1#p')
      - gh auth login --with-token < /dev/stdin
      - gh pr comment $PR_NUMBER --body "released"
    secrets: [github_token]
    when:
      event: tag
YAML
cat > "$T1/codecov.yml" <<'YAML'
flag_management:
  individual_flags:
    - name: unit
      paths: [src/]
      statuses:
        - type: patch
          target: 60%
YAML
cat > "$T1/.husky/pre-commit" <<'SHELL'
#!/bin/sh
. "$(dirname -- "$0")/_/husky.sh"

pnpm exec lint-staged
echo "pre-commit done"
SHELL
chmod +x "$T1/.husky/pre-commit"
init_git_repo "$T1"

OUT1="$T1/.claude/scripts/ci-local.sh"
"$GEN" --repo "$T1" --out "$OUT1" --force >/dev/null 2>&1
T1_RC=$?
assert "Test 1: generator exit 0" "$([ $T1_RC -eq 0 ] && echo 1 || echo 0)"
[ -f "$OUT1" ]
assert "Test 1: ci-local.sh produced" "$([ -f "$OUT1" ] && echo 1 || echo 0)"
bash -n "$OUT1" 2>/dev/null
assert "Test 1: bash syntax valid" "$([ $? -eq 0 ] && echo 1 || echo 0)"
assert_contains "Test 1: includes pnpm install --frozen-lockfile" "$OUT1" "pnpm install --frozen-lockfile"
assert_contains "Test 1: includes prettier --check" "$OUT1" 'pnpm prettier --check "**/*.ts"'
assert_contains "Test 1: includes vitest --coverage" "$OUT1" "pnpm vitest run --coverage"
assert_contains "Test 1: includes lint-staged dev hook" "$OUT1" "pnpm exec lint-staged"
assert_not_contains "Test 1: skips codecov upload" "$OUT1" "uploader.codecov.io"
assert_not_contains "Test 1: skips ./codecov -t" "$OUT1" "./codecov -t"
assert_not_contains "Test 1: skips apk add" "$OUT1" "apk add --no-cache git"
assert_not_contains "Test 1: skips gh auth login" "$OUT1" "gh auth login"
assert_not_contains "Test 1: skips gh pr comment" "$OUT1" "gh pr comment"
assert_not_contains "Test 1: skips CI env-dep PR_NUMBER" "$OUT1" "CI_COMMIT_REF"
assert_contains "Test 1: codecov post-check section emitted" "$OUT1" "Codecov patch coverage compute"
assert_contains "Test 1: empty-coverage net retained" "$OUT1" "no_coverage_data_with_changed_files"
assert_contains "Test 1: command env defaults to UTC" "$OUT1" 'COMMAND_TZ="${CI_LOCAL_TZ:-${TZ:-UTC}}"'
assert_contains "Test 1: command runner exports TZ" "$OUT1" 'TZ="$COMMAND_TZ" bash -lc'
assert_contains "Test 1: install before lint (ordering)" "$OUT1" "Check 1:"
# Verify the install command is the first run_check
FIRST_RUN_LINE="$(grep -n 'run_check ' "$OUT1" | head -1)"
case "$FIRST_RUN_LINE" in
  *"'install'"*) assert "Test 1: first run_check is install" 1 ;;
  *) assert "Test 1: first run_check is install (got: $FIRST_RUN_LINE)" 0 ;;
esac

# ============================================================================
echo "== Test 2: GitHub Actions =="
# ============================================================================
T2="$TMPROOT/gha-repo"
mkdir -p "$T2/.github/workflows"
cat > "$T2/.github/workflows/ci.yml" <<'YAML'
name: CI
on: [pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 22 }
      - run: pnpm install --frozen-lockfile
      - run: pnpm lint
      - run: pnpm test:unit
      - run: pnpm exec tsc --noEmit
YAML
cat > "$T2/.github/workflows/release.yml" <<'YAML'
name: Release
on:
  push:
    tags: ['v*']
jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - run: gh release create $GITHUB_REF
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
YAML
init_git_repo "$T2"
OUT2="$T2/.claude/scripts/ci-local.sh"
"$GEN" --repo "$T2" --out "$OUT2" --force >/dev/null 2>&1
assert "Test 2: generator exit 0" "$([ $? -eq 0 ] && echo 1 || echo 0)"
bash -n "$OUT2" 2>/dev/null
assert "Test 2: bash syntax valid" "$([ $? -eq 0 ] && echo 1 || echo 0)"
assert_contains "Test 2: GitHub Actions provider detected" "$OUT2" "CI provider: github_actions"
assert_contains "Test 2: includes pnpm install" "$OUT2" "pnpm install --frozen-lockfile"
assert_contains "Test 2: includes pnpm lint" "$OUT2" "pnpm lint"
assert_contains "Test 2: includes pnpm test:unit" "$OUT2" "pnpm test:unit"
assert_contains "Test 2: includes tsc typecheck" "$OUT2" "pnpm exec tsc --noEmit"
assert_not_contains "Test 2: skips uses: actions/checkout" "$OUT2" "actions/checkout"

# ============================================================================
echo "== Test 3: GitLab CI =="
# ============================================================================
T3="$TMPROOT/gitlab-repo"
mkdir -p "$T3"
cat > "$T3/.gitlab-ci.yml" <<'YAML'
stages: [test]
variables:
  NODE_VERSION: "22"
test_unit:
  stage: test
  image: node:22
  only: [merge_requests]
  script:
    - corepack enable
    - pnpm install --frozen-lockfile
    - pnpm vitest run
    - pnpm lint
deploy:
  stage: test
  only: [tags]
  script:
    - echo "deploying"
    - curl -X POST $DEPLOY_URL
YAML
init_git_repo "$T3"
OUT3="$T3/.claude/scripts/ci-local.sh"
"$GEN" --repo "$T3" --out "$OUT3" --force >/dev/null 2>&1
assert "Test 3: generator exit 0" "$([ $? -eq 0 ] && echo 1 || echo 0)"
bash -n "$OUT3" 2>/dev/null
assert "Test 3: bash syntax valid" "$([ $? -eq 0 ] && echo 1 || echo 0)"
assert_contains "Test 3: GitLab CI provider detected" "$OUT3" "CI provider: gitlab_ci"
assert_contains "Test 3: includes pnpm install" "$OUT3" "pnpm install --frozen-lockfile"
assert_contains "Test 3: includes pnpm vitest run" "$OUT3" "pnpm vitest run"
assert_contains "Test 3: includes pnpm lint" "$OUT3" "pnpm lint"

# ============================================================================
echo "== Test 4: pre-commit-config.yaml =="
# ============================================================================
T4="$TMPROOT/precommit-repo"
mkdir -p "$T4"
cat > "$T4/.pre-commit-config.yaml" <<'YAML'
repos:
  # Community hook (no entry) — must delegate to `pre-commit run`
  - repo: https://github.com/koalaman/shellcheck-precommit
    rev: v0.11.0
    hooks:
      - id: shellcheck
        args: ["--severity=error"]
  # Entry hook with default pass_filenames (true) — needs file expansion, delegate
  - repo: https://github.com/psf/black
    rev: 24.0.0
    hooks:
      - id: black
        entry: black
        stages: [pre-commit]
  # Local hook with entry + pass_filenames: false — runnable as-is
  - repo: local
    hooks:
      - id: readme-lint
        name: readme-lint
        entry: python3 scripts/readme-lint.py
        language: system
        pass_filenames: false
        stages: [pre-commit]
YAML
init_git_repo "$T4"
OUT4="$T4/.claude/scripts/ci-local.sh"
"$GEN" --repo "$T4" --out "$OUT4" --force >/dev/null 2>&1
assert "Test 4: generator exit 0" "$([ $? -eq 0 ] && echo 1 || echo 0)"
bash -n "$OUT4" 2>/dev/null
assert "Test 4: bash syntax valid" "$([ $? -eq 0 ] && echo 1 || echo 0)"
# Community hook (no entry) → delegated
assert_contains "Test 4: delegates shellcheck (no entry) to pre-commit run" "$OUT4" "pre-commit run shellcheck --all-files"
# Entry hook with default pass_filenames=true → still delegated (entry alone can't expand files)
assert_contains "Test 4: delegates black (pass_filenames default) to pre-commit run" "$OUT4" "pre-commit run black --all-files"
# Local hook with explicit pass_filenames: false → uses entry directly
assert_contains "Test 4: uses readme-lint entry directly" "$OUT4" "python3 scripts/readme-lint.py"
assert_not_contains "Test 4: readme-lint not delegated to pre-commit run" "$OUT4" "pre-commit run readme-lint"
# Hook id alone must never appear as a heredoc body line (regression guard
# against the pre-fix bug where `id: shellcheck` became a bare command line).
if grep -qFx "shellcheck" "$OUT4"; then assert "Test 4: shellcheck not emitted as bare command line" 0; else assert "Test 4: shellcheck not emitted as bare command line" 1; fi
if grep -qFx "ruff-check" "$OUT4"; then assert "Test 4: ruff-check id not emitted as bare command line" 0; else assert "Test 4: ruff-check id not emitted as bare command line" 1; fi

# ============================================================================
echo "== Test 5: NO_CHECKS_CONFIGURED (empty repo) =="
# ============================================================================
T5="$TMPROOT/empty-repo"
mkdir -p "$T5"
init_git_repo "$T5"
OUT5="$T5/.claude/scripts/ci-local.sh"
"$GEN" --repo "$T5" --out "$OUT5" --force >/dev/null 2>&1
assert "Test 5: generator exit 0 even on empty repo" "$([ $? -eq 0 ] && echo 1 || echo 0)"
bash -n "$OUT5" 2>/dev/null
assert "Test 5: bash syntax valid" "$([ $? -eq 0 ] && echo 1 || echo 0)"
assert_contains "Test 5: NO_CHECKS_CONFIGURED branch present" "$OUT5" "NO_CHECKS_CONFIGURED"
assert_not_contains "Test 5: no run_check function emitted" "$OUT5" "run_check()"
# Run the actual script — should produce evidence + exit 0
EVIDENCE_BEFORE="$(ls /tmp/polaris-ci-local-* 2>/dev/null | wc -l)"
(
  cd "$T5"
  bash "$OUT5" >/dev/null 2>&1
)
T5_EXIT=$?
assert "Test 5: generated NO_CHECKS script exits 0" "$([ $T5_EXIT -eq 0 ] && echo 1 || echo 0)"
EVIDENCE_AFTER="$(ls /tmp/polaris-ci-local-* 2>/dev/null | wc -l)"
[ "$EVIDENCE_AFTER" -gt "$EVIDENCE_BEFORE" ]
assert "Test 5: evidence file written" "$([ "$EVIDENCE_AFTER" -gt "$EVIDENCE_BEFORE" ] && echo 1 || echo 0)"
# Find the evidence and verify schema
LATEST_EVIDENCE="$(ls -t /tmp/polaris-ci-local-* 2>/dev/null | head -1)"
if [ -f "$LATEST_EVIDENCE" ]; then
  STATUS="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('status',''))" "$LATEST_EVIDENCE")"
  WRITER="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('writer',''))" "$LATEST_EVIDENCE")"
  REASON="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('reason',''))" "$LATEST_EVIDENCE")"
  [ "$STATUS" = "PASS" ]; assert "Test 5: evidence status=PASS" "$([ "$STATUS" = "PASS" ] && echo 1 || echo 0)"
  [ "$WRITER" = "ci-local.sh" ]; assert "Test 5: evidence writer=ci-local.sh" "$([ "$WRITER" = "ci-local.sh" ] && echo 1 || echo 0)"
  [ "$REASON" = "NO_CHECKS_CONFIGURED" ]; assert "Test 5: evidence reason=NO_CHECKS_CONFIGURED" "$([ "$REASON" = "NO_CHECKS_CONFIGURED" ] && echo 1 || echo 0)"
  # Cache hit on second run
  (cd "$T5"; bash "$OUT5" 2>&1) > /tmp/ci-local-second-run.out
  grep -q "cache hit" /tmp/ci-local-second-run.out
  assert "Test 5: second run hits cache" "$([ $? -eq 0 ] && echo 1 || echo 0)"
  rm -f "$LATEST_EVIDENCE" /tmp/ci-local-second-run.out
fi

# ============================================================================
echo "== Test 6: --force / no-force / --dry-run flags =="
# ============================================================================
T6="$TMPROOT/flags-repo"
mkdir -p "$T6"
init_git_repo "$T6"
OUT6="$T6/.claude/scripts/ci-local.sh"
"$GEN" --repo "$T6" --out "$OUT6" >/dev/null 2>&1
assert "Test 6: first run (no flag) creates file" "$([ -f "$OUT6" ] && echo 1 || echo 0)"
"$GEN" --repo "$T6" --out "$OUT6" >/dev/null 2>&1
assert "Test 6: second run without --force fails" "$([ $? -ne 0 ] && echo 1 || echo 0)"
"$GEN" --repo "$T6" --out "$OUT6" --force >/dev/null 2>&1
assert "Test 6: --force overwrites" "$([ $? -eq 0 ] && echo 1 || echo 0)"
DRY_OUT="$("$GEN" --repo "$T6" --dry-run 2>/dev/null)"
[ -n "$DRY_OUT" ]
assert "Test 6: --dry-run prints non-empty content" "$([ -n "$DRY_OUT" ] && echo 1 || echo 0)"
echo "$DRY_OUT" | head -1 | grep -q "^#!/usr/bin/env bash"
assert "Test 6: --dry-run output starts with shebang" "$([ $? -eq 0 ] && echo 1 || echo 0)"

# ============================================================================
echo "== Test 7: --repo flag (cross-worktree invocation, DP-043 follow-up) =="
# ============================================================================
T7="$TMPROOT/repo-flag-fixture"
mkdir -p "$T7"
init_git_repo "$T7"
OUT7="$T7/.claude/scripts/ci-local.sh"
"$GEN" --repo "$T7" --out "$OUT7" --force >/dev/null 2>&1
assert "Test 7: generator exit 0" "$([ $? -eq 0 ] && echo 1 || echo 0)"
# Generated script must accept --repo flag (NO_CHECKS path is fine — we just
# want to confirm flag parsing works and the script targets the given repo).
T7_HELP_OUT="$(bash "$OUT7" --help 2>&1)"
case "$T7_HELP_OUT" in
  *"--repo"*) assert "Test 7: --help mentions --repo" 1 ;;
  *) assert "Test 7: --help mentions --repo (got: $T7_HELP_OUT)" 0 ;;
esac
# Invoke with --repo from a different cwd; evidence file branch_slug should
# come from $T7's HEAD, not from /tmp.
T7_RUN_OUT="$(cd /tmp && bash "$OUT7" --repo "$T7" 2>&1)"
T7_RUN_RC=$?
assert "Test 7: --repo invocation exit 0" "$([ $T7_RUN_RC -eq 0 ] && echo 1 || echo 0)"
# Locate the most-recent evidence and check its head_sha matches T7's HEAD
T7_HEAD="$(git -C "$T7" rev-parse --short=12 HEAD 2>/dev/null)"
LATEST_EV="$(ls -t /tmp/polaris-ci-local-* 2>/dev/null | head -1)"
if [ -f "$LATEST_EV" ]; then
  EV_SHA="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('head_sha',''))" "$LATEST_EV")"
  if [ "$EV_SHA" = "$T7_HEAD" ]; then
    assert "Test 7: evidence head_sha matches target repo (not cwd)" 1
  else
    assert "Test 7: evidence head_sha matches target repo (expected $T7_HEAD, got $EV_SHA)" 0
  fi
  rm -f "$LATEST_EV"
fi
# Bad --repo path must fail with exit 2
bash "$OUT7" --repo /no/such/path/exists 2>/dev/null
T7_BAD_RC=$?
assert "Test 7: bad --repo exits 2" "$([ $T7_BAD_RC -eq 2 ] && echo 1 || echo 0)"

# ============================================================================
echo "== Test 8: Woodpecker when.branch condition evaluation =="
# ============================================================================
T8="$TMPROOT/woodpecker-branch-conditions"
mkdir -p "$T8/.woodpecker"
cat > "$T8/.woodpecker/lint.yml" <<'YAML'
pipeline:
  lint-and-type-check:
    image: node:22
    commands:
      - echo lint-for-develop
    when:
      event: pull_request
      branch:
        - develop
        - rc
YAML
init_git_repo "$T8"
OUT8="$T8/.claude/scripts/ci-local.sh"
"$GEN" --repo "$T8" --out "$OUT8" --force >/dev/null 2>&1
assert "Test 8: generator exit 0" "$([ $? -eq 0 ] && echo 1 || echo 0)"
bash -n "$OUT8" 2>/dev/null
assert "Test 8: bash syntax valid" "$([ $? -eq 0 ] && echo 1 || echo 0)"
assert_contains "Test 8: generated script includes branch condition" "$OUT8" '"branches":["develop","rc"]'

(cd "$T8" && bash "$OUT8" --repo "$T8" --event pull_request --base-branch feat/topic >/tmp/ci-local-test8-skip.out 2>&1)
T8_SKIP_RC=$?
assert "Test 8: feature-base run exits 0" "$([ $T8_SKIP_RC -eq 0 ] && echo 1 || echo 0)"
assert_contains "Test 8: feature-base output records SKIP" /tmp/ci-local-test8-skip.out "SKIP (branch_not_matched)"
T8_EVIDENCE="$(ls -t /tmp/polaris-ci-local-* 2>/dev/null | head -1)"
python3 - "$T8_EVIDENCE" <<'PY' >/tmp/ci-local-test8-skip-evidence.out
import json, sys
d=json.load(open(sys.argv[1]))
print(d["checks"][0]["status"])
print(d["checks"][0].get("reason"))
print(d["summary"].get("skipped_checks"))
PY
assert_contains "Test 8: evidence status is SKIP" /tmp/ci-local-test8-skip-evidence.out "SKIP"
assert_contains "Test 8: evidence reason is branch_not_matched" /tmp/ci-local-test8-skip-evidence.out "branch_not_matched"

rm -f "$T8_EVIDENCE"
(cd "$T8" && bash "$OUT8" --repo "$T8" --event pull_request --base-branch develop >/tmp/ci-local-test8-run.out 2>&1)
T8_RUN_RC=$?
assert "Test 8: develop-base run exits 0" "$([ $T8_RUN_RC -eq 0 ] && echo 1 || echo 0)"
assert_contains "Test 8: develop-base command executed" /tmp/ci-local-test8-run.out "lint-for-develop"

# ============================================================================
echo "== Test 9: Codecov patch uses explicit stacked PR base =="
# ============================================================================
T9="$TMPROOT/codecov-stacked-base"
mkdir -p "$T9/src" "$T9/coverage"
cat > "$T9/codecov.yml" <<'YAML'
flag_management:
  individual_flags:
    - name: unit
      paths: [src/]
      statuses:
        - type: patch
          target: 60%
YAML
init_git_repo "$T9"
git -C "$T9" branch -M develop
cat > "$T9/src/foo.ts" <<'TS'
export const existing = 1;
TS
git -C "$T9" add .
git -C "$T9" -c user.email=t@t -c user.name=t commit -q -m "develop base"
git -C "$T9" update-ref refs/remotes/origin/develop HEAD
git -C "$T9" checkout -q -b feature/base
cat >> "$T9/src/foo.ts" <<'TS'
export const upstreamCovered1 = 1;
export const upstreamCovered2 = 2;
export const upstreamCovered3 = 3;
export const upstreamCovered4 = 4;
export const upstreamCovered5 = 5;
TS
git -C "$T9" add .
git -C "$T9" -c user.email=t@t -c user.name=t commit -q -m "feature base"
git -C "$T9" update-ref refs/remotes/origin/feature/base HEAD
git -C "$T9" checkout -q -b task/demo
cat >> "$T9/src/foo.ts" <<'TS'
export const taskCovered = 6;
export const taskUncovered1 = 7;
export const taskUncovered2 = 8;
export const taskUncovered3 = 9;
TS
git -C "$T9" add .
git -C "$T9" -c user.email=t@t -c user.name=t commit -q -m "task change"
cat > "$T9/coverage/lcov.info" <<'LCOV'
TN:
SF:src/foo.ts
DA:1,1
DA:2,1
DA:3,1
DA:4,1
DA:5,1
DA:6,1
DA:7,1
DA:8,0
DA:9,0
DA:10,0
end_of_record
LCOV
OUT9="$T9/.claude/scripts/ci-local.sh"
"$GEN" --repo "$T9" --out "$OUT9" --force >/dev/null 2>&1
assert "Test 9: generator exit 0" "$([ $? -eq 0 ] && echo 1 || echo 0)"
bash -n "$OUT9" 2>/dev/null
assert "Test 9: bash syntax valid" "$([ $? -eq 0 ] && echo 1 || echo 0)"

(cd "$T9" && bash "$OUT9" --repo "$T9" --base-branch develop >/tmp/ci-local-test9-develop.out 2>&1)
T9_DEVELOP_RC=$?
assert "Test 9: develop-base run passes" "$([ $T9_DEVELOP_RC -eq 0 ] && echo 1 || echo 0)"

(cd "$T9" && bash "$OUT9" --repo "$T9" --base-branch feature/base >/tmp/ci-local-test9-feature.out 2>&1)
T9_FEATURE_RC=$?
assert "Test 9: feature-base run fails patch coverage" "$([ $T9_FEATURE_RC -ne 0 ] && echo 1 || echo 0)"
T9_EVIDENCE="$(ls -t /tmp/polaris-ci-local-* 2>/dev/null | head -1)"
python3 - "$T9_EVIDENCE" <<'PY' >/tmp/ci-local-test9-evidence.out
import json, sys
d=json.load(open(sys.argv[1]))
g=[x for x in d["codecov_results"] if x.get("status_type")=="patch"][0]
print(d["status"])
print(d["context"]["base_branch"])
print(g["diff_base_ref"])
print(g["coverage_percent"])
PY
assert_contains "Test 9: evidence status FAIL" /tmp/ci-local-test9-evidence.out "FAIL"
assert_contains "Test 9: evidence context records feature base" /tmp/ci-local-test9-evidence.out "feature/base"
assert_contains "Test 9: codecov used origin feature base" /tmp/ci-local-test9-evidence.out "origin/feature/base"
assert_contains "Test 9: feature-base coverage reflects task-only diff" /tmp/ci-local-test9-evidence.out "25.0"
rm -f "$T9_EVIDENCE"

# ============================================================================
echo "== Test 10: Codecov empty-line net allows files with lcov data =="
# ============================================================================
T10="$TMPROOT/codecov-covered-file-no-patch-lines"
mkdir -p "$T10/src" "$T10/coverage"
cat > "$T10/codecov.yml" <<'YAML'
flag_management:
  individual_flags:
    - name: unit
      paths: [src/]
      statuses:
        - type: patch
          target: 60%
YAML
init_git_repo "$T10"
git -C "$T10" branch -M develop
cat > "$T10/src/foo.ts" <<'TS'
export const covered1 = 1;
export const covered2 = 2;
TS
git -C "$T10" add .
git -C "$T10" -c user.email=t@t -c user.name=t commit -q -m "develop base"
git -C "$T10" update-ref refs/remotes/origin/develop HEAD
git -C "$T10" checkout -q -b task/no-instrumented-lines
cat >> "$T10/src/foo.ts" <<'TS'
export const typeOnlyOrUninstrumented = 3;
TS
git -C "$T10" add .
git -C "$T10" -c user.email=t@t -c user.name=t commit -q -m "task change"
cat > "$T10/coverage/lcov.info" <<'LCOV'
TN:
SF:src/foo.ts
DA:1,1
DA:2,1
end_of_record
LCOV
OUT10="$T10/.claude/scripts/ci-local.sh"
"$GEN" --repo "$T10" --out "$OUT10" --force >/dev/null 2>&1
assert "Test 10: generator exit 0" "$([ $? -eq 0 ] && echo 1 || echo 0)"
bash -n "$OUT10" 2>/dev/null
assert "Test 10: bash syntax valid" "$([ $? -eq 0 ] && echo 1 || echo 0)"

(cd "$T10" && bash "$OUT10" --repo "$T10" --base-branch develop >/tmp/ci-local-test10.out 2>&1)
T10_RC=$?
assert "Test 10: run exits 0 when matched file has lcov data" "$([ $T10_RC -eq 0 ] && echo 1 || echo 0)"
T10_EVIDENCE="$(ls -t /tmp/polaris-ci-local-* 2>/dev/null | head -1)"
python3 - "$T10_EVIDENCE" <<'PY' >/tmp/ci-local-test10-evidence.out
import json, sys
d=json.load(open(sys.argv[1]))
g=[x for x in d["codecov_results"] if x.get("status_type")=="patch"][0]
print(d["status"])
print(g["status"])
print(g.get("reason"))
print(",".join(g.get("files_with_coverage_data", [])))
PY
assert_contains "Test 10: evidence status PASS" /tmp/ci-local-test10-evidence.out "PASS"
assert_contains "Test 10: patch gate remains SKIP no instrumented lines" /tmp/ci-local-test10-evidence.out "SKIP"
assert_contains "Test 10: reason remains no_instrumented_patch_lines" /tmp/ci-local-test10-evidence.out "no_instrumented_patch_lines"
assert_contains "Test 10: records files with coverage data" /tmp/ci-local-test10-evidence.out "src/foo.ts"
rm -f "$T10_EVIDENCE" /tmp/ci-local-test10.out /tmp/ci-local-test10-evidence.out

# ============================================================================
echo "== Test 11: Codecov path mismatch with coverage data passes =="
# ============================================================================
T11="$TMPROOT/codecov-path-mismatch"
mkdir -p "$T11/app/src" "$T11/coverage"
cat > "$T11/codecov.yml" <<'YAML'
flag_management:
  individual_flags:
    - name: app
      paths: [app/src/]
      statuses:
        - type: patch
          target: 60%
YAML
init_git_repo "$T11"
git -C "$T11" branch -M develop
cat > "$T11/app/src/foo.ts" <<'TS'
export const covered1 = 1;
TS
git -C "$T11" add .
git -C "$T11" -c user.email=t@t -c user.name=t commit -q -m "develop base"
git -C "$T11" update-ref refs/remotes/origin/develop HEAD
git -C "$T11" checkout -q -b task/path-mismatch
cat >> "$T11/app/src/foo.ts" <<'TS'
export const covered2 = 2;
export const covered3 = 3;
TS
git -C "$T11" add .
git -C "$T11" -c user.email=t@t -c user.name=t commit -q -m "task change"
cat > "$T11/coverage/lcov.info" <<'LCOV'
TN:
SF:src/foo.ts
DA:1,1
DA:2,1
DA:3,1
end_of_record
LCOV
OUT11="$T11/.claude/scripts/ci-local.sh"
"$GEN" --repo "$T11" --out "$OUT11" --force >/dev/null 2>&1
assert "Test 11: generator exit 0" "$([ $? -eq 0 ] && echo 1 || echo 0)"
bash -n "$OUT11" 2>/dev/null
assert "Test 11: bash syntax valid" "$([ $? -eq 0 ] && echo 1 || echo 0)"

(cd "$T11" && bash "$OUT11" --repo "$T11" --base-branch develop >/tmp/ci-local-test11.out 2>&1)
T11_RC=$?
assert "Test 11: run exits zero when coverage data exists" "$([ $T11_RC -eq 0 ] && echo 1 || echo 0)"
T11_EVIDENCE="$(ls -t /tmp/polaris-ci-local-* 2>/dev/null | head -1)"
python3 - "$T11_EVIDENCE" <<'PY' >/tmp/ci-local-test11-evidence.out
import json, sys
d=json.load(open(sys.argv[1]))
g=[x for x in d["codecov_results"] if x.get("status_type")=="patch"][0]
print(d["status"])
print(g["status"])
print(g.get("reason"))
print(g.get("path_mismatch_files", []))
PY
assert_contains "Test 11: evidence status PASS" /tmp/ci-local-test11-evidence.out "PASS"
assert_contains "Test 11: codecov status PASS" /tmp/ci-local-test11-evidence.out "PASS"
assert_contains "Test 11: records changed path" /tmp/ci-local-test11-evidence.out "app/src/foo.ts"
assert_contains "Test 11: records coverage path" /tmp/ci-local-test11-evidence.out "src/foo.ts"
rm -f "$T11_EVIDENCE" /tmp/ci-local-test11.out /tmp/ci-local-test11-evidence.out

# ============================================================================
echo "== Test 11b: Codecov path mismatch without coverage data still fails =="
# ============================================================================
T11B="$TMPROOT/codecov-path-mismatch-empty"
mkdir -p "$T11B/app/src" "$T11B/coverage"
cat > "$T11B/codecov.yml" <<'YAML'
flag_management:
  individual_flags:
    - name: app
      paths: [app/src/]
      statuses:
        - type: patch
          target: 60%
YAML
init_git_repo "$T11B"
git -C "$T11B" branch -M develop
cat > "$T11B/app/src/foo.ts" <<'TS'
export const covered1 = 1;
TS
git -C "$T11B" add .
git -C "$T11B" -c user.email=t@t -c user.name=t commit -q -m "develop base"
git -C "$T11B" update-ref refs/remotes/origin/develop HEAD
git -C "$T11B" checkout -q -b task/path-mismatch-empty
cat >> "$T11B/app/src/foo.ts" <<'TS'
export const covered2 = 2;
TS
git -C "$T11B" add .
git -C "$T11B" -c user.email=t@t -c user.name=t commit -q -m "task change"
cat > "$T11B/coverage/lcov.info" <<'LCOV'
TN:
SF:src/foo.ts
end_of_record
LCOV
OUT11B="$T11B/.claude/scripts/ci-local.sh"
"$GEN" --repo "$T11B" --out "$OUT11B" --force >/dev/null 2>&1
assert "Test 11b: generator exit 0" "$([ $? -eq 0 ] && echo 1 || echo 0)"
bash -n "$OUT11B" 2>/dev/null
assert "Test 11b: bash syntax valid" "$([ $? -eq 0 ] && echo 1 || echo 0)"

set +e
(cd "$T11B" && bash "$OUT11B" --repo "$T11B" --base-branch develop >/tmp/ci-local-test11b.out 2>&1)
T11B_RC=$?
set -e
assert "Test 11b: run exits non-zero without coverage data" "$([ $T11B_RC -ne 0 ] && echo 1 || echo 0)"
T11B_EVIDENCE="$(ls -t /tmp/polaris-ci-local-* 2>/dev/null | head -1)"
python3 - "$T11B_EVIDENCE" <<'PY' >/tmp/ci-local-test11b-evidence.out
import json, sys
d=json.load(open(sys.argv[1]))
g=[x for x in d["codecov_results"] if x.get("status_type")=="patch"][0]
print(d["status"])
print(g["status"])
print(g.get("reason"))
print(g.get("path_mismatch_files", []))
PY
assert_contains "Test 11b: evidence status FAIL" /tmp/ci-local-test11b-evidence.out "FAIL"
assert_contains "Test 11b: codecov reason path mismatch" /tmp/ci-local-test11b-evidence.out "coverage_path_mismatch"
assert_contains "Test 11b: records changed path" /tmp/ci-local-test11b-evidence.out "app/src/foo.ts"
assert_contains "Test 11b: records coverage path" /tmp/ci-local-test11b-evidence.out "src/foo.ts"
rm -f "$T11B_EVIDENCE" /tmp/ci-local-test11b.out /tmp/ci-local-test11b-evidence.out

# ============================================================================
echo "== Test 12: stale generated mirror blocks and regenerated mirror ignores stale cache =="
# ============================================================================
T12="$TMPROOT/stale-mirror-cache"
mkdir -p "$T12/.github/workflows" "$T12/.bin"
cat > "$T12/.bin/pnpm" <<'SH'
#!/usr/bin/env bash
echo "$*"
exit 0
SH
chmod +x "$T12/.bin/pnpm"
cat > "$T12/.github/workflows/ci.yml" <<'YAML'
name: CI
on: [pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: pnpm test:first
YAML
init_git_repo "$T12"
OUT12="$T12/.claude/scripts/ci-local.sh"
"$GEN" --repo "$T12" --out "$OUT12" --force >/dev/null 2>&1
assert "Test 12: generator exit 0" "$([ $? -eq 0 ] && echo 1 || echo 0)"
bash -n "$OUT12" 2>/dev/null
assert "Test 12: bash syntax valid" "$([ $? -eq 0 ] && echo 1 || echo 0)"

(cd "$T12" && PATH="$T12/.bin:$PATH" bash "$OUT12" --repo "$T12" >/tmp/ci-local-test12-first.out 2>&1)
assert "Test 12: first run exits 0" "$([ $? -eq 0 ] && echo 1 || echo 0)"
T12_EVIDENCE="$(ls -t /tmp/polaris-ci-local-* 2>/dev/null | head -1)"
python3 - "$T12_EVIDENCE" <<'PY' >/tmp/ci-local-test12-evidence.out
import json, sys
d=json.load(open(sys.argv[1]))
print(d["status"])
print(bool(d.get("ci_local_mirror_hash")))
PY
assert_contains "Test 12: evidence status PASS" /tmp/ci-local-test12-evidence.out "PASS"
assert_contains "Test 12: evidence has mirror hash" /tmp/ci-local-test12-evidence.out "True"

sleep 1
cat > "$T12/.github/workflows/ci.yml" <<'YAML'
name: CI
on: [pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: pnpm test:second
YAML

set +e
(cd "$T12" && PATH="$T12/.bin:$PATH" bash "$OUT12" --repo "$T12" >/tmp/ci-local-test12-stale.out 2>&1)
T12_RC=$?
set -e
assert "Test 12: stale script exits non-zero" "$([ $T12_RC -ne 0 ] && echo 1 || echo 0)"
assert_contains "Test 12: stale script blocks before cache" /tmp/ci-local-test12-stale.out "CI config changed after ci-local.sh generation"
assert_not_contains "Test 12: stale script does not use cache" /tmp/ci-local-test12-stale.out "cache hit"

"$GEN" --repo "$T12" --out "$OUT12" --force >/dev/null 2>&1
assert_contains "Test 12: regenerated mirror contains new command" "$OUT12" "test:second"
(cd "$T12" && PATH="$T12/.bin:$PATH" bash "$OUT12" --repo "$T12" >/tmp/ci-local-test12-second.out 2>&1)
assert "Test 12: regenerated run exits 0" "$([ $? -eq 0 ] && echo 1 || echo 0)"
assert_not_contains "Test 12: regenerated mirror ignores stale pass cache" /tmp/ci-local-test12-second.out "cache hit"
rm -f "$T12_EVIDENCE" /tmp/ci-local-test12-first.out /tmp/ci-local-test12-stale.out /tmp/ci-local-test12-second.out /tmp/ci-local-test12-evidence.out

# ============================================================================
echo "== Test 13: install DNS failure classified as BLOCKED_ENV =="
# ============================================================================
T13="$TMPROOT/blocked-env-install"
mkdir -p "$T13/.github/workflows" "$T13/.bin"
cat > "$T13/.github/workflows/ci.yml" <<'YAML'
name: CI
on: [pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: pnpm install --frozen-lockfile
      - run: echo SHOULD_NOT_RUN
YAML
cat > "$T13/.bin/pnpm" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "install" ]]; then
  echo "ERR_PNPM_META_FETCH_FAIL getaddrinfo ENOTFOUND nexus3.sit.kkday.com" >&2
  exit 1
fi
echo "unexpected pnpm command: $*" >&2
exit 1
SH
chmod +x "$T13/.bin/pnpm"
init_git_repo "$T13"
OUT13="$T13/.claude/scripts/ci-local.sh"
"$GEN" --repo "$T13" --out "$OUT13" --force >/dev/null 2>&1
assert "Test 13: generator exit 0" "$([ $? -eq 0 ] && echo 1 || echo 0)"
bash -n "$OUT13" 2>/dev/null
assert "Test 13: bash syntax valid" "$([ $? -eq 0 ] && echo 1 || echo 0)"

set +e
(cd "$T13" && PATH="$T13/.bin:$PATH" bash "$OUT13" --repo "$T13" >/tmp/ci-local-test13.out 2>&1)
T13_RC=$?
set -e
assert "Test 13: run exits non-zero" "$([ $T13_RC -ne 0 ] && echo 1 || echo 0)"
assert_contains "Test 13: output includes BLOCKED_ENV" /tmp/ci-local-test13.out "BLOCKED_ENV"
assert_not_contains "Test 13: downstream command not run" /tmp/ci-local-test13.out "SHOULD_NOT_RUN"
T13_EVIDENCE="$(ls -t /tmp/polaris-ci-local-* 2>/dev/null | head -1)"
python3 - "$T13_EVIDENCE" <<'PY' >/tmp/ci-local-test13-evidence.out
import json, sys
d=json.load(open(sys.argv[1]))
print(d["status"])
print(d["summary"]["blocked_env_checks"])
print(d["blocked_env"]["reason"])
print(d["blocked_env"]["host"])
PY
assert_contains "Test 13: evidence status BLOCKED_ENV" /tmp/ci-local-test13-evidence.out "BLOCKED_ENV"
assert_contains "Test 13: evidence has blocked count" /tmp/ci-local-test13-evidence.out "1"
assert_contains "Test 13: evidence reason dns" /tmp/ci-local-test13-evidence.out "dns_resolution_failed"
assert_contains "Test 13: evidence host recorded" /tmp/ci-local-test13-evidence.out "nexus3.sit.kkday.com"
rm -f "$T13_EVIDENCE" /tmp/ci-local-test13.out /tmp/ci-local-test13-evidence.out

# ============================================================================
echo
echo "== Summary =="
echo "  Assertions: $ASSERTIONS"
echo "  Pass:       $PASS"
echo "  Fail:       $FAIL"
[ $FAIL -eq 0 ]
