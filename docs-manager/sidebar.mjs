import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const rootDir = path.dirname(fileURLToPath(import.meta.url));
const docsRoot = path.join(rootDir, 'src/content/docs');
const specsRoot = process.env.POLARIS_SPECS_ROOT
  ? path.resolve(process.env.POLARIS_SPECS_ROOT)
  : path.join(docsRoot, 'specs');

const folderMetadataDocNames = ['index.md', 'plan.md', 'epic.md', 'refinement.md', 'breakdown.md', 'README.md'];
const fileOrder = new Map([
  ['index.md', 0],
  ['README.md', 5],
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
      items: namespaceItems(path.join(specsRoot, 'design-plans')),
    },
    {
      label: 'companies',
      collapsed: false,
      items: companyItems(),
    },
  ].filter((item) => !('items' in item) || item.items.length > 0);
}

function namespaceItems(baseDir) {
  const activeItems = folderChildren(baseDir);
  const archivedItems = folderChildren(path.join(baseDir, 'archive'));
  return [...activeItems, archiveGroup('archive', archivedItems)].filter(
    (item) => !('items' in item) || item.items.length > 0
  );
}

function companyItems() {
  const companiesRoot = path.join(specsRoot, 'companies');
  if (!fs.existsSync(companiesRoot)) return [];

  return fs
    .readdirSync(companiesRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => {
      const companyDir = path.join(companiesRoot, entry.name);
      const items = namespaceItems(companyDir);
      return {
        label: entry.name,
        collapsed: false,
        items,
      };
    })
    .filter((item) => item.items.length > 0);
}

function folderChildren(baseDir) {
  if (!fs.existsSync(baseDir)) return [];

  return fs
    .readdirSync(baseDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .filter((entry) => entry.name !== 'archive')
    .map((entry) => folderItem(path.join(baseDir, entry.name)))
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

function folderItem(dir) {
  if (!fs.existsSync(dir)) return undefined;

  const metadata = readFolderMetadata(dir);
  const items = fs
    .readdirSync(dir, { withFileTypes: true })
    .filter((entry) => entry.name !== '.DS_Store')
    .filter((entry) => entry.name !== 'index.md')
    .filter((entry) => entry.isDirectory() || (entry.isFile() && entry.name.endsWith('.md')))
    .map((entry) => {
      const entryPath = path.join(dir, entry.name);
      return entry.isDirectory() ? folderItem(entryPath) : linkItem(entryPath);
    })
    .filter(Boolean)
    .sort(sortByFilesystemOrderThenLabel);

  if (items.length === 0) {
    if (!metadata.link) return undefined;
    return withSidebarPrivateFields(
      {
        label: metadata.label || path.basename(dir),
        link: metadata.link,
        ...(metadata.badge ? { badge: metadata.badge } : {}),
      },
      metadata,
      path.basename(dir),
      'file'
    );
  }

  const childItems = metadata.link
    ? [
        withSidebarPrivateFields(
          {
            label: 'overview',
            link: metadata.link,
            ...(metadata.badge ? { badge: metadata.badge } : {}),
          },
          { order: -1 },
          'index.md',
          'file'
        ),
        ...items,
      ]
    : items;

  const item = {
    label: metadata.label || path.basename(dir),
    collapsed: true,
    items: childItems,
  };

  if (metadata.badge) item.badge = metadata.badge;
  return withSidebarPrivateFields(item, metadata, path.basename(dir), 'directory');
}

function linkItem(file) {
  const frontmatter = readFrontmatter(file);
  const sidebar = frontmatter.sidebar ?? {};
  const label = sidebar.label || cleanLabel(frontmatter.title, file);
  const item = {
    label,
    link: routePath(file),
  };

  const badge = resolveBadge(frontmatter, sidebar);
  if (badge) item.badge = badge;
  return withSidebarPrivateFields(item, sidebar, path.basename(file), 'file');
}

function withSidebarPrivateFields(item, metadata, entryName, kind) {
  if (Number.isFinite(metadata.order)) {
    Object.defineProperty(item, '__order', { value: metadata.order, enumerable: false });
  }
  Object.defineProperty(item, '__entryName', { value: entryName, enumerable: false });
  Object.defineProperty(item, '__kind', { value: kind, enumerable: false });
  return item;
}

function readFolderMetadata(dir) {
  for (const name of folderMetadataDocNames) {
    const file = path.join(dir, name);
    if (!fs.existsSync(file)) continue;
    const frontmatter = readFrontmatter(file);
    const sidebar = frontmatter.sidebar ?? {};
    return {
      label: sidebar.label || cleanFolderLabel(frontmatter.title, file) || path.basename(dir),
      link: name === 'index.md' ? routePath(file) : undefined,
      badge: resolveBadge(frontmatter, sidebar),
      order: Number.isFinite(sidebar.order) ? sidebar.order : undefined,
    };
  }

  return {};
}

function routePath(file) {
  const relative = path.relative(specsRoot, file).replaceAll(path.sep, '/');
  const withoutExtension = relative.replace(/\.md$/, '');
  if (withoutExtension.endsWith('/index')) {
    return `/specs/${withoutExtension.slice(0, -'/index'.length).toLowerCase()}/`;
  }
  return `/specs/${withoutExtension.toLowerCase()}/`;
}

function cleanLabel(title, file) {
  const container = path.basename(path.dirname(file));
  const fileName = path.basename(file);
  if (!title) return fileName.endsWith('.md') ? fileName.replace(/\.md$/, '') : container;
  if (['index.md', 'README.md', 'epic.md', 'plan.md', 'refinement.md', 'breakdown.md'].includes(fileName)) {
    return fileName.replace(/\.md$/, '');
  }
  return title
    .replace(/^Refinement\s+[—-]\s+/i, '')
    .replace(/^Breakdown\s+[—-]\s+/i, '')
    .replace(/^Work Order\s+[—-]\s+/i, '')
    .trim();
}

function cleanFolderLabel(title, file) {
  const container = path.basename(path.dirname(file));
  if (!title) return container;
  return title
    .replace(/^Refinement\s+[—-]\s+/i, '')
    .replace(/^Breakdown\s+[—-]\s+/i, '')
    .replace(/^Work Order\s+[—-]\s+/i, '')
    .trim();
}

function resolveBadge(frontmatter, sidebar = {}) {
  const status = frontmatter.status;
  if (!status) return sidebar.badge;
  const priority = frontmatter.priority;
  const normalizedStatus = String(status).trim().toUpperCase();
  const normalizedPriority = priority ? String(priority).trim().toUpperCase() : '';
  return {
    text: normalizedPriority ? `${normalizedStatus} / ${normalizedPriority}` : normalizedStatus,
    variant: badgeVariant(normalizedStatus, normalizedPriority),
  };
}

function badgeVariant(status, priority = '') {
  if (!status) return undefined;
  const variants = {
    IMPLEMENTED: 'success',
    IN_PROGRESS: 'caution',
    IMPLEMENTING: 'caution',
    LOCKED: 'tip',
    DISCUSSION: 'note',
    SEEDED: 'note',
    ABANDONED: 'danger',
  };
  if (status === 'LOCKED' && priority && priority !== 'P1') return 'note';
  return variants[status] ?? 'note';
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
