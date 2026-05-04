import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { inferStatusDashboard } from '../src/status/index.mjs';

const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'polaris-status-dashboard-'));
const originalCwd = process.cwd();

try {
  const specsRoot = path.join(tempDir, 'specs');

  writeMarkdown(path.join(specsRoot, 'design-plans/DP-001-active/plan.md'), {
    title: 'Active DP',
    status: 'LOCKED',
    priority: 'P2',
  });
  writeMarkdown(path.join(specsRoot, 'design-plans/DP-001-active/tasks/T1.md'), {
    title: 'T1 active',
    status: 'IN_PROGRESS',
  });
  writeMarkdown(path.join(specsRoot, 'design-plans/DP-001-active/tasks/T2.md'), {
    title: 'T2 done',
    status: 'IMPLEMENTED',
  });
  writeMarkdown(path.join(specsRoot, 'design-plans/archive/DP-999-archived/plan.md'), {
    title: 'Archived DP',
    status: 'LOCKED',
  });
  writeMarkdown(path.join(specsRoot, 'companies/acme/ACME-1/refinement.md'), {
    title: 'Unknown Status Spec',
    status: 'NEEDS_MAGIC',
  });
  fs.mkdirSync(path.join(specsRoot, 'companies/acme/ACME-2/tasks'), { recursive: true });
  writeMarkdown(path.join(specsRoot, 'companies/acme/ACME-2/tasks/T1.md'), {
    title: 'Missing artifact task',
  });

  const dashboard = inferStatusDashboard({ specsRoot });
  const itemsById = new Map(dashboard.items.map((item) => [item.id, item]));

  assert.equal(dashboard.items.length, 3);
  assert.equal(itemsById.has('DP-999-archived'), false);

  assert.equal(itemsById.get('DP-001-active')?.status, 'locked');
  assert.deepEqual(itemsById.get('DP-001-active')?.tasks, {
    total: 2,
    byStatus: {
      implemented: 1,
      in_progress: 1,
      blocked: 0,
      unknown: 0,
    },
  });

  assert.equal(itemsById.get('ACME-1')?.status, 'unknown');
  assert.deepEqual(itemsById.get('ACME-1')?.blockers, ['unknown-status']);

  assert.equal(itemsById.get('ACME-2')?.status, 'unknown');
  assert.deepEqual(itemsById.get('ACME-2')?.blockers, ['missing-primary-artifact']);
  assert.equal(itemsById.get('ACME-2')?.tasks.byStatus.unknown, 1);

  const docsManagerRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  process.chdir(docsManagerRoot);
  const defaultDashboard = inferStatusDashboard();
  assert.equal(
    defaultDashboard.specsRoot,
    path.join(docsManagerRoot, 'src/content/docs/specs')
  );

  console.log('PASS status dashboard inference');
} finally {
  process.chdir(originalCwd);
  fs.rmSync(tempDir, { recursive: true, force: true });
}

function writeMarkdown(file, frontmatter) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const yaml = Object.entries(frontmatter)
    .map(([key, value]) => `${key}: ${JSON.stringify(value)}`)
    .join('\n');
  fs.writeFileSync(file, `---\n${yaml}\n---\n\nBody\n`);
}
