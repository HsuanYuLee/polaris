import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const docsManagerRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const workspaceRoot = path.resolve(docsManagerRoot, '..');
const specsRoot = path.join(docsManagerRoot, 'src/content/docs/specs');
const legacyNames = new Set(['artifacts', 'escalations', 'refinement-inbox', 'tests']);
const write = process.argv.includes('--write');

const moves = [];

function walk(dir, visitor) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const entryPath = path.join(dir, entry.name);
    visitor(entryPath, entry);
    if (entry.isDirectory()) walk(entryPath, visitor);
  }
}

function isInsideAssetsLegacy(targetPath) {
  return targetPath.split(path.sep).includes('assets') && targetPath.split(path.sep).includes('legacy');
}

function listLegacyDirs() {
  const dirs = [];
  walk(specsRoot, (entryPath, entry) => {
    if (!entry.isDirectory()) return;
    if (!legacyNames.has(entry.name)) return;
    if (isInsideAssetsLegacy(entryPath)) return;
    dirs.push(entryPath);
  });
  return dirs.sort((a, b) => b.length - a.length);
}

function listLegacyMarkdownFiles() {
  const files = [];
  walk(specsRoot, (entryPath, entry) => {
    if (!entry.isFile()) return;
    if (!entryPath.endsWith('.md')) return;
    if (!isInsideAssetsLegacy(entryPath)) return;
    files.push(entryPath);
  });
  return files.sort();
}

function ensureDir(dir) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function sameFile(a, b) {
  return fs.existsSync(a) && fs.existsSync(b) && fs.readFileSync(a).equals(fs.readFileSync(b));
}

function movePath(source, target) {
  ensureDir(path.dirname(target));
  if (fs.existsSync(target)) {
    if (fs.statSync(source).isFile() && sameFile(source, target)) {
      fs.rmSync(source);
      return;
    }
    throw new Error(`target already exists: ${target}`);
  }
  fs.renameSync(source, target);
}

function moveDirectoryContents(sourceDir, targetDir, containerDir) {
  ensureDir(targetDir);
  for (const entry of fs.readdirSync(sourceDir, { withFileTypes: true })) {
    const source = path.join(sourceDir, entry.name);
    const target = path.join(targetDir, entry.name);
    if (entry.isDirectory()) {
      moveDirectoryContents(source, target, containerDir);
      if (fs.existsSync(source) && fs.readdirSync(source).length === 0) fs.rmdirSync(source);
      continue;
    }
    movePath(source, target);
    moves.push({ oldPath: source, newPath: target, containerDir });
  }
  if (fs.existsSync(sourceDir) && fs.readdirSync(sourceDir).length === 0) fs.rmdirSync(sourceDir);
}

function migrateLegacyDirs() {
  for (const legacyDir of listLegacyDirs()) {
    const name = path.basename(legacyDir);
    const containerDir = path.dirname(legacyDir);
    const targetDir = path.join(containerDir, 'assets/legacy', name);
    moveDirectoryContents(legacyDir, targetDir, containerDir);
  }
}

function convertLegacyMarkdown() {
  for (const file of listLegacyMarkdownFiles()) {
    const target = `${file}.txt`;
    movePath(file, target);
    moves.push({ oldPath: file, newPath: target, containerDir: nearestSpecContainer(file) });
  }
}

function nearestSpecContainer(file) {
  let current = path.dirname(file);
  while (current.startsWith(specsRoot)) {
    const parent = path.dirname(current);
    if (path.basename(parent) === 'assets' && path.basename(current) === 'legacy') {
      current = path.dirname(parent);
      continue;
    }
    if (fs.existsSync(path.join(current, 'index.md')) || fs.existsSync(path.join(current, 'plan.md'))) return current;
    current = parent;
  }
  return specsRoot;
}

function textFiles() {
  const files = [];
  walk(specsRoot, (entryPath, entry) => {
    if (!entry.isFile()) return;
    if (!/\.(md|json|ya?ml|txt)$/.test(entryPath)) return;
    files.push(entryPath);
  });
  return files;
}

function replacementPairsForMove(move) {
  const pairs = [];
  const oldRelWorkspace = path.relative(workspaceRoot, move.oldPath).replaceAll(path.sep, '/');
  const newRelWorkspace = path.relative(workspaceRoot, move.newPath).replaceAll(path.sep, '/');
  const oldRelSpecs = path.relative(specsRoot, move.oldPath).replaceAll(path.sep, '/');
  const newRelSpecs = path.relative(specsRoot, move.newPath).replaceAll(path.sep, '/');
  const oldRelContainer = path.relative(move.containerDir, move.oldPath).replaceAll(path.sep, '/');
  const newRelContainer = path.relative(move.containerDir, move.newPath).replaceAll(path.sep, '/');

  pairs.push([oldRelWorkspace, newRelWorkspace]);
  pairs.push([oldRelSpecs, newRelSpecs]);
  pairs.push([`specs/${oldRelSpecs}`, `specs/${newRelSpecs}`]);
  pairs.push([oldRelContainer, newRelContainer]);
  pairs.push([`./${oldRelContainer}`, `./${newRelContainer}`]);
  return pairs;
}

function replaceAllLiteral(text, needle, replacement) {
  return text.split(needle).join(replacement);
}

function replacePathReference(text, needle, replacement) {
  if (needle.includes('assets/legacy/')) {
    return replaceAllLiteral(text, needle, replacement);
  }
  return text.replaceAll(new RegExp(`(?<!assets/legacy/)${escapeRegExp(needle)}`, 'g'), replacement);
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function rewriteReferences() {
  const pairs = moves.flatMap(replacementPairsForMove);
  if (pairs.length === 0) return;

  for (const file of textFiles()) {
    let text = fs.readFileSync(file, 'utf8');
    let updated = text;
    for (const [needle, replacement] of pairs) {
      updated = replacePathReference(updated, needle, replacement);
    }
    if (updated !== text) fs.writeFileSync(file, updated);
  }
}

if (!fs.existsSync(specsRoot)) {
  throw new Error(`specs root not found: ${specsRoot}`);
}

if (write) {
  migrateLegacyDirs();
  convertLegacyMarkdown();
  rewriteReferences();
  console.log(`migrated legacy files: ${moves.length}`);
}

const remainingDirs = listLegacyDirs();
const remainingMarkdown = listLegacyMarkdownFiles();
if (remainingDirs.length > 0 || remainingMarkdown.length > 0) {
  console.error('Legacy spec folders or markdown files remain:');
  for (const dir of remainingDirs) console.error(`DIR ${path.relative(workspaceRoot, dir)}`);
  for (const file of remainingMarkdown) console.error(`MD ${path.relative(workspaceRoot, file)}`);
  process.exit(1);
}

console.log('PASS: no routable legacy spec folders found');
