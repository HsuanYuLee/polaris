import fs from 'node:fs';

export function readMarkdownFrontmatter(file) {
  if (!fs.existsSync(file)) return {};

  const text = fs.readFileSync(file, 'utf8');
  const match = /^---\n([\s\S]*?)\n---/.exec(text);
  if (!match) return {};

  return parseYamlSubset(match[1]);
}

export function parseYamlSubset(source) {
  const lines = source
    .split('\n')
    .filter((line) => line.trim() && !line.trimStart().startsWith('#'));
  const [value] = parseBlock(lines, 0, 0);
  return value && !Array.isArray(value) ? value : {};
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

function parseBlock(lines, startIndex, indent) {
  const first = lines[startIndex];
  if (first && lineIndent(first) === indent && first.trimStart().startsWith('- ')) {
    return parseArray(lines, startIndex, indent);
  }
  return parseObject(lines, startIndex, indent);
}

function parseObject(lines, startIndex, indent) {
  const result = {};
  let index = startIndex;

  while (index < lines.length) {
    const line = lines[index];
    const currentIndent = lineIndent(line);
    if (currentIndent < indent) break;
    if (currentIndent > indent) {
      index += 1;
      continue;
    }
    if (line.trimStart().startsWith('- ')) break;

    const match = /^(\s*)([A-Za-z0-9_.-]+):(?:\s*(.*))?$/.exec(line);
    if (!match) {
      index += 1;
      continue;
    }

    const key = match[2];
    const rawValue = match[3] ?? '';
    if (rawValue === '') {
      const next = lines[index + 1];
      if (next && lineIndent(next) > currentIndent) {
        const [child, nextIndex] = parseBlock(lines, index + 1, lineIndent(next));
        result[key] = child;
        index = nextIndex;
      } else {
        result[key] = {};
        index += 1;
      }
    } else {
      result[key] = parseScalar(rawValue);
      index += 1;
    }
  }

  return [result, index];
}

function parseArray(lines, startIndex, indent) {
  const result = [];
  let index = startIndex;

  while (index < lines.length) {
    const line = lines[index];
    const currentIndent = lineIndent(line);
    if (currentIndent < indent) break;
    if (currentIndent > indent) {
      index += 1;
      continue;
    }

    const match = /^(\s*)-\s*(.*)$/.exec(line);
    if (!match) break;

    const rawValue = match[2] ?? '';
    if (rawValue === '') {
      const next = lines[index + 1];
      if (next && lineIndent(next) > currentIndent) {
        const [child, nextIndex] = parseBlock(lines, index + 1, lineIndent(next));
        result.push(child);
        index = nextIndex;
      } else {
        result.push(null);
        index += 1;
      }
      continue;
    }

    const objectMatch = /^([A-Za-z0-9_.-]+):(?:\s*(.*))?$/.exec(rawValue);
    if (objectMatch) {
      const item = {};
      item[objectMatch[1]] =
        objectMatch[2] === '' || objectMatch[2] === undefined ? {} : parseScalar(objectMatch[2]);
      let nextIndex = index + 1;
      const next = lines[nextIndex];
      if (next && lineIndent(next) > currentIndent) {
        const [tail, afterTail] = parseObject(lines, nextIndex, lineIndent(next));
        Object.assign(item, tail);
        nextIndex = afterTail;
      }
      result.push(item);
      index = nextIndex;
    } else {
      result.push(parseScalar(rawValue));
      index += 1;
    }
  }

  return [result, index];
}

function lineIndent(line) {
  return /^ */.exec(line)?.[0].length ?? 0;
}
