#!/usr/bin/env bash
# Purpose: Hermetic selftest for pruning stale company/project rule subtrees from the Polaris template.
# Inputs: none (builds a self-contained instance + template under a tmpdir)
# Outputs: stdout PASS lines; exit 0 on success, non-zero on first failed assertion
# Side effects: creates and removes a tmpdir; never touches the live ~/polaris template

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SYNC="$SCRIPT_DIR/sync-to-polaris.sh"

fail() {
  echo "[selftest] FAIL: $*" >&2
  exit 1
}

[[ -f "$SYNC" ]] || fail "sync-to-polaris.sh not found at $SYNC"

tmpdir="$(mktemp -d -t sync-rule-prune.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

INSTANCE="$tmpdir/instance"
TEMPLATE="$tmpdir/template"

mkdir -p "$INSTANCE/.claude/skills" "$INSTANCE/.claude/rules" \
         "$INSTANCE/.claude/hooks" "$INSTANCE/scripts"
printf '3.99.999\n' >"$INSTANCE/VERSION"

INSTANCE_SYNC="$INSTANCE/scripts/sync-to-polaris.sh"
cp "$SYNC" "$INSTANCE_SYNC"
chmod +x "$INSTANCE_SYNC"

cat >"$INSTANCE/.claude/rules/root-rule.md" <<'MD'
# Root Rule

Root L1 rule that should sync and remain in the template.
MD

mkdir -p "$TEMPLATE/.claude/skills" "$TEMPLATE/.claude/rules/company-a" "$TEMPLATE/.claude/rules/project-a"
cat >"$TEMPLATE/.claude/rules/root-rule.md" <<'MD'
# Old Root Rule
MD
cat >"$TEMPLATE/.claude/rules/stale-root.md" <<'MD'
# Stale Root Rule
MD
cat >"$TEMPLATE/.claude/rules/company-a/handbook.md" <<'MD'
# Company Rule
MD
cat >"$TEMPLATE/.claude/rules/project-a/project.md" <<'MD'
# Project Rule
MD

git -C "$TEMPLATE" init -q
git -C "$TEMPLATE" config user.email selftest@example.com
git -C "$TEMPLATE" config user.name selftest
git -C "$TEMPLATE" add -A
git -C "$TEMPLATE" commit -q -m "fixture template"

output="$("$INSTANCE_SYNC" --polaris "$TEMPLATE" 2>&1)" \
  || { printf '%s\n' "$output" >&2; fail "sync-to-polaris exited non-zero"; }

[[ -f "$TEMPLATE/.claude/rules/root-rule.md" ]] \
  || fail "root L1 rule was not synced to template"
grep -q "Root L1 rule" "$TEMPLATE/.claude/rules/root-rule.md" \
  || fail "root L1 rule content was not updated from instance"
[[ ! -e "$TEMPLATE/.claude/rules/stale-root.md" ]] \
  || fail "stale root L1 rule file was not pruned"
[[ ! -e "$TEMPLATE/.claude/rules/company-a" ]] \
  || fail "stale company rule subtree was not pruned"
[[ ! -e "$TEMPLATE/.claude/rules/project-a" ]] \
  || fail "stale project rule subtree was not pruned"
grep -q "rules/company-a/" <<<"$output" \
  || fail "prune output did not mention stale company rule subtree"
grep -q "rules/project-a/" <<<"$output" \
  || fail "prune output did not mention stale project rule subtree"

echo "[selftest] PASS: stale .claude/rules/*/ subtrees are pruned"
echo "[selftest] PASS: root L1 .claude/rules/*.md sync/prune behavior remains intact"
