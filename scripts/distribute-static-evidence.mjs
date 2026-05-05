#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const IMAGE_EXTENSIONS = new Set(['.png', '.jpg', '.jpeg', '.webp', '.gif', '.svg']);
const VIDEO_EXTENSIONS = new Set(['.webm', '.mp4', '.mov', '.m4v']);
const RAW_EXTENSIONS = new Set(['.json', '.har', '.log', '.txt', '.trace']);
const GENERATED_NAMES = new Set([
  'links.json',
  'publication-manifest.json',
  'verify-report.md',
  'README.md',
]);

const args = parseArgs(process.argv.slice(2));
if (args.help) {
  printUsage();
  process.exit(0);
}

const sourceDir = requiredDir(args.source || args.input, '--source');
const outputDir = path.resolve(args.outputDir || sourceDir);
const scope = safeSlug(args.scope || inferScope(sourceDir));
const publicRoot = path.resolve(args.publicRoot || path.join(process.cwd(), 'docs-manager/public/evidence'));
const publicBase = normalizePublicBase(args.publicBase || '/evidence');
const clean = args.clean === true;

if (clean) {
  cleanGeneratedOutput(outputDir);
}

fs.mkdirSync(outputDir, { recursive: true });

const usedNamesByBucket = new Map();
const sourceFiles = listSourceFiles(sourceDir, outputDir);
const items = sourceFiles.map((sourcePath) => distributeFile(sourcePath)).filter(Boolean);

const generatedAt = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
const links = {
  schema_version: 1,
  kind: 'polaris-static-evidence-links',
  scope,
  source_dir: sourceDir,
  output_dir: outputDir,
  public_root: publicRoot,
  public_base: publicBase,
  generated_at: generatedAt,
  items,
  images: items.filter((item) => item.kind === 'image'),
  videos: items.filter((item) => item.kind === 'video'),
  raw: items.filter((item) => item.kind === 'raw'),
  files: items.filter((item) => item.kind === 'file'),
};

const publicationManifest = {
  schema_version: 1,
  kind: 'polaris-evidence-publication-manifest',
  scope,
  status: 'local_only',
  generated_at: generatedAt,
  note: 'Local board links are publishable in Starlight. Remote PR/Jira attachment upload is handled by a separate flow.',
  artifacts: items
    .filter((item) => item.kind === 'image' || item.kind === 'video')
    .map((item) => ({
      id: item.id,
      kind: item.kind,
      filename: path.basename(item.asset_path),
      local_link: item.relative_link,
      public_url: item.public_url || null,
      sha256: item.sha256,
      publication_required: false,
    })),
};

writeJson(path.join(outputDir, 'links.json'), links);
writeJson(path.join(outputDir, 'publication-manifest.json'), publicationManifest);

console.log(JSON.stringify({
  output_dir: outputDir,
  links: path.join(outputDir, 'links.json'),
  publication_manifest: path.join(outputDir, 'publication-manifest.json'),
  items: items.length,
}, null, 2));

function parseArgs(argv) {
  const parsed = {};
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    switch (arg) {
      case '--source':
      case '--input':
      case '--output-dir':
      case '--scope':
      case '--public-root':
      case '--public-base': {
        const key = arg.slice(2).replace(/-([a-z])/g, (_, char) => char.toUpperCase());
        const value = argv[index + 1];
        if (!value) fail(`${arg} requires a value`);
        parsed[key] = value;
        index += 1;
        break;
      }
      case '--clean':
        parsed.clean = true;
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

function printUsage() {
  console.log(`Usage:
  node scripts/distribute-static-evidence.mjs --source <folder> [--output-dir <folder>] [--scope <id>] [--public-root <folder>] [--public-base <path>] [--clean]

Copies evidence into assets/**, mirrors videos under the configured public root, and writes links.json plus publication-manifest.json.`);
}

function requiredDir(value, label) {
  if (!value) fail(`${label} is required`);
  const resolved = path.resolve(value);
  if (!fs.existsSync(resolved) || !fs.statSync(resolved).isDirectory()) {
    fail(`${label} not found or not a directory: ${resolved}`);
  }
  return resolved;
}

function fail(message) {
  console.error(`[polaris distribute-static-evidence] ${message}`);
  process.exit(64);
}

function inferScope(source) {
  const basename = path.basename(source);
  return basename.replace(/-(pr|jira|evidence)-upload$/u, '') || 'evidence';
}

function safeSlug(value) {
  return String(value)
    .replace(/[^A-Za-z0-9._-]+/gu, '-')
    .replace(/^-+|-+$/gu, '') || 'evidence';
}

function normalizePublicBase(value) {
  const trimmed = String(value || '/evidence').replace(/\/+$/u, '');
  return trimmed.startsWith('/') ? trimmed : `/${trimmed}`;
}

function cleanGeneratedOutput(target) {
  for (const relative of ['assets', 'links.json', 'publication-manifest.json']) {
    fs.rmSync(path.join(target, relative), { recursive: true, force: true });
  }
}

function listSourceFiles(root, output) {
  const result = [];
  const resolvedOutput = path.resolve(output);

  function walk(current) {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const absolute = path.join(current, entry.name);
      if (entry.isDirectory()) {
        if (path.resolve(absolute) === path.join(resolvedOutput, 'assets')) continue;
        if (entry.name === 'node_modules' || entry.name === '.git') continue;
        walk(absolute);
        continue;
      }
      if (!entry.isFile()) continue;
      if (GENERATED_NAMES.has(entry.name)) continue;
      result.push(absolute);
    }
  }

  walk(root);
  return result.sort();
}

function distributeFile(sourcePath) {
  const ext = path.extname(sourcePath).toLowerCase();
  const kind = classifyExtension(ext);
  if (!kind) return null;

  const bucket = kind === 'image' ? 'screenshots' : kind === 'video' ? 'videos' : kind === 'raw' ? 'raw' : 'files';
  const filename = uniqueName(bucket, sourcePath);
  const assetPath = path.join(outputDir, 'assets', bucket, filename);
  fs.mkdirSync(path.dirname(assetPath), { recursive: true });
  fs.copyFileSync(sourcePath, assetPath);

  const sha256 = sha256File(assetPath);
  const item = {
    id: `${kind}-${sha256.slice(0, 12)}`,
    kind,
    source_path: sourcePath,
    asset_path: assetPath,
    relative_link: relativeLink(outputDir, assetPath),
    size: fs.statSync(assetPath).size,
    sha256,
    local_board_publishable: true,
    remote_publication_required: false,
  };

  if (kind === 'video') {
    const publicPath = path.join(publicRoot, scope, filename);
    fs.mkdirSync(path.dirname(publicPath), { recursive: true });
    fs.copyFileSync(sourcePath, publicPath);
    item.public_path = publicPath;
    item.public_url = `${publicBase}/${scope}/${filename}`;
  }

  return item;
}

function classifyExtension(ext) {
  if (IMAGE_EXTENSIONS.has(ext)) return 'image';
  if (VIDEO_EXTENSIONS.has(ext)) return 'video';
  if (RAW_EXTENSIONS.has(ext)) return 'raw';
  return 'file';
}

function uniqueName(bucket, sourcePath) {
  const used = usedNamesByBucket.get(bucket) || new Set();
  usedNamesByBucket.set(bucket, used);

  const base = safeSlug(path.basename(sourcePath, path.extname(sourcePath)));
  const ext = path.extname(sourcePath).toLowerCase();
  let candidate = `${base}${ext}`;
  if (!used.has(candidate)) {
    used.add(candidate);
    return candidate;
  }

  const digest = crypto.createHash('sha256').update(sourcePath).digest('hex').slice(0, 8);
  candidate = `${base}-${digest}${ext}`;
  while (used.has(candidate)) {
    const nextDigest = crypto.createHash('sha256').update(`${candidate}:${sourcePath}`).digest('hex').slice(0, 8);
    candidate = `${base}-${nextDigest}${ext}`;
  }
  used.add(candidate);
  return candidate;
}

function sha256File(file) {
  const hash = crypto.createHash('sha256');
  hash.update(fs.readFileSync(file));
  return hash.digest('hex');
}

function relativeLink(fromDir, file) {
  const relative = path.relative(fromDir, file).split(path.sep).join('/');
  return relative.startsWith('.') ? relative : `./${relative}`;
}

function writeJson(file, data) {
  fs.writeFileSync(file, `${JSON.stringify(data, null, 2)}\n`, 'utf8');
}
