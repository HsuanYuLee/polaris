#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/scripts/selftests/refinement-dp229-fixture-lib.sh"
tmp="$(mktemp -d -t refinement-decision.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
make_refinement_fixture "$tmp/dp"
python3 "$ROOT/scripts/lib/refinement-decision-ac-coverage.py" "$tmp/dp/refinement.json"
perl -0pi -e 's/Enforced by: AC1/No coverage/' "$tmp/dp/refinement.md"
python3 - "$tmp/dp/refinement.json" <<'PY'
import json, sys
p=sys.argv[1]; d=json.load(open(p)); d["acceptance_criteria"][0]["text"]="fixture without decision token"; d["acceptance_criteria"][0]["verification"]["detail"]="fixture"; json.dump(d, open(p,"w"), ensure_ascii=False)
PY
if python3 "$ROOT/scripts/lib/refinement-decision-ac-coverage.py" "$tmp/dp/refinement.json" 2>"$tmp/err"; then exit 1; fi
grep -q POLARIS_DECISION_AC_COVERAGE_MISSING "$tmp/err"
echo "PASS: refinement decision AC coverage"
