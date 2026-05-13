import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  groupDashboardItems,
  inferStatusDashboard,
  primaryLink,
  publicationSummary,
  reportSummary,
  verificationSummary,
  verifyReportLink,
} from '../src/status/index.mjs';

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
  writeMarkdown(path.join(specsRoot, 'design-plans/DP-002-folder-native/index.md'), {
    title: 'Folder Native DP',
    status: 'LOCKED',
    priority: 'P1',
  });
  writeMarkdown(path.join(specsRoot, 'design-plans/DP-002-folder-native/verify-report.md'), {
    title: 'Folder Native Verify Report',
    description: 'Report',
  });
  writeJson(path.join(specsRoot, 'design-plans/DP-002-folder-native/publication-manifest.json'), {
    status: 'published',
  });
  writeMarkdown(path.join(specsRoot, 'design-plans/DP-002-folder-native/tasks/T1/index.md'), {
    title: 'Folder Native Task',
    status: 'IN_PROGRESS',
    verification: {
      behavior_contract: {
        applies: true,
        mode: 'hybrid',
        source_of_truth: 'spec',
        fixture_policy: 'live_allowed',
      },
      visual_regression: {
        expected: 'none_allowed',
      },
    },
  });
  writeMarkdown(path.join(specsRoot, 'design-plans/DP-002-folder-native/tasks/V1/index.md'), {
    title: 'Folder Native Verification',
    status: 'BLOCKED',
  });
  writeMarkdown(path.join(specsRoot, 'design-plans/archive/DP-999-archived/plan.md'), {
    title: 'Archived DP',
    status: 'LOCKED',
  });
  writeMarkdown(path.join(specsRoot, 'companies/acme/ACME-1/refinement.md'), {
    title: 'Unknown Status Spec',
    status: 'NEEDS_MAGIC',
  });
  writeMarkdown(path.join(specsRoot, 'companies/acme/BUG-1/index.md'), {
    title: 'Bug — Checkout error',
    status: 'DISCUSSION',
    jira_issue_type: 'Bug',
  });
  writeMarkdown(path.join(specsRoot, 'companies/acme/BUG-1/evidence/20260514-newer-evidence.md'), {
    title: 'Newer Evidence',
  });
  writeRawMarkdown(
    path.join(specsRoot, 'companies/acme/BUG-1/status-updates/20260513-1100-validation.md'),
    `---
title: "Status update - BUG-1"
phase: validating
summary: "Checkout fix is waiting for validation."
next_owner: "QA"
next_action: "Check checkout error rate after deploy."
waiting_until: 2026-05-12
evidence:
  - "evidence/20260514-newer-evidence.md"
external_refs:
  - type: jira_comment
    id: "12345"
---

Body
`
  );
  fs.mkdirSync(path.join(specsRoot, 'companies/acme/ACME-2/tasks'), { recursive: true });
  writeMarkdown(path.join(specsRoot, 'companies/acme/ACME-2/tasks/T1.md'), {
    title: 'Missing artifact task',
  });

  const dashboard = inferStatusDashboard({ specsRoot, today: '2026-05-13' });
  const groups = groupDashboardItems(dashboard.items);
  const itemsById = new Map(dashboard.items.map((item) => [item.id, item]));

  assert.equal(dashboard.items.length, 5);
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
  assert.equal(itemsById.get('BUG-1')?.issueType, 'Bug');
  assert.equal(itemsById.get('BUG-1')?.derivedPhase, 'validating');
  assert.equal(itemsById.get('BUG-1')?.statusSummary, 'Checkout fix is waiting for validation.');
  assert.equal(itemsById.get('BUG-1')?.nextOwner, 'QA');
  assert.equal(itemsById.get('BUG-1')?.nextAction, 'Check checkout error rate after deploy.');
  assert.equal(itemsById.get('BUG-1')?.waitingUntil, '2026-05-12');
  assert.equal(
    itemsById.get('BUG-1')?.latestStatusUpdate?.path,
    'companies/acme/BUG-1/status-updates/20260513-1100-validation.md'
  );
  assert.deepEqual(itemsById.get('BUG-1')?.evidenceLinks?.map((link) => link.path), [
    'companies/acme/BUG-1/evidence/20260514-newer-evidence.md',
  ]);
  assert.deepEqual(itemsById.get('BUG-1')?.externalRefs, [
    { type: 'jira_comment', id: '12345', url: null },
  ]);
  assert.deepEqual(itemsById.get('BUG-1')?.staleSignals, [
    'waiting-window-expired',
    'evidence-newer-than-status-update',
  ]);
  assert.deepEqual(groups.companyBugs.map((item) => item.id), ['BUG-1']);
  assert(!groups.companySpecs.some((item) => item.id === 'BUG-1'));

  assert.equal(itemsById.get('ACME-2')?.status, 'unknown');
  assert.deepEqual(itemsById.get('ACME-2')?.blockers, ['missing-primary-artifact']);
  assert.equal(itemsById.get('ACME-2')?.tasks.byStatus.unknown, 1);

  const folderNative = itemsById.get('DP-002-folder-native');
  assert.equal(folderNative?.artifact?.name, 'index.md');
  assert.equal(primaryLink(folderNative, '/docs-manager'), '/docs-manager/specs/design-plans/dp-002-folder-native/');
  assert.equal(
    verifyReportLink(folderNative, '/docs-manager'),
    '/docs-manager/specs/design-plans/dp-002-folder-native/verify-report/'
  );
  assert.deepEqual(folderNative?.tasks, {
    total: 2,
    byStatus: {
      implemented: 0,
      in_progress: 1,
      blocked: 1,
      unknown: 0,
    },
  });
  assert.equal(reportSummary(folderNative, 'en'), 'Latest report');
  assert.equal(publicationSummary(folderNative, 'en'), 'Published');
  assert.match(verificationSummary(folderNative, 'en'), /Hybrid behavior check/);
  assert.match(verificationSummary(folderNative, 'en'), /No visual differences allowed/);

  writeMarkdown(path.join(specsRoot, 'design-plans/DP-003-invalid-phase/index.md'), {
    title: 'Invalid Phase DP',
    status: 'LOCKED',
  });
  writeRawMarkdown(
    path.join(specsRoot, 'design-plans/DP-003-invalid-phase/status-updates/20260513-1100-invalid.md'),
    `---
title: "Invalid status update"
phase: waiting
summary: "Invalid phase."
next_owner: "RD"
next_action: "Fix phase."
---

Body
`
  );
  assert.throws(
    () => inferStatusDashboard({ specsRoot }),
    /unknown status update phase/
  );
  fs.rmSync(path.join(specsRoot, 'design-plans/DP-003-invalid-phase'), { recursive: true, force: true });

  writeMarkdown(path.join(specsRoot, 'design-plans/DP-004-missing-next-action/index.md'), {
    title: 'Missing Next Action DP',
    status: 'LOCKED',
  });
  writeRawMarkdown(
    path.join(specsRoot, 'design-plans/DP-004-missing-next-action/status-updates/20260513-1100-missing.md'),
    `---
title: "Missing next action"
phase: validating
summary: "Missing next action."
next_owner: "RD"
---

Body
`
  );
  assert.throws(
    () => inferStatusDashboard({ specsRoot }),
    /missing required status update field: next_action/
  );
  fs.rmSync(path.join(specsRoot, 'design-plans/DP-004-missing-next-action'), { recursive: true, force: true });

  writeMarkdown(path.join(specsRoot, 'design-plans/DP-005-missing-evidence/index.md'), {
    title: 'Missing Evidence DP',
    status: 'LOCKED',
  });
  writeRawMarkdown(
    path.join(specsRoot, 'design-plans/DP-005-missing-evidence/status-updates/20260513-1100-missing-evidence.md'),
    `---
title: "Missing evidence"
phase: validating
summary: "Missing evidence."
next_owner: "RD"
next_action: "Inspect missing evidence."
evidence:
  - "evidence/missing.md"
---

Body
`
  );
  assert.throws(
    () => inferStatusDashboard({ specsRoot }),
    /evidence path does not exist/
  );
  fs.rmSync(path.join(specsRoot, 'design-plans/DP-005-missing-evidence'), { recursive: true, force: true });

  writeMarkdown(path.join(specsRoot, 'design-plans/DP-006-unknown-enum/index.md'), {
    title: 'Unknown Enum DP',
    status: 'LOCKED',
  });
  writeMarkdown(path.join(specsRoot, 'design-plans/DP-006-unknown-enum/tasks/T1/index.md'), {
    title: 'Unknown Enum Task',
    verification: {
      behavior_contract: {
        applies: true,
        mode: 'unknown',
        source_of_truth: 'spec',
        fixture_policy: 'live_allowed',
      },
    },
  });
  assert.throws(
    () => inferStatusDashboard({ specsRoot }),
    /unknown behavior_contract\.mode/
  );

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

function writeRawMarkdown(file, source) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, source);
}

function writeMarkdown(file, frontmatter) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const yaml = toYaml(frontmatter);
  fs.writeFileSync(file, `---\n${yaml}\n---\n\nBody\n`);
}

function writeJson(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(data, null, 2)}\n`);
}

function toYaml(value, indent = 0) {
  return Object.entries(value)
    .map(([key, entry]) => {
      const padding = ' '.repeat(indent);
      if (entry && typeof entry === 'object' && !Array.isArray(entry)) {
        return `${padding}${key}:\n${toYaml(entry, indent + 2)}`;
      }
      return `${padding}${key}: ${JSON.stringify(entry)}`;
    })
    .join('\n');
}
