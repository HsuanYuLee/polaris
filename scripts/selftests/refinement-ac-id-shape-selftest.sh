#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/scripts/selftests/refinement-dp229-fixture-lib.sh"
tmp="$(mktemp -d -t refinement-acid.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
make_refinement_fixture "$tmp/dp"
python3 "$ROOT/scripts/lib/refinement-ac-id-shape.py" "$tmp/dp/refinement.json"
python3 - "$tmp/dp/refinement.json" <<'PY'
import json, sys
p=sys.argv[1]; d=json.load(open(p)); d["acceptance_criteria"][0]["id"]="AC3a"; json.dump(d, open(p,"w"), ensure_ascii=False)
PY
if python3 "$ROOT/scripts/lib/refinement-ac-id-shape.py" "$tmp/dp/refinement.json" 2>"$tmp/err"; then exit 1; fi
grep -q POLARIS_AC_ID_SHAPE_INVALID "$tmp/err"
echo "PASS: refinement AC ID shape"
