#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/scripts/selftests/refinement-dp229-fixture-lib.sh"
tmp="$(mktemp -d -t refinement-render.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
make_refinement_fixture "$tmp/dp"
bash "$ROOT/scripts/render-refinement-md.sh" "$tmp/dp/refinement.json"
cp "$tmp/dp/refinement.md" "$tmp/one.md"
bash "$ROOT/scripts/render-refinement-md.sh" "$tmp/dp/refinement.json"
cmp -s "$tmp/one.md" "$tmp/dp/refinement.md"
grep -q "generated-by: render-refinement-md.sh" "$tmp/dp/refinement.md"
grep -q "checksum: sha256:" "$tmp/dp/refinement.md"
echo "PASS: refinement md generator"
