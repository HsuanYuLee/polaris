#!/usr/bin/env bash
# Selftest for check-runtime-cache-residue.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$SCRIPT_DIR/check-runtime-cache-residue.sh"
TMP="$(mktemp -d -t runtime-cache-residue.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

assert_pass() {
  local label="$1"
  shift
  if ! "$@" >"$TMP/out" 2>"$TMP/err"; then
    echo "FAIL: expected pass: $label" >&2
    cat "$TMP/out" >&2
    cat "$TMP/err" >&2
    exit 1
  fi
}

assert_fail_contains() {
  local label="$1"
  local expected="$2"
  shift 2
  if "$@" >"$TMP/out" 2>"$TMP/err"; then
    echo "FAIL: expected failure: $label" >&2
    cat "$TMP/out" >&2
    exit 1
  fi
  if ! rg -q --fixed-strings "$expected" "$TMP/err"; then
    echo "FAIL: expected '$expected' in stderr for $label" >&2
    cat "$TMP/err" >&2
    exit 1
  fi
}

repo="$TMP/repo"
source_container="$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-demo"
mkdir -p "$source_container/artifacts/external-writes" "$source_container/artifacts/research" "$source_container/jira-comments"

assert_pass "empty runtime cache" "$CHECKER" --repo "$repo" --source-container "$source_container"

printf 'durable\n' >"$source_container/artifacts/external-writes/20260516-body.md"
printf 'research\n' >"$source_container/artifacts/research/2026-05-16-note.md"
assert_pass "source container durable artifacts are allowed" "$CHECKER" --repo "$repo" --source-container "$source_container"

mkdir -p "$repo/.polaris/runtime/external-writes"
printf 'body\n' >"$repo/.polaris/runtime/external-writes/body.md"
assert_fail_contains "shared runtime cache residue" ".polaris/runtime/external-writes/body.md" "$CHECKER" --repo "$repo" --source-container "$source_container"
rm -f "$repo/.polaris/runtime/external-writes/body.md"

mkdir -p "$repo/.codex/external-writes"
printf 'old body\n' >"$repo/.codex/external-writes/body.md"
assert_fail_contains "old codex external write residue" ".codex/external-writes/body.md" "$CHECKER" --repo "$repo" --source-container "$source_container"
rm -f "$repo/.codex/external-writes/body.md"

mkdir -p "$repo/.codex/tmp"
printf 'scratch\n' >"$repo/.codex/tmp/scratch.log"
assert_fail_contains "codex tmp residue" ".codex/tmp/scratch.log" "$CHECKER" --repo "$repo" --source-container "$source_container"
assert_fail_contains "source destination hint" "artifacts/external-writes" "$CHECKER" --repo "$repo" --source-container "$source_container"

echo "check-runtime-cache-residue selftest: PASS"
