#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/scripts/selftests/refinement-dp229-fixture-lib.sh"
tmp="$(mktemp -d -t refinement-release.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
make_refinement_fixture "$tmp/dp"
python3 "$ROOT/scripts/lib/refinement-release-surface-advisory.py" "$tmp/dp/refinement.json" 2>"$tmp/err"
grep -q POLARIS_FRAMEWORK_RELEASE_SURFACE_MISSING "$tmp/err"
python3 "$ROOT/scripts/lib/refinement-release-surface-advisory.py" --json "$tmp/dp/refinement.json" >"$tmp/advisory.json"
grep -q '"id": "framework-release-surface-missing"' "$tmp/advisory.json"
grep -q '"disposition": "pending"' "$tmp/advisory.json"
echo "PASS: refinement release surface advisory"
