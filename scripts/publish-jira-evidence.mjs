#!/usr/bin/env node
import childProcess from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const args = parseArgs(process.argv.slice(2));
if (args.help) {
  printUsage();
  process.exit(0);
}

const repoRoot = path.resolve(args.repo || process.cwd());
const manifestPath = requiredFile(args.manifest, '--manifest');
const linksPath = args.links ? requiredFile(args.links, '--links') : defaultLinksPath(manifestPath);
const reportPath = args.report ? path.resolve(args.report) : null;
const jiraKey = args.jiraKey || args.issueKey || '';
const mode = args.apply ? 'apply' : 'dry-run';
const outputPath = path.resolve(args.output || manifestPath);
const uploader = path.resolve(args.uploader || path.join(repoRoot, 'scripts/jira-upload-attachment.sh'));

const manifest = readJson(manifestPath);
const links = linksPath ? readJson(linksPath) : {};
const safety = runSafetyGate({ repoRoot, manifestPath, linksPath });
const publishableArtifacts = safety.artifacts.filter((artifact) => artifact.status === 'publishable');
const generatedAt = timestamp();

if (!jiraKey || jiraKey === 'N/A') {
  writePublication({
    status: 'local_only',
    reason: 'jira key missing',
    attachments: [],
  });
  console.log(JSON.stringify({
    status: 'local_only',
    jira_key: jiraKey || null,
    planned_uploads: 0,
    manifest: outputPath,
  }, null, 2));
  process.exit(0);
}

if (safety.status !== 'pass') {
  writePublication({
    status: 'blocked',
    reason: 'safety gate blocked remote publication',
    attachments: [],
  });
  console.error(JSON.stringify({
    status: 'blocked',
    jira_key: jiraKey,
    safety_summary: safety.summary,
  }, null, 2));
  process.exit(2);
}

if (publishableArtifacts.length === 0) {
  writePublication({
    status: 'local_only',
    reason: 'no publishable artifacts require Jira publication',
    attachments: [],
  });
  console.log(JSON.stringify({
    status: 'local_only',
    jira_key: jiraKey,
    planned_uploads: 0,
    manifest: outputPath,
  }, null, 2));
  process.exit(0);
}

if (mode === 'dry-run') {
  writePublication({
    status: 'dry_run',
    reason: 'dry-run only; Jira uploader was not called',
    attachments: plannedAttachments(),
  });
  console.log(JSON.stringify({
    status: 'dry_run',
    jira_key: jiraKey,
    planned_uploads: publishableArtifacts.length,
    files: publishableArtifacts.map((artifact) => artifact.path),
    manifest: outputPath,
  }, null, 2));
  process.exit(0);
}

if (!fs.existsSync(uploader) || !fs.statSync(uploader).isFile()) {
  fail(`uploader not found: ${uploader}`, 66);
}

const uploaded = uploadArtifacts();
writePublication({
  status: 'uploaded',
  reason: 'Jira attachments uploaded',
  attachments: uploaded,
});
console.log(JSON.stringify({
  status: 'uploaded',
  jira_key: jiraKey,
  uploaded: uploaded.length,
  manifest: outputPath,
}, null, 2));

function parseArgs(argv) {
  const parsed = {};
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    switch (arg) {
      case '--repo':
      case '--manifest':
      case '--links':
      case '--jira-key':
      case '--issue-key':
      case '--output':
      case '--report':
      case '--uploader': {
        const key = arg.slice(2).replace(/-([a-z])/g, (_, char) => char.toUpperCase());
        const value = argv[index + 1];
        if (!value) fail(`${arg} requires a value`, 64);
        parsed[key] = value;
        index += 1;
        break;
      }
      case '--dry-run':
        parsed.dryRun = true;
        break;
      case '--apply':
        parsed.apply = true;
        break;
      case '-h':
      case '--help':
        parsed.help = true;
        break;
      default:
        fail(`unknown argument: ${arg}`, 64);
    }
  }
  if (parsed.apply && parsed.dryRun) {
    fail('--apply and --dry-run are mutually exclusive', 64);
  }
  return parsed;
}

function printUsage() {
  console.log(`Usage:
  node scripts/publish-jira-evidence.mjs --manifest <publication-manifest.json> [--links <links.json>] --jira-key <KEY> [--dry-run|--apply] [--report <verify-report.md>] [--uploader <script>]

Runs evidence publication safety classification, uploads publishable required artifacts to Jira in apply mode, and writes Jira attachment URLs back to the publication manifest and optional verify report.`);
}

function requiredFile(value, label) {
  if (!value) fail(`${label} is required`, 64);
  const resolved = path.resolve(value);
  if (!fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
    fail(`${label} not found: ${resolved}`, 64);
  }
  return resolved;
}

function defaultLinksPath(manifest) {
  const candidate = path.join(path.dirname(manifest), 'links.json');
  return fs.existsSync(candidate) ? candidate : null;
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function runSafetyGate({ repoRoot: root, manifestPath: manifestFile, linksPath: linksFile }) {
  const safetyGate = path.join(root, 'scripts/safety-gate.sh');
  const commandArgs = ['evidence-publication', '--manifest', manifestFile];
  if (linksFile) commandArgs.push('--links', linksFile);
  const result = childProcess.spawnSync('bash', [safetyGate, ...commandArgs], {
    cwd: root,
    encoding: 'utf8',
  });
  if (!result.stdout) {
    fail(`safety gate produced no JSON output: ${result.stderr}`, result.status || 1);
  }
  let parsed;
  try {
    parsed = JSON.parse(result.stdout);
  } catch (error) {
    fail(`safety gate produced invalid JSON: ${error.message}`, result.status || 1);
  }
  if (result.status !== 0 && result.status !== 2) {
    fail(`safety gate failed: ${result.stderr || result.stdout}`, result.status || 1);
  }
  return parsed;
}

function plannedAttachments() {
  return publishableArtifacts.map((artifact) => ({
    filename: artifact.filename,
    source_path: artifact.path,
    url: null,
    status: 'planned',
  }));
}

function uploadArtifacts() {
  const files = publishableArtifacts.map((artifact) => artifact.path);
  const result = childProcess.spawnSync('bash', [uploader, jiraKey, ...files], {
    cwd: repoRoot,
    encoding: 'utf8',
  });
  if (result.status !== 0) {
    writePublication({
      status: 'failed',
      reason: `Jira uploader failed with exit ${result.status}`,
      attachments: plannedAttachments(),
      error: (result.stderr || result.stdout || '').trim(),
    });
    fail(`Jira uploader failed: ${result.stderr || result.stdout}`, result.status || 1);
  }

  const rows = result.stdout
    .split(/\r?\n/u)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      try {
        return JSON.parse(line);
      } catch (error) {
        fail(`uploader emitted non-JSON line: ${line}`, 65);
      }
    });

  const byFilename = new Map(rows.map((row) => [row.filename, row]));
  return publishableArtifacts.map((artifact) => {
    const uploaded = byFilename.get(artifact.filename) || {};
    if (!uploaded.url) {
      fail(`uploader did not return attachment URL for ${artifact.filename}`, 65);
    }
    return {
      id: uploaded.id || null,
      filename: artifact.filename,
      source_path: artifact.path,
      url: uploaded.url,
      thumbnail: uploaded.thumbnail || null,
      mimeType: uploaded.mimeType || null,
      status: 'uploaded',
    };
  });
}

function writePublication({ status, reason, attachments, error }) {
  const next = structuredClone(manifest);
  const attachmentByFilename = new Map(attachments.map((attachment) => [attachment.filename, attachment]));
  next.status = status === 'uploaded' ? 'jira_uploaded' : manifest.status || 'local_only';
  next.remote_publication = {
    target: 'jira',
    jira_key: jiraKey || null,
    status,
    reason,
    updated_at: generatedAt,
    uploaded_count: attachments.filter((attachment) => attachment.status === 'uploaded').length,
    planned_count: publishableArtifacts.length,
    blocked_count: safety.summary?.blocked || 0,
    error: error || null,
  };
  next.artifacts = Array.isArray(next.artifacts) ? next.artifacts.map((artifact) => {
    const attachment = attachmentByFilename.get(artifact.filename);
    const safetyArtifact = safety.artifacts.find((item) => item.id === artifact.id || item.filename === artifact.filename);
    const updated = {
      ...artifact,
      safety: safetyArtifact ? {
        status: safetyArtifact.status,
        reason: safetyArtifact.reason,
        publishable: safetyArtifact.publishable,
      } : artifact.safety,
    };
    if (attachment) {
      updated.jira_attachment = {
        id: attachment.id || null,
        url: attachment.url || null,
        filename: attachment.filename,
        mimeType: attachment.mimeType || null,
        status: attachment.status,
        uploaded_at: generatedAt,
      };
    }
    return updated;
  }) : [];
  fs.writeFileSync(outputPath, `${JSON.stringify(next, null, 2)}\n`, 'utf8');
  if (reportPath) {
    writeReportSection(reportPath, attachments, status, reason);
  }
}

function writeReportSection(file, attachments, status, reason) {
  const begin = '<!-- polaris-jira-attachments:start -->';
  const end = '<!-- polaris-jira-attachments:end -->';
  const body = [
    begin,
    '',
    '## Jira Attachments',
    '',
    `- Jira key: \`${jiraKey || 'N/A'}\``,
    `- Status: \`${status}\``,
    `- Reason: ${reason}`,
    '',
  ];
  if (attachments.length === 0) {
    body.push('No Jira attachments were published.', '');
  } else {
    body.push('| File | Status | Jira URL |', '|------|--------|----------|');
    for (const attachment of attachments) {
      const href = attachment.url ? `[${attachment.filename}](${attachment.url})` : attachment.filename;
      body.push(`| ${attachment.filename} | \`${attachment.status}\` | ${href} |`);
    }
    body.push('');
  }
  body.push(end, '');

  const rendered = body.join('\n');
  const current = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
  const pattern = new RegExp(`${escapeRegExp(begin)}[\\s\\S]*?${escapeRegExp(end)}\\n?`, 'u');
  const next = pattern.test(current)
    ? current.replace(pattern, rendered)
    : `${current.replace(/\s*$/u, '')}\n\n${rendered}`;
  fs.writeFileSync(file, next, 'utf8');
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
}

function timestamp() {
  return new Date().toISOString().replace(/\.\d{3}Z$/u, 'Z');
}

function fail(message, code = 1) {
  console.error(`[polaris publish-jira-evidence] ${message}`);
  process.exit(code);
}
