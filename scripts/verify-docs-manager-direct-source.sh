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

if [[ ! -f "${SPECS_ROOT}/design-plans/archive/DP-063-docs-manager-source-unification/plan.md" ]]; then
  echo "FAIL: canonical archived DP-063 plan not found under ${SPECS_ROOT}" >&2
  exit 1
fi

if [[ "${SPECS_ROOT}" != "${DOCS_MANAGER}/src/content/docs/specs" ]]; then
  echo "FAIL: specs root is not Starlight native content root: ${SPECS_ROOT}" >&2
  exit 1
fi

node --input-type=module <<'NODE'
import { specsSidebar } from './docs-manager/sidebar.mjs';

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

const kkday = companies.items?.find((item) => item.label === 'kkday');
assert(kkday, 'kkday company sidebar group is missing');
for (const ticket of kkday.items ?? []) {
  if (ticket.label === 'archive') continue;
  assert(ticket.label !== 'refinement', 'company ticket folder collapsed to refinement');
}

assert(labels.some((label) => label.includes('GT-478')), 'company Epic folder label GT-478 is missing');
assert(labels.some((label) => label.includes('GT-521')), 'company Epic folder label GT-521 is missing');
assert(labels.some((label) => label.includes('GT-522')), 'company Epic folder label GT-522 is missing');
assert(!labels.includes('Refinement — GT-478: [CWV] JS Bundle 瘦身（Product + Category 共通）'), 'folder label did not strip Refinement prefix');
assert(links.includes('/specs/companies/kkday/gt-478/tasks/t5/'), 'company Epic task route missing from sidebar');
assert(links.includes('/specs/companies/kkday/gt-478/tasks/pr-release/t1/'), 'company Epic pr-release task route missing from sidebar');
assert(links.includes('/specs/design-plans/dp-062-refinement-research-container-flow/tasks/t2/'), 'DP task route missing from sidebar');
assert(links.includes('/specs/design-plans/archive/dp-063-docs-manager-source-unification/tasks/pr-release/t1/'), 'archived DP pr-release task route missing from sidebar');

const companyImplementing = findItem(kkday.items, (item) => item.label?.includes('GT-478'));
assert(companyImplementing?.badge?.text === 'IMPLEMENTING', 'company Epic IMPLEMENTING badge missing');
assert(companyImplementing?.badge?.variant === 'caution', 'company Epic IMPLEMENTING badge variant should be caution');

const companyDiscussion = findItem(kkday.items, (item) => item.label?.includes('GT-527'));
assert(companyDiscussion?.badge?.text === 'DISCUSSION', 'company Epic DISCUSSION badge missing');
assert(companyDiscussion?.badge?.variant === 'note', 'company Epic DISCUSSION badge variant should be note');

const companyLocked = findItem(kkday.items, (item) => item.label?.includes('GT-528'));
assert(companyLocked?.badge?.text === 'LOCKED', 'company Epic LOCKED badge missing');
assert(companyLocked?.badge?.variant === 'tip', 'company Epic LOCKED badge variant should be tip');

const dpLocked = findItem(designPlans.items, (item) => item.label?.includes('DP-062'));
assert(dpLocked?.badge?.text === 'LOCKED / P1', 'DP status/priority badge was not derived consistently');
assert(dpLocked?.badge?.variant === 'tip', 'DP P1 locked badge variant should be tip');

const dpDiscussion = findItem(designPlans.items, (item) => item.label?.includes('DP-034'));
assert(dpDiscussion?.badge?.text === 'DISCUSSION / P2', 'DP status/priority badge text was not derived consistently');
assert(dpDiscussion?.badge?.variant === 'note', 'DP non-P1 badge variant should be note');

const archivedBug = findItem(kkday.items, (item) => item.label?.includes('KB2CW-3847'));
assert(archivedBug?.badge?.text === 'IMPLEMENTED', 'company archived ticket status badge missing');
assert(archivedBug?.badge?.variant === 'success', 'company archived ticket badge variant should be success');

const inProgressTask = findItem(kkday.items, (item) => item.link === '/specs/companies/kkday/kb2cw-2863/tasks/t1/');
assert(inProgressTask?.badge?.text === 'IN_PROGRESS', 'company task status badge missing');
assert(inProgressTask?.badge?.variant === 'caution', 'company task IN_PROGRESS badge variant should be caution');
NODE

echo "PASS: docs-manager Starlight-native source contract"
