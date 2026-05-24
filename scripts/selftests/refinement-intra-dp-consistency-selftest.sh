#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/scripts/selftests/refinement-dp229-fixture-lib.sh"
tmp="$(mktemp -d -t refinement-intra.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
make_refinement_fixture "$tmp/dp"
python3 "$ROOT/scripts/lib/refinement-intra-dp-consistency.py" "$tmp/dp/refinement.json"
python3 - "$tmp/dp/refinement.md" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
t=p.read_text()
p.write_text(t.replace("`scripts/fixture-driver.sh` | create", "`scripts/fixture-driver.sh` | modify"))
PY
if python3 "$ROOT/scripts/lib/refinement-intra-dp-consistency.py" "$tmp/dp/refinement.json" 2>"$tmp/err"; then exit 1; fi
grep -q POLARIS_INTRA_DP_MODULE_DRIFT "$tmp/err"
echo "PASS: refinement intra-DP consistency"
