#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/resolve-release-surface.sh"

tmpdir="$(mktemp -d -t resolve-release-surface.XXXXXX)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

write_task() {
  local file="$1"
  local frontmatter="$2"
  cat >"$file" <<EOF
---
title: "Work Order - T1: release surface selftest (1 pt)"
description: "Fixture task for release surface resolver selftest."
status: TODO
${frontmatter}
---

# T1: release surface selftest (1 pt)

> Source: DP-137 | Task: DP-137-T1 | JIRA: N/A | Repo: polaris-framework
EOF
}

assert_field() {
  local file="$1"
  local field="$2"
  local expected="$3"
  local actual
  actual="$(bash "$SCRIPT" --task-md "$file" --format field --field "$field")"
  [[ "$actual" == "$expected" ]] || {
    echo "FAIL: $file field=$field expected=$expected got=$actual" >&2
    exit 1
  }
}

assert_json_contains() {
  local file="$1"
  local needle="$2"
  local json
  json="$(bash "$SCRIPT" --task-md "$file" --format json)"
  grep -q "$needle" <<<"$json" || {
    echo "FAIL: $file json missing $needle" >&2
    echo "$json" >&2
    exit 1
  }
}

task_none="$tmpdir/none.md"
task_pr="$tmpdir/pr.md"
task_pkg="$tmpdir/pkg.md"
task_ext="$tmpdir/ext.md"
task_amb="$tmpdir/amb.md"

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
write_task "$task_ext" 'deliverable:
  pr_url: https://github.com/example-org/example/pull/456
  pr_state: OPEN
  head_sha: def5678
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
    vr: N/A'
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

assert_field "$task_none" class "none"
assert_field "$task_none" release_required "false"

assert_field "$task_pr" class "developer_pr"
assert_field "$task_pr" release_required "true"

assert_field "$task_pkg" class "package_release"
assert_field "$task_pkg" release_required "true"

assert_field "$task_ext" class "local_extension"
assert_field "$task_ext" release_required "true"
assert_json_contains "$task_ext" '"developer_pr"'
assert_json_contains "$task_ext" '"local_extension"'

assert_field "$task_amb" class "ambiguous"
assert_field "$task_amb" release_required "true"
assert_json_contains "$task_amb" 'extension_deliverable_without_local_extension_endpoint'

echo "PASS: resolve-release-surface selftest"
