#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { inferStatusDashboard } from '../docs-manager/src/status/index.mjs';

const TERMINAL_STATUSES = new Set(['implemented', 'abandoned', 'superseded']);
const FRONTMATTER_STATUS = {
  seeded: 'SEEDED',
  discussion: 'DISCUSSION',
  locked: 'LOCKED',
  implementing: 'IMPLEMENTING',
  implemented: 'IMPLEMENTED',
  abandoned: 'ABANDONED',
  superseded: 'SUPERSEDED',
};
const DEFAULT_SPECS_ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '../docs-manager/src/content/docs/specs'
);
const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));

export function inferLifecycleReport(options = {}) {
  const specsRoot = path.resolve(options.specsRoot ?? DEFAULT_SPECS_ROOT);
  const dashboard = inferStatusDashboard({ specsRoot, today: options.today });
  const items = dashboard.items
    .filter((item) => matchesSource(item, specsRoot, options.source))
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

export function applyLifecycleReport(options = {}) {
  const report = inferLifecycleReport(options);
  const results = [];

  if (!options.sweep && report.items.length !== 1) {
    return {
      ...report,
      applied: false,
      applyResults: results,
    };
  }

  for (const item of report.items) {
    results.push(applyLifecycleItem(report.specsRoot, item, options));
  }

  return {
    ...report,
    applied: true,
    applyResults: results,
  };
}

function projectLifecycleItem(item, specsRoot) {
  const blockers = [...new Set([...(item.blockers ?? [])])];
  const terminal = TERMINAL_STATUSES.has(item.status);
  const archiveEligible = terminal && !item.relativePath.includes('/archive/');
  const checklist = readImplementationChecklist(specsRoot, item.artifact?.path);
  const taskCounts = item.tasks.byStatus;
  const completedTasks = taskCounts.implemented ?? 0;
  // ABANDONED / SUPERSEDED siblings are terminal-resolved: they are not pending
  // work, so they must be excluded from the implementable denominator. Otherwise
  // a parent with one ABANDONED task can never derive implemented (total stays
  // above completed forever — DP-338/T4 first triggered this path).
  const terminalResolved = (taskCounts.abandoned ?? 0) + (taskCounts.superseded ?? 0);
  const realImplementable = item.tasks.total - terminalResolved;
  const allTasksImplemented = realImplementable > 0 && completedTasks === realImplementable;
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
    parentFile: item.artifact?.path ?? null,
    currentStatus: item.status,
    derivedStatus,
    archiveEligible,
    blockers: [...new Set(blockers)].sort(),
    tasks: item.tasks,
    checklist,
    actions: lifecycleActions({
      currentStatus: item.status,
      derivedStatus,
      archiveEligible,
      blockers,
    }),
  };
}

function lifecycleActions(item) {
  const actions = [];
  if (item.currentStatus !== item.derivedStatus) {
    actions.push({
      type: 'update-status',
      status: FRONTMATTER_STATUS[item.derivedStatus] ?? item.derivedStatus.toUpperCase(),
      blocked: item.blockers.length > 0,
    });
  }
  if (item.archiveEligible) {
    actions.push({ type: 'archive', blocked: false });
  }
  return actions;
}

function applyLifecycleItem(specsRoot, item, options) {
  const result = { id: item.id, actions: [] };
  const parentFile = item.parentFile ? path.join(specsRoot, item.parentFile) : null;

  if (item.currentStatus !== item.derivedStatus) {
    const status = FRONTMATTER_STATUS[item.derivedStatus];
    if (!status) {
      result.actions.push({ type: 'update-status', status: item.derivedStatus, result: 'blocked', reason: 'unsupported-derived-status' });
    } else if (item.blockers.length > 0) {
      result.actions.push({ type: 'update-status', status, result: 'blocked', blockers: item.blockers });
    } else if (!parentFile || !fs.existsSync(parentFile)) {
      result.actions.push({ type: 'update-status', status, result: 'blocked', reason: 'missing-parent-file' });
    } else {
      updateFrontmatterStatus(parentFile, status);
      if (status === 'IMPLEMENTED') updateFrontmatterScalar(parentFile, 'implemented_at', options.today ?? todayString());
      syncSidebarMetadata(parentFile);
      result.actions.push({ type: 'update-status', status, result: 'applied', file: path.relative(specsRoot, parentFile) });
    }
  }

  if (item.archiveEligible) {
    if (options.archive === false) {
      result.actions.push({ type: 'archive', result: 'skipped', reason: 'archive-disabled' });
    } else {
      const archiveResult = archiveContainer(specsRoot, item);
      result.actions.push({ type: 'archive', ...archiveResult });
    }
  }

  if (result.actions.length === 0) {
    result.actions.push({ type: 'noop', result: 'skipped', reason: 'already-consistent' });
  }
  return result;
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

function matchesSource(item, specsRoot, source) {
  if (!source) return true;
  const normalized = String(source).trim();
  if (item.id === normalized) return true;
  if (/^DP-\d{3}$/.test(normalized) && item.id.startsWith(`${normalized}-`)) return true;
  const sourcePath = path.isAbsolute(normalized)
    ? path.relative(specsRoot, normalized)
    : normalized.replace(/^docs-manager\/src\/content\/docs\/specs\//, '');
  return (
    item.relativePath === sourcePath ||
    item.relativePath.endsWith(`/${sourcePath}`) ||
    item.artifact?.path === sourcePath ||
    item.artifact?.path?.endsWith(`/${sourcePath}`)
  );
}

function updateFrontmatterStatus(file, status) {
  updateFrontmatterScalar(file, 'status', status);
}

function updateFrontmatterScalar(file, key, value) {
  const text = fs.readFileSync(file, 'utf8');
  if (!text.startsWith('---\n')) {
    fs.writeFileSync(file, `---\n${key}: ${value}\n---\n\n${text}`, 'utf8');
    return;
  }
  const end = text.indexOf('\n---\n', 4);
  if (end === -1) throw new Error(`${file}: unterminated YAML frontmatter`);
  const frontmatter = text.slice(4, end).split('\n');
  const body = text.slice(end);
  const pattern = new RegExp(`^${escapeRegExp(key)}:\\s*`);
  let found = false;
  const nextFrontmatter = frontmatter.map((line) => {
    if (!pattern.test(line)) return line;
    found = true;
    return `${key}: ${value}`;
  });
  if (!found) nextFrontmatter.push(`${key}: ${value}`);
  fs.writeFileSync(file, `---\n${nextFrontmatter.join('\n')}${body}`, 'utf8');
}

function syncSidebarMetadata(file) {
  const syncScript = path.join(SCRIPT_DIR, 'sync-spec-sidebar-metadata.sh');
  if (!fs.existsSync(syncScript)) return;
  const result = spawnSync('bash', [syncScript, '--apply', file], {
    cwd: path.resolve(SCRIPT_DIR, '..'),
    encoding: 'utf8',
  });
  if (result.status !== 0) {
    const detail = (result.stderr || result.stdout || '').trim();
    throw new Error(detail || `failed to sync sidebar metadata for ${file}`);
  }
}

function archiveContainer(specsRoot, item) {
  const source = path.join(specsRoot, item.relativePath);
  const destination = archiveDestination(specsRoot, item.relativePath);
  if (!destination) return { result: 'blocked', reason: 'unsupported-container' };
  if (!fs.existsSync(source)) return { result: 'blocked', reason: 'missing-source', source: item.relativePath };
  if (fs.existsSync(destination)) {
    return { result: 'blocked', reason: 'destination-exists', destination: path.relative(specsRoot, destination) };
  }
  if (item.parentFile) syncSidebarMetadata(path.join(specsRoot, item.parentFile));
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.renameSync(source, destination);
  return {
    result: 'applied',
    source: item.relativePath,
    destination: path.relative(specsRoot, destination),
  };
}

function archiveDestination(specsRoot, relativePath) {
  const parts = relativePath.split('/');
  if (parts.length === 2 && parts[0] === 'design-plans' && /^DP-\d{3}-/.test(parts[1])) {
    return path.join(specsRoot, 'design-plans', 'archive', parts[1]);
  }
  if (parts.length === 3 && parts[0] === 'companies') {
    return path.join(specsRoot, 'companies', parts[1], 'archive', parts[2]);
  }
  return null;
}

function todayString() {
  return new Date().toISOString().slice(0, 10);
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function parseArgs(argv) {
  const options = { specsRoot: DEFAULT_SPECS_ROOT, sweep: false, source: null, apply: false, archive: true };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--specs-root') {
      options.specsRoot = argv[index + 1];
      index += 1;
    } else if (arg === '--apply') {
      options.apply = true;
    } else if (arg === '--no-archive') {
      options.archive = false;
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
  console.error('usage: reconcile-spec-lifecycle.mjs [--specs-root <path>] [--today YYYY-MM-DD] [--apply] [--no-archive] [--sweep|<SPEC_ID>|<spec-path>]');
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
    const report = options.apply ? applyLifecycleReport(options) : inferLifecycleReport(options);
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
