#!/usr/bin/env node
import { accessSync, constants } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const require = createRequire(import.meta.url);
const packageRoot = dirname(dirname(dirname(fileURLToPath(import.meta.url))));

try {
  require.resolve('@playwright/test');
  const cli = join(packageRoot, 'node_modules', '.bin', process.platform === 'win32' ? 'playwright.cmd' : 'playwright');
  accessSync(cli, constants.X_OK);
  const version = spawnSync(cli, ['--version'], { encoding: 'utf8' });
  if (version.status !== 0) {
    throw new Error(version.stderr || 'playwright --version failed');
  }
  process.stdout.write(`Playwright: ${version.stdout.trim()}\n`);
  process.stdout.write('PASS: browser.playwright doctor\n');
} catch (error) {
  process.stderr.write(`FAIL: browser.playwright doctor: ${error.message}\n`);
  process.stderr.write('Repair: pnpm --filter polaris-toolchain install\n');
  process.exit(1);
}
