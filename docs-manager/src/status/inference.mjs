import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readMarkdownFrontmatter } from './frontmatter.mjs';

export const STATUS_VALUES = [
  'seeded',
  'discussion',
  'locked',
  'in_progress',
  'implementing',
  'implemented',
  'blocked',
  'abandoned',
  'unknown',
];

const ACTIVE_STATUS_VALUES = new Set(STATUS_VALUES.filter((status) => status !== 'unknown'));
const STATUS_ALIASES = new Map([
  ['IN_PROGRESS', 'in_progress'],
  ['IMPLEMENTING', 'implementing'],
]);

const PRIMARY_ARTIFACTS = ['index.md', 'plan.md', 'refinement.md'];
const DEFAULT_SPECS_ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '../content/docs/specs'
);
const BEHAVIOR_MODES = new Set(['parity', 'visual_target', 'pm_flow', 'hybrid']);
const BEHAVIOR_SOURCES = new Set(['existing_behavior', 'figma', 'pm_flow', 'spec']);
const FIXTURE_POLICIES = new Set(['mockoon_required', 'live_allowed', 'static_only']);
const VISUAL_EXPECTATIONS = new Set(['none_allowed', 'baseline_required', 'update_baseline']);

/**
 * @typedef {'design-plan' | 'company-spec'} StatusSourceType
 * @typedef {'seeded' | 'discussion' | 'locked' | 'in_progress' | 'implementing' | 'implemented' | 'blocked' | 'abandoned' | 'unknown'} DashboardStatus
 * @typedef {{total: number, byStatus: {implemented: number, in_progress: number, blocked: number, unknown: number}}} TaskSummary
 * @typedef {{name: string, path: string}} DashboardArtifact
 * @typedef {{name: string, path: string}} DashboardReport
 * @typedef {{status: string, path?: string}} PublicationSummary
 * @typedef {{behaviorContract?: object, visualRegression?: object}} VerificationSummary
 * @typedef {{
 *   id: string,
 *   title: string,
 *   sourceType: StatusSourceType,
 *   company?: string,
 *   status: DashboardStatus,
 *   priority: string | number | null,
 *   relativePath: string,
 *   artifact: DashboardArtifact | null,
 *   verifyReport: DashboardReport | null,
 *   publication: PublicationSummary,
 *   verification: VerificationSummary,
 *   tasks: TaskSummary,
 *   blockers: string[],
 * }} DashboardItem
 */

export function inferStatusDashboard(options = {}) {
  const specsRoot = path.resolve(options.specsRoot ?? DEFAULT_SPECS_ROOT);
  return {
    specsRoot,
    items: collectStatusItems(specsRoot),
  };
}

/** @returns {DashboardItem[]} */
export function collectStatusItems(specsRoot) {
  return [
    ...collectDesignPlans(specsRoot),
    ...collectCompanySpecs(specsRoot),
  ].sort((a, b) => a.id.localeCompare(b.id));
}

function collectDesignPlans(specsRoot) {
  const baseDir = path.join(specsRoot, 'design-plans');
  if (!fs.existsSync(baseDir)) return [];

  return readChildDirectories(baseDir)
    .map((dir) => buildItem({ specsRoot, dir, sourceType: 'design-plan' }))
    .filter(Boolean);
}

function collectCompanySpecs(specsRoot) {
  const companiesRoot = path.join(specsRoot, 'companies');
  if (!fs.existsSync(companiesRoot)) return [];

  return readChildDirectories(companiesRoot).flatMap((companyDir) =>
    readChildDirectories(companyDir).map((dir) =>
      buildItem({
        specsRoot,
        dir,
        sourceType: 'company-spec',
        company: path.basename(companyDir),
      })
    )
  );
}

function buildItem({ specsRoot, dir, sourceType, company }) {
  const artifact = findPrimaryArtifact(dir);
  const report = findLatestVerifyReport(dir);
  const blockers = [];
  const id = path.basename(dir);
  const frontmatter = artifact ? readMarkdownFrontmatter(artifact.file) : {};

  if (!artifact) {
    blockers.push('missing-primary-artifact');
  }

  const status = normalizeStatus(frontmatter.status);
  if (artifact && status === 'unknown') {
    blockers.push(frontmatter.status ? 'unknown-status' : 'missing-status');
  }

  return {
    id,
    title: frontmatter.title || id,
    sourceType,
    company,
    status,
    priority: frontmatter.priority ?? null,
    relativePath: path.relative(specsRoot, dir).replaceAll(path.sep, '/'),
    artifact: artifact
      ? {
          name: artifact.name,
          path: path.relative(specsRoot, artifact.file).replaceAll(path.sep, '/'),
        }
      : null,
    verifyReport: report
      ? {
          name: 'verify-report.md',
          path: path.relative(specsRoot, report).replaceAll(path.sep, '/'),
        }
      : null,
    publication: summarizePublication(dir),
    verification: inferVerification(dir, artifact?.file),
    tasks: summarizeTasks(path.join(dir, 'tasks')),
    blockers,
  };
}

function readChildDirectories(dir) {
  return fs
    .readdirSync(dir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .filter((entry) => entry.name !== 'archive')
    .map((entry) => path.join(dir, entry.name));
}

function findPrimaryArtifact(dir) {
  for (const name of PRIMARY_ARTIFACTS) {
    const file = path.join(dir, name);
    if (fs.existsSync(file)) return { name, file };
  }
  return null;
}

function findLatestVerifyReport(dir) {
  const reports = [];
  walkFiles(dir, (file) => {
    if (path.basename(file) === 'verify-report.md') reports.push(file);
  });
  reports.sort((a, b) => {
    const mtimeDiff = fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs;
    return mtimeDiff || a.localeCompare(b);
  });
  return reports[0] ?? null;
}

function summarizePublication(dir) {
  const manifests = [];
  walkFiles(dir, (file) => {
    if (path.basename(file) === 'publication-manifest.json') manifests.push(file);
  });
  if (manifests.length === 0) {
    return findLatestVerifyReport(dir) ? { status: 'local_only' } : { status: 'not_available' };
  }
  manifests.sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs || a.localeCompare(b));
  const manifest = manifests[0];
  const relative = path.relative(dir, manifest).replaceAll(path.sep, '/');
  try {
    const data = JSON.parse(fs.readFileSync(manifest, 'utf8'));
    return {
      status: normalizePublicationStatus(data.status ?? data.publication_status),
      path: relative,
    };
  } catch {
    return {
      status: 'blocked',
      path: relative,
    };
  }
}

function normalizePublicationStatus(value) {
  const normalized = String(value ?? '').trim().toLowerCase();
  if (['published', 'partial', 'blocked', 'local_only', 'not_required'].includes(normalized)) {
    return normalized;
  }
  return normalized ? 'blocked' : 'local_only';
}

function inferVerification(dir, primaryFile) {
  const candidates = [
    primaryFile,
    ...taskFiles(path.join(dir, 'tasks')),
  ].filter(Boolean);

  const summary = {};
  for (const file of candidates) {
    const frontmatter = readMarkdownFrontmatter(file);
    const behaviorContract = frontmatter.verification?.behavior_contract;
    const visualRegression = frontmatter.verification?.visual_regression;
    if (!summary.behaviorContract && behaviorContract) {
      validateBehaviorContract(file, behaviorContract);
      summary.behaviorContract = behaviorContract;
    }
    if (!summary.visualRegression && visualRegression) {
      validateVisualRegression(file, visualRegression);
      summary.visualRegression = visualRegression;
    }
    if (summary.behaviorContract && summary.visualRegression) break;
  }
  return summary;
}

function validateBehaviorContract(file, contract) {
  if (contract.applies === false) return;
  if (contract.applies !== true) return;
  if (!BEHAVIOR_MODES.has(contract.mode)) {
    throw new Error(`${file}: unknown behavior_contract.mode: ${contract.mode}`);
  }
  if (!BEHAVIOR_SOURCES.has(contract.source_of_truth)) {
    throw new Error(`${file}: unknown behavior_contract.source_of_truth: ${contract.source_of_truth}`);
  }
  if (!FIXTURE_POLICIES.has(contract.fixture_policy)) {
    throw new Error(`${file}: unknown behavior_contract.fixture_policy: ${contract.fixture_policy}`);
  }
}

function validateVisualRegression(file, visualRegression) {
  if (!VISUAL_EXPECTATIONS.has(visualRegression.expected)) {
    throw new Error(`${file}: unknown visual_regression.expected: ${visualRegression.expected}`);
  }
}

function summarizeTasks(tasksDir) {
  const summary = {
    total: 0,
    byStatus: {
      implemented: 0,
      in_progress: 0,
      blocked: 0,
      unknown: 0,
    },
  };

  if (!fs.existsSync(tasksDir)) return summary;

  for (const file of taskFiles(tasksDir)) {
    summary.total += 1;
    const frontmatter = readMarkdownFrontmatter(file);
    const status = normalizeStatus(frontmatter.status);
    if (status === 'implemented') {
      summary.byStatus.implemented += 1;
    } else if (status === 'in_progress' || status === 'implementing') {
      summary.byStatus.in_progress += 1;
    } else if (status === 'blocked') {
      summary.byStatus.blocked += 1;
    } else {
      summary.byStatus.unknown += 1;
    }
  }

  return summary;
}

function taskFiles(tasksDir) {
  if (!fs.existsSync(tasksDir)) return [];
  return fs
    .readdirSync(tasksDir, { withFileTypes: true })
    .flatMap((entry) => {
      if (entry.isFile() && /^T\d+[a-z]*\.md$/i.test(entry.name)) {
        return [path.join(tasksDir, entry.name)];
      }
      if (entry.isDirectory() && /^T\d+[a-z]*$/i.test(entry.name)) {
        const indexFile = path.join(tasksDir, entry.name, 'index.md');
        return fs.existsSync(indexFile) ? [indexFile] : [];
      }
      return [];
    })
    .sort();
}

function walkFiles(dir, visit) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'archive') continue;
    const entryPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walkFiles(entryPath, visit);
    } else if (entry.isFile()) {
      visit(entryPath);
    }
  }
}

function normalizeStatus(value) {
  if (!value) return 'unknown';
  const raw = String(value).trim();
  const aliased = STATUS_ALIASES.get(raw.toUpperCase()) ?? raw.toLowerCase();
  return ACTIVE_STATUS_VALUES.has(aliased) ? aliased : 'unknown';
}
