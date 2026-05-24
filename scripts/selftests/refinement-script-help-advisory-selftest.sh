#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/scripts/selftests/refinement-dp229-fixture-lib.sh"
tmp="$(mktemp -d -t refinement-help.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
make_refinement_fixture "$tmp/dp"
python3 - "$tmp/dp/refinement.json" <<'PY'
import json, sys
p=sys.argv[1]; d=json.load(open(p)); d["acceptance_criteria"][0]["verification"]["detail"]="bash scripts/fixture-driver.sh --ledger"; json.dump(d, open(p,"w"), ensure_ascii=False)
PY
mkdir -p "$tmp/repo/scripts"
cat >"$tmp/repo/scripts/fixture-driver.sh" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "--help" ]]; then echo "--ledger"; exit 0; fi
SH
chmod +x "$tmp/repo/scripts/fixture-driver.sh"
(cd "$tmp/repo" && python3 "$ROOT/scripts/lib/refinement-script-help-advisory.py" "$tmp/dp/refinement.json" 2>"$tmp/err")
grep -q POLARIS_SCRIPT_HELP_ADVISORY "$tmp/err"
echo "PASS: refinement script help advisory"
