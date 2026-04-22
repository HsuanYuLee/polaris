#!/usr/bin/env bash
# pre-commit-quality.sh — Run lint, typecheck, test and write quality evidence
#
# Usage: ./pre-commit-quality.sh --repo <path>
#
# Leverages detect-project-and-changes.sh for project detection.
# On all-pass: writes /tmp/polaris-quality-{branch}.json
# On fail: prints failures, exits non-zero
#
# Quality evidence is checked by quality-gate.sh (PreToolUse hook on git commit).
#
# Env:
#   POLARIS_SKIP_QUALITY=1  — skip all checks, write bypass evidence
#
# Exit 0 = all checks passed, Exit 1 = checks failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_DIR="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$REPO_DIR" ]]; then
  echo "Usage: pre-commit-quality.sh --repo <path>" >&2
  exit 1
fi

# Resolve to absolute path
REPO_DIR="$(cd "$REPO_DIR" && pwd)"

# Get branch name for evidence file
branch=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
evidence_file="/tmp/polaris-quality-${branch}.json"

# ── Bypass ──────────────────────────────────────────────────────────

if [[ "${POLARIS_SKIP_QUALITY:-}" == "1" ]]; then
  echo "⏭️  POLARIS_SKIP_QUALITY=1 — skipping quality checks" >&2
  python3 -c "
import json, datetime
evidence = {
    'branch': '${branch}',
    'repo': '${REPO_DIR}',
    'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'bypassed': True,
    'results': {'lint': 'SKIP', 'typecheck': 'SKIP', 'test': 'SKIP'},
    'advisory': {}
}
with open('${evidence_file}', 'w') as f:
    json.dump(evidence, f, indent=2)
print('Evidence written to ${evidence_file}')
" >&2
  exit 0
fi

# ── Step 1: Detect project ──────────────────────────────────────────

echo "━━━ Pre-Commit Quality Check ━━━" >&2
echo "Repo: $REPO_DIR" >&2
echo "Branch: $branch" >&2
echo "" >&2

detect_json=$("$SCRIPT_DIR/detect-project-and-changes.sh" --project-dir "$REPO_DIR" 2>/dev/null || echo "{}")

if [[ -z "$detect_json" || "$detect_json" == "{}" ]]; then
  echo "⚠️  Could not detect project type. Skipping quality checks." >&2
  exit 0
fi

project=$(printf '%s' "$detect_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('project','unknown'))" 2>/dev/null || echo "unknown")
test_framework=$(printf '%s' "$detect_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('test_framework','none'))" 2>/dev/null || echo "none")
lint_command=$(printf '%s' "$detect_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('lint_command',''))" 2>/dev/null || echo "")
test_command=$(printf '%s' "$detect_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('test_command',''))" 2>/dev/null || echo "")
missing_count=$(printf '%s' "$detect_json" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('missing_tests',[])))" 2>/dev/null || echo "0")
missing_tests=$(printf '%s' "$detect_json" | python3 -c "import sys,json; print('\n'.join(json.load(sys.stdin).get('missing_tests',[])))" 2>/dev/null || echo "")

echo "Project: $project ($test_framework)" >&2
echo "" >&2

# ── Step 2: Detect package manager ──────────────────────────────────

pkg_manager="npx"
if [[ -f "$REPO_DIR/pnpm-lock.yaml" ]]; then
  pkg_manager="pnpm"
elif [[ -f "$REPO_DIR/yarn.lock" ]]; then
  pkg_manager="yarn"
fi

# ── Step 3: Detect typecheck command ────────────────────────────────

typecheck_command=""
if [[ -f "$REPO_DIR/package.json" ]]; then
  typecheck_command=$(python3 -c "
import json
with open('${REPO_DIR}/package.json') as f:
    scripts = json.load(f).get('scripts', {})
for key in ['typecheck', 'type-check', 'check:types']:
    if key in scripts:
        print(key)
        break
" 2>/dev/null || echo "")
fi

# ── Step 4: Run quality checks ──────────────────────────────────────

failed=false
results_lint="SKIP"
results_typecheck="SKIP"
results_test="SKIP"
results_ci_contract="SKIP"
failure_details=""

# 4a. Lint
if [[ -n "$lint_command" ]]; then
  echo "🔍 [1/3] Lint..." >&2
  lint_output=""
  if lint_output=$(cd "$REPO_DIR" && $lint_command --no-fix 2>&1); then
    results_lint="PASS"
    echo "  ✅ lint passed" >&2
  else
    results_lint="FAIL"
    failed=true
    failure_details="${failure_details}--- LINT FAILURE ---\n$(echo "$lint_output" | tail -30)\n\n"
    echo "  ❌ lint failed" >&2
  fi
else
  echo "⏭️  [1/3] Lint — no lint command detected, skipping" >&2
fi

# 4b. Typecheck
if [[ -n "$typecheck_command" ]]; then
  echo "🔍 [2/3] Typecheck..." >&2
  tc_output=""
  if tc_output=$(cd "$REPO_DIR" && $pkg_manager run "$typecheck_command" 2>&1); then
    results_typecheck="PASS"
    echo "  ✅ typecheck passed" >&2
  else
    results_typecheck="FAIL"
    failed=true
    failure_details="${failure_details}--- TYPECHECK FAILURE ---\n$(echo "$tc_output" | tail -30)\n\n"
    echo "  ❌ typecheck failed" >&2
  fi
else
  echo "⏭️  [2/3] Typecheck — no typecheck script detected, skipping" >&2
fi

# 4c. Test
if [[ -n "$test_command" && "$test_framework" != "none" ]]; then
  echo "🔍 [3/3] Test..." >&2

  # Get test files to run (affected only)
  test_files_to_run=$(printf '%s' "$detect_json" | python3 -c "
import sys, json
files = json.load(sys.stdin).get('test_files_to_run', [])
print(' '.join(files))
" 2>/dev/null || echo "")

  test_output=""
  if [[ -n "$test_files_to_run" ]]; then
    # Run only affected test files
    if test_output=$(cd "$REPO_DIR" && $test_command $test_files_to_run 2>&1); then
      results_test="PASS"
      echo "  ✅ test passed" >&2
    else
      results_test="FAIL"
      failed=true
      failure_details="${failure_details}--- TEST FAILURE ---\n$(echo "$test_output" | tail -40)\n\n"
      echo "  ❌ test failed" >&2
    fi
  else
    echo "  ⏭️  No affected test files to run" >&2
    results_test="SKIP"
  fi
else
  echo "⏭️  [3/3] Test — no test framework detected, skipping" >&2
fi

# 4d. CI contract parity (repo-specific dynamic gate)
if [[ "${POLARIS_SKIP_CI_CONTRACT:-}" == "1" ]]; then
  echo "⏭️  [4/4] CI contract parity — POLARIS_SKIP_CI_CONTRACT=1, skipping" >&2
  results_ci_contract="SKIP"
else
  echo "🔍 [4/4] CI contract parity..." >&2
  ci_output=""
  if ci_output=$("$SCRIPT_DIR/ci-contract-run.sh" --repo "$REPO_DIR" --skip-install --write-coverage-evidence 2>&1); then
    results_ci_contract="PASS"
    echo "  ✅ ci contract parity passed" >&2
  else
    results_ci_contract="FAIL"
    failed=true
    failure_details="${failure_details}--- CI CONTRACT FAILURE ---\n$(echo "$ci_output" | tail -60)\n\n"
    echo "  ❌ ci contract parity failed" >&2
  fi
fi

# ── Step 5: Coverage advisory (non-blocking) ────────────────────────

advisory=""
if [[ "$missing_count" -gt 0 && -n "$missing_tests" ]]; then
  advisory="$missing_tests"
  echo "" >&2
  echo "⚠️  Coverage advisory — $missing_count source files have no test counterpart:" >&2
  while IFS= read -r f; do
    echo "    - $f" >&2
  done <<< "$missing_tests"
  echo "   (Advisory only — not blocking)" >&2
fi

# ── Step 6: Write evidence ──────────────────────────────────────────

echo "" >&2

python3 -c "
import json, datetime

evidence = {
    'branch': '${branch}',
    'repo': '${REPO_DIR}',
    'project': '${project}',
    'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'bypassed': False,
    'results': {
        'lint': '${results_lint}',
        'typecheck': '${results_typecheck}',
        'test': '${results_test}',
        'ci_contract': '${results_ci_contract}'
    },
    'all_passed': '${results_lint}' != 'FAIL' and '${results_typecheck}' != 'FAIL' and '${results_test}' != 'FAIL' and '${results_ci_contract}' != 'FAIL',
    'advisory': {
        'missing_test_count': ${missing_count},
        'missing_tests': $(printf '%s' "$detect_json" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin).get('missing_tests',[])))" 2>/dev/null || echo "[]")
    }
}
with open('${evidence_file}', 'w') as f:
    json.dump(evidence, f, indent=2)
"

# ── Step 7: Report ──────────────────────────────────────────────────

if $failed; then
  echo "━━━ FAILED ━━━" >&2
  echo "" >&2
  printf "%b" "$failure_details" >&2
  echo "Quality evidence written (with failures): $evidence_file" >&2
  echo "Fix the issues and re-run." >&2
  exit 1
else
  echo "━━━ ALL PASSED ━━━" >&2
  echo "  lint: $results_lint | typecheck: $results_typecheck | test: $results_test | ci_contract: $results_ci_contract" >&2
  echo "  Quality evidence: $evidence_file" >&2
  exit 0
fi
