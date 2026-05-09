#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/check-release-eligible.sh"

tmpdir="$(mktemp -d -t check-release-eligible.XXXXXX)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

repo="$tmpdir/repo"
mkdir -p "$repo"
mkdir -p "$repo/.changeset"
cat >"$repo/.changeset/config.json" <<'EOF'
{ "$schema": "x", "changelog": "@changesets/cli/changelog", "commit": false, "fixed": [], "linked": [], "access": "restricted", "baseBranch": "main", "updateInternalDependencies": "patch", "ignore": [], "privatePackages": {"tag": true} }
EOF
cat >"$repo/package.json" <<'EOF'
{ "name": "@example/package", "version": "0.0.1" }
EOF

delivery_pass="$tmpdir/check-delivery-pass.sh"
delivery_fail="$tmpdir/check-delivery-fail.sh"
local_pass="$tmpdir/check-local-pass.sh"
local_fail="$tmpdir/check-local-fail.sh"

cat >"$delivery_pass" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$delivery_fail" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
cat >"$local_pass" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$local_fail" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
chmod +x "$delivery_pass" "$delivery_fail" "$local_pass" "$local_fail"

write_task() {
  local file="$1"
  local frontmatter="$2"
  cat >"$file" <<EOF
---
title: "Work Order - T1: release eligible selftest (1 pt)"
description: "Fixture task for release eligible gate selftest."
status: TODO
${frontmatter}
---

# T1: release eligible selftest (1 pt)

> Source: DP-137 | Task: DP-137-T1 | JIRA: N/A | Repo: repo
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
task_amb="$tmpdir/amb.md"
task_pkg="$tmpdir/pkg.md"
task_pr="$tmpdir/pr.md"
task_ext="$tmpdir/ext.md"

write_task "$task_none" ""
write_task "$task_amb" 'extension_deliverable:
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
write_task "$task_pkg" 'deliverables:
  changeset:
    package_scope: "@example/package"
    bump_level_default: patch
    filename_slug: example-package'
write_task "$task_pr" 'deliverable:
  pr_url: https://github.com/example-org/example/pull/123
  pr_state: OPEN
  head_sha: abc1234'
write_task "$task_ext" 'extension_deliverable:
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
assert_gate 2 BLOCKED ambiguous_surface bash "$SCRIPT" --task-md "$task_amb" --repo "$repo"
assert_gate 2 BLOCKED changeset_missing_or_invalid bash "$SCRIPT" --task-md "$task_pkg" --repo "$repo"
cat >"$repo/.changeset/example-package.md" <<'EOF'
---
"@example/package": patch
---

release eligible selftest
EOF
assert_gate 0 ELIGIBLE "" bash "$SCRIPT" --task-md "$task_pkg" --repo "$repo"
assert_gate 0 ELIGIBLE "" env POLARIS_CHECK_DELIVERY_COMPLETION_BIN="$delivery_pass" bash "$SCRIPT" --task-md "$task_pr" --repo "$repo"
assert_gate 2 BLOCKED completion_gate_failed env POLARIS_CHECK_DELIVERY_COMPLETION_BIN="$delivery_fail" bash "$SCRIPT" --task-md "$task_pr" --repo "$repo"
assert_gate 0 ELIGIBLE "" env POLARIS_CHECK_LOCAL_EXTENSION_COMPLETION_BIN="$local_pass" bash "$SCRIPT" --task-md "$task_ext" --repo "$repo"
assert_gate 2 BLOCKED local_extension_completion_failed env POLARIS_CHECK_LOCAL_EXTENSION_COMPLETION_BIN="$local_fail" bash "$SCRIPT" --task-md "$task_ext" --repo "$repo"

echo "PASS: check-release-eligible selftest"
