#!/usr/bin/env bash
# Purpose: selftest for framework-scope-escalation-gate.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$ROOT/scripts/framework-scope-escalation-gate.sh"
TMP="$(mktemp -d -t framework-scope-escalation.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

init_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git init -q -b main "$repo"
  git -C "$repo" config user.name "Polaris Selftest"
  git -C "$repo" config user.email "polaris-selftest@example.com"
  printf 'base\n' >"$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "base"
}

repo="$TMP/repo"
init_repo "$repo"
base="$(git -C "$repo" rev-parse HEAD)"

mkdir -p "$repo/src"
printf 'product\n' >"$repo/src/product.ts"
git -C "$repo" add src/product.ts
git -C "$repo" commit -q -m "product change"
"$GATE" --repo "$repo" --base "$base" --mode product >/dev/null

mkdir -p "$repo/.claude/skills/example"
printf 'framework\n' >"$repo/.claude/skills/example/SKILL.md"
git -C "$repo" add .claude/skills/example/SKILL.md
git -C "$repo" commit -q -m "framework change"
if "$GATE" --repo "$repo" --base "$base" --mode product >/dev/null 2>"$TMP/product.err"; then
  echo "FAIL: product mode allowed framework-owned diff" >&2
  exit 1
fi
grep -Fq "POLARIS_FRAMEWORK_SCOPE_ESCALATION_REQUIRED" "$TMP/product.err" || {
  echo "FAIL: missing escalation marker" >&2
  cat "$TMP/product.err" >&2
  exit 1
}

"$GATE" --repo "$repo" --base "$base" --mode framework >/dev/null

echo "PASS: framework scope escalation gate selftest"
