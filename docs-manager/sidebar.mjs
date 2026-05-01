import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const rootDir = path.dirname(fileURLToPath(import.meta.url));
const docsRoot = path.join(rootDir, 'src/content/docs');
const specsRoot = path.join(docsRoot, 'specs');

const primaryDocNames = ['epic.md', 'refinement.md', 'breakdown.md', 'plan.md', 'README.md'];

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
    .map((entry) => path.join(base, entry.name, 'plan.md'))
    .filter((file) => fs.existsSync(file))
    .map((file) => linkItem(file))
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
    .map((entry) => findPrimaryDoc(path.join(base, entry.name)))
    .filter(Boolean)
    .map((file) => linkItem(file))
    .sort(sortByOrderThenLabel);
}

function archiveGroup(label, items) {
  return {
    label,
    collapsed: true,
    items,
  };
}

function findPrimaryDoc(containerDir) {
  for (const name of primaryDocNames) {
    const candidate = path.join(containerDir, name);
    if (fs.existsSync(candidate)) return candidate;
  }

  const fallback = firstMarkdownFile(containerDir);
  return fallback;
}

function firstMarkdownFile(dir) {
  if (!fs.existsSync(dir)) return undefined;

  const direct = fs
    .readdirSync(dir, { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith('.md'))
    .map((entry) => path.join(dir, entry.name))
    .sort();
  if (direct[0]) return direct[0];

  for (const entry of fs.readdirSync(dir, { withFileTypes: true }).filter((entry) => entry.isDirectory())) {
    const nested = firstMarkdownFile(path.join(dir, entry.name));
    if (nested) return nested;
  }
  return undefined;
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
  return item;
}

function routePath(file) {
  const relative = path.relative(docsRoot, file).replaceAll(path.sep, '/');
  const withoutExtension = relative.replace(/\.md$/, '');
  return `/${withoutExtension.toLowerCase()}/`;
}

function cleanLabel(title, file) {
  const container = path.basename(path.dirname(file));
  if (!title) return container;
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
