#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/scripts/selftests/refinement-dp229-fixture-lib.sh"
tmp="$(mktemp -d -t refinement-referrer.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
make_refinement_fixture "$tmp/dp"
python3 - "$tmp/dp/refinement.json" <<'PY'
import json, sys
p=sys.argv[1]; d=json.load(open(p)); d["modules"]=[{"path":".claude/skills/references/old.md","action":"delete"}]; json.dump(d, open(p,"w"), ensure_ascii=False)
PY
(cd "$ROOT" && python3 scripts/lib/refinement-referrer-cascade.py "$tmp/dp/refinement.json" 2>"$tmp/err")
grep -q POLARIS_REFERRER_CASCADE_REVIEW "$tmp/err"
echo "PASS: refinement referrer cascade"
