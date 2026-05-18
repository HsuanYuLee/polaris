#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVER="$SCRIPT_DIR/resolve-specs-root.sh"
TMPDIR="$(mktemp -d -t polaris-specs-root.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "[resolve-specs-root-selftest] FAIL $label: expected $needle in $haystack" >&2
    exit 1
  fi
}

mkdir -p "$TMPDIR/workspace/docs-manager/src/content/docs/specs/design-plans/DP-001-example/tasks"
cat > "$TMPDIR/workspace/workspace-config.yaml" <<'YAML'
language: zh-TW
YAML

out="$("$RESOLVER" --workspace "$TMPDIR/workspace")"
[[ "$out" == "$TMPDIR/workspace/docs-manager/src/content/docs/specs" ]] || {
  echo "[resolve-specs-root-selftest] FAIL direct workspace specs root: $out" >&2
  exit 1
}

mkdir -p "$TMPDIR/implementation-worktree"
out="$("$RESOLVER" --workspace "$TMPDIR/implementation-worktree" --specs-source "$TMPDIR/workspace/docs-manager/src/content/docs/specs")"
[[ "$out" == "$TMPDIR/workspace/docs-manager/src/content/docs/specs" ]] || {
  echo "[resolve-specs-root-selftest] FAIL explicit specs source: $out" >&2
  exit 1
}

out="$("$RESOLVER" --workspace "$TMPDIR/workspace/implementation-worktree")"
[[ "$out" == "$TMPDIR/workspace/docs-manager/src/content/docs/specs" ]] || {
  echo "[resolve-specs-root-selftest] FAIL workspace overlay specs root: $out" >&2
  exit 1
}

mkdir -p "$TMPDIR/symlink-worktree/docs-manager/src/content/docs"
ln -s "$TMPDIR/workspace/docs-manager/src/content/docs/specs" "$TMPDIR/symlink-worktree/docs-manager/src/content/docs/specs"
if "$RESOLVER" --workspace "$TMPDIR/symlink-worktree" >"$TMPDIR/symlink.out" 2>"$TMPDIR/symlink.err"; then
  echo "[resolve-specs-root-selftest] FAIL symlink primary path should fail" >&2
  exit 1
fi
assert_contains "$(cat "$TMPDIR/symlink.err")" "symlink primary path is not allowed" "symlink primary rejection"

if "$RESOLVER" --workspace "$TMPDIR/implementation-worktree" --specs-source "$TMPDIR/missing/specs" >"$TMPDIR/missing.out" 2>"$TMPDIR/missing.err"; then
  echo "[resolve-specs-root-selftest] FAIL missing explicit specs source should fail" >&2
  exit 1
fi
assert_contains "$(cat "$TMPDIR/missing.err")" "pass --specs-source or run from the main checkout" "missing explicit source"

echo "[resolve-specs-root-selftest] PASS"
