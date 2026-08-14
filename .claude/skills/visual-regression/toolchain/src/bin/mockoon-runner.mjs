#!/usr/bin/env node
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const packageRoot = dirname(dirname(dirname(fileURLToPath(import.meta.url))));
const workspaceRoot = resolve(packageRoot, '../..');
const runner = resolve(workspaceRoot, 'scripts/mockoon/mockoon-runner.sh');
const args = process.argv.slice(2);

const result = spawnSync('bash', [runner, ...args], {
  cwd: workspaceRoot,
  env: {
    ...process.env,
    POLARIS_TOOLCHAIN_DIR: packageRoot,
  },
  stdio: 'inherit',
});

process.exit(result.status ?? 1);
