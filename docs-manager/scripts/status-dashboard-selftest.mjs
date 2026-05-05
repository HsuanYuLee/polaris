import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
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

  assert.equal(dashboard.items.length, 4);
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

  const folderNative = itemsById.get('DP-002-folder-native');
  assert.equal(folderNative?.artifact?.name, 'index.md');
  assert.equal(primaryLink(folderNative, '/docs-manager'), '/docs-manager/specs/design-plans/dp-002-folder-native/');
  assert.equal(
    verifyReportLink(folderNative, '/docs-manager'),
    '/docs-manager/specs/design-plans/dp-002-folder-native/verify-report/'
  );
  assert.deepEqual(folderNative?.tasks, {
    total: 1,
    byStatus: {
      implemented: 0,
      in_progress: 1,
      blocked: 0,
      unknown: 0,
    },
  });
  assert.equal(reportSummary(folderNative, 'en'), 'Latest report');
  assert.equal(publicationSummary(folderNative, 'en'), 'Published');
  assert.match(verificationSummary(folderNative, 'en'), /Hybrid behavior check/);
  assert.match(verificationSummary(folderNative, 'en'), /No visual differences allowed/);

  writeMarkdown(path.join(specsRoot, 'design-plans/DP-003-unknown-enum/index.md'), {
    title: 'Unknown Enum DP',
    status: 'LOCKED',
  });
  writeMarkdown(path.join(specsRoot, 'design-plans/DP-003-unknown-enum/tasks/T1/index.md'), {
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
