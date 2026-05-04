import fs from 'node:fs';

export function readMarkdownFrontmatter(file) {
  if (!fs.existsSync(file)) return {};

  const text = fs.readFileSync(file, 'utf8');
  const match = /^---\n([\s\S]*?)\n---/.exec(text);
  if (!match) return {};

  return parseYamlSubset(match[1]);
}

export function parseYamlSubset(source) {
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
  if (trimmed === '[]') return [];
  if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
    const body = trimmed.slice(1, -1).trim();
    if (!body) return [];
    return body.split(',').map((part) => parseScalar(part.trim()));
  }
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
