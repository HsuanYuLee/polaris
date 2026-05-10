#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/check-flow-gap-audit.sh"
tmpdir="$(mktemp -d -t flow-gap-audit.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

repo="$tmpdir/repo"
git init -q "$repo"
git -C "$repo" config user.email polaris@example.invalid
git -C "$repo" config user.name "Polaris Selftest"
echo base >"$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -q -m init
head_sha="$(git -C "$repo" rev-parse HEAD)"

task="$tmpdir/T1.md"
cat >"$task" <<'MD'
# T1: Flow gap audit fixture (1 pt)

> Source: DP-140 | Task: DP-140-T1 | JIRA: N/A | Repo: repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DP-140-T1 |
| Parent Epic | DP-140 |
| Base branch | main |
| Task branch | task/DP-140-T1 |

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Verify Command

```bash
echo PASS
```
MD

if bash "$SCRIPT" --repo "$repo" --task-md "$task" --head-sha "$head_sha" >/dev/null 2>&1; then
  echo "FAIL: missing evidence passed" >&2
  exit 1
fi

mkdir -p "$repo/.polaris/evidence/verify"
cat >"$repo/.polaris/evidence/verify/polaris-verified-DP-140-T1-${head_sha}.json" <<JSON
{"ticket":"DP-140-T1","head_sha":"${head_sha}","writer":"manual","exit_code":0,"at":"2026-05-10T00:00:00Z"}
JSON
if bash "$SCRIPT" --repo "$repo" --task-md "$task" --head-sha "$head_sha" >/dev/null 2>&1; then
  echo "FAIL: invalid evidence writer passed" >&2
  exit 1
fi

cat >"$repo/.polaris/evidence/verify/polaris-verified-DP-140-T1-${head_sha}.json" <<JSON
{"ticket":"DP-140-T1","head_sha":"${head_sha}","writer":"run-verify-command.sh","exit_code":0,"at":"2026-05-10T00:00:00Z"}
JSON
bash "$SCRIPT" --repo "$repo" --task-md "$task" --head-sha "$head_sha" >/dev/null

echo "PASS: check-flow-gap-audit selftest"
