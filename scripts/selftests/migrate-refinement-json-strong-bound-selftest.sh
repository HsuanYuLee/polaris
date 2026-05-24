#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/scripts/selftests/refinement-dp229-fixture-lib.sh"
tmp="$(mktemp -d -t refinement-migrate.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
make_refinement_fixture "$tmp/dp"
python3 - "$tmp/dp/refinement.json" <<'PY'
import json, sys
p=sys.argv[1]; d=json.load(open(p)); d.pop("schema_version", None); d.pop("tasks", None); d.pop("adversarial_pass", None); json.dump(d, open(p,"w"), ensure_ascii=False)
PY
bash "$ROOT/scripts/migrate-refinement-json.sh" "$tmp/dp/refinement.json" >/dev/null
bash "$ROOT/scripts/validate-refinement-json.sh" "$tmp/dp/refinement.json"
echo "PASS: migrate refinement JSON strong-bound"
