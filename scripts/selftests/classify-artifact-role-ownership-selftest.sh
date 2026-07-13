#!/usr/bin/env bash
# Purpose: Selftest for scripts/classify-artifact-role-ownership.sh (DP-417 T1).
# Inputs:  none (self-contained fixtures under a temp dir).
# Outputs: per-case PASS/FAIL lines; exit 0 when every case passes, else exit 1.
# Fixtures cover AC1 (role classification), AC-NEG1 (mixed diff fail-closed with a
# POLARIS_* marker pointing at the framework owner path), and a no-false-positive
# case (a product repo's own scripts/ dir must NOT classify as framework-owned).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLASSIFY="$SCRIPT_DIR/classify-artifact-role-ownership.sh"

PASS=0
FAIL=0

ok() { echo "PASS $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL $1" >&2; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d -t artifact-role-ownership.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Hermetic owned-path fixture mirroring the shape of
# scripts/lib/framework-source-owned-paths.json (canonical framework-owned glob set).
owned="$TMP/owned.json"
cat >"$owned" <<'EOF'
{
  "schema_version": 1,
  "owned_path_globs": [
    ".claude/skills/**",
    ".claude/rules/**",
    ".claude/hooks/**",
    "scripts/**",
    "CLAUDE.md",
    "AGENTS.md"
  ]
}
EOF

run_args() {
  POLARIS_FRAMEWORK_OWNED_PATHS_JSON="$owned" \
    bash "$CLASSIFY" "$@" >"$TMP/out.txt" 2>"$TMP/err.txt" </dev/null
}

# Case 1 (AC1): product-only diff -> PASS + artifact-role=product.
run_args "exampleco/exampleco-web/apps/main/pages/product/index.vue" \
  "exampleco/exampleco-web/apps/main/store/cart.ts"
rc=$?
if [[ "$rc" -eq 0 ]] && grep -q 'artifact-role=product' "$TMP/out.txt"; then
  ok "product-only diff classifies as product"
else
  bad "product-only diff should PASS as product (rc=$rc)"
fi

# Case 2 (AC1): framework-only diff -> PASS + artifact-role=framework.
run_args "scripts/auto-pass-runner.sh" ".claude/skills/engineering/SKILL.md"
rc=$?
if [[ "$rc" -eq 0 ]] && grep -q 'artifact-role=framework' "$TMP/out.txt"; then
  ok "framework-only diff classifies as framework"
else
  bad "framework-only diff should PASS as framework (rc=$rc)"
fi

# Case 3 (AC-NEG1): mixed diff (product PR + framework flow repair) -> fail-closed
# with POLARIS_* marker on stderr naming the framework owner path.
run_args "exampleco/exampleco-web/apps/main/store/cart.ts" "scripts/auto-pass-runner.sh"
rc=$?
if [[ "$rc" -eq 2 ]] \
  && grep -q 'POLARIS_MIXED_ARTIFACT_ROLE_DIFF' "$TMP/err.txt" \
  && grep -q 'scripts/auto-pass-runner.sh' "$TMP/err.txt"; then
  ok "mixed diff fails closed with marker + framework owner path"
else
  bad "mixed diff should exit 2 with POLARIS_MIXED_ARTIFACT_ROLE_DIFF (rc=$rc)"
fi

# Case 4 (AC-NEG): no false positive — a product repo's OWN scripts/ dir is
# product-owned (only the repo-root scripts/ tree is framework-owned).
run_args "exampleco/exampleco-web/scripts/build.mjs" \
  "exampleco/exampleco-web/apps/main/index.ts"
rc=$?
if [[ "$rc" -eq 0 ]] && grep -q 'artifact-role=product' "$TMP/out.txt"; then
  ok "product repo scripts/ dir does not classify as framework-owned"
else
  bad "product repo scripts/ dir should stay product (rc=$rc)"
fi

# Case 5: stdin path input mode is honoured (parity with CLI args).
printf '%s\n' "scripts/check-framework-pr-gate.sh" "CLAUDE.md" \
  | POLARIS_FRAMEWORK_OWNED_PATHS_JSON="$owned" bash "$CLASSIFY" \
    >"$TMP/out.txt" 2>"$TMP/err.txt"
rc=$?
if [[ "$rc" -eq 0 ]] && grep -q 'artifact-role=framework' "$TMP/out.txt"; then
  ok "stdin path input classifies as framework"
else
  bad "stdin path input should PASS as framework (rc=$rc)"
fi

echo "----"
echo "classify-artifact-role-ownership selftest: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
