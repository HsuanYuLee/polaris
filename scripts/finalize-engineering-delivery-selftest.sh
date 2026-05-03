#!/usr/bin/env bash
set -euo pipefail

# Selftest for finalize-engineering-delivery.sh stable-cwd cleanup behavior.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FINALIZE="$SCRIPT_DIR/finalize-engineering-delivery.sh"
TMPROOT="$(mktemp -d -t finalize-delivery-selftest-XXXXXX)"

cleanup() {
  rm -rf "$TMPROOT"
}
trap cleanup EXIT

write_pr_template() {
  local repo="$1"
  mkdir -p "$repo/.github"
  cat > "$repo/.github/pull_request_template.md" <<'EOF'
## Description

## Changed

## Screenshots (Test Plan)

## Related documents

## QA notes
EOF
}

write_task() {
  local workspace="$1"
  local head_sha="$2"
  local task_dir="$workspace/docs-manager/src/content/docs/specs/design-plans/DP-999-finalize-cwd/tasks"
  mkdir -p "$task_dir"
  cat > "$workspace/docs-manager/src/content/docs/specs/design-plans/DP-999-finalize-cwd/plan.md" <<'EOF'
---
title: "DP-999: Finalize cwd selftest"
status: LOCKED
locked_at: 2026-05-03
---

# DP-999

## Implementation Checklist

- [ ] T1: finalize cwd selftest

## Work Orders

- [T1](tasks/T1.md)
EOF
  cat > "$task_dir/T1.md" <<EOF
---
deliverable:
  pr_url: https://github.com/demo/example/pull/1
  pr_state: OPEN
  head_sha: $head_sha
status: IN_PROGRESS
depends_on: []
---

# T1: finalize cwd selftest (1 pt)

> Source: DP-999 | Task: DP-999-T1 | JIRA: N/A | Repo: example

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-999 |
| Task ID | DP-999-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Branch chain | main -> task/DP-999-T1-finalize-cwd |
| Task branch | task/DP-999-T1-finalize-cwd |
| Depends on | N/A |

## Allowed Files

- \`scripts/**\`

## Test Command

\`\`\`bash
echo ok
\`\`\`

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Verify Command

\`\`\`bash
echo ok
\`\`\`
EOF
}

install_mock_gh() {
  local mockbin="$1"
  local head_sha="$2"
  mkdir -p "$mockbin"
  cat > "$mockbin/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$1 \$2" == "pr view" ]]; then
  python3 - <<'PY'
import json
print(json.dumps({
    "body": "## Description\\n\\nSelftest.\\n\\n## Changed\\n\\n- finalize\\n\\n## Screenshots (Test Plan)\\n\\n- selftest\\n\\n## Related documents\\n\\n- DP-999\\n\\n## QA notes\\n\\n- N/A\\n",
    "isDraft": False,
    "state": "OPEN",
    "url": "https://github.com/demo/example/pull/1",
    "headRefName": "task/DP-999-T1-finalize-cwd",
    "headRefOid": "$head_sha",
    "baseRefName": "main",
}))
PY
  exit 0
fi
echo "unexpected gh call: \$*" >&2
exit 1
EOF
  chmod +x "$mockbin/gh"
}

main_repo="$TMPROOT/workspace"
worktree_repo="$TMPROOT/.worktrees/finalize-cwd"
mockbin="$TMPROOT/bin"

mkdir -p "$main_repo"
git -C "$main_repo" init -q
git -C "$main_repo" checkout -q -b main
git -C "$main_repo" config user.email "polaris@example.test"
git -C "$main_repo" config user.name "Polaris Selftest"
git -C "$main_repo" remote add origin https://github.com/demo/example.git
cat > "$main_repo/workspace-config.yaml" <<'EOF'
language: zh-TW
EOF
write_pr_template "$main_repo"
touch "$main_repo/README.md"
git -C "$main_repo" add README.md workspace-config.yaml .github/pull_request_template.md
git -C "$main_repo" commit -q -m init
git -C "$main_repo" checkout -q -b task/DP-999-T1-finalize-cwd
git -C "$main_repo" checkout -q main
git -C "$main_repo" worktree add -q "$worktree_repo" task/DP-999-T1-finalize-cwd

head_sha="$(git -C "$worktree_repo" rev-parse HEAD)"
write_task "$main_repo" "$head_sha"
install_mock_gh "$mockbin" "$head_sha"

set +e
out="$(
  cd "$worktree_repo" &&
    POLARIS_SKIP_CI_LOCAL=1 \
    POLARIS_SKIP_EVIDENCE=1 \
    POLARIS_SKIP_PR_TITLE_GATE=1 \
    POLARIS_SKIP_CHANGESET_GATE=1 \
    PATH="$mockbin:$PATH" \
    "$FINALIZE" --repo "$worktree_repo" --ticket DP-999-T1 --workspace "$main_repo" 2>&1
)"
rc=$?
set -e

if [[ "$rc" -ne 0 ]]; then
  printf '%s\n' "$out" >&2
  echo "not ok finalize exited $rc" >&2
  exit 1
fi

if printf '%s\n' "$out" | grep -qE 'getcwd|cannot access parent directories'; then
  printf '%s\n' "$out" >&2
  echo "not ok finalize emitted deleted-cwd noise" >&2
  exit 1
fi

if [[ -d "$worktree_repo" ]]; then
  echo "not ok implementation worktree still exists" >&2
  exit 1
fi

task_path="$main_repo/docs-manager/src/content/docs/specs/design-plans/DP-999-finalize-cwd/tasks/pr-release/T1.md"
if [[ ! -f "$task_path" ]] || ! grep -q '^status: IMPLEMENTED$' "$task_path"; then
  echo "not ok finalized task missing or status not implemented" >&2
  exit 1
fi

echo "[finalize-engineering-delivery-selftest] PASS"
