import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const specsRoot = process.env.POLARIS_SPECS_ROOT
  ? path.resolve(process.env.POLARIS_SPECS_ROOT)
  : path.join(rootDir, 'src/content/docs/specs');
const shouldWrite = process.argv.includes('--write');

function walk(dir, visitor) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const entryPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(entryPath, visitor);
      continue;
    }
    visitor(entryPath);
  }
}

function isLegacyTaskDoc(file) {
  if (!file.endsWith('.md')) return false;
  if (path.basename(file) === 'index.md') return false;

  const parentName = path.basename(path.dirname(file));
  return parentName === 'tasks' || parentName === 'pr-release';
}

const migrations = [];
walk(specsRoot, (file) => {
  if (!isLegacyTaskDoc(file)) return;
  const parent = path.dirname(file);
  const taskName = path.basename(file, '.md');
  const target = path.join(parent, taskName, 'index.md');
  migrations.push({ source: file, target });
});

if (!shouldWrite) {
  for (const migration of migrations) {
    console.log(`${path.relative(rootDir, migration.source)} -> ${path.relative(rootDir, migration.target)}`);
  }
  if (migrations.length > 0) {
    console.error(`FAIL: ${migrations.length} legacy task markdown file(s) need migration. Run with --write.`);
    process.exit(1);
  }
  console.log('PASS: no legacy task markdown files found');
  process.exit(0);
}

for (const { source, target } of migrations) {
  if (fs.existsSync(target)) {
    throw new Error(`Refusing to overwrite existing task index: ${target}`);
  }
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.renameSync(source, target);
  console.log(`${path.relative(rootDir, source)} -> ${path.relative(rootDir, target)}`);
}

console.log(`Migrated ${migrations.length} legacy task markdown file(s).`);
