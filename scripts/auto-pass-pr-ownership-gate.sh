#!/usr/bin/env bash
# Purpose: Validate auto-pass PR ownership/readiness at consumption points.
# Inputs:  --state-file JSON, or --stdin
# Outputs: PASS line on success; structured POLARIS_AUTO_PASS_PR_* marker on
#          stderr and exit 2 on blocked input.
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/auto-pass-pr-ownership-gate.sh --state-file /path/to/pr-state.json
  scripts/auto-pass-pr-ownership-gate.sh --stdin

The JSON object may carry fields at top level or under auto_pass_pr_ownership /
pr_ownership:
  pr_url, isDraft|is_draft|draft, publisher|writer|provenance.writer,
  engineering_completion_marker|completion_marker|completion_gate.status,
  base_freshness|readiness.base_freshness

When engineering_no_bypass_required/no_bypass_required is true, the object must
also carry task_md_lineage, resolver_lock, readiness_pack_snapshot, and
skill_boundary_marker as present/PASS values.
USAGE
  exit 2
}

STATE_FILE=""
READ_STDIN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state-file) STATE_FILE="${2:-}"; shift 2 ;;
    --stdin) READ_STDIN=1; shift ;;
    --help|-h) usage ;;
    *) echo "auto-pass-pr-ownership-gate: unknown arg: $1" >&2; usage ;;
  esac
done

if [[ "$READ_STDIN" -eq 1 && -n "$STATE_FILE" ]]; then
  echo "auto-pass-pr-ownership-gate: choose exactly one input source" >&2
  exit 2
fi
if [[ "$READ_STDIN" -eq 0 && -z "$STATE_FILE" ]]; then
  usage
fi
if [[ -n "$STATE_FILE" && ! -f "$STATE_FILE" ]]; then
  echo "POLARIS_AUTO_PASS_PR_OWNERSHIP_BLOCKED:state file not found: $STATE_FILE" >&2
  exit 2
fi

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/auto_pass_auto_pass_pr_ownership_gate_1.py" "$STATE_FILE" "$READ_STDIN"
