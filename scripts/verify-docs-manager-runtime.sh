#!/usr/bin/env bash
# Verify docs-manager local runtime contract across one or more ports.
# Usage:
#   scripts/verify-docs-manager-runtime.sh --ports 8080,3334 [--preview] [--keep-server]

set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORTS="8080"
PREVIEW_MODE=false
KEEP_SERVER=false
PIDS=()
STARTED_PORTS=()

usage() {
  cat <<EOF
Usage:
  scripts/verify-docs-manager-runtime.sh --ports 8080,3334 [--preview] [--keep-server]

Options:
  --ports        要驗證的 comma-separated port list。
  --preview      使用 docs-manager preview mode，包含 production search 檢查。
  --keep-server  保留 verifier 自己啟動的 server；預設只 cleanup verifier 自己啟動的 server。
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ports) PORTS="${2:-}"; shift 2 ;;
    --preview) PREVIEW_MODE=true; shift ;;
    --keep-server) KEEP_SERVER=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "未知選項：$1" >&2; usage >&2; exit 2 ;;
  esac
done

cd "$WORKSPACE_ROOT"

cleanup() {
  if [[ "$KEEP_SERVER" == "true" ]]; then
    return 0
  fi

  for pid in "${PIDS[@]:-}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done

  for port in "${STARTED_PORTS[@]:-}"; do
    bash "$WORKSPACE_ROOT/scripts/polaris-viewer.sh" --stop --port "$port" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

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

wait_for_docs_manager() {
  local origin="$1"
  local port="$2"
  local deadline=$((SECONDS + 60))
  while (( SECONDS < deadline )); do
    if is_docs_manager_available "$origin"; then
      ensure_docs_manager_owner "$port" "$origin"
      return 0
    fi
    sleep 1
  done
  echo "等待 $origin/docs-manager/ 逾時" >&2
  return 1
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

start_or_reuse_docs_manager() {
  local port="$1"
  local origin="http://127.0.0.1:$port"

  if lsof -i :"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    if is_docs_manager_available "$origin"; then
      if [[ "$PREVIEW_MODE" == "true" ]] && ! is_preview_search_available "$origin"; then
        echo "Port $port 是 docs-manager dev server，但 --preview 需要 production preview/search assets。" >&2
        echo "請改用其他 port，或先用 polaris-viewer.sh --stop 停掉該 port 後再跑 preview verification。" >&2
        return 1
      fi
      ensure_docs_manager_owner "$port" "$origin"
      echo "重用 docs-manager：$origin/docs-manager/"
      return 0
    fi
    echo "Port $port 已被非 docs-manager 服務占用。" >&2
    return 1
  fi

  local mode_args=()
  if [[ "$PREVIEW_MODE" == "true" ]]; then
    mode_args+=(--preview)
  fi

  echo "啟動 docs-manager：$origin/docs-manager/"
  bash "$WORKSPACE_ROOT/scripts/polaris-viewer.sh" --port "$port" --no-open "${mode_args[@]+"${mode_args[@]}"}" >"/tmp/polaris-docs-manager-$port.log" 2>&1 &
  PIDS+=("$!")
  STARTED_PORTS+=("$port")
  wait_for_docs_manager "$origin" "$port"
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
assert(await page.getByText('design-plans', { exact: true }).first().isVisible(), 'Top-level specs groups are not visible');
assert(!(await page.getByText('DP-001-design-plan-skill', { exact: true }).first().isVisible()), 'Autogenerated specs subgroups should be collapsed by default');
const companyRefinementHref = await page
  .locator('a[href^="/docs-manager/specs/companies/"][href$="/refinement/"]')
  .first()
  .getAttribute('href');
assert(companyRefinementHref, 'No company refinement route found in sidebar');

const activePlanLink = page.locator('a[href^="/docs-manager/specs/design-plans/dp-"][href$="/plan/"]').first();
assert(await activePlanLink.count() > 0, 'No active DP plan link found in sidebar');
await activePlanLink.scrollIntoViewIfNeeded();
const activePlanHref = await activePlanLink.getAttribute('href');
assert(activePlanHref, 'Active DP plan link has no href');
const activeDpDetails = page.locator(`details:has(a[href="${activePlanHref}"])`).first();
assert(await activeDpDetails.count() > 0, `Active DP folder details not found for ${activePlanHref}`);
await activeDpDetails.evaluate((element) => {
  element.open = true;
});
const activeDpText = (await activeDpDetails.textContent()) || '';
assert(/DP-\d{3}:/.test(activeDpText), `Active DP folder label not found: ${activeDpText}`);
assert(/(SEEDED|DISCUSSION|LOCKED|IMPLEMENTED)( \/ P[0-3])?/.test(activeDpText), `Active DP folder badge text not found: ${activeDpText}`);
const activeDpBase = activePlanHref.replace(/plan\/$/, '');
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
  start_or_reuse_docs_manager "$port"
  run_browser_assertions "$port" "$PREVIEW_MODE"
done

echo "PASS: docs-manager runtime contract"
