#!/usr/bin/env node
import process from 'node:process';

const target = process.argv[2];

if (!target) {
  console.error('usage: status-live-link-check.mjs <status-page-url>');
  process.exit(2);
}

const statusUrl = new URL(target);
const response = await fetch(statusUrl, { redirect: 'manual' });
if (!response.ok) {
  console.error(`status page failed: ${statusUrl.href} -> ${response.status}`);
  process.exit(1);
}

const html = await response.text();
const bodyMatch = html.match(/<body\b[^>]*>([\s\S]*?)<\/body>/i);
const body = bodyMatch ? bodyMatch[1] : html;
const links = [...body.matchAll(/<a\b[^>]*\bhref=(["'])(.*?)\1/gi)]
  .map((match) => match[2].trim())
  .filter(Boolean)
  .filter((href) => !href.startsWith('#'))
  .map((href) => {
    try {
      return new URL(href, statusUrl);
    } catch {
      return null;
    }
  })
  .filter(Boolean)
  .filter((url) => url.origin === statusUrl.origin)
  .filter((url) => url.pathname.startsWith('/docs-manager/'));

const uniqueLinks = [...new Map(links.map((url) => [url.href, url])).values()];
const failures = [];

for (const url of uniqueLinks) {
  const linkResponse = await fetch(url, { redirect: 'manual' });
  if (linkResponse.status >= 400) {
    failures.push(`${url.href} -> ${linkResponse.status}`);
  }
}

if (failures.length > 0) {
  console.error('Status body links returned errors:');
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(`PASS: docs-manager status body links (${uniqueLinks.length} checked)`);
