import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const docsManagerRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const workspaceRoot = path.resolve(docsManagerRoot, '..');

export function inferToolchainHealth(options = {}) {
  const root = path.resolve(options.workspaceRoot ?? workspaceRoot);
  // DP-518：前兩格檢查的是 `polaris-toolchain.yaml` 與 `scripts/polaris-toolchain.sh`。
  // 後者從 51b8208c 那次搬家起就不在那個路徑上，所以這個狀態頁的 runner 那一格一直是紅的
  // ——而它報的是「去 git restore」，一個永遠救不回來的修法。runner 與那份 manifest 已經
  // 退場（它的 parser 在同一次搬家被刪掉、沒有跟著搬），剩下的三格檢查的是真的還在的東西。
  const checks = [
    {
      id: 'docs.viewer',
      label: 'docs.viewer dependencies',
      ok: fs.existsSync(path.join(root, 'docs-manager/node_modules')),
      repair: 'pnpm --dir docs-manager install',
    },
    {
      id: 'tools.package',
      label: '.claude/skills/visual-regression/toolchain package',
      ok: fs.existsSync(path.join(root, '.claude/skills/visual-regression/toolchain/package.json')),
      repair: 'pnpm --dir .claude/skills/visual-regression/toolchain install',
    },
    {
      id: 'tools.dependencies',
      label: 'Playwright and Mockoon dependencies',
      ok:
        fs.existsSync(path.join(root, '.claude/skills/visual-regression/toolchain/node_modules/.bin/playwright')) &&
        fs.existsSync(path.join(root, '.claude/skills/visual-regression/toolchain/node_modules/.bin/mockoon-cli')),
      repair: 'pnpm --dir .claude/skills/visual-regression/toolchain install',
    },
  ];

  const failures = checks.filter((check) => !check.ok);
  return {
    status: failures.length === 0 ? 'pass' : 'fail',
    workspaceRoot: root,
    checks,
    failures,
    repairCommand: 'mise run bootstrap -- --profile runtime',
    navRepairCommand: 'pnpm --dir docs-manager dev',
  };
}
