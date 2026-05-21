#!/usr/bin/env bash
# gate-hook-adapter.sh
# Execute a Claude-style gate script by feeding synthetic hook JSON.
#
# Usage:
#   gate-hook-adapter.sh <gate_script> <command_string>
#
# Env:
#   GATE_PROJECT_DIR=<path>  Optional project dir; defaults to git root or cwd.
#   POLARIS_TASK_ID=<id>     Optional task id for gate-failure ledger naming.
#
# Exit code follows gate script exit code (0 allow, 2 block). When the child
# gate exits 2, this adapter appends deterministic failure evidence before
# returning the child gate status.

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <gate_script> <command_string>" >&2
  exit 1
fi

gate_script="$1"
shift
command_string="$*"

if [[ ! -f "$gate_script" ]]; then
  echo "Gate script not found: $gate_script" >&2
  exit 1
fi

if [[ -n "${GATE_PROJECT_DIR:-}" ]]; then
  project_dir="$GATE_PROJECT_DIR"
elif git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  project_dir="$git_root"
else
  project_dir="$(pwd)"
fi

resolve_repo_root() {
  local candidate="$1"
  if git_root="$(git -C "$candidate" rev-parse --show-toplevel 2>/dev/null)"; then
    printf '%s\n' "$git_root"
  else
    printf '%s\n' "$candidate"
  fi
}

resolve_evidence_repo() {
  local repo="$1"
  local common_git_dir=""
  if common_git_dir="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
    if [[ "$(basename "$common_git_dir")" == ".git" ]]; then
      dirname "$common_git_dir"
      return
    fi
  fi
  printf '%s\n' "$repo"
}

resolve_task_id() {
  if [[ -n "${POLARIS_TASK_ID:-}" ]]; then
    printf '%s\n' "$POLARIS_TASK_ID"
    return
  fi
  if [[ -n "${POLARIS_WORK_ITEM_ID:-}" ]]; then
    printf '%s\n' "$POLARIS_WORK_ITEM_ID"
    return
  fi
  if [[ -n "${TASK_ID:-}" ]]; then
    printf '%s\n' "$TASK_ID"
    return
  fi

  local branch_name=""
  branch_name="$(git -C "$repo_root" branch --show-current 2>/dev/null || true)"
  python3 - "$command_string" "$branch_name" <<'PY'
import re
import sys

command = sys.argv[1]
branch = sys.argv[2]
for candidate in (command, branch):
    match = re.search(r"\bDP-\d{3}-T\d+[a-z]?\b", candidate)
    if match:
        print(match.group(0))
        sys.exit(0)
for candidate in (command, branch):
    match = re.search(r"\b[A-Z][A-Z0-9]+-\d+\b", candidate)
    if match:
        print(match.group(0))
        sys.exit(0)
print("unknown-task")
PY
}

append_gate_failure_ledger() {
  local evidence_repo="$1"
  local task_id="$2"
  local gate_id="$3"
  local repo="$4"
  local head_sha="$5"
  local exit_code="$6"
  local stderr_excerpt="$7"
  local ledger_dir="${POLARIS_GATE_FAILURE_LEDGER_DIR:-$evidence_repo/.polaris/evidence/gate-failures}"
  local ledger_path="$ledger_dir/$task_id.jsonl"
  local attempt=1

  while [[ "$attempt" -le 3 ]]; do
    if python3 - "$ledger_path" "$task_id" "$gate_id" "$repo" "$head_sha" "$exit_code" "$stderr_excerpt" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ledger_path = Path(sys.argv[1])
entry = {
    "ts": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    "task_id": sys.argv[2],
    "gate_id": sys.argv[3],
    "repo": sys.argv[4],
    "head_sha": sys.argv[5],
    "exit_code": int(sys.argv[6]),
    "stderr_excerpt": sys.argv[7][:4000],
    "classification": "pending",
}
ledger_path.parent.mkdir(parents=True, exist_ok=True)
with ledger_path.open("a", encoding="utf-8") as handle:
    handle.write(json.dumps(entry, ensure_ascii=False, sort_keys=True) + "\n")
PY
    then
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 0.1
  done

  echo "gate-hook-adapter: failed to write gate-failure ledger after 3 attempts: $ledger_path" >&2
  return 1
}

repo_root="$(resolve_repo_root "$project_dir")"
evidence_repo="$(resolve_evidence_repo "$repo_root")"
task_id="$(resolve_task_id)"
gate_id="$(basename "$gate_script")"
gate_id="${gate_id%.*}"
if head_sha="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null)"; then
  :
else
  head_sha="unknown"
fi

payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$command_string")"

set +e
gate_output="$(printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$project_dir" bash "$gate_script" 2>&1)"
gate_rc=$?
set -e

if [[ -n "$gate_output" ]]; then
  printf '%s\n' "$gate_output"
fi

if [[ "$gate_rc" -eq 2 ]]; then
  append_gate_failure_ledger "$evidence_repo" "$task_id" "$gate_id" "$repo_root" "$head_sha" "$gate_rc" "$gate_output" || exit 2
  # DP-220: deterministic friction trigger — emit kind=deterministic_gap when
  # the auto-pass orchestrator ledger is in scope (AUTO_PASS_LEDGER_PATH set).
  # No-op outside /auto-pass runs.
  if [[ -n "${AUTO_PASS_LEDGER_PATH:-}" ]]; then
    "$(dirname "${BASH_SOURCE[0]}")/append-auto-pass-friction.sh" \
      "$AUTO_PASS_LEDGER_PATH" \
      --stage engineering \
      --kind deterministic_gap \
      --summary "gate exit 2: gate_id=$gate_id task=$task_id (auto-trigger from gate-hook-adapter, DP-220)" \
      >/dev/null 2>&1 || true
  fi
fi

exit "$gate_rc"
