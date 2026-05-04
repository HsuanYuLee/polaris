import assert from 'node:assert/strict';
import { specsSidebar } from '../sidebar.mjs';
import { inferStatusDashboard, primaryLink } from '../src/status/index.mjs';

function flattenLinks(items, links = new Set()) {
  for (const item of items) {
    if (item.link) links.add(item.link);
    if (item.items) flattenLinks(item.items, links);
  }
  return links;
}

const dashboard = inferStatusDashboard();
const sidebarLinks = flattenLinks(specsSidebar());
const base = '/docs-manager';

for (const item of dashboard.items) {
  const link = primaryLink(item, base);
  if (!link) continue;
  const sidebarLink = link.replace(/^\/docs-manager/, '');
  assert(
    sidebarLinks.has(sidebarLink),
    `Status item ${item.id} has runtime link ${sidebarLink}, but sidebar navigation does not include it`
  );
}

console.log('PASS nav/status sync selftest');
