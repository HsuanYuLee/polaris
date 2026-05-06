#!/usr/bin/env bash
# measure-review-inbox-session.sh — emit review-inbox telemetry JSON.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

RUN_ID="review-inbox-$(date +%Y%m%d%H%M%S)"
CANDIDATE_COUNT=0
REVIEWED_COUNT=0
RUNTIME_PLAN_KIND="unknown"
DURATION_SECONDS=0
SUB_AGENT_TOKENS=0
INPUT_FILE=""
OUTPUT_FILE=""
ARTIFACT_DIR=""
OUT_PATH=""
WRITE_LEARNINGS=false
LEARNINGS_SCRIPT="$WORKSPACE_ROOT/.claude/skills/references/scripts/polaris-learnings.sh"

usage() {
  cat >&2 <<'EOF'
Usage:
  measure-review-inbox-session.sh [options]

Options:
  --run-id ID
  --candidate-count N
  --reviewed-count N
  --runtime-plan-kind KIND
  --duration-seconds N
  --sub-agent-tokens N
  --input-file PATH
  --output-file PATH
  --artifact-dir PATH
  --out PATH
  --write-learnings
  --learnings-script PATH
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id) RUN_ID="$2"; shift 2 ;;
    --candidate-count) CANDIDATE_COUNT="$2"; shift 2 ;;
    --reviewed-count) REVIEWED_COUNT="$2"; shift 2 ;;
    --runtime-plan-kind) RUNTIME_PLAN_KIND="$2"; shift 2 ;;
    --duration-seconds) DURATION_SECONDS="$2"; shift 2 ;;
    --sub-agent-tokens) SUB_AGENT_TOKENS="$2"; shift 2 ;;
    --input-file) INPUT_FILE="$2"; shift 2 ;;
    --output-file) OUTPUT_FILE="$2"; shift 2 ;;
    --artifact-dir) ARTIFACT_DIR="$2"; shift 2 ;;
    --out) OUT_PATH="$2"; shift 2 ;;
    --write-learnings) WRITE_LEARNINGS=true; shift ;;
    --learnings-script) LEARNINGS_SCRIPT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

for number in "$CANDIDATE_COUNT" "$REVIEWED_COUNT" "$DURATION_SECONDS" "$SUB_AGENT_TOKENS"; do
  if ! [[ "$number" =~ ^[0-9]+$ ]]; then
    echo "measure-review-inbox-session: numeric option expected, got '$number'" >&2
    exit 2
  fi
done

payload=$(python3 - "$RUN_ID" "$CANDIDATE_COUNT" "$REVIEWED_COUNT" "$RUNTIME_PLAN_KIND" \
  "$DURATION_SECONDS" "$SUB_AGENT_TOKENS" "$INPUT_FILE" "$OUTPUT_FILE" "$ARTIFACT_DIR" <<'PY'
import json
import math
import os
import sys
from pathlib import Path

(
    run_id,
    candidate_count,
    reviewed_count,
    runtime_plan_kind,
    duration_seconds,
    sub_agent_tokens,
    input_file,
    output_file,
    artifact_dir,
) = sys.argv[1:]

def text_stats(path: str) -> tuple[int, int, int]:
    if not path:
        return 0, 0, 0
    file_path = Path(path)
    if not file_path.is_file():
        return 0, 0, 0
    text = file_path.read_text(errors="replace")
    lines = 0 if text == "" else text.count("\n") + (0 if text.endswith("\n") else 1)
    chars = len(text)
    estimated_tokens = max(math.ceil(chars / 4), lines * 8)
    return lines, chars, estimated_tokens

def artifact_stats(path: str) -> tuple[int, int]:
    if not path:
        return 0, 0
    root = Path(path)
    if not root.exists():
        return 0, 0
    files = [item for item in root.rglob("*") if item.is_file()]
    return len(files), sum(item.stat().st_size for item in files)

input_lines, input_chars, input_tokens = text_stats(input_file)
output_lines, output_chars, output_tokens = text_stats(output_file)
artifact_count, artifact_bytes = artifact_stats(artifact_dir)

print(json.dumps({
    "run_id": run_id,
    "candidate_count": int(candidate_count),
    "reviewed_count": int(reviewed_count),
    "main_session_input_tokens": input_tokens,
    "main_session_output_tokens": output_tokens,
    "sub_agent_tokens": int(sub_agent_tokens),
    "runtime_plan_kind": runtime_plan_kind,
    "duration_seconds": int(duration_seconds),
    "estimator_kind": "line_count_proxy",
    "artifact_count": artifact_count,
    "artifact_bytes": artifact_bytes,
    "input_line_count": input_lines,
    "output_line_count": output_lines,
    "input_char_count": input_chars,
    "output_char_count": output_chars,
}, ensure_ascii=False, sort_keys=True))
PY
)

if [[ -n "$OUT_PATH" ]]; then
  mkdir -p "$(dirname "$OUT_PATH")"
  printf '%s\n' "$payload" > "$OUT_PATH"
else
  printf '%s\n' "$payload"
fi

if [[ "$WRITE_LEARNINGS" == "true" ]]; then
  if [[ ! -x "$LEARNINGS_SCRIPT" ]]; then
    echo "measure-review-inbox-session: learnings script not executable: $LEARNINGS_SCRIPT" >&2
    exit 2
  fi
  "$LEARNINGS_SCRIPT" add \
    --key "review-inbox-run-$RUN_ID" \
    --type telemetry \
    --content "review-inbox telemetry run $RUN_ID" \
    --confidence 5 \
    --source review-inbox \
    --tag review-inbox \
    --metadata "{\"review_inbox_run\":$payload}" >/dev/null
fi
