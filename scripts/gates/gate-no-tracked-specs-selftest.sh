#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATE="$SCRIPT_DIR/gate-no-tracked-specs.sh"

fail() {
  echo "[gate-no-tracked-specs-selftest] FAIL: $*" >&2
  exit 1
}

tmpdir="$(mktemp -d -t no-tracked-specs.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

repo="$tmpdir/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email "polaris@example.invalid"
git -C "$repo" config user.name "Polaris Selftest"

cat >"$repo/.gitignore" <<'EOF'
docs-manager/src/content/docs/specs/
EOF
git -C "$repo" add .gitignore
git -C "$repo" commit -q -m "init"

spec="$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-demo/plan.md"
mkdir -p "$(dirname "$spec")"
echo "local only" >"$spec"

bash "$GATE" --repo "$repo" >/tmp/no-tracked-specs-pass.out 2>/tmp/no-tracked-specs-pass.err \
  || fail "ignored untracked specs should pass"

git -C "$repo" add -f "$spec"
if bash "$GATE" --repo "$repo" >/tmp/no-tracked-specs-fail.out 2>/tmp/no-tracked-specs-fail.err; then
  fail "forced-added specs should be blocked"
fi
grep -q "BLOCKED: docs-manager specs are tracked" /tmp/no-tracked-specs-fail.err \
  || fail "blocked message missing"

git -C "$repo" rm --cached -q -- "$spec"
bash "$GATE" --repo "$repo" >/tmp/no-tracked-specs-clean.out 2>/tmp/no-tracked-specs-clean.err \
  || fail "rm --cached cleanup should pass"
[[ -f "$spec" ]] || fail "rm --cached should keep local spec file"

echo "[gate-no-tracked-specs-selftest] PASS"
