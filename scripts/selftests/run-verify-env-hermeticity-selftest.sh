#!/usr/bin/env bash
# Purpose: DP-382 T3 selftest for run-verify-command.sh env hermeticity.
#          Verifies live POLARIS_WORKSPACE_ROOT / POLARIS_SPECS_ROOT do not leak
#          into the task Verify Command process.
# Inputs:  none.
# Outputs: PASS line on success; exits 1 on assertion failure.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN_VERIFY="$ROOT_DIR/scripts/run-verify-command.sh"
WORKDIR="$(mktemp -d -t run-verify-env-hermeticity.XXXXXX)"
trap 'rm -rf "$WORKDIR"; rm -f /tmp/polaris-verified-DP-382-T3-env-*.json' EXIT

repo="$WORKDIR/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email selftest@example.com
git -C "$repo" config user.name "run-verify env selftest"
printf 'fixture\n' >"$repo/README.md"
git -C "$repo" add -A
git -C "$repo" -c commit.gpgsign=false commit -q -m "fixture"

task_md="$WORKDIR/task.md"
cat >"$task_md" <<'MD'
---
title: "DP-382-T3 env hermeticity fixture"
description: "selftest fixture"
status: PLANNED
verification:
  behavior_contract:
    applies: false
    reason: "selftest"
depends_on: []
---

# DP-382-T3 env hermeticity fixture

> Source: DP-382 | Task: DP-382-T3-env | JIRA: N/A | Repo: repo

## Allowed Files

- README.md

## Test Command

```bash
true
```

## Test Environment

- **Level**: static

## Verify Command

```bash
if env | grep -q '^POLARIS_WORKSPACE_ROOT='; then
  echo "POLARIS_WORKSPACE_ROOT leaked" >&2
  exit 7
fi
if env | grep -q '^POLARIS_SPECS_ROOT='; then
  echo "POLARIS_SPECS_ROOT leaked" >&2
  exit 8
fi
echo "PASS: verify command env scrubbed"
```
MD

POLARIS_WORKSPACE_ROOT="$WORKDIR/live-workspace" \
POLARIS_SPECS_ROOT="$WORKDIR/live-specs" \
  bash "$RUN_VERIFY" --repo "$repo" --task-md "$task_md" --ticket DP-382-T3-env >/tmp/dp382-t3-env.out 2>&1 || {
    cat /tmp/dp382-t3-env.out >&2
    exit 1
  }

grep -q "PASS: verify command env scrubbed" /tmp/dp382-t3-env.out
echo "PASS: run-verify env hermeticity selftest"
