#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/scripts/selftests/refinement-dp229-fixture-lib.sh"
tmp="$(mktemp -d -t refinement-handedit.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
make_refinement_fixture "$tmp/dp"
bash "$ROOT/scripts/render-refinement-md.sh" "$tmp/dp/refinement.json"
python3 "$ROOT/scripts/lib/refinement-md-hand-edit-detector.py" "$tmp/dp/refinement.json"
printf '\\nmanual edit\\n' >> "$tmp/dp/refinement.md"
if python3 "$ROOT/scripts/lib/refinement-md-hand-edit-detector.py" "$tmp/dp/refinement.json" 2>"$tmp/err"; then exit 1; fi
grep -q POLARIS_REFINEMENT_MD_HAND_EDIT_DETECTED "$tmp/err"
echo "PASS: refinement md hand-edit detector"
