#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCS_MANAGER="${ROOT}/docs-manager"
CONTENT_CONFIG="${DOCS_MANAGER}/src/content.config.ts"

# shellcheck source=lib/specs-root.sh
. "${ROOT}/scripts/lib/specs-root.sh"

if ! rg -n 'docsLoader\(' "$CONTENT_CONFIG" >/dev/null; then
  echo "FAIL: docs-manager does not use Starlight docsLoader" >&2
  exit 1
fi

if rg -n 'canonicalSpecsLoader|specs-loader' "$CONTENT_CONFIG" "${DOCS_MANAGER}/src" >/dev/null; then
  echo "FAIL: docs-manager still references the custom specs loader" >&2
  exit 1
fi

if [[ -e "${DOCS_MANAGER}/src/lib/specs-loader.ts" ]]; then
  echo "FAIL: custom specs loader file still exists" >&2
  exit 1
fi

if [[ -e "${DOCS_MANAGER}/specs" ]]; then
  echo "FAIL: legacy docs-manager/specs source still exists" >&2
  exit 1
fi

SPECS_ROOT="$(resolve_specs_root "$ROOT")" || {
  echo "FAIL: unable to resolve canonical specs root" >&2
  exit 1
}
OVERLAY_MODE=false

if [[ ! -f "${SPECS_ROOT}/design-plans/archive/DP-063-docs-manager-source-unification/plan.md" ]]; then
  MAIN_WORKSPACE_ROOT="$(resolve_specs_workspace_root "$ROOT" 2>/dev/null || true)"
  if [[ -n "$MAIN_WORKSPACE_ROOT" && "$MAIN_WORKSPACE_ROOT" != "$ROOT" ]]; then
    OVERLAY_SPECS_ROOT="$(resolve_specs_root "$MAIN_WORKSPACE_ROOT" 2>/dev/null || true)"
    if [[ -f "${OVERLAY_SPECS_ROOT}/design-plans/archive/DP-063-docs-manager-source-unification/plan.md" ]]; then
      SPECS_ROOT="$OVERLAY_SPECS_ROOT"
      OVERLAY_MODE=true
    fi
  fi
fi

if [[ ! -f "${SPECS_ROOT}/design-plans/archive/DP-063-docs-manager-source-unification/plan.md" ]]; then
  echo "FAIL: canonical archived DP-063 plan not found under ${SPECS_ROOT}" >&2
  exit 1
fi

if [[ "${SPECS_ROOT}" != "${DOCS_MANAGER}/src/content/docs/specs" ]]; then
  if [[ "$OVERLAY_MODE" != true ]]; then
    echo "FAIL: specs root is not Starlight native content root: ${SPECS_ROOT}" >&2
    exit 1
  fi
  if [[ "$SPECS_ROOT" != "${MAIN_WORKSPACE_ROOT}/docs-manager/src/content/docs/specs" ]]; then
    echo "FAIL: specs overlay root is not main checkout Starlight content root: ${SPECS_ROOT}" >&2
    exit 1
  fi
fi

if [[ "$OVERLAY_MODE" == true ]]; then
  echo "INFO: using read-only specs overlay: ${SPECS_ROOT}" >&2
fi

POLARIS_SPECS_ROOT="${SPECS_ROOT}" node --input-type=module <<'NODE'
import { specsSidebar } from './docs-manager/sidebar.mjs';

if (!process.env.POLARIS_SPECS_ROOT) {
  console.error('FAIL: POLARIS_SPECS_ROOT was not provided to sidebar contract check');
  process.exit(1);
}

function assert(condition, message) {
  if (!condition) {
    console.error(`FAIL: ${message}`);
    process.exit(1);
  }
}

function findItem(items, predicate) {
  let found;
  walk(items, (item) => {
    if (!found && predicate(item)) found = item;
  });
  return found;
}

const sidebar = specsSidebar();
const labels = [];
const links = [];

function walk(items, visitor = undefined) {
  for (const item of items) {
    if (visitor) visitor(item);
    if (item.label) labels.push(item.label);
    if (item.link) links.push(item.link);
    if (item.items) walk(item.items, visitor);
  }
}

walk(sidebar);

const designPlans = sidebar.find((item) => item.label === 'design-plans');
const companies = sidebar.find((item) => item.label === 'companies');
assert(designPlans, 'design-plans sidebar group is missing');
assert(companies, 'companies sidebar group is missing');

const companyGroup = companies.items?.find((item) => item.label !== 'archive');
assert(companyGroup, 'company sidebar group is missing');
const companySlug = companyGroup.label;
for (const ticket of companyGroup.items ?? []) {
  if (ticket.label === 'archive') continue;
  assert(ticket.label !== 'refinement', 'company ticket folder collapsed to refinement');
}

assert(labels.some((label) => /^[A-Z][A-Z0-9]+-\d+/.test(label)), 'company ticket folder label is missing');
assert(!labels.some((label) => label.startsWith('Refinement — ')), 'folder label did not strip Refinement prefix');
assert(
  links.some((link) => link.startsWith(`/specs/companies/${companySlug}/`) && link.endsWith('/tasks/t5/')),
  'company Epic task route missing from sidebar',
);
assert(
  links.some((link) => link.startsWith(`/specs/companies/${companySlug}/`) && link.endsWith('/tasks/pr-release/t1/')),
  'company Epic pr-release task route missing from sidebar',
);
assert(links.includes('/specs/design-plans/archive/dp-062-refinement-research-container-flow/tasks/pr-release/t2/'), 'archived DP pr-release task route missing from sidebar');
assert(links.includes('/specs/design-plans/archive/dp-063-docs-manager-source-unification/tasks/pr-release/t1/'), 'archived DP pr-release task route missing from sidebar');

const companyImplementing = findItem(companyGroup.items, (item) => item.badge?.text === 'IMPLEMENTING');
assert(companyImplementing?.badge?.text === 'IMPLEMENTING', 'company Epic IMPLEMENTING badge missing');
assert(companyImplementing?.badge?.variant === 'caution', 'company Epic IMPLEMENTING badge variant should be caution');

const companyDiscussion = findItem(companyGroup.items, (item) => item.badge?.text === 'DISCUSSION');
assert(companyDiscussion?.badge?.text === 'DISCUSSION', 'company Epic DISCUSSION badge missing');
assert(companyDiscussion?.badge?.variant === 'note', 'company Epic DISCUSSION badge variant should be note');

const companyLocked = findItem(companyGroup.items, (item) => item.badge?.text === 'LOCKED');
assert(companyLocked?.badge?.text === 'LOCKED', 'company Epic LOCKED badge missing');
assert(companyLocked?.badge?.variant === 'tip', 'company Epic LOCKED badge variant should be tip');

const dpImplemented = findItem(designPlans.items, (item) => item.label?.includes('DP-035'));
const dp035BadgeText = dpImplemented?.badge?.text;
const dp035BadgeVariant = dpImplemented?.badge?.variant;
assert(
  (dp035BadgeText === 'IMPLEMENTING / P2' && dp035BadgeVariant === 'caution') ||
    (dp035BadgeText === 'IMPLEMENTED / P2' && dp035BadgeVariant === 'success'),
  'DP-035 status/priority badge was not derived consistently',
);

const dpDiscussion = findItem(designPlans.items, (item) => item.label?.includes('DP-034'));
assert(dpDiscussion?.badge?.text === 'DISCUSSION / P2', 'DP status/priority badge text was not derived consistently');
assert(dpDiscussion?.badge?.variant === 'note', 'DP non-P1 badge variant should be note');

const archivedBug = findItem(companyGroup.items, (item) => item.badge?.text === 'IMPLEMENTED');
assert(archivedBug?.badge?.text === 'IMPLEMENTED', 'company archived ticket status badge missing');
assert(archivedBug?.badge?.variant === 'success', 'company archived ticket badge variant should be success');

const inProgressTask = findItem(
  companyGroup.items,
  (item) =>
    item.link?.startsWith(`/specs/companies/${companySlug}/`) &&
    item.link.endsWith('/tasks/t1/') &&
    item.badge?.text === 'IN_PROGRESS',
);
assert(inProgressTask?.badge?.text === 'IN_PROGRESS', 'company task status badge missing');
assert(inProgressTask?.badge?.variant === 'caution', 'company task IN_PROGRESS badge variant should be caution');
NODE

echo "PASS: docs-manager Starlight-native source contract"
