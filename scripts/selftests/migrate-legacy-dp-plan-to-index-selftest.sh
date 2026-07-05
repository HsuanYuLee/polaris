#!/usr/bin/env bash
# Purpose: Regression selftest for legacy DP plan.md inventory and migration.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER="$ROOT/scripts/migrate-legacy-dp-plan-to-index.sh"

tmp="$(mktemp -d -t legacy-dp-plan-migration.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

assert_absent() {
  [[ ! -e "$1" ]] || fail "unexpected path exists: $1"
}

assert_contains() {
  local file="$1" needle="$2"
  grep -qF "$needle" "$file" || fail "$file missing '$needle'"
}

workspace="$tmp/workspace"
active_dir="$workspace/docs-manager/src/content/docs/specs/design-plans/DP-999-legacy-active"
archive_dir="$workspace/docs-manager/src/content/docs/specs/design-plans/archive/DP-998-legacy-archive"
mkdir -p "$active_dir" "$archive_dir"

cat >"$active_dir/plan.md" <<'MD'
---
title: "DP-999 legacy active"
description: "Legacy active plan fixture."
status: LOCKED
---

# DP-999 Legacy Active

Historical body must survive.
MD

cat >"$archive_dir/plan.md" <<'MD'
---
title: "DP-998 legacy archive"
description: "Legacy archive plan fixture."
status: IMPLEMENTED
---

# DP-998 Legacy Archive

Archived historical body must survive when explicitly migrated.
MD

set +e
bash "$HELPER" --workspace "$workspace" --dry-run >"$tmp/dry-run-active.out" 2>"$tmp/dry-run-active.err"
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail "dry-run accepted active legacy plan.md"
assert_contains "$tmp/dry-run-active.err" "POLARIS_LEGACY_DP_PLAN_ACTIVE"
assert_contains "$tmp/dry-run-active.out" "active=1"
assert_contains "$tmp/dry-run-active.out" "archive_allowlisted=1"

bash "$HELPER" --workspace "$workspace" --execute >"$tmp/execute-active.out"
assert_absent "$active_dir/plan.md"
assert_file "$active_dir/index.md"
assert_contains "$active_dir/index.md" "status: LOCKED"
assert_contains "$active_dir/index.md" "Historical body must survive."
assert_file "$archive_dir/plan.md"

bash "$HELPER" --workspace "$workspace" --dry-run >"$tmp/dry-run-clean.out"
assert_contains "$tmp/dry-run-clean.out" "active=0"
assert_contains "$tmp/dry-run-clean.out" "archive_allowlisted=1"

bash "$HELPER" --workspace "$workspace" --execute >"$tmp/execute-idempotent.out"
assert_contains "$tmp/execute-idempotent.out" "no matching plan.md files"

bash "$HELPER" --workspace "$workspace" --execute --include-archive >"$tmp/execute-archive.out"
assert_absent "$archive_dir/plan.md"
assert_file "$archive_dir/index.md"
assert_contains "$archive_dir/index.md" "status: IMPLEMENTED"
assert_contains "$archive_dir/index.md" "Archived historical body must survive"

bash "$HELPER" --workspace "$workspace" --dry-run >"$tmp/dry-run-final.out"
assert_contains "$tmp/dry-run-final.out" "active=0"
assert_contains "$tmp/dry-run-final.out" "archive_allowlisted=0"

echo "[migrate-legacy-dp-plan-to-index-selftest] PASS"
