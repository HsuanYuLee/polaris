#!/usr/bin/env bash
# Purpose: Verify the destination a human declared at the first gate actually
#          constrains where that source's work is allowed to land.
# Inputs:  Hermetic git repositories under mktemp.
# Outputs: PASS when a template-bound source may write anywhere, a
#          workspace-bound source may write to company and source paths but not
#          to shared framework paths, an ignored path counts as workspace-only,
#          and a source declaring no destination or an unknown one fails closed.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK="$ROOT_DIR/scripts/check-source-destination.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Description: build a repo with one company directory and one source declaring
#   the given destination, and echo the repo path.
# Args: $1 = case name, $2 = destination line ("" to omit the field entirely)
new_repo() {
  local name="$1" destination="$2" repo="$WORK/$1"
  mkdir -p "$repo/sources/DP-000-selftest" "$repo/exampleco" "$repo/scripts"
  git -C "$repo" init -q 2>/dev/null || git init -q "$repo"
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name selftest

  # A company is detected the same way sync detects one: a top-level directory
  # holding a workspace-config.yaml.
  echo "language: zh-TW" > "$repo/exampleco/workspace-config.yaml"
  echo "language: zh-TW" > "$repo/workspace-config.yaml"
  printf 'ignored-by-design/\n' > "$repo/.gitignore"

  {
    echo "---"
    echo "title: selftest source"
    [[ -n "$destination" ]] && echo "destination: $destination"
    echo "---"
    echo
    echo "body"
  } > "$repo/sources/DP-000-selftest/index.md"

  git -C "$repo" add -A
  git -C "$repo" commit -qm base
  printf '%s' "$repo"
}

run_check() {
  # Description: run the check for the selftest source with the given paths.
  # Args: $1 = repo, $2.. = changed paths
  local repo="$1"; shift
  local args=() path
  for path in "$@"; do
    args+=(--changed "$path")
  done
  (cd "$repo" && bash "$CHECK" --source sources/DP-000-selftest "${args[@]}")
}

echo "check-source-destination selftest"

# Shipping outward is unconstrained by path; whether the content is generic
# enough is a different question, asked by the leak scan.
repo="$(new_repo template template)"
run_check "$repo" scripts/shared-tool.sh .claude/rules/some-rule.md >/dev/null 2>&1 \
  || fail "a template-bound source should be free to write shared paths"
echo "  ok  template destination unconstrained by path"

# Staying put means staying somewhere that provably does not sync out.
repo="$(new_repo workspace workspace)"
run_check "$repo" exampleco/notes.md >/dev/null 2>&1 \
  || fail "a company directory should count as workspace-only"
run_check "$repo" .claude/skills/exampleco/thing/SKILL.md >/dev/null 2>&1 \
  || fail "a company-scoped skill should count as workspace-only"
run_check "$repo" sources/DP-000-selftest/index.md >/dev/null 2>&1 \
  || fail "the source's own directory should count as workspace-only"
run_check "$repo" ignored-by-design/thing.md >/dev/null 2>&1 \
  || fail "an ignored path should count as workspace-only"
echo "  ok  workspace destination accepts paths that stay"

# The one that matters: a workspace-bound source quietly writing a shared file
# is how company knowledge escapes into the template.
if run_check "$repo" scripts/shared-tool.sh >/dev/null 2>&1; then
  fail "a workspace-bound source must not write a shared script"
fi
if run_check "$repo" .claude/rules/some-rule.md >/dev/null 2>&1; then
  fail "a workspace-bound source must not write a shared rule"
fi
echo "  ok  workspace destination blocks paths that would sync"

# Unknown paths are refused rather than guessed at — stricter than needed, but
# never wrong in the direction that leaks.
if run_check "$repo" some/unfamiliar/place.md >/dev/null 2>&1; then
  fail "an unrecognised path must not be assumed workspace-only"
fi
echo "  ok  unrecognised path refused rather than assumed"

# No declaration and an unknown declaration both fail closed; a default here
# would be the silent third state the assertions forbid.
repo="$(new_repo nodest "")"
if run_check "$repo" exampleco/notes.md >/dev/null 2>&1; then
  fail "a source declaring no destination should fail closed"
fi
repo="$(new_repo baddest somewhere-else)"
if run_check "$repo" exampleco/notes.md >/dev/null 2>&1; then
  fail "an unknown destination value should fail closed"
fi
echo "  ok  missing and unknown destinations fail closed"

echo "PASS: check-source-destination"
