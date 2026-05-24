#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/scripts/selftests/refinement-dp229-fixture-lib.sh"
tmp="$(mktemp -d -t refinement-section.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
make_refinement_fixture "$tmp/dp"
python3 "$ROOT/scripts/lib/refinement-section-presence-advisory.py" --mode predecessor "$tmp/dp/refinement.json"
python3 "$ROOT/scripts/lib/refinement-section-presence-advisory.py" --mode adversarial "$tmp/dp/refinement.json"
perl -0pi -e 's/## Predecessor Scan/## Missing Scan/' "$tmp/dp/refinement.md"
if python3 "$ROOT/scripts/lib/refinement-section-presence-advisory.py" --mode predecessor "$tmp/dp/refinement.json" 2>"$tmp/err"; then exit 1; fi
grep -q POLARIS_PREDECESSOR_SCAN_MISSING "$tmp/err"
echo "PASS: refinement section presence advisory"
