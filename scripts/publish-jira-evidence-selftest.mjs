#!/usr/bin/env node
import childProcess from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';

const repoRoot = path.resolve(path.join(path.dirname(new URL(import.meta.url).pathname), '..'));
const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'polaris-publish-jira-evidence-'));

try {
  testDryRun();
  testApplyWritesAttachmentUrls();
  testBlockedArtifact();
  testMissingJiraKey();
  console.log('PASS: publish-jira-evidence selftest');
} finally {
  fs.rmSync(tempRoot, { recursive: true, force: true });
}

function testDryRun() {
  const bundle = createBundle('dry-run');
  const result = runPublisher([
    '--repo', repoRoot,
    '--manifest', bundle.manifest,
    '--links', bundle.links,
    '--jira-key', 'PROJ-123',
    '--dry-run',
  ]);
  assert(result.status === 0, `dry-run should pass: ${result.stderr}`);
  const output = JSON.parse(result.stdout);
  assert(output.status === 'dry_run', 'dry-run output status mismatch');
  const manifest = readJson(bundle.manifest);
  assert(manifest.remote_publication.status === 'dry_run', 'manifest dry-run status mismatch');
  assert(manifest.remote_publication.planned_count === 2, 'dry-run planned count mismatch');
}

function testApplyWritesAttachmentUrls() {
  const bundle = createBundle('apply');
  const uploader = path.join(bundle.dir, 'mock-uploader.sh');
  fs.writeFileSync(uploader, `#!/usr/bin/env bash
set -euo pipefail
issue="$1"
shift
for file in "$@"; do
  name="$(basename "$file")"
  printf '{"filename":"%s","id":"att-%s","url":"https://jira.example/attachments/%s/%s","mimeType":"application/octet-stream"}\\n' "$name" "$name" "$issue" "$name"
done
`, 'utf8');
  fs.chmodSync(uploader, 0o755);

  const result = runPublisher([
    '--repo', repoRoot,
    '--manifest', bundle.manifest,
    '--links', bundle.links,
    '--jira-key', 'PROJ-123',
    '--apply',
    '--uploader', uploader,
    '--report', bundle.report,
  ]);
  assert(result.status === 0, `apply should pass: ${result.stderr}`);
  const manifest = readJson(bundle.manifest);
  assert(manifest.remote_publication.status === 'uploaded', 'apply manifest status mismatch');
  const attachmentUrls = manifest.artifacts.map((item) => item.jira_attachment?.url).filter(Boolean);
  assert(attachmentUrls.length === 2, 'expected two attachment URLs');
  const report = fs.readFileSync(bundle.report, 'utf8');
  assert(report.includes('## Jira Attachments'), 'report should include Jira section');
  assert(report.includes('https://jira.example/attachments/PROJ-123/screenshot.png'), 'report should include attachment URL');
}

function testBlockedArtifact() {
  const bundle = createBundle('blocked');
  const manifest = readJson(bundle.manifest);
  manifest.artifacts.push({
    id: 'raw-secret',
    kind: 'raw',
    filename: 'secret.json',
    local_link: './assets/raw/secret.json',
    requires_publication: true,
    publishable: true,
  });
  fs.mkdirSync(path.join(bundle.dir, 'assets/raw'), { recursive: true });
  fs.writeFileSync(path.join(bundle.dir, 'assets/raw/secret.json'), '{"token":"abcdef1234567890"}\n', 'utf8');
  fs.writeFileSync(bundle.manifest, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');

  const result = runPublisher([
    '--repo', repoRoot,
    '--manifest', bundle.manifest,
    '--links', bundle.links,
    '--jira-key', 'PROJ-123',
    '--dry-run',
  ]);
  assert(result.status === 2, 'blocked artifact should fail-stop');
  const updated = readJson(bundle.manifest);
  assert(updated.remote_publication.status === 'blocked', 'blocked manifest status mismatch');
}

function testMissingJiraKey() {
  const bundle = createBundle('missing-jira');
  const result = runPublisher([
    '--repo', repoRoot,
    '--manifest', bundle.manifest,
    '--links', bundle.links,
    '--dry-run',
  ]);
  assert(result.status === 0, `missing Jira key should become local_only: ${result.stderr}`);
  const manifest = readJson(bundle.manifest);
  assert(manifest.remote_publication.status === 'local_only', 'missing Jira key status mismatch');
}

function createBundle(name) {
  const dir = path.join(tempRoot, name);
  fs.mkdirSync(path.join(dir, 'assets/screenshots'), { recursive: true });
  fs.mkdirSync(path.join(dir, 'assets/videos'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'assets/screenshots/screenshot.png'), 'fake-png\n', 'utf8');
  fs.writeFileSync(path.join(dir, 'assets/videos/behavior.webm'), 'fake-webm\n', 'utf8');
  const links = {
    schema_version: 1,
    kind: 'polaris-static-evidence-links',
    scope: name,
    items: [
      {
        id: 'image-1',
        kind: 'image',
        asset_path: path.join(dir, 'assets/screenshots/screenshot.png'),
        relative_link: './assets/screenshots/screenshot.png',
        remote_publication_required: true,
        publishable: true,
      },
      {
        id: 'video-1',
        kind: 'video',
        asset_path: path.join(dir, 'assets/videos/behavior.webm'),
        relative_link: './assets/videos/behavior.webm',
        remote_publication_required: true,
        publishable: true,
      },
    ],
  };
  const manifest = {
    schema_version: 1,
    kind: 'polaris-evidence-publication-manifest',
    scope: name,
    status: 'local_only',
    artifacts: [
      {
        id: 'image-1',
        kind: 'image',
        filename: 'screenshot.png',
        local_link: './assets/screenshots/screenshot.png',
        requires_publication: true,
        publishable: true,
      },
      {
        id: 'video-1',
        kind: 'video',
        filename: 'behavior.webm',
        local_link: './assets/videos/behavior.webm',
        requires_publication: true,
        publishable: true,
      },
      {
        id: 'image-skipped',
        kind: 'image',
        filename: 'optional.png',
        local_link: './assets/screenshots/optional.png',
        requires_publication: false,
        publishable: false,
      },
    ],
  };
  const linksPath = path.join(dir, 'links.json');
  const manifestPath = path.join(dir, 'publication-manifest.json');
  const reportPath = path.join(dir, 'verify-report.md');
  fs.writeFileSync(linksPath, `${JSON.stringify(links, null, 2)}\n`, 'utf8');
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
  fs.writeFileSync(reportPath, '---\ntitle: "Verify Report"\n---\n\n## Summary\n\n- Status: `LOCAL_EVIDENCE`\n', 'utf8');
  return { dir, links: linksPath, manifest: manifestPath, report: reportPath };
}

function runPublisher(args) {
  return childProcess.spawnSync('node', [path.join(repoRoot, 'scripts/publish-jira-evidence.mjs'), ...args], {
    cwd: repoRoot,
    encoding: 'utf8',
  });
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}
