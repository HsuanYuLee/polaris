#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { inferStatusDashboard } from '../docs-manager/src/status/index.mjs';

const TERMINAL_STATUSES = new Set(['implemented', 'abandoned', 'superseded']);
const DEFAULT_SPECS_ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '../docs-manager/src/content/docs/specs'
);

export function inferLifecycleReport(options = {}) {
  const specsRoot = path.resolve(options.specsRoot ?? DEFAULT_SPECS_ROOT);
  const dashboard = inferStatusDashboard({ specsRoot, today: options.today });
  const items = dashboard.items
    .filter((item) => matchesSource(item, options.source))
    .map((item) => projectLifecycleItem(item, specsRoot));

  return {
    specsRoot,
    mode: options.sweep ? 'sweep' : 'single',
    items,
    summary: {
      total: items.length,
      statusMismatches: items.filter((item) => item.currentStatus !== item.derivedStatus).length,
      archiveEligible: items.filter((item) => item.archiveEligible).length,
      blockers: items.filter((item) => item.blockers.length > 0).length,
    },
  };
}

function projectLifecycleItem(item, specsRoot) {
  const blockers = [...new Set([...(item.blockers ?? [])])];
  const terminal = TERMINAL_STATUSES.has(item.status);
  const archiveEligible = terminal && !item.relativePath.includes('/archive/');
  const checklist = readImplementationChecklist(specsRoot, item.artifact?.path);
  const taskCounts = item.tasks.byStatus;
  const completedTasks = taskCounts.implemented ?? 0;
  const allTasksImplemented = item.tasks.total > 0 && completedTasks === item.tasks.total;
  const hasStartedWork =
    item.tasks.total > 0 &&
    completedTasks + (taskCounts.in_progress ?? 0) + (taskCounts.in_review ?? 0) + (taskCounts.blocked ?? 0) > 0;

  let derivedStatus = item.status;
  if (!terminal && item.tasks.total > 0) {
    if (allTasksImplemented) {
      if (checklist.openItems.length === 0 && blockers.length === 0) {
        derivedStatus = 'implemented';
      } else if (checklist.openItems.length > 0) {
        blockers.push('parent-checklist-open');
      }
    } else if (hasStartedWork && ['seeded', 'discussion', 'locked'].includes(item.status)) {
      derivedStatus = 'implementing';
    }
  }

  return {
    id: item.id,
    sourceType: item.sourceType,
    relativePath: item.relativePath,
    currentStatus: item.status,
    derivedStatus,
    archiveEligible,
    blockers: [...new Set(blockers)].sort(),
    tasks: item.tasks,
    checklist,
  };
}

function readImplementationChecklist(specsRoot, artifactPath) {
  if (!artifactPath) return { openItems: [], checkedItems: [], present: false };
  const file = path.join(specsRoot, artifactPath);
  if (!fs.existsSync(file)) return { openItems: [], checkedItems: [], present: false };

  const lines = fs.readFileSync(file, 'utf8').split('\n');
  const openItems = [];
  const checkedItems = [];
  let inChecklist = false;

  for (const line of lines) {
    if (/^##\s+Implementation Checklist\s*$/.test(line.trim())) {
      inChecklist = true;
      continue;
    }
    if (inChecklist && /^##\s+/.test(line)) break;
    if (!inChecklist) continue;

    if (/^\s*-\s+\[\s\]\s+/.test(line)) openItems.push(line.trim());
    if (/^\s*-\s+\[[xX]\]\s+/.test(line)) checkedItems.push(line.trim());
  }

  return {
    openItems,
    checkedItems,
    present: openItems.length > 0 || checkedItems.length > 0,
  };
}

function matchesSource(item, source) {
  if (!source) return true;
  const normalized = String(source).trim();
  if (item.id === normalized) return true;
  if (/^DP-\d{3}$/.test(normalized) && item.id.startsWith(`${normalized}-`)) return true;
  return item.relativePath === normalized || item.relativePath.endsWith(`/${normalized}`);
}

function parseArgs(argv) {
  const options = { specsRoot: DEFAULT_SPECS_ROOT, sweep: false, source: null };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--specs-root') {
      options.specsRoot = argv[index + 1];
      index += 1;
    } else if (arg === '--sweep') {
      options.sweep = true;
    } else if (arg === '--today') {
      options.today = argv[index + 1];
      index += 1;
    } else if (arg === '--help' || arg === '-h') {
      options.help = true;
    } else if (!options.source) {
      options.source = arg;
    } else {
      throw new Error(`unexpected argument: ${arg}`);
    }
  }
  return options;
}

function printUsage() {
  console.error('usage: reconcile-spec-lifecycle.mjs [--specs-root <path>] [--today YYYY-MM-DD] [--sweep|<SPEC_ID>]');
}

if (import.meta.url === `file://${process.argv[1]}`) {
  try {
    const options = parseArgs(process.argv.slice(2));
    if (options.help) {
      printUsage();
      process.exit(0);
    }
    if (!options.sweep && !options.source) {
      printUsage();
      process.exit(2);
    }
    const report = inferLifecycleReport(options);
    if (!options.sweep && report.items.length !== 1) {
      console.error(`expected exactly one spec, got ${report.items.length}`);
      process.exit(1);
    }
    console.log(JSON.stringify(report, null, 2));
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
}
