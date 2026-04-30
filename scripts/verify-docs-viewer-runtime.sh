#!/usr/bin/env bash
# Verify docs-viewer local origin contract across one or more ports.
# Usage:
#   scripts/verify-docs-viewer-runtime.sh --ports 8080,3334 [--style-check]

set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORTS="8080,3334"
STYLE_CHECK=false
PIDS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ports) PORTS="${2:-}"; shift 2 ;;
    --style-check) STYLE_CHECK=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

cd "$WORKSPACE_ROOT"

cleanup() {
  for pid in "${PIDS[@]:-}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
}
trap cleanup EXIT

is_viewer_available() {
  local origin="$1"
  local body
  body="$(curl -fsS --max-time 5 "$origin/docs-viewer/" 2>/dev/null || true)"
  [[ "$body" == *"Polaris Specs"* && "$body" == *"starlight"* ]]
}

wait_for_viewer() {
  local origin="$1"
  local deadline=$((SECONDS + 45))
  while (( SECONDS < deadline )); do
    if is_viewer_available "$origin"; then
      return 0
    fi
    sleep 1
  done
  echo "Timed out waiting for $origin/docs-viewer/" >&2
  return 1
}

ensure_e2e_deps() {
  if [[ ! -d "$WORKSPACE_ROOT/scripts/e2e/node_modules" ]]; then
    npm install --prefix "$WORKSPACE_ROOT/scripts/e2e" --silent
  fi
  if ! npx --prefix "$WORKSPACE_ROOT/scripts/e2e" playwright install chromium >/dev/null 2>&1; then
    npx --prefix "$WORKSPACE_ROOT/scripts/e2e" playwright install chromium
  fi
}

start_or_reuse_viewer() {
  local port="$1"
  local origin="http://127.0.0.1:$port"

  if lsof -i :"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    if is_viewer_available "$origin"; then
      echo "Reusing viewer on $origin/docs-viewer/"
      return 0
    fi
    echo "Port $port is occupied by a non-viewer service." >&2
    return 1
  fi

  echo "Starting viewer on $origin/docs-viewer/"
  bash "$WORKSPACE_ROOT/scripts/polaris-viewer.sh" --port "$port" --no-open >"/tmp/polaris-viewer-$port.log" 2>&1 &
  PIDS+=("$!")
  wait_for_viewer "$origin"
}

run_browser_assertions() {
  local port="$1"
  local origin="http://127.0.0.1:$port"
  local style_flag="$2"

  DOCS_VIEWER_ORIGIN="$origin" DOCS_VIEWER_STYLE_CHECK="$style_flag" \
    node --input-type=module <<'NODE'
import playwright from './scripts/e2e/node_modules/playwright/index.js';

const origin = process.env.DOCS_VIEWER_ORIGIN;
const styleCheck = process.env.DOCS_VIEWER_STYLE_CHECK === 'true';
const home = `${origin}/docs-viewer/`;
const { chromium } = playwright;

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });

async function gotoOk(url) {
  const response = await page.goto(url, { waitUntil: 'networkidle', timeout: 20_000 });
  assert(response && response.status() < 400, `HTTP ${response?.status()} for ${url}`);
  assert(new URL(page.url()).origin === origin, `Origin drift after goto: ${page.url()}`);
}

await gotoOk(home);

await page.goto(home, { waitUntil: 'networkidle', timeout: 20_000 });
const sampleLink = page.locator('a[href*="DP-058"], a[href*="dp-058"]').first();
assert(await sampleLink.count() > 0, 'No DP-058 sample specs link found');
const href = await sampleLink.getAttribute('href');
assert(href, 'DP-058 sample link has no href');
await gotoOk(new URL(href, origin).toString());

await page.goto(home, { waitUntil: 'networkidle', timeout: 20_000 });
const sidebarLink = page.locator('a[href*="/docs-viewer/specs/"]:visible').first();
assert(await sidebarLink.count() > 0, 'No specs sidebar link found');
await sidebarLink.click();
await page.waitForLoadState('networkidle');
assert(new URL(page.url()).origin === origin, `Origin drift after sidebar click: ${page.url()}`);
assert(page.url().includes('/docs-viewer/specs/'), `Sidebar click did not reach specs route: ${page.url()}`);

await page.goto(home, { waitUntil: 'networkidle', timeout: 20_000 });
const paginationLink = page.locator('a[rel="next"]:visible, a[aria-label*="Next"]:visible, a[aria-label*="next"]:visible, a:has-text("Next"):visible').first();
assert(await paginationLink.count() > 0, 'No bottom pagination link found');
await paginationLink.click();
await page.waitForLoadState('networkidle');
assert(new URL(page.url()).origin === origin, `Origin drift after pagination click: ${page.url()}`);

if (styleCheck) {
  await page.goto(home, { waitUntil: 'networkidle', timeout: 20_000 });
  assert(await page.locator('starlight-theme-select, button[aria-label*="theme" i]').count() > 0, 'Theme selector not found');
  assert(await page.locator('input[type="search"], button[aria-label*="search" i]').count() > 0, 'Search control not found');
}

await browser.close();
console.log(`PASS: ${origin}/docs-viewer/ keeps current origin`);
NODE
}

ensure_e2e_deps

IFS=',' read -r -a port_list <<< "$PORTS"
for port in "${port_list[@]}"; do
  port="$(echo "$port" | xargs)"
  [[ -n "$port" ]] || continue
  start_or_reuse_viewer "$port"
  run_browser_assertions "$port" "$STYLE_CHECK"
done

echo "PASS: docs-viewer runtime origin contract"
