#!/usr/bin/env node
import assert from 'node:assert/strict';
import childProcess from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'polaris-verify-report-'));

try {
  const source = path.join(tempDir, 'bundle');
  const output = path.join(tempDir, 'report-source');
  const publicRoot = path.join(tempDir, 'public/evidence');
  fs.mkdirSync(source, { recursive: true });
  fs.writeFileSync(path.join(source, 'open.png'), 'image\n');
  fs.writeFileSync(path.join(source, 'playwright-flow.webm'), 'video\n');
  fs.writeFileSync(path.join(source, 'verify.json'), '{"status":"PASS"}\n');

  execNode([
    'scripts/distribute-static-evidence.mjs',
    '--source', source,
    '--output-dir', output,
    '--scope', 'SAMPLE-123',
    '--public-root', publicRoot,
    '--public-base', '/docs/evidence',
  ]);

  const reportPath = path.join(output, 'verify-report.md');
  const result = JSON.parse(execNode([
    'scripts/generate-verify-report.mjs',
    '--links', path.join(output, 'links.json'),
    '--output', reportPath,
    '--title', 'Verify Report - SAMPLE-123',
    '--description', 'Verification evidence report for SAMPLE-123.',
    '--status', 'PASS',
  ]));

  assert.equal(result.images, 1);
  assert.equal(result.videos, 1);
  const report = fs.readFileSync(reportPath, 'utf8');
  assert.match(report, /^---\ntitle: "Verify Report - SAMPLE-123"\ndescription: "Verification evidence report for SAMPLE-123\."\n---/u);
  assert.match(report, /## Screenshots/u);
  assert.match(report, /!\[open\]\(\.\/assets\/screenshots\/open\.png\)/u);
  assert.match(report, /\[playwright-flow\.webm\]\(\/docs\/evidence\/SAMPLE-123\/playwright-flow\.webm\)/u);
  assert.doesNotMatch(report, /<video/iu);
  assert.match(report, /\[verify\.json\]\(\.\/assets\/raw\/verify\.json\)/u);

  console.log('PASS: generate-verify-report selftest');
} finally {
  fs.rmSync(tempDir, { recursive: true, force: true });
}

function execNode(args) {
  return childProcess.execFileSync(process.execPath, args, {
    cwd: root,
    encoding: 'utf8',
  });
}
