import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { applyLifecycleReport, inferLifecycleReport } from '../reconcile-spec-lifecycle.mjs';

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

  writeMarkdown(
    path.join(specsRoot, 'design-plans/DP-005-complete/index.md'),
    { title: 'Complete DP', status: 'IMPLEMENTING' },
    ['## Implementation Checklist', '', '- [x] T1: Done']
  );
  writeMarkdown(path.join(specsRoot, 'design-plans/DP-005-complete/tasks/pr-release/T1/index.md'), {
    title: 'Done task',
    status: 'IMPLEMENTED',
  });

  const report = inferLifecycleReport({ specsRoot, sweep: true });
  const items = new Map(report.items.map((item) => [item.id, item]));

  assert.equal(items.get('DP-001-active')?.derivedStatus, 'implementing');
  assert.deepEqual(items.get('DP-001-active')?.actions, [
    { type: 'update-status', status: 'IMPLEMENTING', blocked: false },
  ]);
  assert.equal(items.get('DP-002-terminal')?.archiveEligible, true);
  assert.equal(items.get('DP-003-checklist-blocked')?.derivedStatus, 'locked');
  assert.deepEqual(items.get('DP-003-checklist-blocked')?.blockers, ['parent-checklist-open']);
  assert.equal(items.get('DP-004-planned')?.tasks.byStatus.planned, 1);
  assert.equal(report.summary.archiveEligible, 1);
  assert.equal(items.get('DP-005-complete')?.derivedStatus, 'implemented');
  assert.equal(report.summary.statusMismatches, 2);

  const single = inferLifecycleReport({ specsRoot, source: 'DP-002-terminal' });
  assert.equal(single.items.length, 1);
  assert.equal(single.items[0].id, 'DP-002-terminal');

  const byPath = inferLifecycleReport({
    specsRoot,
    source: path.join(specsRoot, 'design-plans/DP-001-active/index.md'),
  });
  assert.equal(byPath.items.length, 1);
  assert.equal(byPath.items[0].id, 'DP-001-active');

  const activeApply = applyLifecycleReport({ specsRoot, source: 'DP-001-active' });
  assert.equal(activeApply.applyResults[0].actions[0].result, 'applied');
  assert.match(
    fs.readFileSync(path.join(specsRoot, 'design-plans/DP-001-active/index.md'), 'utf8'),
    /^status: IMPLEMENTING$/m
  );

  const blockedApply = applyLifecycleReport({ specsRoot, source: 'DP-003-checklist-blocked' });
  assert.equal(blockedApply.applyResults[0].actions[0].result, 'skipped');
  assert.match(
    fs.readFileSync(path.join(specsRoot, 'design-plans/DP-003-checklist-blocked/index.md'), 'utf8'),
    /^status:\s+"?LOCKED"?$/m
  );

  const completeApply = applyLifecycleReport({ specsRoot, source: 'DP-005-complete', today: '2026-05-15' });
  assert.equal(completeApply.applyResults[0].actions[0].result, 'applied');
  const completeText = fs.readFileSync(path.join(specsRoot, 'design-plans/DP-005-complete/index.md'), 'utf8');
  assert.match(completeText, /^status: IMPLEMENTED$/m);
  assert.match(completeText, /^implemented_at: 2026-05-15$/m);

  const archiveApply = applyLifecycleReport({ specsRoot, source: 'DP-002-terminal' });
  assert.equal(archiveApply.applyResults[0].actions[0].type, 'archive');
  assert.equal(archiveApply.applyResults[0].actions[0].result, 'applied');
  assert.equal(fs.existsSync(path.join(specsRoot, 'design-plans/DP-002-terminal')), false);
  assert.equal(fs.existsSync(path.join(specsRoot, 'design-plans/archive/DP-002-terminal/index.md')), true);

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
