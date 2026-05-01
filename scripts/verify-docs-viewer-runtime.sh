#!/usr/bin/env bash
# Verify docs-viewer local origin contract across one or more ports.
# Usage:
#   scripts/verify-docs-viewer-runtime.sh --ports 8080,3334 [--style-check] [--preview]

set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORTS="8080,3334"
STYLE_CHECK=false
PREVIEW_MODE=false
PIDS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ports) PORTS="${2:-}"; shift 2 ;;
    --style-check) STYLE_CHECK=true; shift ;;
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

check_generated_sidebar_metadata() {
  local base="$WORKSPACE_ROOT/docs-viewer/src/content/docs/specs/design-plans/DP-061-docs-viewer-sidebar-search-usability"
  local plan="$base/plan.md"
  local task2

  [[ -f "$plan" ]] || return 0

  grep -q '^title: "docs-viewer sidebar and search usability 🔒"$' "$plan"
  grep -q '^description: "specs/design-plans/DP-061-docs-viewer-sidebar-search-usability/plan.md"$' "$plan"
  grep -q '^sidebar:$' "$plan"
  grep -q '^  label: "Plan"$' "$plan"
  grep -q '^  order: 0$' "$plan"
  if grep -q '^# DP-061：docs-viewer sidebar and search usability$' "$plan"; then
    echo "Duplicate generated H1 found in $plan" >&2
    return 1
  fi

  task2="$(find "$base/tasks" -maxdepth 1 -iname 't2.md' -print -quit 2>/dev/null || true)"
  [[ -n "$task2" ]] || return 0
  grep -q '^sidebar:$' "$task2"
  grep -q '^  label: "T2: Starlight-native generated sidebar metadata"$' "$task2"
  grep -q '^  order: 120$' "$task2"
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

  local mode_args=()
  if [[ "$PREVIEW_MODE" == "true" ]]; then
    mode_args+=(--preview)
  fi

  echo "Starting viewer on $origin/docs-viewer/"
  bash "$WORKSPACE_ROOT/scripts/polaris-viewer.sh" --port "$port" --no-open "${mode_args[@]+"${mode_args[@]}"}" >"/tmp/polaris-viewer-$port.log" 2>&1 &
  PIDS+=("$!")
  wait_for_viewer "$origin"
}

run_browser_assertions() {
  local port="$1"
  local origin="http://127.0.0.1:$port"
  local style_flag="$2"
  local preview_flag="$3"

  DOCS_VIEWER_ORIGIN="$origin" DOCS_VIEWER_STYLE_CHECK="$style_flag" DOCS_VIEWER_PREVIEW_MODE="$preview_flag" \
    node --input-type=module <<'NODE'
import playwright from './scripts/e2e/node_modules/playwright/index.js';

const origin = process.env.DOCS_VIEWER_ORIGIN;
const styleCheck = process.env.DOCS_VIEWER_STYLE_CHECK === 'true';
const previewMode = process.env.DOCS_VIEWER_PREVIEW_MODE === 'true';
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

  const dp061Links = await page.locator('nav[aria-label="Main"] a[href*="dp-061-docs-viewer-sidebar-search-usability"]').evaluateAll((anchors) =>
    anchors.map((anchor) => ({
      href: anchor.getAttribute('href') || '',
      text: (anchor.textContent || '').replace(/\s+/g, ' ').trim(),
    }))
  );

  const linkFor = (suffix) => dp061Links.find((link) => link.href.toLowerCase().endsWith(suffix));
  const planLink = linkFor('/plan/');
  const refinementLink = linkFor('/refinement/');
  const task1Link = linkFor('/tasks/t1/');
  const task2Link = linkFor('/tasks/t2/');

  assert(planLink?.text === 'Plan', `DP-061 plan sidebar label mismatch: ${planLink?.text || 'missing'}`);
  assert(refinementLink?.text === 'Refinement', `DP-061 refinement sidebar label mismatch: ${refinementLink?.text || 'missing'}`);
  assert(task1Link?.text === 'T1: docs-viewer production preview search path', `DP-061 T1 sidebar label mismatch: ${task1Link?.text || 'missing'}`);
  assert(task2Link?.text === 'T2: Starlight-native generated sidebar metadata', `DP-061 T2 sidebar label mismatch: ${task2Link?.text || 'missing'}`);

  const order = [planLink, refinementLink, task1Link, task2Link].map((target) => dp061Links.indexOf(target));
  assert(order.every((idx) => idx >= 0), `DP-061 sidebar links missing from order check: ${JSON.stringify(order)}`);
  assert(order[0] < order[1] && order[1] < order[2] && order[2] < order[3], `DP-061 sidebar order mismatch: ${JSON.stringify(dp061Links)}`);
}

if (styleCheck && previewMode) {
  await page.goto(home, { waitUntil: 'networkidle', timeout: 20_000 });
  const searchButton = page.locator('site-search button[data-open-modal], button[aria-label*="search" i]').first();
  assert(await searchButton.count() > 0, 'Search open button not found');
  await searchButton.click();

  const dialog = page.locator('site-search dialog[open], dialog[open][aria-label*="search" i]').first();
  await dialog.waitFor({ state: 'visible', timeout: 10_000 });

  const searchInput = page.locator('#starlight__search input[type="search"], #starlight__search .pagefind-ui__search-input').first();
  await searchInput.waitFor({ state: 'visible', timeout: 20_000 });

  const resultLink = page.locator('#starlight__search .pagefind-ui__result-link, #starlight__search a[href]').first();
  let matchedTerm = '';
  let lastError;
  for (const term of ['DP-058', 'refinement']) {
    await searchInput.fill(term);
    try {
      await resultLink.waitFor({ state: 'visible', timeout: 12_000 });
      matchedTerm = term;
      break;
    } catch (error) {
      lastError = error;
    }
  }
  assert(matchedTerm, `Search returned no result for DP-058 or refinement: ${lastError?.message || 'unknown error'}`);

  await resultLink.click();
  await page.waitForLoadState('networkidle');
  assert(new URL(page.url()).origin === origin, `Origin drift after search result click: ${page.url()}`);
  assert(page.url().includes('/docs-viewer/'), `Search result left docs-viewer base path: ${page.url()}`);
}

await browser.close();
console.log(`PASS: ${origin}/docs-viewer/ keeps current origin`);
NODE
}

ensure_e2e_deps
if [[ "$STYLE_CHECK" == "true" ]]; then
  check_generated_sidebar_metadata
fi

IFS=',' read -r -a port_list <<< "$PORTS"
for port in "${port_list[@]}"; do
  port="$(echo "$port" | xargs)"
  [[ -n "$port" ]] || continue
  start_or_reuse_viewer "$port"
  run_browser_assertions "$port" "$STYLE_CHECK" "$PREVIEW_MODE"
done

echo "PASS: docs-viewer runtime origin contract"
