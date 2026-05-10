#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/check-release-completed.sh"

tmpdir="$(mktemp -d -t check-release-completed.XXXXXX)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

repo="$tmpdir/repo"
git init -q "$repo"
git -C "$repo" config user.email "polaris@example.invalid"
git -C "$repo" config user.name "Polaris Selftest"
printf 'init\n' >"$repo/README.md"
mkdir -p "$repo/.changeset"
cat >"$repo/.changeset/config.json" <<'EOF'
{ "$schema": "x", "changelog": "@changesets/cli/changelog", "commit": false, "fixed": [], "linked": [], "access": "restricted", "baseBranch": "main", "updateInternalDependencies": "patch", "ignore": [], "privatePackages": {"tag": true} }
EOF
cat >"$repo/package.json" <<'EOF'
{ "name": "@example/package", "version": "0.0.1" }
EOF
git -C "$repo" add README.md
git -C "$repo" add .changeset/config.json package.json
git -C "$repo" commit -q -m "init"

local_pass="$tmpdir/check-local-pass.sh"
local_fail="$tmpdir/check-local-fail.sh"
delivery_pass="$tmpdir/check-delivery-pass.sh"
cat >"$local_pass" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$local_fail" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
cat >"$delivery_pass" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$local_pass" "$local_fail" "$delivery_pass"

write_task() {
  local file="$1"
  local frontmatter="$2"
  mkdir -p "$(dirname "$file")"
  cat >"$file" <<EOF
---
title: "Work Order - T1: release completed selftest (1 pt)"
description: "Fixture task for release completed gate selftest."
status: TODO
${frontmatter}
---

# T1: release completed selftest (1 pt)

> Source: DP-137 | Task: DP-137-T1 | JIRA: N/A | Repo: repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DP-137-T1 |
| Parent Epic | DP-137 |
| Base branch | main |
| Task branch | task/DP-137-T1-release |
EOF
}

json_field() {
  local file="$1"
  local field="$2"
  python3 - "$file" "$field" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
value = data.get(sys.argv[2])
if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
else:
    print(value)
PY
}

assert_gate() {
  local expected_rc="$1"
  local expected_status="$2"
  local expected_reason="$3"
  shift 3

  local out="$tmpdir/out.json"
  set +e
  "$@" --format json >"$out"
  local rc=$?
  set -e
  [[ "$rc" == "$expected_rc" ]] || {
    echo "FAIL: expected rc=$expected_rc got $rc" >&2
    cat "$out" >&2 || true
    exit 1
  }
  local status reason
  status="$(json_field "$out" status)"
  reason="$(json_field "$out" blocking_reason)"
  [[ "$status" == "$expected_status" ]] || {
    echo "FAIL: expected status=$expected_status got $status" >&2
    cat "$out" >&2
    exit 1
  }
  [[ "$reason" == "$expected_reason" ]] || {
    echo "FAIL: expected reason=$expected_reason got $reason" >&2
    cat "$out" >&2
    exit 1
  }
}

task_none="$tmpdir/none.md"
task_pr="$tmpdir/pr.md"
task_pkg="$tmpdir/pkg.md"
task_ext_active="$tmpdir/tasks/T1.md"
task_ext_pr="$tmpdir/tasks/pr-release/T1.md"

write_task "$task_none" ""
write_task "$task_pr" 'deliverable:
  pr_url: https://github.com/example-org/example/pull/123
  pr_state: OPEN
  head_sha: abc1234'
write_task "$task_pkg" 'deliverables:
  changeset:
    package_scope: "@example/package"
    bump_level_default: patch
    filename_slug: example-package'
write_task "$task_ext_active" 'extension_deliverable:
  endpoint: local_extension
  extension_id: framework-release
  task_head_sha: def5678
  workspace_commit: 1111111
  template_commit: 2222222
  version_tag: v1.2.3
  release_url: https://github.com/example-org/template/releases/tag/v1.2.3
  completed_at: 2026-05-08T12:00:00Z
  evidence:
    ci_local: N/A
    verify: /tmp/polaris-verified.json
    vr: N/A'

assert_gate 0 NOT_REQUIRED "" bash "$SCRIPT" --task-md "$task_none" --repo "$repo"
assert_gate 2 BLOCKED task_not_moved_to_pr_release env POLARIS_CHECK_DELIVERY_COMPLETION_BIN="$delivery_pass" bash "$SCRIPT" --task-md "$task_pr" --repo "$repo"
assert_gate 2 BLOCKED changeset_missing_or_invalid bash "$SCRIPT" --task-md "$task_pkg" --repo "$repo"
cat >"$repo/.changeset/example-package.md" <<'EOF'
---
"@example/package": patch
---

release completed selftest
EOF
assert_gate 2 BLOCKED task_not_moved_to_pr_release bash "$SCRIPT" --task-md "$task_pkg" --repo "$repo"
assert_gate 2 BLOCKED local_extension_completion_failed env POLARIS_CHECK_LOCAL_EXTENSION_COMPLETION_BIN="$local_fail" bash "$SCRIPT" --task-md "$task_ext_active" --repo "$repo"
assert_gate 2 BLOCKED task_not_moved_to_pr_release env POLARIS_CHECK_LOCAL_EXTENSION_COMPLETION_BIN="$local_pass" bash "$SCRIPT" --task-md "$task_ext_active" --repo "$repo"

task_pr_terminal="$tmpdir/tasks/pr-release/T2.md"
mkdir -p "$(dirname "$task_pr_terminal")"
cp "$task_pr" "$task_pr_terminal"
python3 - "$task_pr_terminal" <<'PY'
from pathlib import Path
path = Path(__import__("sys").argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace("status: TODO", "status: IMPLEMENTED", 1)
path.write_text(text, encoding="utf-8")
PY
git -C "$repo" branch task/DP-137-T1-release
mkdir -p "$repo/.worktrees"
git -C "$repo" worktree add "$repo/.worktrees/repo-engineering-DP-137-T1-release" task/DP-137-T1-release >/dev/null 2>&1
assert_gate 2 BLOCKED worktree_not_cleaned env POLARIS_CHECK_DELIVERY_COMPLETION_BIN="$delivery_pass" bash "$SCRIPT" --task-md "$task_pr_terminal" --repo "$repo"
git -C "$repo" worktree remove "$repo/.worktrees/repo-engineering-DP-137-T1-release" --force >/dev/null 2>&1
assert_gate 0 COMPLETED "" env POLARIS_CHECK_DELIVERY_COMPLETION_BIN="$delivery_pass" bash "$SCRIPT" --task-md "$task_pr_terminal" --repo "$repo"

task_pkg_terminal="$tmpdir/tasks/pr-release/T3.md"
mkdir -p "$(dirname "$task_pkg_terminal")"
cp "$task_pkg" "$task_pkg_terminal"
python3 - "$task_pkg_terminal" <<'PY'
from pathlib import Path
path = Path(__import__("sys").argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace("status: TODO", "status: IMPLEMENTED", 1)
path.write_text(text, encoding="utf-8")
PY
git -C "$repo" worktree add "$repo/.worktrees/repo-engineering-DP-137-T1-release" task/DP-137-T1-release >/dev/null 2>&1
assert_gate 2 BLOCKED worktree_not_cleaned bash "$SCRIPT" --task-md "$task_pkg_terminal" --repo "$repo"
git -C "$repo" worktree remove "$repo/.worktrees/repo-engineering-DP-137-T1-release" --force >/dev/null 2>&1
assert_gate 0 COMPLETED "" bash "$SCRIPT" --task-md "$task_pkg_terminal" --repo "$repo"

mkdir -p "$(dirname "$task_ext_pr")"
cp "$task_ext_active" "$task_ext_pr"
python3 - "$task_ext_pr" <<'PY'
from pathlib import Path
path = Path(__import__("sys").argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace("status: TODO", "status: IMPLEMENTED", 1)
path.write_text(text, encoding="utf-8")
PY

mkdir -p "$repo/.worktrees"
git -C "$repo" worktree add "$repo/.worktrees/repo-engineering-DP-137-T1-release" task/DP-137-T1-release >/dev/null 2>&1
assert_gate 2 BLOCKED worktree_not_cleaned env POLARIS_CHECK_LOCAL_EXTENSION_COMPLETION_BIN="$local_pass" bash "$SCRIPT" --task-md "$task_ext_pr" --repo "$repo"
git -C "$repo" worktree remove "$repo/.worktrees/repo-engineering-DP-137-T1-release" --force >/dev/null 2>&1

assert_gate 0 COMPLETED "" env POLARIS_CHECK_LOCAL_EXTENSION_COMPLETION_BIN="$local_pass" bash "$SCRIPT" --task-md "$task_ext_pr" --repo "$repo"

dp_invalid="$tmpdir/dp-invalid"
mkdir -p "$dp_invalid/tasks/pr-release" "$dp_invalid/tasks/V1"
cat >"$dp_invalid/index.md" <<'MD'
---
status: IMPLEMENTED
---
# DP invalid verification closeout
MD
task_ext_invalid="$dp_invalid/tasks/pr-release/T1.md"
cat >"$task_ext_invalid" <<EOF
---
title: "Work Order - T1: invalid verification closeout (1 pt)"
description: "Fixture task for release completed verification closeout guard."
status: IMPLEMENTED
extension_deliverable:
  endpoint: local_extension
  extension_id: framework-release
  task_head_sha: def5678
  workspace_commit: 1111111
  template_commit: 2222222
  version_tag: v1.2.3
  release_url: https://github.com/example-org/template/releases/tag/v1.2.3
  completed_at: 2026-05-08T12:00:00Z
  evidence:
    ci_local: N/A
    verify: /tmp/polaris-verified.json
    vr: N/A
---

# T1: invalid verification closeout (1 pt)

> Source: DP-137 | Task: DP-137-T1 | JIRA: N/A | Repo: repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DP-137-T1 |
| Parent Epic | DP-137 |
| Base branch | main |
| Task branch | task/DP-137-T1-release |
EOF
cat >"$dp_invalid/tasks/V1/index.md" <<'MD'
# V1
MD
assert_gate 2 BLOCKED verification_closeout_incomplete env POLARIS_CHECK_LOCAL_EXTENSION_COMPLETION_BIN="$local_pass" bash "$SCRIPT" --task-md "$task_ext_invalid" --repo "$repo"

echo "PASS: check-release-completed selftest"
