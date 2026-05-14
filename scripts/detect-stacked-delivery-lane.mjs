#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const USAGE = `usage: node scripts/detect-stacked-delivery-lane.mjs (--input PATH | --text PATH | --stdin-json)

Detects long linear delivery lanes that should become sibling Epics before task.md / JIRA child writes.

Input JSON shape:
{
  "tasks": [
    {
      "id": "T3e",
      "depends_on": ["T3d"],
      "base": "T3e",
      "aggregation_branch": true,
      "independent_release": true,
      "independent_revert": true,
      "strong_coupling": false
    }
  ],
  "decision": {
    "override": false,
    "reason": ""
  }
}
`;

function parseArgs(argv) {
  const args = { mode: null, file: null };
  for (let index = 2; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === '--input') {
      args.mode = 'json';
      args.file = argv[index + 1];
      index += 1;
    } else if (token === '--text') {
      args.mode = 'text';
      args.file = argv[index + 1];
      index += 1;
    } else if (token === '--stdin-json') {
      args.mode = 'stdin-json';
    } else if (token === '--help' || token === '-h') {
      console.log(USAGE);
      process.exit(0);
    } else {
      throw new Error(`unknown argument: ${token}`);
    }
  }
  if (!args.mode) throw new Error('missing input mode');
  if ((args.mode === 'json' || args.mode === 'text') && !args.file) {
    throw new Error(`missing path for ${args.mode} mode`);
  }
  return args;
}

function readStdin() {
  return fs.readFileSync(0, 'utf8');
}

function taskFamily(id) {
  const match = String(id || '').match(/^([A-Z]+[0-9]+)([a-z]+)$/i);
  if (!match) return null;
  return {
    family: match[1].toUpperCase(),
    suffix: match[2].toLowerCase(),
  };
}

function suffixRank(suffix) {
  let rank = 0;
  for (const char of suffix) {
    rank = rank * 26 + (char.charCodeAt(0) - 96);
  }
  return rank;
}

function normalizeTask(raw) {
  const id = String(raw.id || raw.task || raw.key || '').trim();
  return {
    id,
    title: String(raw.title || raw.summary || ''),
    depends_on: Array.isArray(raw.depends_on) ? raw.depends_on.map(String) : [],
    base: raw.base ? String(raw.base) : '',
    branch: raw.branch ? String(raw.branch) : '',
    aggregation_branch: raw.aggregation_branch === true,
    independent_release: raw.independent_release === true,
    independent_revert: raw.independent_revert === true,
    strong_coupling: raw.strong_coupling === true,
  };
}

function parseTextTasks(text) {
  const seen = new Set();
  const tasks = [];
  const taskPattern = /\b([A-Z]+[0-9]+[a-z]+)\b/g;
  for (const match of text.matchAll(taskPattern)) {
    const id = match[1];
    if (seen.has(id)) continue;
    seen.add(id);
    tasks.push(normalizeTask({ id }));
  }
  return { tasks };
}

function loadInput(args) {
  if (args.mode === 'stdin-json') {
    return JSON.parse(readStdin());
  }
  const absolute = path.resolve(args.file);
  const content = fs.readFileSync(absolute, 'utf8');
  if (args.mode === 'text') return parseTextTasks(content);
  return JSON.parse(content);
}

function groupTasks(tasks) {
  const groups = new Map();
  for (const task of tasks) {
    const parsed = taskFamily(task.id);
    if (!parsed) continue;
    const item = { ...task, ...parsed, rank: suffixRank(parsed.suffix) };
    if (!groups.has(parsed.family)) groups.set(parsed.family, []);
    groups.get(parsed.family).push(item);
  }
  return [...groups.entries()].map(([family, items]) => ({
    family,
    tasks: items.sort((left, right) => left.rank - right.rank || left.id.localeCompare(right.id)),
  }));
}

function hasAggregationSignal(tasks) {
  if (tasks.length < 3) return false;
  const first = tasks[0];
  if (first.aggregation_branch) return true;
  return tasks.slice(1).some((task) => {
    const deps = task.depends_on || [];
    const base = task.base || task.branch || '';
    return deps.includes(first.id) || base === first.id || base.includes(first.id);
  });
}

function allIndependentlyShippable(tasks) {
  return tasks.every((task) => task.independent_release || task.independent_revert) &&
    tasks.every((task) => !task.strong_coupling);
}

export function detectStackedDeliveryLane(input) {
  const tasks = Array.isArray(input.tasks) ? input.tasks.map(normalizeTask) : [];
  const override = input.decision?.override === true;
  const overrideReason = String(input.decision?.reason || '').trim();
  const lanes = [];

  for (const group of groupTasks(tasks)) {
    if (group.tasks.length < 3) continue;
    const aggregationSignal = hasAggregationSignal(group.tasks);
    const shippable = allIndependentlyShippable(group.tasks);
    const severity = aggregationSignal && shippable ? 'required' : 'advisory';
    lanes.push({
      family: group.family,
      tasks: group.tasks.map((task) => task.id),
      feat_task: group.tasks[0].id,
      task_count: group.tasks.length,
      aggregation_signal: aggregationSignal,
      independently_shippable: shippable,
      severity,
      recommendation: severity === 'required'
        ? 'split_sibling_epic_before_task_write'
        : 'review_sibling_epic_before_preview',
    });
  }

  const required = lanes.some((lane) => lane.severity === 'required');
  const advisory = lanes.length > 0;
  let status = required ? 'required' : advisory ? 'advisory' : 'ok';
  if (override && advisory) status = 'overridden';

  return {
    status,
    override: override ? { accepted: true, reason: overrideReason } : null,
    lanes,
    summary: buildSummary(status, lanes, overrideReason),
  };
}

function buildSummary(status, lanes, overrideReason) {
  if (status === 'ok') return 'No stacked delivery sibling Epic signal detected.';
  if (status === 'overridden') {
    return `Stacked delivery signal overridden: ${overrideReason || 'no reason provided'}`;
  }
  const laneText = lanes.map((lane) => `${lane.family} (${lane.tasks.join(' -> ')})`).join('; ');
  if (status === 'required') {
    return `Sibling Epic required before task write: ${laneText}`;
  }
  return `Sibling Epic review recommended before preview: ${laneText}`;
}

function main() {
  try {
    const args = parseArgs(process.argv);
    const input = loadInput(args);
    const result = detectStackedDeliveryLane(input);
    console.log(JSON.stringify(result, null, 2));
    process.exit(result.status === 'required' ? 1 : 0);
  } catch (error) {
    console.error(`detect-stacked-delivery-lane: ${error.message}`);
    console.error(USAGE);
    process.exit(2);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
