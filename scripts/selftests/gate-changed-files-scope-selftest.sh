#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$ROOT_DIR/scripts/gates/gate-changed-files-scope.sh"
WORKDIR="$(mktemp -d -t dp207-changed-files-scope.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

git -C "$WORKDIR" init -q
git -C "$WORKDIR" config user.email test@example.com
git -C "$WORKDIR" config user.name "Scope Gate Test"
mkdir -p "$WORKDIR/scripts" "$WORKDIR/docs"
echo base >"$WORKDIR/scripts/allowed.sh"
git -C "$WORKDIR" add scripts/allowed.sh
git -C "$WORKDIR" commit -q -m base

cat >"$WORKDIR/refinement.json" <<'JSON'
{
  "changed_files": ["scripts/**"]
}
JSON

echo changed >"$WORKDIR/scripts/allowed.sh"
git -C "$WORKDIR" commit -am allowed -q
"$GATE" --repo "$WORKDIR" --refinement "$WORKDIR/refinement.json" --base HEAD~1 --head HEAD >/tmp/dp207-scope-pass.out

echo extra >"$WORKDIR/docs/extra.md"
git -C "$WORKDIR" add docs/extra.md
git -C "$WORKDIR" commit -q -m extra
if "$GATE" --repo "$WORKDIR" --refinement "$WORKDIR/refinement.json" --base HEAD~1 --head HEAD >/tmp/dp207-scope-extra.out 2>&1; then
  echo "FAIL: extra file should fail" >&2
  exit 1
fi
rg -n 'exceed refinement.json changed_files' /tmp/dp207-scope-extra.out >/dev/null

cat >"$WORKDIR/no-changed-files.json" <<'JSON'
{
  "acceptance_criteria": []
}
JSON
if "$GATE" --repo "$WORKDIR" --refinement "$WORKDIR/no-changed-files.json" --base HEAD~1 --head HEAD >/tmp/dp207-scope-missing.out 2>&1; then
  echo "FAIL: missing changed_files should fail" >&2
  exit 1
fi
rg -n 'changed_files is required' /tmp/dp207-scope-missing.out >/dev/null

echo "PASS: changed files scope gate selftest"
