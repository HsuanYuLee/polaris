#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/scripts/selftests/refinement-dp229-fixture-lib.sh"
tmp="$(mktemp -d -t refinement-parity.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
make_refinement_fixture "$tmp/dp"
python3 "$ROOT/scripts/lib/refinement-selftest-parity.py" "$tmp/dp/refinement.json" 2>"$tmp/ok"
test ! -s "$tmp/ok"
python3 - "$tmp/dp/refinement.json" <<'PY'
import json, sys
p=sys.argv[1]; d=json.load(open(p)); d["modules"]=d["modules"][:1]; json.dump(d, open(p,"w"), ensure_ascii=False)
PY
python3 "$ROOT/scripts/lib/refinement-selftest-parity.py" "$tmp/dp/refinement.json" 2>"$tmp/err"
grep -q POLARIS_SELFTEST_PARITY_MISSING "$tmp/err"
echo "PASS: refinement selftest parity"
