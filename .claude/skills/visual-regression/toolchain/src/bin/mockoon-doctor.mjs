#!/usr/bin/env node
import { accessSync, constants } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const packageRoot = dirname(dirname(dirname(fileURLToPath(import.meta.url))));
const cli = join(packageRoot, 'node_modules', '.bin', process.platform === 'win32' ? 'mockoon-cli.cmd' : 'mockoon-cli');

try {
  accessSync(cli, constants.X_OK);
  const version = spawnSync(cli, ['--version'], { encoding: 'utf8' });
  if (version.status !== 0) {
    throw new Error(version.stderr || 'mockoon-cli --version failed');
  }
  process.stdout.write(`Mockoon CLI: ${version.stdout.trim()}\n`);
  process.stdout.write('PASS: fixtures.mockoon doctor\n');
} catch (error) {
  process.stderr.write(`FAIL: fixtures.mockoon doctor: ${error.message}\n`);
  process.stderr.write('Repair: pnpm install，在這個 package 自己的目錄下跑\n');
  process.exit(1);
}
