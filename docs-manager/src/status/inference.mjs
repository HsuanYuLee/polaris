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

const PRIMARY_ARTIFACTS = ['plan.md', 'refinement.md'];
const DEFAULT_SPECS_ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '../content/docs/specs'
);

/**
 * @typedef {'design-plan' | 'company-spec'} StatusSourceType
 * @typedef {'seeded' | 'discussion' | 'locked' | 'in_progress' | 'implementing' | 'implemented' | 'blocked' | 'abandoned' | 'unknown'} DashboardStatus
 * @typedef {{total: number, byStatus: {implemented: number, in_progress: number, blocked: number, unknown: number}}} TaskSummary
 * @typedef {{name: string, path: string}} DashboardArtifact
 * @typedef {{
 *   id: string,
 *   title: string,
 *   sourceType: StatusSourceType,
 *   company?: string,
 *   status: DashboardStatus,
 *   priority: string | number | null,
 *   relativePath: string,
 *   artifact: DashboardArtifact | null,
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
  return fs
    .readdirSync(tasksDir, { withFileTypes: true })
    .filter((entry) => entry.isFile())
    .filter((entry) => /^T\d+[a-z]*\.md$/i.test(entry.name))
    .map((entry) => path.join(tasksDir, entry.name))
    .sort();
}

function normalizeStatus(value) {
  if (!value) return 'unknown';
  const raw = String(value).trim();
  const aliased = STATUS_ALIASES.get(raw.toUpperCase()) ?? raw.toLowerCase();
  return ACTIVE_STATUS_VALUES.has(aliased) ? aliased : 'unknown';
}
