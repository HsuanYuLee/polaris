#!/usr/bin/env node
import assert from 'node:assert/strict';
import http from 'node:http';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const scriptPath = fileURLToPath(new URL('./status-live-link-check.mjs', import.meta.url));

function createServer(mode) {
  return http.createServer((request, response) => {
    if (request.url === '/docs-manager/status/') {
      response.writeHead(200, { 'content-type': 'text/html' });
      const bodyLink = mode === 'fail'
        ? '<a href="/docs-manager/missing/">missing</a>'
        : '<a href="/docs-manager/specs/example/">ok</a>';
      response.end(`
        <html>
          <head>
            <link rel="icon" href="/docs-manager/favicon.svg">
            <link rel="sitemap" href="/docs-manager/sitemap-index.xml">
          </head>
          <body>${bodyLink}</body>
        </html>
      `);
      return;
    }
    if (request.url === '/docs-manager/specs/example/') {
      response.writeHead(200, { 'content-type': 'text/html' });
      response.end('ok');
      return;
    }
    response.writeHead(404, { 'content-type': 'text/plain' });
    response.end('missing');
  });
}

async function withServer(mode, fn) {
  const server = createServer(mode);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const { port } = server.address();
    return await fn(`http://127.0.0.1:${port}/docs-manager/status/`);
  } finally {
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
  }
}

function runChecker(url) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [scriptPath, url], { stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => {
      stdout += chunk;
    });
    child.stderr.on('data', (chunk) => {
      stderr += chunk;
    });
    child.on('close', (status) => resolve({ status, stdout, stderr }));
  });
}

await withServer('pass', async (url) => {
  const result = await runChecker(url);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /PASS: docs-manager status body links/);
});

await withServer('fail', async (url) => {
  const result = await runChecker(url);
  assert.equal(result.status, 1, result.stderr || result.stdout);
  assert.match(result.stderr, /missing/);
});

console.log('PASS status live link check selftest');
