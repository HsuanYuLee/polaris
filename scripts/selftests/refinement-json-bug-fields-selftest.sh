#!/usr/bin/env bash
# Purpose: Verify source.type=bug refinement.json requires canonical bug fields.
# Inputs:  Repository checkout with validate-refinement-json.sh and refinement fixtures.
# Outputs: PASS line on success; exits non-zero on schema drift.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/scripts/selftests/refinement-dp229-fixture-lib.sh"

tmp="$(mktemp -d -t refinement-bug-fields.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

make_bug_fixture() {
  local dir="$1"
  make_refinement_fixture "$dir"
  python3 - "$dir/refinement.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["source"]["type"] = "bug"
data["source"]["id"] = "BUG-123"
data["source"]["jira_key"] = "BUG-123"
for task in data.get("tasks", []):
    task["id"] = "BUG-123-T1"
    task.pop("allowed_files", None)
    task.pop("estimate_points", None)
data["reproduction_steps"] = ["open source", "run refinement", "observe missing bug fields"]
data["root_cause"] = "Bug source artifacts were accepted without bug triage fields."
data["source_pr"] = "N/A - no source PR identified in fixture"
data["severity"] = "medium"
data["impact_scope"] = "refinement bug-source handoff"
data["regression"] = False
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

expect_fail_contains() {
  local label="$1"
  local file="$2"
  local needle="$3"
  if bash "$ROOT/scripts/validate-refinement-json.sh" "$file" >"$tmp/${label}.out" 2>"$tmp/${label}.err"; then
    echo "FAIL: ${label} unexpectedly passed" >&2
    exit 1
  fi
  grep -Fq "$needle" "$tmp/${label}.err"
}

make_bug_fixture "$tmp/bug"
bash "$ROOT/scripts/validate-refinement-json.sh" "$tmp/bug/refinement.json"

cp "$tmp/bug/refinement.json" "$tmp/missing.json"
python3 - "$tmp/missing.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data.pop("reproduction_steps", None)
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_fail_contains "missing-reproduction-steps" "$tmp/missing.json" "strong-bound schema: reproduction_steps"

cp "$tmp/bug/refinement.json" "$tmp/empty.json"
python3 - "$tmp/empty.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["reproduction_steps"] = []
data["root_cause"] = " "
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_fail_contains "empty-bug-fields" "$tmp/empty.json" "bug field reproduction_steps must be a non-empty array"
grep -Fq "bug field root_cause must be a non-empty string" "$tmp/empty-bug-fields.err"

make_refinement_fixture "$tmp/nonbug"
python3 - "$tmp/nonbug/refinement.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
for task in data.get("tasks", []):
    task.pop("allowed_files", None)
    task.pop("estimate_points", None)
data["reproduction_steps"] = ["non-bug source must not carry bug fields"]
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_fail_contains "nonbug-bug-field" "$tmp/nonbug/refinement.json" "strong-bound schema: reproduction_steps"

echo "PASS: refinement JSON bug fields"
