#!/usr/bin/env node
import assert from 'node:assert/strict';
import childProcess from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'polaris-static-evidence-'));

try {
  const source = path.join(tempDir, 'SAMPLE-123-pr-upload');
  const output = path.join(tempDir, 'output');
  const publicRoot = path.join(tempDir, 'public/evidence');
  fs.mkdirSync(path.join(source, 'nested'), { recursive: true });
  fs.writeFileSync(path.join(source, '01-open.png'), 'open-image\n');
  fs.writeFileSync(path.join(source, 'nested', '01-open.png'), 'collision-image\n');
  fs.writeFileSync(path.join(source, 'playwright-flow.webm'), 'video\n');
  fs.writeFileSync(path.join(source, 'verify.json'), '{"status":"PASS"}\n');
  fs.writeFileSync(path.join(source, 'notes.txt'), 'notes\n');
  fs.writeFileSync(path.join(source, 'README.md'), '# should be ignored\n');

  const result = JSON.parse(execNode([
    'scripts/distribute-static-evidence.mjs',
    '--source', source,
    '--output-dir', output,
    '--scope', 'SAMPLE-123',
    '--public-root', publicRoot,
    '--public-base', '/docs/evidence',
    '--clean',
  ]));

  assert.equal(result.items, 5);
  const links = readJson(path.join(output, 'links.json'));
  assert.equal(links.kind, 'polaris-static-evidence-links');
  assert.equal(links.scope, 'SAMPLE-123');
  assert.equal(links.images.length, 2);
  assert.equal(links.videos.length, 1);
  assert.equal(links.raw.length, 2);

  const imageNames = links.images.map((item) => path.basename(item.asset_path));
  assert.equal(new Set(imageNames).size, 2, 'image filenames should not collide');
  for (const item of links.items) {
    assert.ok(fs.existsSync(item.asset_path), `missing asset: ${item.asset_path}`);
    assert.match(item.sha256, /^[a-f0-9]{64}$/u);
    assert.equal(item.remote_publication_required, false);
  }

  const [video] = links.videos;
  assert.equal(video.public_url, `/docs/evidence/SAMPLE-123/${path.basename(video.asset_path)}`);
  assert.ok(fs.existsSync(video.public_path), 'video should be mirrored to public root');

  const publication = readJson(path.join(output, 'publication-manifest.json'));
  assert.equal(publication.kind, 'polaris-evidence-publication-manifest');
  assert.equal(publication.status, 'local_only');
  assert.equal(publication.artifacts.length, 3);
  assert.ok(publication.artifacts.every((item) => item.publication_required === false));

  console.log('PASS: distribute-static-evidence selftest');
} finally {
  fs.rmSync(tempDir, { recursive: true, force: true });
}

function execNode(args) {
  return childProcess.execFileSync(process.execPath, args, {
    cwd: root,
    encoding: 'utf8',
  });
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}
