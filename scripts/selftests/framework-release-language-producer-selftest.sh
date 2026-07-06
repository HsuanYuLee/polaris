#!/usr/bin/env bash
# Purpose: 確認 framework-release 類 producer 的預設外部文案會依 workspace
#          language 產生，且送出 GitHub surface 前先跑 external-write gate。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local needle="$2"
  local label="$3"
  grep -qF -- "$needle" "$file" || fail "$label missing: $needle"
}

assert_not_contains() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if grep -qF -- "$needle" "$file"; then
    fail "$label should not contain: $needle"
  fi
}

execute="$ROOT/scripts/framework-release-execute.sh"
closeout="$ROOT/scripts/framework-release-closeout.sh"
sweep="$ROOT/scripts/release-cleanup-sweep.sh"
sync="$ROOT/scripts/sync-to-polaris.sh"

assert_contains "$execute" "default_release_pr_title" "release PR title producer"
assert_contains "$execute" "Polaris 框架發版" "zh-TW release PR title"
assert_contains "$execute" "write_default_release_pr_body" "release PR body producer"
assert_contains "$execute" "gate_release_pr_title" "release PR title language gate"
assert_contains "$execute" "gate_external_body pr-body" "release PR body language gate"
assert_contains "$execute" "read_workspace_language" "release PR workspace language read"

assert_contains "$closeout" "write_task_pr_close_comment" "bundled task PR comment producer"
assert_contains "$closeout" "已發版 %s" "zh-TW bundled task PR comment"
assert_contains "$closeout" "gate_github_comment_body" "bundled task PR comment gate"
assert_contains "$closeout" "--body-file" "bundled task PR comment body-file write"
assert_not_contains "$closeout" "--body \"released" "bundled task PR inline English comment"

assert_contains "$sweep" "write_orphan_pr_cleanup_comment" "orphan cleanup comment producer"
assert_contains "$sweep" "已發版：%s" "zh-TW orphan cleanup comment"
assert_contains "$sweep" "gate_github_comment_body" "orphan cleanup comment gate"
assert_contains "$sweep" "--body-file" "orphan cleanup comment body-file write"
assert_not_contains "$sweep" "--body \"released" "orphan cleanup inline English comment"

assert_contains "$sync" "release_notes_fallback" "GitHub release notes fallback producer"
assert_contains "$sync" "Polaris %s 發版" "zh-TW GitHub release notes fallback"
assert_contains "$sync" "gate_release_notes" "GitHub release notes gate"
assert_contains "$sync" "--notes-file" "GitHub release notes body-file write"
assert_not_contains "$sync" "RELEASE_NOTES=\"Release" "GitHub release notes English fallback"

echo "PASS: framework-release language producer selftest"
