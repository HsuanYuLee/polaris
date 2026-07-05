#!/usr/bin/env bash
# Purpose: Verify the explicit Bug source detector only triggers on Bug signals.
# Inputs:  Repository checkout containing scripts/lib/refinement-bug-source-detector.py.
# Outputs: PASS line on success; exits non-zero on detector drift.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DETECTOR="$ROOT/scripts/lib/refinement-bug-source-detector.py"

run_json() {
  python3 "$DETECTOR" "$@"
}

bug_out="$(run_json --source-kind bug)"
python3 - "$bug_out" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
expected = {
    "reproduction",
    "rca_investigation",
    "source_pr_identification",
    "severity_impact_assessment",
}
assert data["bug_source_mode"] is True
assert set(data["required_substeps"]) == expected
PY

jira_out="$(run_json --payload-json '{"fields":{"issuetype":{"name":"Bug"}}}')"
python3 - "$jira_out" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
assert data["bug_source_mode"] is True
assert data["source_kind"] == "bug"
PY

non_bug_out="$(run_json --source-kind dp --issue-type Story)"
python3 - "$non_bug_out" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
assert data["bug_source_mode"] is False
assert data["required_substeps"] == []
PY

echo "PASS: refinement-bug-source-detector selftest"
