import assert from 'node:assert/strict';
import path from 'node:path';

import { affectsSpecsSidebar } from '../sidebar-dev-restart.mjs';

const specsRoot = path.join(process.cwd(), 'src/content/docs/specs');

assert.equal(
  affectsSpecsSidebar(path.join(specsRoot, 'companies/exampleco/EPIC-1/tasks/T1/index.md'), 'change', specsRoot),
  true,
  'task markdown changes should refresh sidebar metadata'
);
assert.equal(
  affectsSpecsSidebar(path.join(specsRoot, 'companies/exampleco/EPIC-1/tasks/T2'), 'addDir', specsRoot),
  true,
  'new task folders should refresh sidebar structure'
);
assert.equal(
  affectsSpecsSidebar(path.join(specsRoot, 'companies/exampleco/EPIC-1/tasks/pr-release/T1/index.md'), 'add', specsRoot),
  true,
  'released task markdown should refresh sidebar structure'
);
assert.equal(
  affectsSpecsSidebar(path.join(specsRoot, 'companies/exampleco/EPIC-1/tasks/T1/links.json'), 'change', specsRoot),
  false,
  'non-markdown task artifacts should not restart the viewer'
);
assert.equal(
  affectsSpecsSidebar(path.join(specsRoot, 'companies/exampleco/EPIC-1/tasks/T1/assets/evidence.md'), 'add', specsRoot),
  false,
  'hidden evidence folders should not affect sidebar'
);
assert.equal(
  affectsSpecsSidebar(path.join(process.cwd(), 'README.md'), 'change', specsRoot),
  false,
  'files outside specs root should not affect sidebar'
);

console.log('PASS sidebar dev restart selftest');
