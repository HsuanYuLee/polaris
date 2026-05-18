#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WRAPPER="$ROOT_DIR/scripts/polaris-pr-create.sh"
LEGACY_SELFTEST="$ROOT_DIR/scripts/selftests/polaris-pr-create-selftest.sh"
TMPROOT="$(mktemp -d -t polaris-pr-create-root-selftest.XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

bash "$LEGACY_SELFTEST"

workspace="$TMPROOT/workspace"
repo="$workspace/repo"
mockbin="$TMPROOT/bin"
mkdir -p "$repo" "$mockbin"
cat >"$workspace/workspace-config.yaml" <<'EOF'
language: zh-TW
user:
  github_username: "cfg-user"
projects:
  - name: repo
    repo: demo/example
EOF

git init -q -b main "$repo"
git -C "$repo" config user.name "Polaris Selftest"
git -C "$repo" config user.email "polaris-selftest@example.invalid"
printf 'fixture\n' >"$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -q -m "base"
git -C "$repo" checkout -q -b task/DP-189-T1-pr-create-evidence

task_md="$workspace/docs-manager/src/content/docs/specs/design-plans/DP-189-pr-create-selftest/tasks/T1/index.md"
mkdir -p "$(dirname "$task_md")"
cat >"$task_md" <<'EOF'
---
title: "DP-189-T1: PR evidence selftest"
description: "驗證 PR create evidence 寫入失敗時 fail-stop。"
status: PLANNED
depends_on: []
---

# T1: PR evidence selftest (1 pt)

> Source: DP-189 | Task: DP-189-T1 | JIRA: N/A | Repo: repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-189 |
| Task ID | DP-189-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Branch chain | main -> task/DP-189-T1-pr-create-evidence |
| Task branch | task/DP-189-T1-pr-create-evidence |
| Depends on | N/A |

## Allowed Files

- `scripts/polaris-pr-create.sh`

## Verify Command

```bash
echo ok
```
EOF

cat >"$mockbin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "pr" && "$2" == "create" ]]; then
  printf 'https://github.com/demo/example/pull/189\n'
  exit 0
fi
if [[ "$1" == "api" && "${2:-}" == "user" ]]; then
  printf 'cfg-user\n'
  exit 0
fi
printf 'unexpected gh call: %s\n' "$*" >&2
exit 1
EOF
chmod +x "$mockbin/gh"

blocked_evidence_dir="$TMPROOT/not-a-dir"
printf 'blocked\n' >"$blocked_evidence_dir"
set +e
output="$(
  PATH="$mockbin:$PATH" POLARIS_PR_CREATE_EVIDENCE_DIR="$blocked_evidence_dir" \
    bash "$WRAPPER" --repo "$repo" --task-md "$task_md" --skip-gates --base main --title "fixture" --body "fixture" 2>&1
)"
rc=$?
set -e

if [[ "$rc" -ne 2 ]]; then
  echo "FAIL: expected PR create evidence write failure to exit 2" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
grep -q "failed to write PR create evidence after 3 attempts" <<<"$output" || {
  echo "FAIL: missing evidence fail-stop message" >&2
  printf '%s\n' "$output" >&2
  exit 1
}
if grep -q '^deliverable:' "$task_md"; then
  echo "FAIL: deliverable was written after PR create evidence failure" >&2
  exit 1
fi

echo "PASS: polaris-pr-create root selftest"
