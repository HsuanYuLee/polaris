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
  'superseded',
  'blocked',
  'abandoned',
  'unknown',
];

const ACTIVE_STATUS_VALUES = new Set(STATUS_VALUES.filter((status) => status !== 'unknown'));
const STATUS_ALIASES = new Map([
  ['IN_PROGRESS', 'in_progress'],
  ['IMPLEMENTING', 'implementing'],
]);
const TASK_STATUS_VALUES = new Set([
  'planned',
  'in_progress',
  'implementing',
  'implemented',
  'blocked',
  'abandoned',
]);
const TASK_STATUS_ALIASES = new Map([
  ...STATUS_ALIASES,
  ['PLANNED', 'planned'],
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
const STATUS_UPDATE_PHASES = new Set([
  'discussion',
  'ready',
  'implementing',
  'validating',
  'blocked',
  'done',
]);
const STATUS_UPDATE_FILENAME = /^(\d{8})-(\d{4})-.+\.md$/;
const EXTERNAL_REF_TYPES = new Set(['jira_comment', 'pr', 'slack', 'report', 'other']);

/**
 * @typedef {'design-plan' | 'company-spec'} StatusSourceType
 * @typedef {'seeded' | 'discussion' | 'locked' | 'in_progress' | 'implementing' | 'implemented' | 'superseded' | 'blocked' | 'abandoned' | 'unknown'} DashboardStatus
 * @typedef {{total: number, byStatus: {planned: number, implemented: number, in_progress: number, in_review: number, blocked: number, unknown: number, stale: number}, staleSignals: string[]}} TaskSummary
 * @typedef {{name: string, path: string}} DashboardArtifact
 * @typedef {{name: string, path: string}} DashboardReport
 * @typedef {{status: string, path?: string}} PublicationSummary
 * @typedef {{behaviorContract?: object, visualRegression?: object}} VerificationSummary
 * @typedef {{
 *   id: string,
 *   title: string,
 *   sourceType: StatusSourceType,
 *   company?: string,
 *   issueType: string | null,
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
  const today = normalizeDateString(options.today) ?? new Date().toISOString().slice(0, 10);

  return {
    specsRoot,
    items: collectStatusItems(specsRoot, { today }),
  };
}

/** @returns {DashboardItem[]} */
export function collectStatusItems(specsRoot, options = {}) {
  return [
    ...collectDesignPlans(specsRoot, options),
    ...collectCompanySpecs(specsRoot, options),
  ].sort((a, b) => a.id.localeCompare(b.id));
}

function collectDesignPlans(specsRoot, options) {
  const baseDir = path.join(specsRoot, 'design-plans');
  if (!fs.existsSync(baseDir)) return [];

  return readChildDirectories(baseDir)
    .map((dir) => buildItem({ specsRoot, dir, sourceType: 'design-plan', today: options.today }))
    .filter(Boolean);
}

function collectCompanySpecs(specsRoot, options) {
  const companiesRoot = path.join(specsRoot, 'companies');
  if (!fs.existsSync(companiesRoot)) return [];

  return readChildDirectories(companiesRoot).flatMap((companyDir) =>
    readChildDirectories(companyDir).map((dir) =>
      buildItem({
        specsRoot,
        dir,
        sourceType: 'company-spec',
        company: path.basename(companyDir),
        today: options.today,
      })
    )
  );
}

function buildItem({ specsRoot, dir, sourceType, company, today }) {
  const artifact = findPrimaryArtifact(dir);
  const report = findLatestVerifyReport(dir);
  const blockers = [];
  const id = path.basename(dir);
  const frontmatter = artifact ? readMarkdownFrontmatter(artifact.file) : {};
  const statusUpdate = findLatestStatusUpdate(dir, specsRoot, today);
  const tasks = summarizeTasks(path.join(dir, 'tasks'));
  const staleSignals = [...new Set([...(statusUpdate?.staleSignals ?? []), ...tasks.staleSignals])];

  if (!artifact) {
    blockers.push('missing-primary-artifact');
  }

  const status = normalizeStatus(frontmatter.status);
  if (artifact && status === 'unknown') {
    blockers.push(frontmatter.status ? 'unknown-status' : 'missing-status');
  }
  if (status === 'superseded') {
    return null;
  }
  const verification = inferVerification(dir, artifact?.file);
  blockers.push(...verification.blockers);

  return {
    id,
    title: frontmatter.title || id,
    sourceType,
    company,
    issueType: normalizeIssueType(frontmatter.jira_issue_type ?? frontmatter.issue_type),
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
    verification: {
      behaviorContract: verification.behaviorContract,
      visualRegression: verification.visualRegression,
    },
    tasks,
    blockers,
    derivedPhase: statusUpdate?.phase ?? null,
    statusSummary: statusUpdate?.summary ?? null,
    nextOwner: statusUpdate?.nextOwner ?? null,
    nextAction: statusUpdate?.nextAction ?? null,
    waitingUntil: statusUpdate?.waitingUntil ?? null,
    latestStatusUpdate: statusUpdate?.latestStatusUpdate ?? null,
    evidenceLinks: statusUpdate?.evidenceLinks ?? [],
    externalRefs: statusUpdate?.externalRefs ?? [],
    staleSignals,
  };
}

function normalizeIssueType(value) {
  const normalized = String(value ?? '').trim();
  return normalized || null;
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

function findLatestStatusUpdate(dir, specsRoot, today) {
  const updatesDir = path.join(dir, 'status-updates');
  if (!fs.existsSync(updatesDir)) return null;

  const updates = fs
    .readdirSync(updatesDir, { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith('.md'))
    .map((entry) => {
      const match = STATUS_UPDATE_FILENAME.exec(entry.name);
      if (!match) {
        throw new Error(`${path.join(updatesDir, entry.name)}: invalid status update filename`);
      }
      return {
        name: entry.name,
        file: path.join(updatesDir, entry.name),
        timestamp: `${match[1]}${match[2]}`,
        date: `${match[1].slice(0, 4)}-${match[1].slice(4, 6)}-${match[1].slice(6, 8)}`,
      };
    });

  if (updates.length === 0) return null;
  updates.sort((a, b) => b.timestamp.localeCompare(a.timestamp) || a.name.localeCompare(b.name));
  return parseStatusUpdate({ dir, specsRoot, update: updates[0], today });
}

function parseStatusUpdate({ dir, specsRoot, update, today }) {
  const frontmatter = readMarkdownFrontmatter(update.file);
  const phase = requireStatusUpdateString(update.file, frontmatter, 'phase').toLowerCase();
  if (!STATUS_UPDATE_PHASES.has(phase)) {
    throw new Error(`${update.file}: unknown status update phase: ${frontmatter.phase}`);
  }

  const summary = requireStatusUpdateString(update.file, frontmatter, 'summary');
  const hasNextOwner = Object.hasOwn(frontmatter, 'next_owner');
  const nextOwner = hasNextOwner ? String(frontmatter.next_owner ?? '').trim() : '';
  if (!hasNextOwner) {
    throw new Error(`${update.file}: missing required status update field: next_owner`);
  }
  if (!nextOwner && phase !== 'blocked') {
    throw new Error(`${update.file}: empty required status update field: next_owner`);
  }
  const nextAction = requireStatusUpdateString(update.file, frontmatter, 'next_action');
  const waitingUntil = normalizeDateString(frontmatter.waiting_until);
  if (frontmatter.waiting_until !== undefined && !waitingUntil) {
    throw new Error(`${update.file}: invalid waiting_until date: ${frontmatter.waiting_until}`);
  }

  const evidenceLinks = parseEvidenceLinks(update.file, dir, specsRoot, frontmatter.evidence, update.date);
  const externalRefs = parseExternalRefs(update.file, frontmatter.external_refs);
  const staleSignals = [];
  if (phase === 'blocked' && !nextOwner) {
    staleSignals.push('blocked-without-next-owner');
  }
  if (phase === 'validating' && waitingUntil && today && waitingUntil < today) {
    staleSignals.push('waiting-window-expired');
  }
  if (evidenceLinks.some((evidence) => evidence.date && evidence.date > update.date)) {
    staleSignals.push('evidence-newer-than-status-update');
  }

  return {
    phase,
    summary,
    nextOwner,
    nextAction,
    waitingUntil,
    latestStatusUpdate: {
      name: update.name,
      path: path.relative(specsRoot, update.file).replaceAll(path.sep, '/'),
      date: update.date,
    },
    evidenceLinks,
    externalRefs,
    staleSignals,
  };
}

function requireStatusUpdateString(file, frontmatter, field) {
  if (!Object.hasOwn(frontmatter, field)) {
    throw new Error(`${file}: missing required status update field: ${field}`);
  }
  const value = String(frontmatter[field] ?? '').trim();
  if (!value) {
    throw new Error(`${file}: empty required status update field: ${field}`);
  }
  return value;
}

function parseEvidenceLinks(file, dir, specsRoot, evidence, updateDate) {
  if (evidence === undefined) return [];
  if (!Array.isArray(evidence)) {
    throw new Error(`${file}: evidence must be an array`);
  }
  return evidence.map((entry) => {
    if (typeof entry !== 'string' || !entry.trim()) {
      throw new Error(`${file}: evidence entries must be non-empty strings`);
    }
    const normalized = entry.trim();
    const evidenceFile = path.resolve(dir, normalized);
    if (!evidenceFile.startsWith(`${path.resolve(dir)}${path.sep}`) && evidenceFile !== path.resolve(dir)) {
      throw new Error(`${file}: evidence path must stay inside the spec container: ${normalized}`);
    }
    if (!fs.existsSync(evidenceFile)) {
      throw new Error(`${file}: evidence path does not exist: ${normalized}`);
    }
    return {
      name: path.basename(normalized),
      path: path.relative(specsRoot, evidenceFile).replaceAll(path.sep, '/'),
      date: extractDate(normalized) ?? extractDate(path.basename(evidenceFile)) ?? null,
      staleComparedTo: updateDate,
    };
  });
}

function parseExternalRefs(file, externalRefs) {
  if (externalRefs === undefined) return [];
  if (!Array.isArray(externalRefs)) {
    throw new Error(`${file}: external_refs must be an array`);
  }
  return externalRefs.map((entry, index) => {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
      throw new Error(`${file}: external_refs[${index}] must be an object`);
    }
    const type = String(entry.type ?? '').trim();
    if (!EXTERNAL_REF_TYPES.has(type)) {
      throw new Error(`${file}: external_refs[${index}].type is invalid: ${entry.type}`);
    }
    const id = entry.id === undefined ? null : String(entry.id).trim();
    const url = entry.url === undefined ? null : String(entry.url).trim();
    if (!id && !url) {
      throw new Error(`${file}: external_refs[${index}] requires id or url`);
    }
    return { type, id, url };
  });
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

  const summary = {
    blockers: [],
  };
  for (const file of candidates) {
    const frontmatter = readMarkdownFrontmatter(file);
    const behaviorContract = frontmatter.verification?.behavior_contract;
    const visualRegression = frontmatter.verification?.visual_regression;
    if (!summary.behaviorContract && behaviorContract) {
      summary.blockers.push(...validateBehaviorContract(behaviorContract));
      summary.behaviorContract = behaviorContract;
    }
    if (!summary.visualRegression && visualRegression) {
      summary.blockers.push(...validateVisualRegression(visualRegression));
      summary.visualRegression = visualRegression;
    }
    if (summary.behaviorContract && summary.visualRegression) break;
  }
  return summary;
}

function validateBehaviorContract(contract) {
  const blockers = [];
  if (contract.applies === false) return blockers;
  if (contract.applies !== true) return blockers;
  if (!BEHAVIOR_MODES.has(contract.mode)) {
    blockers.push('unknown-behavior-contract-mode');
  }
  if (!BEHAVIOR_SOURCES.has(contract.source_of_truth)) {
    blockers.push('unknown-behavior-contract-source');
  }
  if (!FIXTURE_POLICIES.has(contract.fixture_policy)) {
    blockers.push('unknown-behavior-contract-fixture');
  }
  return blockers;
}

function validateVisualRegression(visualRegression) {
  const blockers = [];
  if (!VISUAL_EXPECTATIONS.has(visualRegression.expected)) {
    blockers.push('unknown-visual-regression-expected');
  }
  return blockers;
}

function summarizeTasks(tasksDir) {
  const summary = {
    total: 0,
    byStatus: {
      planned: 0,
      implemented: 0,
      in_progress: 0,
      in_review: 0,
      blocked: 0,
      unknown: 0,
      stale: 0,
    },
    staleSignals: [],
  };

  if (!fs.existsSync(tasksDir)) return summary;

  for (const file of taskFiles(tasksDir)) {
    summary.total += 1;
    const projection = projectTaskState(file);
    summary.byStatus[projection.bucket] += 1;
    if (projection.staleSignals.length > 0) {
      summary.byStatus.stale += 1;
      summary.staleSignals.push(...projection.staleSignals);
    }
  }

  summary.staleSignals = [...new Set(summary.staleSignals)].sort();
  return summary;
}

function taskFiles(tasksDir) {
  if (!fs.existsSync(tasksDir)) return [];
  const activeTasks = fs
    .readdirSync(tasksDir, { withFileTypes: true })
    .flatMap((entry) => {
      if (entry.isFile() && /^[TV]\d+[a-z]*\.md$/i.test(entry.name)) {
        return [path.join(tasksDir, entry.name)];
      }
      if (entry.isDirectory() && /^[TV]\d+[a-z]*$/i.test(entry.name)) {
        const indexFile = path.join(tasksDir, entry.name, 'index.md');
        return fs.existsSync(indexFile) ? [indexFile] : [];
      }
      return [];
    });
  const prReleaseDir = path.join(tasksDir, 'pr-release');
  const releasedTasks = fs.existsSync(prReleaseDir)
    ? fs
        .readdirSync(prReleaseDir, { withFileTypes: true })
        .flatMap((entry) => {
          if (entry.isFile() && /^[TV]\d+[a-z]*\.md$/i.test(entry.name)) {
            return [path.join(prReleaseDir, entry.name)];
          }
          if (entry.isDirectory() && /^[TV]\d+[a-z]*$/i.test(entry.name)) {
            const indexFile = path.join(prReleaseDir, entry.name, 'index.md');
            return fs.existsSync(indexFile) ? [indexFile] : [];
          }
          return [];
        })
    : [];
  return [...activeTasks, ...releasedTasks]
    .sort();
}

function projectTaskState(file) {
  const frontmatter = readMarkdownFrontmatter(file);
  const status = normalizeTaskStatus(frontmatter.status);
  const deliverable = normalizeDeliverable(frontmatter.deliverable);
  const publication = readTaskPublicationManifest(file);
  const snapshot = readTaskPrSnapshot(file);
  const staleSignals = [...deliverable.staleSignals];

  if (publication.invalid) staleSignals.push('task-publication-manifest-invalid');
  if (
    deliverable.valid &&
    publication.headSha &&
    deliverable.headSha &&
    publication.headSha !== deliverable.headSha
  ) {
    staleSignals.push('task-deliverable-publication-head-mismatch');
  }
  if (
    deliverable.valid &&
    snapshot &&
    snapshot.headSha &&
    deliverable.headSha &&
    snapshot.headSha !== deliverable.headSha
  ) {
    staleSignals.push('task-deliverable-pr-snapshot-head-mismatch');
  }
  if (
    deliverable.valid &&
    snapshot &&
    snapshot.prState &&
    snapshot.prState !== 'UNKNOWN' &&
    deliverable.prState &&
    snapshot.prState !== deliverable.prState
  ) {
    staleSignals.push('task-deliverable-pr-snapshot-state-mismatch');
  }

  if (status === 'planned') return { bucket: 'planned', staleSignals };
  if (status === 'implemented') return { bucket: 'implemented', staleSignals };
  if (status === 'in_progress' || status === 'implementing') {
    return { bucket: 'in_progress', staleSignals };
  }
  if (status === 'blocked') return { bucket: 'blocked', staleSignals };
  if (deliverable.valid) return { bucket: 'in_review', staleSignals };
  return { bucket: 'unknown', staleSignals };
}

function normalizeDeliverable(deliverable) {
  const staleSignals = [];
  if (deliverable === undefined) return { valid: false, staleSignals };
  if (!deliverable || typeof deliverable !== 'object' || Array.isArray(deliverable)) {
    return { valid: false, staleSignals: ['task-deliverable-invalid'] };
  }
  const prUrl = String(deliverable.pr_url ?? '').trim();
  const prState = String(deliverable.pr_state ?? '').trim().toUpperCase();
  const headSha = String(deliverable.head_sha ?? '').trim();
  if (!/^https:\/\/github\.com\/.+\/pull\/\d+$/.test(prUrl)) {
    staleSignals.push('task-deliverable-invalid');
  }
  if (!['OPEN', 'MERGED', 'CLOSED'].includes(prState)) {
    staleSignals.push('task-deliverable-invalid');
  }
  if (!/^[0-9a-f]{7,}$/i.test(headSha)) {
    staleSignals.push('task-deliverable-invalid');
  }
  const valid = staleSignals.length === 0;
  if (!valid) {
    return { valid: false, staleSignals: [...new Set(staleSignals)] };
  }
  return { valid: true, prUrl, prState, headSha, staleSignals };
}

function readTaskPublicationManifest(taskFile) {
  const taskDir = taskArtifactDir(taskFile);
  const manifest = path.join(taskDir, 'publication-manifest.json');
  if (!fs.existsSync(manifest)) return {};
  try {
    const data = JSON.parse(fs.readFileSync(manifest, 'utf8'));
    const headSha = String(data.head_sha ?? '').trim();
    return {
      headSha: /^[0-9a-f]{7,}$/i.test(headSha) ? headSha : null,
    };
  } catch {
    return { invalid: true };
  }
}

function readTaskPrSnapshot(taskFile) {
  const snapshotFile = path.join(taskArtifactDir(taskFile), 'pr-state-snapshot.json');
  if (!fs.existsSync(snapshotFile)) return null;
  let data;
  try {
    data = JSON.parse(fs.readFileSync(snapshotFile, 'utf8'));
  } catch {
    throw new Error(`${snapshotFile}: invalid PR state snapshot JSON`);
  }
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new Error(`${snapshotFile}: invalid PR state snapshot shape`);
  }
  const prState = String(data.pr_state ?? 'UNKNOWN').trim().toUpperCase();
  if (!['OPEN', 'MERGED', 'CLOSED', 'UNKNOWN'].includes(prState)) {
    throw new Error(`${snapshotFile}: invalid pr_state: ${data.pr_state}`);
  }
  const rawHeadSha = data.head_sha === null || data.head_sha === undefined ? null : String(data.head_sha).trim();
  if (rawHeadSha && !/^[0-9a-f]{7,}$/i.test(rawHeadSha)) {
    throw new Error(`${snapshotFile}: invalid head_sha: ${data.head_sha}`);
  }
  return { prState, headSha: rawHeadSha };
}

function taskArtifactDir(taskFile) {
  if (path.basename(taskFile) === 'index.md') return path.dirname(taskFile);
  return path.join(path.dirname(taskFile), path.basename(taskFile, '.md'));
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

function normalizeTaskStatus(value) {
  if (!value) return 'unknown';
  const raw = String(value).trim();
  const aliased = TASK_STATUS_ALIASES.get(raw.toUpperCase()) ?? raw.toLowerCase();
  return TASK_STATUS_VALUES.has(aliased) ? aliased : 'unknown';
}

function normalizeDateString(value) {
  if (value === undefined || value === null || value === '') return null;
  const raw = String(value).trim();
  if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) return raw;
  if (/^\d{8}$/.test(raw)) return `${raw.slice(0, 4)}-${raw.slice(4, 6)}-${raw.slice(6, 8)}`;
  return null;
}

function extractDate(value) {
  const raw = String(value);
  const compact = raw.match(/(?:^|[^0-9])(\d{8})(?:[^0-9]|$)/);
  if (compact) return normalizeDateString(compact[1]);
  const dashed = raw.match(/(?:^|[^0-9])(\d{4}-\d{2}-\d{2})(?:[^0-9]|$)/);
  return dashed ? normalizeDateString(dashed[1]) : null;
}
