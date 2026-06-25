#!/usr/bin/env node
// Purpose: assert reconcile-spec-lifecycle + status/inference認列 ABANDONED/SUPERSEDED
//          task 為 terminal-resolved sibling，使含 terminal-resolved sibling 的 parent
//          能 derive/寫出 IMPLEMENTED；只含 terminal-resolved (realImplementable===0)
//          或 genuinely-incomplete sibling 仍不 close。直接 import 真實 module（無 fake
//          shim），並 end-to-end 跑真實 close-parent-spec-if-complete.sh。
// Inputs:  none (builds temp specs fixtures under os.tmpdir()).
// Outputs: stdout PASS line; exit 0 PASS / exit 1 FAIL (assert throws).
// Covers:  AC1 / AC2 / AC-NF1 / AC-NEG1 / AC-NEG2 / AC-NEG3.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { applyLifecycleReport, inferLifecycleReport } from '../reconcile-spec-lifecycle.mjs';
import { collectStatusItems } from '../../docs-manager/src/status/inference.mjs';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(SCRIPT_DIR, '../..');
const CLOSE_PARENT = path.join(REPO_ROOT, 'scripts', 'close-parent-spec-if-complete.sh');

const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'polaris-terminal-resolved-'));

try {
  // ---------------------------------------------------------------------------
  // AC1: N implemented pr-release tasks + 1 ABANDONED sibling (kept under tasks/)
  //      → derives implemented and writes IMPLEMENTED. Covers ABANDONED variant.
  // ---------------------------------------------------------------------------
  {
    const specsRoot = path.join(tempDir, 'ac1-abandoned', 'specs');
    writeMarkdown(
      path.join(specsRoot, 'design-plans/DP-101-abandoned-sibling/index.md'),
      { title: 'Abandoned Sibling DP', status: 'IMPLEMENTING' }
    );
    writeMarkdown(
      path.join(specsRoot, 'design-plans/DP-101-abandoned-sibling/tasks/pr-release/T1/index.md'),
      { title: 'T1 done', status: 'IMPLEMENTED' }
    );
    writeMarkdown(
      path.join(specsRoot, 'design-plans/DP-101-abandoned-sibling/tasks/pr-release/T2/index.md'),
      { title: 'T2 done', status: 'IMPLEMENTED' }
    );
    // ABANDONED sibling stays under tasks/ (not pr-release/), per AC-NEG13 carve-out.
    writeMarkdown(
      path.join(specsRoot, 'design-plans/DP-101-abandoned-sibling/tasks/T3/index.md'),
      { title: 'T3 abandoned', status: 'ABANDONED' }
    );

    const report = inferLifecycleReport({ specsRoot, source: 'DP-101-abandoned-sibling' });
    const item = report.items.find((i) => i.id === 'DP-101-abandoned-sibling');
    assert.ok(item, 'AC1 abandoned: DP item should be present');
    assert.equal(
      item.derivedStatus,
      'implemented',
      'AC1 abandoned: parent with implemented siblings + ABANDONED sibling must derive implemented (RED before fix)'
    );

    const applied = applyLifecycleReport({
      specsRoot,
      source: 'DP-101-abandoned-sibling',
      archive: false,
      today: '2026-06-26',
    });
    assert.equal(
      applied.applyResults[0].actions[0].result,
      'applied',
      'AC1 abandoned: status update should be applied'
    );
    assert.match(
      fs.readFileSync(
        path.join(specsRoot, 'design-plans/DP-101-abandoned-sibling/index.md'),
        'utf8'
      ),
      /^status: IMPLEMENTED$/m,
      'AC1 abandoned: parent index.md must be written IMPLEMENTED'
    );
  }

  // ---------------------------------------------------------------------------
  // AC1 (SUPERSEDED variant): N implemented + 1 SUPERSEDED sibling → IMPLEMENTED.
  // ---------------------------------------------------------------------------
  {
    const specsRoot = path.join(tempDir, 'ac1-superseded', 'specs');
    writeMarkdown(
      path.join(specsRoot, 'design-plans/DP-102-superseded-sibling/index.md'),
      { title: 'Superseded Sibling DP', status: 'IMPLEMENTING' }
    );
    writeMarkdown(
      path.join(specsRoot, 'design-plans/DP-102-superseded-sibling/tasks/pr-release/T1/index.md'),
      { title: 'T1 done', status: 'IMPLEMENTED' }
    );
    writeMarkdown(
      path.join(specsRoot, 'design-plans/DP-102-superseded-sibling/tasks/T2/index.md'),
      { title: 'T2 superseded', status: 'SUPERSEDED' }
    );

    const report = inferLifecycleReport({ specsRoot, source: 'DP-102-superseded-sibling' });
    const item = report.items.find((i) => i.id === 'DP-102-superseded-sibling');
    assert.ok(item, 'AC1 superseded: DP item should be present');
    assert.equal(
      item.derivedStatus,
      'implemented',
      'AC1 superseded: parent with implemented sibling + SUPERSEDED sibling must derive implemented (RED before fix)'
    );

    const applied = applyLifecycleReport({
      specsRoot,
      source: 'DP-102-superseded-sibling',
      archive: false,
      today: '2026-06-26',
    });
    assert.equal(applied.applyResults[0].actions[0].result, 'applied', 'AC1 superseded: applied');
    assert.match(
      fs.readFileSync(
        path.join(specsRoot, 'design-plans/DP-102-superseded-sibling/index.md'),
        'utf8'
      ),
      /^status: IMPLEMENTED$/m,
      'AC1 superseded: parent index.md must be written IMPLEMENTED'
    );
  }

  // ---------------------------------------------------------------------------
  // AC2: byStatus.abandoned===1 and byStatus.superseded===1; neither counted in
  //      byStatus.unknown. Asserted directly against inference.mjs summarizeTasks.
  // ---------------------------------------------------------------------------
  {
    const specsRoot = path.join(tempDir, 'ac2-buckets', 'specs');
    writeMarkdown(
      path.join(specsRoot, 'design-plans/DP-103-bucket-mix/index.md'),
      { title: 'Bucket Mix DP', status: 'IMPLEMENTING' }
    );
    writeMarkdown(
      path.join(specsRoot, 'design-plans/DP-103-bucket-mix/tasks/pr-release/T1/index.md'),
      { title: 'T1 done', status: 'IMPLEMENTED' }
    );
    writeMarkdown(
      path.join(specsRoot, 'design-plans/DP-103-bucket-mix/tasks/T2/index.md'),
      { title: 'T2 abandoned', status: 'ABANDONED' }
    );
    writeMarkdown(
      path.join(specsRoot, 'design-plans/DP-103-bucket-mix/tasks/T3/index.md'),
      { title: 'T3 superseded', status: 'SUPERSEDED' }
    );

    const items = collectStatusItems(specsRoot);
    const item = items.find((i) => i.id === 'DP-103-bucket-mix');
    assert.ok(item, 'AC2: DP item should be present');
    const byStatus = item.tasks.byStatus;
    assert.equal(byStatus.abandoned, 1, 'AC2: byStatus.abandoned must be 1 (RED: no bucket before fix)');
    assert.equal(byStatus.superseded, 1, 'AC2: byStatus.superseded must be 1 (RED: no bucket before fix)');
    assert.equal(byStatus.unknown, 0, 'AC2: abandoned/superseded must not fall through to unknown');
    assert.equal(item.tasks.total, 3, 'AC2: total task count is 3');
  }

  // ---------------------------------------------------------------------------
  // AC-NF1: end-to-end. close-parent decider emits action=close (AC-NEG13) and
  //         delegates the status write to the real reconciler. Assert parent
  //         IMPLEMENTED + archived.
  // ---------------------------------------------------------------------------
  {
    // Resolve the physical path so `cd && pwd` (close-parent) and Python's
    // Path.resolve() (its decider) agree on macOS, where /var symlinks to
    // /private/var. The reconciler matches source by relative path, so a
    // /var vs /private/var mismatch would produce "expected exactly one spec".
    const workspaceRootRaw = path.join(tempDir, 'ac-nf1-e2e');
    fs.mkdirSync(workspaceRootRaw, { recursive: true });
    const workspaceRoot = fs.realpathSync(workspaceRootRaw);
    const specsRoot = path.join(workspaceRoot, 'docs-manager/src/content/docs/specs');
    const dpDir = path.join(specsRoot, 'design-plans/DP-104-e2e-abandoned');
    // archive-spec.sh validates collection shape: every page needs `description`.
    writeMarkdown(path.join(dpDir, 'index.md'), {
      title: 'E2E Abandoned DP',
      description: 'DP-366-T1 e2e abandoned-sibling closeout fixture.',
      status: 'IMPLEMENTING',
    });
    writeMarkdown(path.join(dpDir, 'tasks/pr-release/T1/index.md'), {
      title: 'T1 done',
      description: 'DP-366-T1 e2e implemented sibling fixture.',
      status: 'IMPLEMENTED',
    });
    writeMarkdown(path.join(dpDir, 'tasks/T2/index.md'), {
      title: 'T2 abandoned',
      description: 'DP-366-T1 e2e abandoned sibling fixture.',
      status: 'ABANDONED',
    });

    const releaseTask = path.join(dpDir, 'tasks/pr-release/T1/index.md');
    const result = spawnSync(
      'bash',
      [CLOSE_PARENT, '--task-md', releaseTask, '--workspace', workspaceRoot, '--archive-terminal-parent'],
      { encoding: 'utf8' }
    );
    assert.equal(
      result.status,
      0,
      `AC-NF1: close-parent should exit 0; stderr=${result.stderr}\nstdout=${result.stdout}`
    );
    // Parent must be archived (moved out of active design-plans tree) and IMPLEMENTED.
    const archivedParent = path.join(specsRoot, 'design-plans/archive/DP-104-e2e-abandoned/index.md');
    assert.equal(
      fs.existsSync(path.join(dpDir, 'index.md')),
      false,
      'AC-NF1: parent must no longer be in active design-plans tree (archived)'
    );
    assert.equal(
      fs.existsSync(archivedParent),
      true,
      'AC-NF1: parent must be archived to design-plans/archive/'
    );
    assert.match(
      fs.readFileSync(archivedParent, 'utf8'),
      /^status: IMPLEMENTED$/m,
      'AC-NF1: archived parent must be IMPLEMENTED'
    );
  }

  // ---------------------------------------------------------------------------
  // AC-NEG1: 1 implemented + 1 genuinely-incomplete (in_progress) sibling →
  //          derivedStatus implementing, not IMPLEMENTED.
  // ---------------------------------------------------------------------------
  {
    const specsRoot = path.join(tempDir, 'ac-neg1-incomplete', 'specs');
    writeMarkdown(
      path.join(specsRoot, 'design-plans/DP-105-incomplete/index.md'),
      { title: 'Incomplete DP', status: 'IMPLEMENTING' }
    );
    writeMarkdown(
      path.join(specsRoot, 'design-plans/DP-105-incomplete/tasks/pr-release/T1/index.md'),
      { title: 'T1 done', status: 'IMPLEMENTED' }
    );
    writeMarkdown(
      path.join(specsRoot, 'design-plans/DP-105-incomplete/tasks/T2/index.md'),
      { title: 'T2 in progress', status: 'IN_PROGRESS' }
    );

    const report = inferLifecycleReport({ specsRoot, source: 'DP-105-incomplete' });
    const item = report.items.find((i) => i.id === 'DP-105-incomplete');
    assert.ok(item, 'AC-NEG1: DP item should be present');
    assert.equal(
      item.derivedStatus,
      'implementing',
      'AC-NEG1: genuinely-incomplete sibling must keep parent implementing'
    );
    assert.notEqual(item.derivedStatus, 'implemented', 'AC-NEG1: must NOT derive implemented');
  }

  // ---------------------------------------------------------------------------
  // AC-NEG2: only 1 ABANDONED task (realImplementable===0) → must NOT auto-close.
  // ---------------------------------------------------------------------------
  {
    const specsRoot = path.join(tempDir, 'ac-neg2-only-abandoned', 'specs');
    writeMarkdown(
      path.join(specsRoot, 'design-plans/DP-106-only-abandoned/index.md'),
      { title: 'Only Abandoned DP', status: 'IMPLEMENTING' }
    );
    writeMarkdown(
      path.join(specsRoot, 'design-plans/DP-106-only-abandoned/tasks/T1/index.md'),
      { title: 'T1 abandoned', status: 'ABANDONED' }
    );

    const report = inferLifecycleReport({ specsRoot, source: 'DP-106-only-abandoned' });
    const item = report.items.find((i) => i.id === 'DP-106-only-abandoned');
    assert.ok(item, 'AC-NEG2: DP item should be present');
    assert.notEqual(
      item.derivedStatus,
      'implemented',
      'AC-NEG2: parent with only ABANDONED sibling (realImplementable===0) must NOT derive implemented'
    );
  }

  // ---------------------------------------------------------------------------
  // AC-NEG3: existing reconcile-spec-lifecycle-selftest.mjs全 case 重跑維持 PASS.
  // ---------------------------------------------------------------------------
  {
    const existing = spawnSync(
      'node',
      [path.join(SCRIPT_DIR, 'reconcile-spec-lifecycle-selftest.mjs')],
      { encoding: 'utf8' }
    );
    assert.equal(
      existing.status,
      0,
      `AC-NEG3: existing reconcile selftest must stay green; stderr=${existing.stderr}\nstdout=${existing.stdout}`
    );
  }

  console.log('PASS reconcile spec lifecycle terminal-resolved selftest');
} finally {
  fs.rmSync(tempDir, { recursive: true, force: true });
}

// Emit plain unquoted YAML scalars. close-parent-spec-if-complete.sh's decider
// parses status with a quote-naive `line.split(":", 1)[1].strip()`, so a
// JSON-quoted `status: "ABANDONED"` would not match `== "ABANDONED"`. The proven
// shell fixtures (DP-998) and the bare-key selftest also use unquoted scalars.
function writeMarkdown(file, frontmatter, bodyLines = ['Body']) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const yaml = Object.entries(frontmatter)
    .map(([key, value]) => `${key}: ${value}`)
    .join('\n');
  fs.writeFileSync(file, `---\n${yaml}\n---\n\n${bodyLines.join('\n')}\n`);
}
