#!/usr/bin/env bash
# Ensure skills and references consume Polaris runtime tools through capability ids.

set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
failures=0

scan_patterns() {
  local root="$1"
  shift
  local pattern
  for pattern in "$@"; do
    if rg -n --glob '*.md' --glob 'SKILL.md' "$pattern" "$root"; then
      failures=$((failures + 1))
    fi
  done
}

echo "Checking skill/reference runtime tool invocations..."
scan_patterns "$WORKSPACE_ROOT/.claude/skills" \
  'npx playwright' \
  'pnpm --dir docs-manager' \
  'scripts/polaris-viewer\.sh' \
  'scripts/verify-docs-manager-runtime\.sh' \
  'mockoon-runner\.sh'

echo "Checking script runtime tool invocations..."
if rg -n \
  --glob '!**/node_modules/**' \
  --glob '!scripts/polaris-toolchain.sh' \
  --glob '!scripts/validate-polaris-toolchain-consumers.sh' \
  --glob '!scripts/mockoon/mockoon-runner.sh' \
  --glob '!scripts/e2e/e2e-verify.sh' \
  --glob '!scripts/verify-docs-manager-runtime.sh' \
  'npx --prefix .*playwright|npm install --prefix .*scripts/(e2e|mockoon)|scripts/(e2e|mockoon)/node_modules' \
  "$WORKSPACE_ROOT/scripts" "$WORKSPACE_ROOT/.claude/skills"; then
  failures=$((failures + 1))
fi

if [[ "$failures" -gt 0 ]]; then
  cat >&2 <<'EOF'
FAIL: direct runtime tool invocation found.

Use:
  scripts/polaris-toolchain.sh run docs.viewer.<command>
  scripts/polaris-toolchain.sh run fixtures.mockoon.<command>
  scripts/polaris-toolchain.sh run browser.playwright.<command>

Compatibility wrappers are allowed only in scripts/e2e, scripts/mockoon, and docs-manager runtime scripts.
EOF
  exit 1
fi

echo "PASS: Polaris toolchain consumers"
