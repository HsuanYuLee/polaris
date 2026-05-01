#!/usr/bin/env bash
# Verify docs-manager local runtime contract across one or more ports.
# Usage:
#   scripts/verify-docs-manager-runtime.sh --ports 8080,3334 [--preview]

set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORTS="8080"
PREVIEW_MODE=false
PIDS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ports) PORTS="${2:-}"; shift 2 ;;
    --preview) PREVIEW_MODE=true; shift ;;
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

is_docs_manager_available() {
  local origin="$1"
  local body
  body="$(curl -fsS --max-time 5 "$origin/docs-manager/" 2>/dev/null || true)"
  [[ "$body" == *"Polaris Specs"* && "$body" == *"starlight"* ]]
}

wait_for_docs_manager() {
  local origin="$1"
  local deadline=$((SECONDS + 60))
  while (( SECONDS < deadline )); do
    if is_docs_manager_available "$origin"; then
      return 0
    fi
    sleep 1
  done
  echo "Timed out waiting for $origin/docs-manager/" >&2
  return 1
}

ensure_e2e_deps() {
  if [[ ! -d "$WORKSPACE_ROOT/scripts/e2e/node_modules" ]]; then
    npm install --prefix "$WORKSPACE_ROOT/scripts/e2e" --silent --no-package-lock
  fi
  if ! npx --prefix "$WORKSPACE_ROOT/scripts/e2e" playwright install chromium >/dev/null 2>&1; then
    npx --prefix "$WORKSPACE_ROOT/scripts/e2e" playwright install chromium
  fi
}

start_or_reuse_docs_manager() {
  local port="$1"
  local origin="http://127.0.0.1:$port"

  if lsof -i :"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    if is_docs_manager_available "$origin"; then
      echo "Reusing docs-manager on $origin/docs-manager/"
      return 0
    fi
    echo "Port $port is occupied by a non-docs-manager service." >&2
    return 1
  fi

  local mode_args=()
  if [[ "$PREVIEW_MODE" == "true" ]]; then
    mode_args+=(--preview)
  fi

  echo "Starting docs-manager on $origin/docs-manager/"
  bash "$WORKSPACE_ROOT/scripts/polaris-viewer.sh" --port "$port" --no-open "${mode_args[@]+"${mode_args[@]}"}" >"/tmp/polaris-docs-manager-$port.log" 2>&1 &
  PIDS+=("$!")
  wait_for_docs_manager "$origin"
}

run_browser_assertions() {
  local port="$1"
  local origin="http://127.0.0.1:$port"
  local preview_flag="$2"

  DOCS_MANAGER_ORIGIN="$origin" DOCS_MANAGER_PREVIEW_MODE="$preview_flag" \
    node --input-type=module <<'NODE'
import playwright from './scripts/e2e/node_modules/playwright/index.js';

const origin = process.env.DOCS_MANAGER_ORIGIN;
const previewMode = process.env.DOCS_MANAGER_PREVIEW_MODE === 'true';
const home = `${origin}/docs-manager/`;
const sampleRoute = `${origin}/docs-manager/specs/design-plans/archive/DP-063-docs-manager-source-unification/tasks/pr-release/T2/`;
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
await gotoOk(sampleRoute);
assert((await page.textContent('body'))?.includes('direct specs content loader') || (await page.textContent('body'))?.includes('canonical specs'), 'Archived canonical DP-063 T2 route content not found');

await page.goto(home, { waitUntil: 'networkidle', timeout: 20_000 });
const sidebarLink = page.locator('a[href*="/docs-manager/specs/"]:visible').first();
assert(await sidebarLink.count() > 0, 'No specs sidebar link found');
await sidebarLink.click();
await page.waitForLoadState('networkidle');
assert(new URL(page.url()).origin === origin, `Origin drift after sidebar click: ${page.url()}`);
assert(page.url().includes('/docs-manager/specs/'), `Sidebar click did not reach specs route: ${page.url()}`);

if (previewMode) {
  await page.goto(home, { waitUntil: 'networkidle', timeout: 20_000 });
  const searchButton = page.locator('site-search button[data-open-modal], button[aria-label*="search" i]').first();
  assert(await searchButton.count() > 0, 'Search open button not found');
  await searchButton.click();

  const dialog = page.locator('site-search dialog[open], dialog[open][aria-label*="search" i]').first();
  await dialog.waitFor({ state: 'visible', timeout: 10_000 });

  const searchInput = page.locator('#starlight__search input[type="search"], #starlight__search .pagefind-ui__search-input').first();
  await searchInput.waitFor({ state: 'visible', timeout: 20_000 });
  await searchInput.fill('DP-063');

  const resultLink = page.locator('#starlight__search .pagefind-ui__result-link, #starlight__search a[href]').first();
  await resultLink.waitFor({ state: 'visible', timeout: 12_000 });
  await resultLink.click();
  await page.waitForLoadState('networkidle');
  assert(new URL(page.url()).origin === origin, `Origin drift after search result click: ${page.url()}`);
  assert(page.url().includes('/docs-manager/'), `Search result left docs-manager base path: ${page.url()}`);
}

await browser.close();
console.log(`PASS: ${origin}/docs-manager/ keeps current origin`);
NODE
}

ensure_e2e_deps

IFS=',' read -r -a port_list <<< "$PORTS"
for port in "${port_list[@]}"; do
  port="$(echo "$port" | xargs)"
  [[ -n "$port" ]] || continue
  start_or_reuse_docs_manager "$port"
  run_browser_assertions "$port" "$PREVIEW_MODE"
done

echo "PASS: docs-manager runtime contract"
