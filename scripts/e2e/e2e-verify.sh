#!/usr/bin/env bash
# e2e-verify.sh — Polaris framework E2E page verification
#
# Usage:
#   scripts/e2e/e2e-verify.sh                                     # Verify homepage
#   scripts/e2e/e2e-verify.sh "/zh-tw/product/12345"               # Verify specific URL
#   scripts/e2e/e2e-verify.sh "/zh-tw/product/12345,/zh-tw"        # Multiple URLs
#   E2E_PAGES='[{"url":"/zh-tw","type":"home"}]' scripts/e2e/e2e-verify.sh
#
# Env vars:
#   E2E_BASE_URL  — override base URL (default: https://dev.kkday.com)
#   E2E_URLS      — comma-separated paths
#   E2E_PAGES     — JSON array of {url, type} targets
#
# Exit codes:
#   0 = all checks passed
#   1 = one or more checks failed
#   2 = pre-flight failed (dev server not running)
#   3 = dependency install failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TOOLCHAIN_DIR="$WORKSPACE_ROOT/tools/polaris-toolchain"
BASE_URL="${E2E_BASE_URL:-https://dev.kkday.com}"

# --- Pre-flight: check Mockoon (optional) ---
MOCKOON_STATUS="unknown"
MOCKOON_PORTS="${E2E_MOCKOON_PORTS:-4001}"  # default: check member-ci proxy port
for port in $(echo "$MOCKOON_PORTS" | tr ',' ' '); do
  if curl -s --max-time 2 -o /dev/null "http://localhost:$port" 2>/dev/null; then
    MOCKOON_STATUS="running"
    break
  fi
done

if [[ "$MOCKOON_STATUS" == "running" ]]; then
  echo "Pre-flight: Mockoon proxy detected (stable fixtures) ✅"
else
  echo "Pre-flight: Mockoon not running — using live backend (results may vary)"
fi

# --- Pre-flight: check dev server ---
echo "Pre-flight: checking $BASE_URL ..."
if ! curl -sk --max-time 5 -o /dev/null -w "%{http_code}" "$BASE_URL/zh-tw" 2>/dev/null | grep -q "^[23]"; then
  echo "ERROR: $BASE_URL is not reachable." >&2
  echo "" >&2
  echo "Make sure:" >&2
  echo "  1. Docker (kkday-web-docker) is running" >&2
  echo "  2. Nuxt dev server is running (pnpm dev:main)" >&2
  echo "  3. /etc/hosts has: 127.0.0.1 dev.kkday.com" >&2
  exit 2
fi
echo "Pre-flight: OK"

# --- Ensure dependencies installed ---
if [[ ! -x "$TOOLCHAIN_DIR/node_modules/.bin/playwright" ]]; then
  echo "Installing E2E dependencies via Polaris toolchain..."
  pnpm --dir "$TOOLCHAIN_DIR" install --silent 2>&1 || { echo "ERROR: pnpm install failed" >&2; exit 3; }
fi

# --- Ensure Chromium browser installed ---
if ! pnpm --dir "$TOOLCHAIN_DIR" exec playwright install chromium 2>/dev/null; then
  echo "Installing Playwright Chromium..." >&2
  pnpm --dir "$TOOLCHAIN_DIR" exec playwright install chromium 2>&1
fi

# --- Set URLs from args if provided ---
if [[ -n "${1:-}" && -z "${E2E_PAGES:-}" && -z "${E2E_URLS:-}" ]]; then
  export E2E_URLS="$1"
fi

# --- Clean previous results ---
rm -rf "$SCRIPT_DIR/e2e-results"
rm -f "$SCRIPT_DIR/e2e-results.json"

# --- Run Playwright ---
echo ""
echo "Running E2E verification..."
echo ""

bash "$WORKSPACE_ROOT/scripts/polaris-toolchain.sh" run browser.playwright.verify -- test --config "$SCRIPT_DIR/playwright.config.ts" 2>&1
exit_code=$?

# --- Summary ---
if [[ -f "$SCRIPT_DIR/e2e-results.json" ]]; then
  echo ""
  echo "=== E2E Results ==="
  python3 -c "
import json, sys
with open('$SCRIPT_DIR/e2e-results.json') as f:
    data = json.load(f)
suites = data.get('suites', [])
for suite in suites:
    for spec in suite.get('specs', []):
        title = spec.get('title', '')
        ok = spec.get('ok', False)
        status = '✅' if ok else '❌'
        print(f'  {status} {title}')
passed = sum(1 for s in suites for sp in s.get('specs', []) if sp.get('ok'))
total = sum(1 for s in suites for sp in s.get('specs', []))
print(f'\n  Total: {passed}/{total} passed')
" 2>/dev/null || true
fi

exit $exit_code
