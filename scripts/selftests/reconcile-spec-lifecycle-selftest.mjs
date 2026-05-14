import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { inferLifecycleReport } from '../reconcile-spec-lifecycle.mjs';

const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'polaris-lifecycle-reconcile-'));

try {
  const specsRoot = path.join(tempDir, 'specs');

  writeMarkdown(
    path.join(specsRoot, 'design-plans/DP-001-active/index.md'),
    { title: 'Active DP', status: 'LOCKED' },
    ['## Implementation Checklist', '', '- [ ] T1: Active task']
  );
  writeMarkdown(path.join(specsRoot, 'design-plans/DP-001-active/tasks/T1/index.md'), {
    title: 'T1 active',
    status: 'IN_PROGRESS',
  });

  writeMarkdown(path.join(specsRoot, 'design-plans/DP-002-terminal/index.md'), {
    title: 'Terminal DP',
    status: 'IMPLEMENTED',
  });

  writeMarkdown(
    path.join(specsRoot, 'design-plans/DP-003-checklist-blocked/index.md'),
    { title: 'Checklist Blocked DP', status: 'LOCKED' },
    ['## Implementation Checklist', '', '- [ ] Manual closeout']
  );
  writeMarkdown(path.join(specsRoot, 'design-plans/DP-003-checklist-blocked/tasks/pr-release/T1/index.md'), {
    title: 'Done task',
    status: 'IMPLEMENTED',
  });

  writeMarkdown(path.join(specsRoot, 'design-plans/DP-004-planned/index.md'), {
    title: 'Planned DP',
    status: 'LOCKED',
  });
  writeMarkdown(path.join(specsRoot, 'design-plans/DP-004-planned/tasks/T1/index.md'), {
    title: 'Planned task',
    status: 'PLANNED',
  });

  const report = inferLifecycleReport({ specsRoot, sweep: true });
  const items = new Map(report.items.map((item) => [item.id, item]));

  assert.equal(items.get('DP-001-active')?.derivedStatus, 'implementing');
  assert.equal(items.get('DP-002-terminal')?.archiveEligible, true);
  assert.equal(items.get('DP-003-checklist-blocked')?.derivedStatus, 'locked');
  assert.deepEqual(items.get('DP-003-checklist-blocked')?.blockers, ['parent-checklist-open']);
  assert.equal(items.get('DP-004-planned')?.tasks.byStatus.planned, 1);
  assert.equal(report.summary.archiveEligible, 1);
  assert.equal(report.summary.statusMismatches, 1);

  const single = inferLifecycleReport({ specsRoot, source: 'DP-002-terminal' });
  assert.equal(single.items.length, 1);
  assert.equal(single.items[0].id, 'DP-002-terminal');

  console.log('PASS reconcile spec lifecycle selftest');
} finally {
  fs.rmSync(tempDir, { recursive: true, force: true });
}

function writeMarkdown(file, frontmatter, bodyLines = ['Body']) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const yaml = Object.entries(frontmatter)
    .map(([key, value]) => `${key}: ${JSON.stringify(value)}`)
    .join('\n');
  fs.writeFileSync(file, `---\n${yaml}\n---\n\n${bodyLines.join('\n')}\n`);
}
