import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'polaris-sidebar-structure-'));
const specsRoot = path.join(tempRoot, 'specs');
process.env.POLARIS_SPECS_ROOT = specsRoot;

function writeFile(file, content) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, content);
}

function writeDoc(relativePath, frontmatter = {}, body = '') {
  const yaml = Object.entries(frontmatter)
    .map(([key, value]) => `${key}: ${JSON.stringify(value)}`)
    .join('\n');
  writeFile(path.join(specsRoot, relativePath), `---\n${yaml}\n---\n\n${body}\n`);
}

function walk(items, visitor, ancestors = []) {
  for (const item of items) {
    visitor(item, ancestors);
    if (item.items) walk(item.items, visitor, [...ancestors, item]);
  }
}

function findItem(items, predicate) {
  let found;
  walk(items, (item, ancestors) => {
    if (!found && predicate(item, ancestors)) found = { item, ancestors };
  });
  return found;
}

function labels(items = []) {
  return new Set(items.map((item) => item.label));
}

function assertLocalized(actual, expectedLabels, message) {
  assert(expectedLabels.includes(actual), `${message}: ${actual}`);
}

writeDoc('companies/exampleco/epic-alpha/index.md', {
  title: 'Epic Alpha',
  status: 'IMPLEMENTING',
});
writeDoc('companies/exampleco/index.md', {
  title: 'ExampleCo Specs Overview',
  description: 'Company-level source index.',
  sidebar: {
    label: 'overview',
  },
});
writeDoc('companies/exampleco/epic-alpha/tasks/pr-release/T1/index.md', {
  title: 'T1: Completed setup task (2 pt)',
  status: 'IMPLEMENTED',
});
writeDoc('companies/exampleco/epic-alpha/tasks/pr-release/T2/index.md', {
  title: 'T2: Completed tracking fix (1 pt)',
  status: 'IMPLEMENTED',
});
writeDoc('companies/exampleco/epic-alpha/tasks/T8b/index.md', {
  title: 'T8b: Folder-native task with evidence (5 pt)',
  status: 'IMPLEMENTED',
});
writeDoc('companies/exampleco/epic-alpha/tasks/T8b/verify-report.md', {
  title: 'Verify Report - SAMPLE-3822',
});
writeDoc('companies/exampleco/epic-alpha/assets/legacy/artifacts/old-note.md.txt', {}, 'legacy artifact');
writeDoc('companies/exampleco/epic-alpha/artifacts/hidden.md', {}, 'hidden artifact');
writeDoc('companies/exampleco/epic-alpha/escalations/hidden.md', {}, 'hidden escalation');
writeDoc('companies/exampleco/epic-alpha/jira-comments/hidden.md', {}, 'hidden JIRA comment');
writeDoc('companies/exampleco/epic-alpha/refinement-inbox/hidden.md', {}, 'hidden inbox');
writeDoc('companies/exampleco/epic-alpha/tests/hidden.md', {}, 'hidden test');
writeDoc('companies/exampleco/epic-beta/index.md', {
  title: 'Epic Beta',
  status: 'DISCUSSION',
});
writeDoc('companies/exampleco/BUG-1/index.md', {
  title: 'Bug — ExampleCo checkout error',
  status: 'DISCUSSION',
  jira_issue_type: 'Bug',
});
writeDoc('design-plans/archive/plan-alpha/index.md', {
  title: 'PLAN Alpha',
  status: 'IMPLEMENTED',
});
writeDoc('design-plans/archive/plan-alpha/tasks/pr-release/V1/index.md', {
  title: 'V1: Verification work item',
  status: 'IMPLEMENTED',
});

const { specsSidebar } = await import('../sidebar.mjs');
const sidebar = specsSidebar();
assert.equal(sidebar[0]?.label, 'companies', 'Companies should be the first sidebar namespace');
assert.equal(sidebar[1]?.label, 'design-plans', 'Design plans should follow companies in sidebar');

const hiddenPublicLabels = new Set(['assets', 'artifacts', 'escalations', 'jira-comments', 'refinement-inbox', 'tests']);

walk(sidebar, (item, ancestors) => {
  assert(
    !hiddenPublicLabels.has(item.label),
    `Sidebar leaked non-public folder label "${item.label}" under ${ancestors.map((entry) => entry.label).join(' > ')}`
  );
});

const epicAlpha = findItem(sidebar, (item) => item.label === 'Epic Alpha')?.item;
assert(epicAlpha, 'Epic Alpha sidebar item missing');
const exampleco = findItem(sidebar, (item) => item.label === 'exampleco')?.item;
assert(exampleco, 'ExampleCo company sidebar item missing');
assert(
  exampleco.items?.some((item) => item.label === 'overview' && item.link === '/specs/companies/exampleco/'),
  'ExampleCo company overview link missing'
);
const examplecoBugs = exampleco.items?.find((item) => item.label === 'bugs');
assert(examplecoBugs, 'ExampleCo bugs sidebar group missing');
assert(
  findItem(examplecoBugs.items ?? [], (item) => item.link === '/specs/companies/exampleco/bug-1/'),
  'ExampleCo bug link missing from bugs sidebar group'
);
assert(
  !exampleco.items?.some((item) => item.label === 'Bug — ExampleCo checkout error'),
  'ExampleCo standalone bug should live under bugs group, not top-level company list'
);
const epicAlphaChildLabels = labels(epicAlpha.items);
for (const hiddenLabel of hiddenPublicLabels) {
  assert(!epicAlphaChildLabels.has(hiddenLabel), `Epic Alpha sidebar leaked non-public folder: ${hiddenLabel}`);
}
assert(epicAlphaChildLabels.has('overview'), 'Epic Alpha sidebar missing overview entry');
assertLocalized(epicAlpha.badge?.text, ['實作中', 'Implementing'], 'Epic Alpha badge should use localized status label');

const epicAlphaTasks = epicAlpha.items?.find((item) => item.label === 'tasks');
assert(epicAlphaTasks, 'Epic Alpha tasks group missing');
assert(
  !epicAlphaTasks.items?.some((item) => item.label === 'pr-release'),
  'Epic Alpha tasks group leaked lifecycle folder label: pr-release'
);
assert(
  findItem(epicAlphaTasks.items ?? [], (item) => item.link === '/specs/companies/exampleco/epic-alpha/tasks/pr-release/t1/'),
  'Epic Alpha completed task route missing after flattening pr-release'
);

const taskOne = epicAlphaTasks.items?.find((item) => item.label === 'T1: Completed setup task (2 pt)');
assert(taskOne?.items, 'Completed T1 should render as a task folder after migration');
assert(
  taskOne.items.some((item) => item.label === 'index' && item.link === '/specs/companies/exampleco/epic-alpha/tasks/pr-release/t1/'),
  'Completed T1 task folder missing index child'
);

const taskTwo = epicAlphaTasks.items?.find((item) => item.label === 'T2: Completed tracking fix (1 pt)');
assert(taskTwo?.items, 'Completed T2 should render as a task folder after migration');
assert(
  taskTwo.items.some((item) => item.label === 'index' && item.link === '/specs/companies/exampleco/epic-alpha/tasks/pr-release/t2/'),
  'Completed T2 task folder missing index child'
);

const taskWithEvidence = epicAlphaTasks.items?.find((item) => item.label === 'T8b: Folder-native task with evidence (5 pt)');
assert(taskWithEvidence?.items, 'T8b should render as a task folder with child pages');
assert(
  taskWithEvidence.items.some((item) => item.label === 'index' && item.link === '/specs/companies/exampleco/epic-alpha/tasks/t8b/'),
  'T8b task folder missing index child'
);
assert(
  taskWithEvidence.items.some(
    (item) => item.label === 'Verify Report - SAMPLE-3822' && item.link === '/specs/companies/exampleco/epic-alpha/tasks/t8b/verify-report/'
  ),
  'T8b task folder missing verify-report child'
);

const epicBeta = findItem(sidebar, (item) => item.label === 'Epic Beta')?.item;
assert(epicBeta, 'Epic Beta sidebar item missing');
assert(epicBeta.items, 'Discussion-only spec should render as a folder, not a leaf link');
assertLocalized(epicBeta.badge?.text, ['討論中', 'Discussion'], 'Epic Beta badge should use localized status label');
assert(
  epicBeta.items.some((item) => item.label === 'overview' && item.link === '/specs/companies/exampleco/epic-beta/'),
  'Discussion-only spec folder missing overview child'
);

const planAlpha = findItem(sidebar, (item) => item.label === 'PLAN Alpha')?.item;
assert(planAlpha, 'Archived plan sidebar item missing');
const planAlphaTasks = planAlpha.items?.find((item) => item.label === 'tasks');
assert(planAlphaTasks, 'Archived plan tasks group missing');
assert(
  !planAlphaTasks.items?.some((item) => item.label === 'pr-release'),
  'Archived plan tasks group leaked lifecycle folder label: pr-release'
);
assert(
  findItem(planAlphaTasks.items ?? [], (item) => item.link === '/specs/design-plans/archive/plan-alpha/tasks/pr-release/v1/'),
  'Archived plan completed V1 route missing after flattening pr-release'
);

fs.rmSync(tempRoot, { recursive: true, force: true });
console.log('PASS sidebar structure selftest');
