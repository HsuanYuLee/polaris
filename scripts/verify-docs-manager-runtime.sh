#!/usr/bin/env bash
# Verify docs-manager local runtime contract across one or more ports.
# Usage:
#   scripts/verify-docs-manager-runtime.sh --ports 8080,3334 [--preview]

set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORTS="8080"
PREVIEW_MODE=false

usage() {
  cat <<EOF
Usage:
  scripts/verify-docs-manager-runtime.sh --ports 8080,3334 [--preview]

Options:
  --ports        要驗證的 comma-separated port list。
  --preview      使用 docs-manager preview mode，包含 production search 檢查。

Notes:
  docs-manager viewer lifecycle is user-owned. This verifier only checks an
  already-running docs-manager listener; it does not start, stop, reload, or
  restart the viewer.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ports) PORTS="${2:-}"; shift 2 ;;
    --preview) PREVIEW_MODE=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "未知選項：$1" >&2; usage >&2; exit 2 ;;
  esac
done

cd "$WORKSPACE_ROOT"

is_docs_manager_available() {
  local origin="$1"
  local body
  body="$(curl -fsS --max-time 5 "$origin/docs-manager/" 2>/dev/null || true)"
  [[ "$body" == *"Polaris Specs"* && "$body" == *"starlight"* ]]
}

is_preview_search_available() {
  local origin="$1"
  curl -fsS --max-time 5 "$origin/docs-manager/pagefind/pagefind-ui.js" >/dev/null 2>&1
}

listener_pid() {
  local port="$1"
  lsof -tiTCP:"$port" -sTCP:LISTEN -n -P 2>/dev/null | head -n1 || true
}

listener_cwd() {
  local pid="$1"
  local cwd=""
  cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -n1 || true)"
  if [[ -n "$cwd" && -d "$cwd" ]]; then
    (cd "$cwd" && pwd -P)
  fi
}

expected_docs_manager_cwd() {
  (cd "$WORKSPACE_ROOT/docs-manager" && pwd -P)
}

ensure_docs_manager_owner() {
  local port="$1"
  local origin="$2"
  local pid cwd expected

  pid="$(listener_pid "$port")"
  if [[ -z "$pid" ]]; then
    echo "Port $port 沒有 listener，無法確認 docs-manager owner。" >&2
    return 1
  fi

  cwd="$(listener_cwd "$pid")"
  expected="$(expected_docs_manager_cwd)"
  if [[ -n "$cwd" && "$cwd" != "$expected" ]]; then
    echo "Port $port 的 docs-manager 來自不同 workspace，拒絕重用。" >&2
    echo "Expected cwd: $expected" >&2
    echo "Actual cwd: $cwd" >&2
    echo "URL: $origin/docs-manager/" >&2
    return 1
  fi

  if [[ -z "$cwd" ]]; then
    echo "WARN: 無法讀取 port $port listener cwd；已確認 body 是 docs-manager，繼續驗證。" >&2
  fi
}

ensure_e2e_deps() {
  local toolchain_dir="$WORKSPACE_ROOT/tools/polaris-toolchain"
  if [[ ! -x "$toolchain_dir/node_modules/.bin/playwright" ]]; then
    pnpm --dir "$toolchain_dir" install --silent
  fi
  if ! pnpm --dir "$toolchain_dir" exec playwright install chromium >/dev/null 2>&1; then
    pnpm --dir "$toolchain_dir" exec playwright install chromium
  fi
}

require_docs_manager() {
  local port="$1"
  local origin="http://127.0.0.1:$port"

  if lsof -i :"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    if is_docs_manager_available "$origin"; then
      if [[ "$PREVIEW_MODE" == "true" ]] && ! is_preview_search_available "$origin"; then
        echo "Port $port 是 docs-manager dev server，但 --preview 需要 production preview/search assets。" >&2
        echo "請由使用者在 preview mode 啟動 docs-manager 後，再對該 port 重跑 preview verification。" >&2
        return 1
      fi
      ensure_docs_manager_owner "$port" "$origin"
      echo "驗證 docs-manager：$origin/docs-manager/"
      return 0
    fi
    echo "Port $port 已被非 docs-manager 服務占用。" >&2
    return 1
  fi

  echo "Port $port 沒有 docs-manager listener；viewer lifecycle is user-owned。" >&2
  echo "請先由使用者啟動 docs-manager，再重跑此 verifier。" >&2
  return 1
}

run_browser_assertions() {
  local port="$1"
  local origin="http://127.0.0.1:$port"
  local preview_flag="$2"

  DOCS_MANAGER_ORIGIN="$origin" DOCS_MANAGER_PREVIEW_MODE="$preview_flag" \
    node --input-type=module <<'NODE'
import playwright from './tools/polaris-toolchain/node_modules/@playwright/test/index.js';

const { chromium } = playwright;

const origin = process.env.DOCS_MANAGER_ORIGIN;
const previewMode = process.env.DOCS_MANAGER_PREVIEW_MODE === 'true';
  const home = `${origin}/docs-manager/`;
  const sampleRoute = `${origin}/docs-manager/specs/design-plans/archive/dp-063-docs-manager-source-unification/tasks/pr-release/t2/`;

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
assert(await page.getByText('companies', { exact: true }).count() > 0, 'Top-level companies group not found');
const companyRouteHref = await page
  .locator('a[href^="/docs-manager/specs/companies/"]')
  .first()
  .getAttribute('href');
assert(companyRouteHref, 'No company route found in sidebar');
const companyBugHref = await page
  .locator('details:has-text("bugs") a[href^="/docs-manager/specs/companies/"]')
  .first()
  .getAttribute('href');
assert(companyBugHref, 'No company bug route found in bugs sidebar group');
assert(await page.getByText('design-plans', { exact: true }).count() > 0, 'Top-level design-plans group not found');
assert(!(await page.getByText('DP-001-design-plan-skill', { exact: true }).first().isVisible()), 'Autogenerated specs subgroups should be collapsed by default');
const companyRefinementHref = await page
  .locator('a[href^="/docs-manager/specs/companies/"][href$="/refinement/"]')
  .first()
  .getAttribute('href');
assert(companyRefinementHref, 'No company refinement route found in sidebar');

const activePlanLink = page
  .locator('a[href^="/docs-manager/specs/design-plans/dp-"]:not([href*="/archive/"])')
  .first();
assert(await activePlanLink.count() > 0, 'No active DP overview link found in sidebar');
await activePlanLink.scrollIntoViewIfNeeded();
const activePlanHref = await activePlanLink.getAttribute('href');
assert(activePlanHref, 'Active DP overview link has no href');
const activeDpDetails = page.locator(`details:has(a[href="${activePlanHref}"])`).first();
assert(await activeDpDetails.count() > 0, `Active DP folder details not found for ${activePlanHref}`);
await activeDpDetails.evaluate((element) => {
  element.open = true;
});
const activeDpText = (await activeDpDetails.textContent()) || '';
assert(/DP-\d{3}:/.test(activeDpText), `Active DP folder label not found: ${activeDpText}`);
assert(/(SEEDED|DISCUSSION|LOCKED|IMPLEMENTED|IN_PROGRESS|IMPLEMENTING)( \/ P[0-3])?/.test(activeDpText), `Active DP folder badge text not found: ${activeDpText}`);
const activeDpBase = activePlanHref.endsWith('/plan/') ? activePlanHref.replace(/plan\/$/, '') : activePlanHref;
const nestedHrefs = await activeDpDetails.locator(`a[href^="${activeDpBase}"]`).evaluateAll((links) =>
  links.map((link) => link.getAttribute('href')).filter(Boolean)
);
assert(nestedHrefs.length > 0, `Active DP nested sidebar route not found under ${activeDpBase}`);
let activeNestedHref = nestedHrefs.find((href) => href !== activePlanHref) || activePlanHref;
if (!activeNestedHref.endsWith('/')) {
  activeNestedHref = `${activeNestedHref}/`;
}
await gotoOk(sampleRoute);
assert((await page.textContent('body'))?.includes('direct specs content loader') || (await page.textContent('body'))?.includes('canonical specs'), 'Archived canonical DP-063 T2 route content not found');
await gotoOk(`${origin}${activeNestedHref}`);
assert((await page.textContent('body'))?.includes('DP-'), 'Active DP route content not found');
await gotoOk(`${origin}${companyRefinementHref}`);
assert((await page.textContent('body'))?.includes('Refinement'), 'Company ticket refinement route content not found');
const h1Texts = await page.locator('h1').allTextContents();
assert(new Set(h1Texts.map((text) => text.trim())).size === h1Texts.length, `Duplicate H1 titles found: ${h1Texts.join(' | ')}`);

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
  require_docs_manager "$port"
  run_browser_assertions "$port" "$PREVIEW_MODE"
done

echo "PASS: docs-manager runtime contract"
