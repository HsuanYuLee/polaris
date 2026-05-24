#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/scripts/selftests/refinement-dp229-fixture-lib.sh"
tmp="$(mktemp -d -t refinement-json.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
make_refinement_fixture "$tmp/dp"
bash "$ROOT/scripts/validate-refinement-json.sh" "$tmp/dp/refinement.json"
python3 - "$tmp/dp/refinement.json" <<'PY'
import json, sys
p=sys.argv[1]; d=json.load(open(p)); d.pop("schema_version", None); json.dump(d, open(p,"w"), ensure_ascii=False)
PY
if bash "$ROOT/scripts/validate-refinement-json.sh" "$tmp/dp/refinement.json" 2>"$tmp/err"; then exit 1; fi
grep -q "strong-bound schema: schema_version" "$tmp/err"
echo "PASS: validate refinement JSON strong-bound"
