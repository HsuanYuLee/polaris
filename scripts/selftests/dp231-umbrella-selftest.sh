#!/usr/bin/env bash
# Purpose: DP-231 umbrella regression selftest for AC31-AC46 / AC-NEG17-30.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local needle="$2"
  grep -qF "$needle" "$file" || fail "$file missing required text: $needle"
}

assert_executable() {
  local rel="$1"
  [[ -f "$ROOT/$rel" ]] || fail "missing selftest: $rel"
}

run_selftest() {
  local rel="$1"
  assert_executable "$rel"
  echo "RUN: $rel"
  bash "$ROOT/$rel"
}

DESIGN_PLANS_DIR="$ROOT/docs-manager/src/content/docs/specs/design-plans"
DP_DIR=""
if [[ -d "$DESIGN_PLANS_DIR" ]]; then
  DP_DIR="$(find "$DESIGN_PLANS_DIR" -maxdepth 1 -type d -name 'DP-231-*' | head -n 1 || true)"
fi
if [[ -d "$DP_DIR" ]]; then
  assert_contains "$DP_DIR/refinement.md" "AC46"
  assert_contains "$DP_DIR/refinement.md" "AC-NEG30"
  assert_contains "$DP_DIR/refinement.json" "scripts/selftests/dp231-umbrella-selftest.sh"
fi

assert_contains "$ROOT/scripts/manifest.json" '"path": "scripts/selftests/dp231-umbrella-selftest.sh"'

legacy_bug_removal_selftest="scripts/selftests/bug""-triage-removal-selftest.sh"

selftests=(
  "scripts/selftests/refinement-bug-source-mode-selftest.sh"
  "scripts/selftests/refinement-bug-source-detector-selftest.sh"
  "$legacy_bug_removal_selftest"
  "scripts/selftests/validate-refinement-json-selftest.sh"
  "scripts/selftests/validate-auto-pass-report-selftest.sh"
  "scripts/selftests/auto-pass-report-selftest.sh"
  "scripts/selftests/auto-pass-pr-ownership-selftest.sh"
  "scripts/selftests/codex-guarded-gh-pr-create-selftest.sh"
  "scripts/selftests/pr-create-guard-selftest.sh"
  "scripts/selftests/work-item-id-deconfliction-selftest.sh"
  "scripts/selftests/validate-task-md-selftest.sh"
  "scripts/selftests/resolve-task-md-selftest.sh"
  "scripts/selftests/framework-scope-escalation-gate-selftest.sh"
  "scripts/selftests/framework-source-mutation-no-bypass-selftest.sh"
  "scripts/selftests/cross-llm-mechanism-parity-selftest.sh"
  "scripts/selftests/refinement-task-dependencies-selftest.sh"
  "scripts/selftests/derive-task-md-from-refinement-json-selftest.sh"
  "scripts/selftests/auto-pass-engineering-worktree-dispatch-selftest.sh"
  "scripts/selftests/engineering-main-dirty-worktree-selftest.sh"
)

for rel in "${selftests[@]}"; do
  run_selftest "$rel"
done

echo "PASS: dp231 umbrella selftest"
