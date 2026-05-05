#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const args = parseArgs(process.argv.slice(2));
if (args.help) {
  printUsage();
  process.exit(0);
}

const linksPath = requiredFile(args.links, '--links');
const links = JSON.parse(fs.readFileSync(linksPath, 'utf8'));
const outputPath = path.resolve(args.output || path.join(path.dirname(linksPath), 'verify-report.md'));
const reportDir = path.dirname(outputPath);
const scope = args.scope || links.scope || 'evidence';
const title = args.title || `Verify Report - ${scope}`;
const description = args.description || `Verification evidence report for ${scope}.`;
const status = args.status || 'LOCAL_EVIDENCE';

fs.mkdirSync(reportDir, { recursive: true });
fs.writeFileSync(outputPath, renderReport(), 'utf8');

console.log(JSON.stringify({ output: outputPath, images: images().length, videos: videos().length }, null, 2));

function parseArgs(argv) {
  const parsed = {};
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    switch (arg) {
      case '--links':
      case '--output':
      case '--title':
      case '--description':
      case '--status':
      case '--scope': {
        const key = arg.slice(2).replace(/-([a-z])/g, (_, char) => char.toUpperCase());
        const value = argv[index + 1];
        if (!value) fail(`${arg} requires a value`);
        parsed[key] = value;
        index += 1;
        break;
      }
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

function printUsage() {
  console.log(`Usage:
  node scripts/generate-verify-report.mjs --links <links.json> [--output <verify-report.md>] [--title <title>] [--description <text>] [--status <status>]

Generates a Starlight-valid Markdown verification report from deterministic evidence links.`);
}

function requiredFile(value, label) {
  if (!value) fail(`${label} is required`);
  const resolved = path.resolve(value);
  if (!fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
    fail(`${label} not found: ${resolved}`);
  }
  return resolved;
}

function fail(message) {
  console.error(`[polaris generate-verify-report] ${message}`);
  process.exit(64);
}

function renderReport() {
  const lines = [
    '---',
    `title: ${JSON.stringify(title)}`,
    `description: ${JSON.stringify(description)}`,
    '---',
    '',
    '## Summary',
    '',
    `- Scope: \`${scope}\``,
    `- Status: \`${status}\``,
    `- Generated at: \`${links.generated_at || 'unknown'}\``,
    `- Links manifest: [links.json](${relativeLink(linksPath)})`,
    `- Publication manifest: [publication-manifest.json](${relativeLink(path.join(path.dirname(linksPath), 'publication-manifest.json'))})`,
    '',
  ];

  appendScreenshots(lines);
  appendVideos(lines);
  appendSupportingEvidence(lines);
  return `${lines.join('\n')}\n`;
}

function appendScreenshots(lines) {
  lines.push('## Screenshots', '');
  const entries = images();
  if (entries.length === 0) {
    lines.push('No screenshot evidence was collected.', '');
    return;
  }
  for (const item of entries) {
    lines.push(`![${altText(item)}](${relativeLink(item.asset_path)})`, '');
  }
}

function appendVideos(lines) {
  lines.push('## Videos', '');
  const entries = videos();
  if (entries.length === 0) {
    lines.push('No video evidence was collected.', '');
    return;
  }
  for (const item of entries) {
    const href = item.public_url || relativeLink(item.asset_path);
    lines.push(`- [${label(item)}](${href})`);
  }
  lines.push('');
}

function appendSupportingEvidence(lines) {
  const entries = items().filter((item) => item.kind !== 'image' && item.kind !== 'video');
  lines.push('## Supporting Evidence', '');
  if (entries.length === 0) {
    lines.push('No supporting raw evidence was collected.', '');
    return;
  }
  lines.push('| File | Kind | SHA-256 |', '|------|------|---------|');
  for (const item of entries) {
    lines.push(`| [${path.basename(item.asset_path)}](${relativeLink(item.asset_path)}) | \`${item.kind}\` | \`${item.sha256}\` |`);
  }
  lines.push('');
}

function images() {
  return items().filter((item) => item.kind === 'image');
}

function videos() {
  return items().filter((item) => item.kind === 'video');
}

function items() {
  return Array.isArray(links.items) ? links.items : [];
}

function relativeLink(file) {
  if (!file) return '#';
  const resolved = path.resolve(file);
  let relative = path.relative(reportDir, resolved).split(path.sep).join('/');
  if (!relative.startsWith('.')) relative = `./${relative}`;
  return relative;
}

function label(item) {
  return path.basename(item.asset_path || item.public_url || item.id || 'evidence');
}

function altText(item) {
  return label(item)
    .replace(/\.[^.]+$/u, '')
    .replace(/[-_]+/gu, ' ')
    .trim() || 'verification screenshot';
}
