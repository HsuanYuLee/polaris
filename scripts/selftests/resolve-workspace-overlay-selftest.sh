#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVER="$SCRIPT_DIR/resolve-workspace-overlay.sh"
TMPDIR="$(mktemp -d -t polaris-overlay.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/workspace/docs-manager/src/content/docs/specs"
mkdir -p "$TMPDIR/workspace/.codex"
mkdir -p "$TMPDIR/workspace/docs-manager/dist"
mkdir -p "$TMPDIR/local-skills/framework-release"
cat > "$TMPDIR/workspace/workspace-config.yaml" <<'YAML'
language: zh-TW
YAML

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "[resolve-workspace-overlay-selftest] FAIL $label: expected $needle in $haystack" >&2
    exit 1
  fi
}

out="$(POLARIS_LOCAL_SKILLS_ROOT="$TMPDIR/local-skills" "$RESOLVER" --workspace "$TMPDIR/workspace" --kind specs-root)"
assert_contains "$out" '"kind":"specs-root"' "specs kind"
assert_contains "$out" '"authoring_allowed":false' "specs read-only overlay"
assert_contains "$out" '"generated":false' "specs generated flag"

out="$(POLARIS_LOCAL_SKILLS_ROOT="$TMPDIR/local-skills" "$RESOLVER" --workspace "$TMPDIR/workspace" --kind workspace-config-root)"
assert_contains "$out" '"kind":"workspace-config-root"' "workspace-config kind"
assert_contains "$out" '"path":"'"$TMPDIR"'/workspace/workspace-config.yaml"' "workspace-config path"

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

mkdir -p "$TMPDIR/no-specs"
if POLARIS_LOCAL_SKILLS_ROOT="$TMPDIR/local-skills" "$RESOLVER" --workspace "$TMPDIR/no-specs" --kind specs-root >"$TMPDIR/no-specs.out" 2>"$TMPDIR/no-specs.err"; then
  echo "[resolve-workspace-overlay-selftest] FAIL missing specs overlay should fail" >&2
  exit 1
fi
assert_contains "$(cat "$TMPDIR/no-specs.err")" "overlay missing specs root" "missing specs root"

mkdir -p "$TMPDIR/symlink-workspace/docs-manager/src/content/docs"
ln -s "$TMPDIR/workspace/docs-manager/src/content/docs/specs" "$TMPDIR/symlink-workspace/docs-manager/src/content/docs/specs"
if POLARIS_LOCAL_SKILLS_ROOT="$TMPDIR/local-skills" "$RESOLVER" --workspace "$TMPDIR/symlink-workspace" --kind specs-root >"$TMPDIR/symlink.out" 2>"$TMPDIR/symlink.err"; then
  echo "[resolve-workspace-overlay-selftest] FAIL symlink specs primary should fail" >&2
  exit 1
fi
assert_contains "$(cat "$TMPDIR/symlink.err")" "symlink primary path is not allowed" "symlink specs root"

mkdir -p "$TMPDIR/root/repo"
cat > "$TMPDIR/root/workspace-config.yaml" <<'YAML'
language: zh-TW
YAML
mkdir -p "$TMPDIR/root/docs-manager/src/content/docs/specs"
git -C "$TMPDIR/root/repo" init -q
git -C "$TMPDIR/root/repo" config user.name "Polaris Selftest"
git -C "$TMPDIR/root/repo" config user.email "polaris-selftest@example.com"
cat > "$TMPDIR/root/repo/README.md" <<'MD'
# repo
MD
git -C "$TMPDIR/root/repo" add README.md
git -C "$TMPDIR/root/repo" commit -qm "init"
mkdir -p "$TMPDIR/linked-worktree"
git -C "$TMPDIR/root/repo" worktree add --detach "$TMPDIR/linked-worktree/outside" >/dev/null
out="$(POLARIS_LOCAL_SKILLS_ROOT="$TMPDIR/local-skills" "$RESOLVER" --workspace "$TMPDIR/linked-worktree/outside" --kind workspace-config-root)"
assert_contains "$out" '/root/workspace-config.yaml"' "linked worktree workspace-config path"
out="$(POLARIS_LOCAL_SKILLS_ROOT="$TMPDIR/local-skills" "$RESOLVER" --workspace "$TMPDIR/linked-worktree/outside" --kind specs-root)"
assert_contains "$out" '/root/docs-manager/src/content/docs/specs"' "linked worktree specs overlay path"
assert_contains "$out" '"authoring_allowed":false' "linked specs read-only"

echo "[resolve-workspace-overlay-selftest] PASS"
