#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const args = parseArgs(process.argv.slice(2));
if (args.help) {
  usage();
  process.exit(0);
}

const specsRoot = path.resolve(args.specsRoot || 'docs-manager/src/content/docs/specs');
const apply = args.apply === true;
const includeArchive = args.includeArchive === true;
const cleanupLegacyBundles = args.cleanupLegacyBundles === true;

if (!fs.existsSync(specsRoot)) fail(`specs root not found: ${specsRoot}`);
const actions = [];
planContainerMoves(specsRoot, actions);
if (cleanupLegacyBundles) planBundleCleanup(specsRoot, actions);

if (apply) {
  const blockers = actions.filter((action) => action.action.startsWith('blocked_'));
  if (blockers.length > 0) {
    printReport(actions);
    console.error(`[polaris migrate-spec-container-layout] blocked by ${blockers.length} guard action(s); no files were changed`);
    process.exit(1);
  }
  for (const action of actions) {
    if (action.action === 'move') applyMove(action);
    if (action.action === 'cleanup_legacy_bundle') applyCleanup(action);
  }
}

printReport(actions);

function parseArgs(argv) {
  const parsed = {};
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    switch (arg) {
      case '--specs-root':
        parsed.specsRoot = argv[++index];
        if (!parsed.specsRoot) fail('--specs-root requires a value');
        break;
      case '--dry-run':
        parsed.apply = false;
        break;
      case '--apply':
        parsed.apply = true;
        break;
      case '--include-archive':
        parsed.includeArchive = true;
        break;
      case '--cleanup-legacy-bundles':
        parsed.cleanupLegacyBundles = true;
        break;
      case '-h':
      case '--help':
        parsed.help = true;
        break;
      default:
        fail(`unknown argument: ${arg}`);
    }
  }
  return parsed;
}

function usage() {
  console.log(`Usage:
  bash scripts/migrate-spec-container-layout.sh [--specs-root <path>] [--dry-run|--apply] [--include-archive] [--cleanup-legacy-bundles]

Default mode is dry-run and active namespace only.`);
}

function fail(message) {
  console.error(`[polaris migrate-spec-container-layout] ${message}`);
  process.exit(64);
}

function printReport(reportActions) {
  console.log(JSON.stringify({
    mode: apply ? 'apply' : 'dry-run',
    specs_root: specsRoot,
    include_archive: includeArchive,
    cleanup_legacy_bundles: cleanupLegacyBundles,
    actions: reportActions,
  }, null, 2));
}

function planContainerMoves(root, output) {
  const designPlans = path.join(root, 'design-plans');
  if (fs.existsSync(designPlans)) {
    for (const container of listDirectories(designPlans)) {
      if (container.endsWith(`${path.sep}archive`)) continue;
      if (path.basename(container).startsWith('DP-')) planDesignPlanContainer(container, output);
    }
    const archive = path.join(designPlans, 'archive');
    if (includeArchive && fs.existsSync(archive)) {
      for (const container of listDirectories(archive)) {
        if (path.basename(container).startsWith('DP-')) planDesignPlanContainer(container, output);
      }
    }
  }

  const companies = path.join(root, 'companies');
  if (fs.existsSync(companies)) {
    for (const company of listDirectories(companies)) {
      for (const container of listDirectories(company)) {
        if (path.basename(container) === 'archive') {
          if (includeArchive) {
            for (const archived of listDirectories(container)) planCompanyContainer(archived, output);
          }
          continue;
        }
        planCompanyContainer(container, output);
      }
    }
  }
}

function planDesignPlanContainer(container, output) {
  planPrimaryMove(container, 'plan.md', 'index.md', output);
  for (const tasksDir of [path.join(container, 'tasks'), path.join(container, 'tasks', 'pr-release')]) {
    planTasks(tasksDir, output);
  }
}

function planCompanyContainer(container, output) {
  planPrimaryMove(container, 'refinement.md', 'index.md', output);
  for (const tasksDir of [path.join(container, 'tasks'), path.join(container, 'tasks', 'pr-release')]) {
    planTasks(tasksDir, output);
  }
}

function planTasks(tasksDir, output) {
  if (!fs.existsSync(tasksDir)) return;
  for (const entry of fs.readdirSync(tasksDir, { withFileTypes: true })) {
    if (!entry.isFile() || !/^[TV][A-Za-z0-9-]*\.md$/u.test(entry.name)) continue;
    const key = entry.name.replace(/\.md$/u, '');
    const source = path.join(tasksDir, entry.name);
    const target = path.join(tasksDir, key, 'index.md');
    planMove(source, target, output, { rewrite_links: true });
  }
}

function planPrimaryMove(container, sourceName, targetName, output) {
  const source = path.join(container, sourceName);
  const target = path.join(container, targetName);
  if (!fs.existsSync(source)) return;
  planMove(source, target, output, { rewrite_links: false });
}

function planMove(source, target, output, options) {
  if (fs.existsSync(target)) {
    output.push({ action: 'blocked_collision', source, target });
    return;
  }
  output.push({ action: 'move', source, target, rewrite_links: options.rewrite_links });
}

function planBundleCleanup(root, output) {
  for (const dir of listDirectoriesRecursive(root)) {
    if (!dir.includes(`${path.sep}artifacts${path.sep}`)) continue;
    if (!/(?:-pr-upload|-jira-upload|-evidence-upload)$/u.test(path.basename(dir))) continue;
    const required = ['links.json', 'publication-manifest.json', 'verify-report.md', 'assets'];
    const missing = required.filter((name) => !fs.existsSync(path.join(dir, name)));
    if (missing.length > 0) {
      output.push({ action: 'blocked_cleanup', bundle: dir, missing });
      continue;
    }
    const remove = fs.readdirSync(dir)
      .filter((name) => !required.includes(name) && name !== 'README.md')
      .map((name) => path.join(dir, name));
    if (remove.length > 0) output.push({ action: 'cleanup_legacy_bundle', bundle: dir, remove });
  }
}

function applyMove(action) {
  fs.mkdirSync(path.dirname(action.target), { recursive: true });
  const original = fs.readFileSync(action.source, 'utf8');
  fs.writeFileSync(action.target, action.rewrite_links ? rewriteLinks(original) : original, 'utf8');
  fs.rmSync(action.source);
}

function applyCleanup(action) {
  for (const target of action.remove) fs.rmSync(target, { recursive: true, force: true });
}

function rewriteLinks(markdown) {
  return markdown.replace(/(!?\[[^\]]*\]\()((?![a-z]+:|#|\/)(?:\.\/)?[^)#]+)(\))/giu, (_match, open, href, close) => {
    if (href.startsWith('../')) return `${open}${href}${close}`;
    return `${open}../${href.replace(/^\.\//u, '')}${close}`;
  });
}

function listDirectories(dir) {
  return fs.readdirSync(dir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => path.join(dir, entry.name))
    .sort();
}

function listDirectoriesRecursive(root) {
  const output = [];
  const stack = [root];
  while (stack.length > 0) {
    const current = stack.pop();
    output.push(current);
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      if (entry.isDirectory()) stack.push(path.join(current, entry.name));
    }
  }
  return output.sort();
}
