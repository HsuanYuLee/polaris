#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

run() {
  local label="$1"
  shift
  printf '[dp230-umbrella] %s\n' "$label"
  "$@"
}

run "D14 friction capture contract" \
  bash scripts/selftests/friction-capture-contract-selftest.sh
run "D15 task schema validator parity" \
  bash scripts/selftests/validate-task-md-shape-parity-selftest.sh
run "D16 bundle PR identity" \
  bash scripts/selftests/engineering-bundle-pr-identity-selftest.sh
run "D17 external write language preflight" \
  bash scripts/selftests/external-write-language-preflight-selftest.sh
run "D18 framework artifact writer CWD resolver" \
  bash scripts/selftests/framework-artifact-writer-cwd-selftest.sh
run "D19 selftest portability" \
  bash scripts/selftests/selftest-portability-selftest.sh
run "D20 manifest parity" \
  bash scripts/selftests/validate-manifest-parity-selftest.sh
run "D21 leak-scan workspace exception" \
  bash scripts/selftests/scan-template-leaks-workspace-exception-selftest.sh
run "D22 completion gate dispatcher" \
  bash scripts/selftests/check-local-extension-completion-dispatch-selftest.sh
run "D23 worktree classifier" \
  bash scripts/selftests/worktree-classifier-selftest.sh
run "D28 deterministic breakdown consumption" \
  bash scripts/selftests/derive-task-md-from-refinement-json-selftest.sh
run "D30 verify-AC deterministic consumption" \
  bash scripts/selftests/verify-AC-deterministic-consumption-selftest.sh
run "D31 verify-AC evidence producer" \
  bash scripts/selftests/verify-AC-evidence-layout-producer-selftest.sh
run "D32 auto-pass report producer" \
  bash scripts/selftests/auto-pass-report-producer-selftest.sh
run "D33 task worktree resolver" \
  bash scripts/selftests/resolve-task-worktree-selftest.sh
run "D34 selftest direct-call governance" \
  bash scripts/selftests/closeout-chain-archive-selftest.sh
run "D35 bare DP closeout" \
  bash scripts/selftests/mark-spec-implemented-bare-key-selftest.sh
run "D36 workspace config fixture" \
  bash scripts/selftests/workspace-config-fixture-selftest.sh
run "D37 aggregate release PR identity" \
  bash scripts/selftests/polaris-pr-create-aggregate-release-selftest.sh
run "D38 Python subprocess scanner" \
  bash scripts/selftests/python-subprocess-tool-call-scanner-selftest.sh
run "D39 runtime response language guard" \
  bash scripts/selftests/runtime-final-response-language-guard-selftest.sh
run "D40 skill workflow boundary gate" \
  bash scripts/selftests/skill-workflow-boundary-gate-selftest.sh
run "D40 refinement handoff integration" \
  bash scripts/selftests/refinement-handoff-gate-selftest.sh
run "script manifest parity" \
  bash scripts/check-script-manifest.sh --root "$ROOT_DIR" --quiet

echo "PASS: DP-230-V1 umbrella regression"
