import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const rootDir = path.dirname(fileURLToPath(import.meta.url));
const docsRoot = path.join(rootDir, 'src/content/docs');
const specsRoot = path.join(docsRoot, 'specs');

const folderMetadataDocNames = ['plan.md', 'epic.md', 'refinement.md', 'breakdown.md', 'README.md'];
const fileOrder = new Map([
  ['README.md', 0],
  ['epic.md', 10],
  ['plan.md', 20],
  ['refinement.md', 30],
  ['breakdown.md', 40],
]);
const directoryOrder = new Map([
  ['artifacts', 80],
  ['escalations', 90],
  ['tasks', 100],
  ['tests', 110],
  ['verification', 120],
  ['archive', 900],
  ['pr-release', 910],
]);

export function specsSidebar() {
  return [
    {
      label: 'design-plans',
      collapsed: false,
      items: [...designPlanItems(false), archiveGroup('archive', designPlanItems(true))],
    },
    {
      label: 'companies',
      collapsed: false,
      items: companyItems(),
    },
  ].filter((item) => !('items' in item) || item.items.length > 0);
}

function designPlanItems(archived) {
  const base = archived
    ? path.join(specsRoot, 'design-plans/archive')
    : path.join(specsRoot, 'design-plans');
  if (!fs.existsSync(base)) return [];

  return fs
    .readdirSync(base, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .filter((entry) => entry.name.startsWith('DP-'))
    .map((entry) => folderItem(path.join(base, entry.name), { metadataFile: 'plan.md' }))
    .filter(Boolean)
    .sort(sortByOrderThenLabel);
}

function companyItems() {
  const companiesRoot = path.join(specsRoot, 'companies');
  if (!fs.existsSync(companiesRoot)) return [];

  return fs
    .readdirSync(companiesRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => {
      const companyDir = path.join(companiesRoot, entry.name);
      const items = [...ticketItems(companyDir, false), archiveGroup('archive', ticketItems(companyDir, true))];
      return {
        label: entry.name,
        collapsed: false,
        items: items.filter((item) => !('items' in item) || item.items.length > 0),
      };
    })
    .filter((item) => item.items.length > 0);
}

function ticketItems(companyDir, archived) {
  const base = archived ? path.join(companyDir, 'archive') : companyDir;
  if (!fs.existsSync(base)) return [];

  return fs
    .readdirSync(base, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .filter((entry) => entry.name !== 'archive')
    .map((entry) => folderItem(path.join(base, entry.name)))
    .filter(Boolean)
    .sort(sortByOrderThenLabel);
}

function archiveGroup(label, items) {
  return {
    label,
    collapsed: true,
    items,
  };
}

function folderItem(dir, options = {}) {
  if (!fs.existsSync(dir)) return undefined;

  const metadata = readFolderMetadata(dir, options.metadataFile);
  const items = fs
    .readdirSync(dir, { withFileTypes: true })
    .filter((entry) => entry.name !== '.DS_Store')
    .filter((entry) => entry.isDirectory() || (entry.isFile() && entry.name.endsWith('.md')))
    .map((entry) => {
      const entryPath = path.join(dir, entry.name);
      return entry.isDirectory() ? folderItem(entryPath) : linkItem(entryPath);
    })
    .filter(Boolean)
    .sort(sortByFilesystemOrderThenLabel);

  if (items.length === 0) return undefined;

  const item = {
    label: metadata.label || path.basename(dir),
    collapsed: true,
    items,
  };

  if (metadata.badge) item.badge = metadata.badge;
  if (Number.isFinite(metadata.order)) {
    Object.defineProperty(item, '__order', { value: metadata.order, enumerable: false });
  }
  Object.defineProperty(item, '__entryName', { value: path.basename(dir), enumerable: false });
  Object.defineProperty(item, '__kind', { value: 'directory', enumerable: false });
  return item;
}

function linkItem(file) {
  const frontmatter = readFrontmatter(file);
  const sidebar = frontmatter.sidebar ?? {};
  const label = sidebar.label || cleanLabel(frontmatter.title, file);
  const item = {
    label,
    link: routePath(file),
  };

  const badge = sidebar.badge || statusBadge(frontmatter.status);
  if (badge) item.badge = badge;
  if (Number.isFinite(sidebar.order)) {
    Object.defineProperty(item, '__order', { value: sidebar.order, enumerable: false });
  }
  Object.defineProperty(item, '__entryName', { value: path.basename(file), enumerable: false });
  Object.defineProperty(item, '__kind', { value: 'file', enumerable: false });
  return item;
}

function readFolderMetadata(dir, preferredFile) {
  const names = preferredFile
    ? [preferredFile, ...folderMetadataDocNames.filter((name) => name !== preferredFile)]
    : folderMetadataDocNames;

  for (const name of names) {
    const file = path.join(dir, name);
    if (!fs.existsSync(file)) continue;
    const frontmatter = readFrontmatter(file);
    const sidebar = frontmatter.sidebar ?? {};
    return {
      label: sidebar.label || cleanLabel(frontmatter.title, file) || path.basename(dir),
      badge: sidebar.badge || statusBadge(frontmatter.status),
      order: Number.isFinite(sidebar.order) ? sidebar.order : undefined,
    };
  }

  return {};
}

function routePath(file) {
  const relative = path.relative(docsRoot, file).replaceAll(path.sep, '/');
  const withoutExtension = relative.replace(/\.md$/, '');
  return `/${withoutExtension.toLowerCase()}/`;
}

function cleanLabel(title, file) {
  const container = path.basename(path.dirname(file));
  const fileName = path.basename(file);
  if (!title) return fileName.endsWith('.md') ? fileName.replace(/\.md$/, '') : container;
  if (['README.md', 'epic.md', 'plan.md', 'refinement.md', 'breakdown.md'].includes(fileName)) {
    return fileName.replace(/\.md$/, '');
  }
  return title
    .replace(/^Refinement\s+[—-]\s+/i, '')
    .replace(/^Breakdown\s+[—-]\s+/i, '')
    .replace(/^Work Order\s+[—-]\s+/i, '')
    .trim();
}

function statusBadge(status) {
  if (!status) return undefined;
  const normalized = String(status).trim().toUpperCase();
  const variants = {
    IMPLEMENTED: 'success',
    IN_PROGRESS: 'caution',
    IMPLEMENTING: 'caution',
    LOCKED: 'tip',
    DISCUSSION: 'note',
    SEEDED: 'note',
    ABANDONED: 'danger',
  };
  return {
    text: normalized,
    variant: variants[normalized] ?? 'note',
  };
}

function sortByOrderThenLabel(a, b) {
  const aOrder = Number.isFinite(a.__order) ? a.__order : Number.MAX_SAFE_INTEGER;
  const bOrder = Number.isFinite(b.__order) ? b.__order : Number.MAX_SAFE_INTEGER;
  if (aOrder !== bOrder) return aOrder - bOrder;
  return a.label.localeCompare(b.label);
}

function sortByFilesystemOrderThenLabel(a, b) {
  const aOrder = a.__kind === 'directory' && Number.isFinite(a.__order) ? a.__order : defaultEntryOrder(a);
  const bOrder = b.__kind === 'directory' && Number.isFinite(b.__order) ? b.__order : defaultEntryOrder(b);
  if (aOrder !== bOrder) return aOrder - bOrder;
  if (a.__kind !== b.__kind) return a.__kind === 'file' ? -1 : 1;
  return a.label.localeCompare(b.label);
}

function defaultEntryOrder(item) {
  const name = item.__entryName || item.label;
  if (item.__kind === 'file') {
    if (fileOrder.has(name)) return fileOrder.get(name);
    if (/^[TV][0-9]+[a-z]*\.md$/i.test(name)) return 200;
    return 500;
  }
  return directoryOrder.get(name) ?? 700;
}

function readFrontmatter(file) {
  const text = fs.readFileSync(file, 'utf8');
  const match = /^---\n([\s\S]*?)\n---/.exec(text);
  if (!match) return {};
  return parseYamlSubset(match[1]);
}

function parseYamlSubset(source) {
  const root = {};
  const stack = [{ indent: -1, value: root }];

  for (const rawLine of source.split('\n')) {
    if (!rawLine.trim() || rawLine.trimStart().startsWith('#')) continue;
    const match = /^(\s*)([A-Za-z0-9_.-]+):(?:\s*(.*))?$/.exec(rawLine);
    if (!match) continue;

    const indent = match[1].length;
    const key = match[2];
    const rawValue = match[3] ?? '';

    while (stack.length > 1 && indent <= stack[stack.length - 1].indent) {
      stack.pop();
    }

    const parent = stack[stack.length - 1].value;
    if (rawValue === '') {
      const child = {};
      parent[key] = child;
      stack.push({ indent, value: child });
    } else {
      parent[key] = parseScalar(rawValue);
    }
  }

  return root;
}

function parseScalar(value) {
  const trimmed = value.trim();
  if (/^-?\d+$/.test(trimmed)) return Number(trimmed);
  if (trimmed === 'true') return true;
  if (trimmed === 'false') return false;
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed.slice(1, -1);
  }
  return trimmed;
}
