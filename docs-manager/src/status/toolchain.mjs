import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const docsManagerRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const workspaceRoot = path.resolve(docsManagerRoot, '..');

export function inferToolchainHealth(options = {}) {
  const root = path.resolve(options.workspaceRoot ?? workspaceRoot);
  const checks = [
    {
      id: 'manifest',
      label: 'Root toolchain manifest',
      ok: fs.existsSync(path.join(root, 'polaris-toolchain.yaml')),
      repair: 'git restore polaris-toolchain.yaml or rerun DP-087-T1',
    },
    {
      id: 'runner',
      label: 'Toolchain runner',
      ok: fs.existsSync(path.join(root, 'scripts/polaris-toolchain.sh')),
      repair: 'git restore scripts/polaris-toolchain.sh or rerun DP-087-T1',
    },
    {
      id: 'docs.viewer',
      label: 'docs.viewer dependencies',
      ok: fs.existsSync(path.join(root, 'docs-manager/node_modules')),
      repair: 'bash scripts/polaris-toolchain.sh run docs.viewer.install',
    },
    {
      id: 'tools.package',
      label: 'tools/polaris-toolchain package',
      ok: fs.existsSync(path.join(root, 'tools/polaris-toolchain/package.json')),
      repair: 'bash scripts/polaris-toolchain.sh install --required',
    },
    {
      id: 'tools.dependencies',
      label: 'Playwright and Mockoon dependencies',
      ok:
        fs.existsSync(path.join(root, 'tools/polaris-toolchain/node_modules/.bin/playwright')) &&
        fs.existsSync(path.join(root, 'tools/polaris-toolchain/node_modules/.bin/mockoon-cli')),
      repair: 'bash scripts/polaris-toolchain.sh install --required',
    },
  ];

  const failures = checks.filter((check) => !check.ok);
  return {
    status: failures.length === 0 ? 'pass' : 'fail',
    workspaceRoot: root,
    checks,
    failures,
    repairCommand: 'bash scripts/polaris-toolchain.sh install --required && bash scripts/polaris-toolchain.sh doctor --required',
    navRepairCommand: 'bash scripts/polaris-viewer.sh --reload --port 8080 --host 127.0.0.1 --mode dev',
  };
}
