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

OUT1="$T1/scripts/ci-local.sh"
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
OUT2="$T2/scripts/ci-local.sh"
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
OUT3="$T3/scripts/ci-local.sh"
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
OUT4="$T4/scripts/ci-local.sh"
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
OUT5="$T5/scripts/ci-local.sh"
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
OUT6="$T6/scripts/ci-local.sh"
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
echo
echo "== Summary =="
echo "  Assertions: $ASSERTIONS"
echo "  Pass:       $PASS"
echo "  Fail:       $FAIL"
[ $FAIL -eq 0 ]
