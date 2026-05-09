#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/write-ac-verification.sh"
VALIDATOR="$ROOT_DIR/scripts/validate-task-md.sh"
GATE="$ROOT_DIR/scripts/check-verification-passed.sh"

tmpdir="$(mktemp -d -t write-ac-verification-selftest.XXXXXX)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

repo="$tmpdir/fake-repo"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.email "polaris@example.invalid"
git -C "$repo" config user.name "Polaris Selftest"
printf 'fixture\n' >"$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -q -m "init"

task="$tmpdir/spec/tasks/V1/index.md"
mkdir -p "$(dirname "$task")"
cat >"$task" <<'MD'
---
title: "Work Order - V1: AC verification fixture (1 pt)"
description: "Fixture for write-ac-verification lifecycle metadata."
---

# V1: AC verification fixture (1 pt)

> Epic: EP-999 | JIRA: CHK-9 | Repo: fake-repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | CHK-9 |
| Parent Epic | EP-999 |
| Implementation tasks | T1 |
| Base branch | feat/ep-999-fixture |
| Depends on | N/A |
| References to load | - `skills/references/task-md-schema.md` |

## Verification Handoff

驗收委派 verify-AC。

## 目標

驗證 ac_verification writer。

## 驗收項目

- AC-1: fixture

## 估點理由

1 pt - selftest fixture。

## 驗收計畫（AC level）

- 驗證 ac_verification lifecycle。

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## 驗收步驟

```bash
echo "verify-AC executes this fixture"
```
MD

bash "$SCRIPT" "$task" \
  --status FAIL \
  --last-run-at 2026-05-09T01:02:03Z \
  --ac-total 2 \
  --ac-pass 1 \
  --ac-fail 1 \
  --ac-manual-required 0 \
  --ac-uncertain 0 \
  --human-disposition rejected \
  --summary "first run failed" >/dev/null

bash "$VALIDATOR" "$task" >/dev/null
bash "$GATE" --task-md "$task" --repo "$repo" >/tmp/write-ac-verification-gate.out 2>/dev/null && {
  echo "FAIL: failed verification should not pass gate" >&2
  exit 1
}
grep -q "status=FAIL" /tmp/write-ac-verification-gate.out

bash "$SCRIPT" "$task" \
  --status PASS \
  --last-run-at 2026-05-09T02:03:04Z \
  --ac-total 2 \
  --ac-pass 2 \
  --ac-fail 0 \
  --ac-manual-required 0 \
  --ac-uncertain 0 \
  --summary "second run passed" >/dev/null

bash "$VALIDATOR" "$task" >/dev/null
bash "$GATE" --task-md "$task" --repo "$repo" >/dev/null

grep -q "last_run_at: 2026-05-09T02:03:04Z" "$task"
grep -q "summary: \"first run failed\"" "$task"
grep -q "summary: \"second run passed\"" "$task"

echo "PASS: write-ac-verification selftest"
