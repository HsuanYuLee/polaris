#!/usr/bin/env bash
# Selftest for measure-review-inbox-session.sh.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
measurer="$script_dir/measure-review-inbox-session.sh"
learnings="$script_dir/../../references/scripts/polaris-learnings.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

input="$tmp/input.txt"
output="$tmp/output.txt"
artifacts="$tmp/artifacts"
home="$tmp/home"
workspace="$tmp/workspace"
mkdir -p "$artifacts" "$home" "$workspace"
printf 'line one\nline two\n' > "$input"
printf 'summary\n' > "$output"
printf 'diff body\n' > "$artifacts/pr-1.diff"

telemetry="$tmp/telemetry.json"
"$measurer" \
  --run-id test-run \
  --candidate-count 3 \
  --reviewed-count 2 \
  --runtime-plan-kind main_session_sequential \
  --duration-seconds 12 \
  --sub-agent-tokens 34 \
  --input-file "$input" \
  --output-file "$output" \
  --artifact-dir "$artifacts" \
  --out "$telemetry"

python3 - "$telemetry" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
required = {
    "run_id",
    "candidate_count",
    "reviewed_count",
    "main_session_input_tokens",
    "main_session_output_tokens",
    "sub_agent_tokens",
    "runtime_plan_kind",
    "duration_seconds",
    "estimator_kind",
    "artifact_count",
    "artifact_bytes",
}
missing = required - set(data)
if missing:
    raise SystemExit(f"missing keys: {sorted(missing)}")
if data["main_session_input_tokens"] <= 0:
    raise SystemExit("expected positive input token estimate")
if data["estimator_kind"] != "line_count_proxy":
    raise SystemExit(f"unexpected estimator: {data['estimator_kind']}")
PY

HOME="$home" POLARIS_WORKSPACE_ROOT="$workspace" "$measurer" \
  --run-id learnings-run \
  --candidate-count 1 \
  --reviewed-count 1 \
  --runtime-plan-kind main_session_sequential \
  --input-file "$input" \
  --write-learnings \
  --learnings-script "$learnings" >/dev/null

HOME="$home" POLARIS_WORKSPACE_ROOT="$workspace" "$learnings" query \
  --type telemetry \
  --tag review-inbox \
  | jq -e '.[0].metadata.review_inbox_run.main_session_input_tokens > 0' >/dev/null

echo "measure-review-inbox-session selftest: PASS"
