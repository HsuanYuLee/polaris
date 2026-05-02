#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/resolve-workspace-overlay.sh"
TMPDIR="$(mktemp -d -t polaris-overlay.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/workspace/docs-manager/src/content/docs/specs"
mkdir -p "$TMPDIR/workspace/.codex"
mkdir -p "$TMPDIR/workspace/docs-manager/dist"
mkdir -p "$TMPDIR/local-skills/framework-release"

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "[resolve-workspace-overlay-selftest] FAIL $label: expected $needle in $haystack" >&2
    exit 1
  fi
}

out="$(POLARIS_LOCAL_SKILLS_ROOT="$TMPDIR/local-skills" "$RESOLVER" --workspace "$TMPDIR/workspace" --kind specs-root)"
assert_contains "$out" '"kind":"specs-root"' "specs kind"
assert_contains "$out" '"authoring_allowed":true' "specs authoring"
assert_contains "$out" '"generated":false' "specs generated flag"

out="$(POLARIS_LOCAL_SKILLS_ROOT="$TMPDIR/local-skills" "$RESOLVER" --workspace "$TMPDIR/workspace" --kind codex-rules)"
assert_contains "$out" '"kind":"codex-rules"' "codex kind"
assert_contains "$out" '"authoring_allowed":false' "codex read only"

out="$(POLARIS_LOCAL_SKILLS_ROOT="$TMPDIR/local-skills" "$RESOLVER" --workspace "$TMPDIR/workspace" --kind local-skill framework-release)"
assert_contains "$out" '"kind":"local-skill"' "local skill kind"
assert_contains "$out" 'framework-release' "local skill path"

out="$(POLARIS_LOCAL_SKILLS_ROOT="$TMPDIR/local-skills" "$RESOLVER" --workspace "$TMPDIR/workspace" --kind generated-output)"
assert_contains "$out" '"kind":"generated-output"' "generated kind"
assert_contains "$out" '"authoring_allowed":false' "generated not authoring"
assert_contains "$out" '"generated":true' "generated flag"

if POLARIS_LOCAL_SKILLS_ROOT="$TMPDIR/local-skills" "$RESOLVER" --workspace "$TMPDIR/workspace" --kind local-skill missing >/tmp/polaris-overlay-missing.out 2>/tmp/polaris-overlay-missing.err; then
  echo "[resolve-workspace-overlay-selftest] FAIL missing local skill should fail" >&2
  exit 1
fi

echo "[resolve-workspace-overlay-selftest] PASS"
