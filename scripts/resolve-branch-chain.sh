#!/usr/bin/env bash
# resolve-branch-chain.sh — resolve task.md Branch chain contract.
#
# Usage:
#   resolve-branch-chain.sh <path/to/task.md> [--format lines|json]
#
# Output:
#   lines (default): one branch name per line, upstream → downstream
#   json: {"task_md":"...","branch_chain":["develop","feat/...","task/..."]}
#
# Semantics:
#   - Prefer Operational Context `Branch chain` when present.
#   - Fallback for older task.md:
#       develop + Base branch + Task branch when Base branch is feat/* or task/*
#       Base branch + Task branch otherwise.
#   - Remove duplicate adjacent entries.

set -u

log_err() {
  printf '[resolve-branch-chain] %s\n' "$*" >&2
}

parse_table_field() {
  local field="$1"
  local file="$2"
  awk -F '|' -v key="$field" '
    {
      if ($0 ~ /^[[:space:]]*\|[[:space:]]*-+/) next
      if (NF < 3) next
      f = $2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", f)
      if (f == key) {
        v = $3
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        print v
        exit
      }
    }
  ' "$file"
}

usage() {
  cat >&2 <<'USAGE'
usage: resolve-branch-chain.sh <path/to/task.md> [--format lines|json]
USAGE
}

TASK_MD=""
FORMAT="lines"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --format)
      [ "$#" -ge 2 ] || { log_err "--format requires a value"; usage; exit 2; }
      FORMAT="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    -*)
      log_err "unknown option: $1"; usage; exit 2 ;;
    *)
      if [ -n "$TASK_MD" ]; then
        log_err "unexpected argument: $1"; usage; exit 2
      fi
      TASK_MD="$1"; shift ;;
  esac
done

if [ -z "$TASK_MD" ]; then
  usage
  exit 2
fi
if [ ! -f "$TASK_MD" ]; then
  log_err "file not found: $TASK_MD"
  exit 2
fi
case "$FORMAT" in
  lines|json) ;;
  *) log_err "invalid --format: $FORMAT"; exit 2 ;;
esac

BRANCH_CHAIN=$(parse_table_field "Branch chain" "$TASK_MD")
BASE_BRANCH=$(parse_table_field "Base branch" "$TASK_MD")
TASK_BRANCH=$(parse_table_field "Task branch" "$TASK_MD")

if [ -n "$BRANCH_CHAIN" ]; then
  RAW_CHAIN="$BRANCH_CHAIN"
else
  if [ -z "$BASE_BRANCH" ] || [ -z "$TASK_BRANCH" ]; then
    log_err "Branch chain missing and cannot fallback without Base branch + Task branch"
    exit 1
  fi
  case "$BASE_BRANCH" in
    feat/*|task/*) RAW_CHAIN="develop -> $BASE_BRANCH -> $TASK_BRANCH" ;;
    *) RAW_CHAIN="$BASE_BRANCH -> $TASK_BRANCH" ;;
  esac
fi

python3 - "$TASK_MD" "$FORMAT" "$RAW_CHAIN" <<'PY'
import json
import re
import sys

task_md, fmt, raw = sys.argv[1], sys.argv[2], sys.argv[3]

parts = [
    p.strip().strip("`")
    for p in re.split(r"\s*(?:->|→|,|\n)\s*", raw)
    if p.strip().strip("`")
]

chain = []
for p in parts:
    if not chain or chain[-1] != p:
        chain.append(p)

if len(chain) < 2:
    sys.stderr.write("[resolve-branch-chain] branch chain must contain at least upstream + task branch\n")
    sys.exit(1)

if fmt == "json":
    sys.stdout.write(json.dumps({"task_md": task_md, "branch_chain": chain}, separators=(",", ":")) + "\n")
else:
    sys.stdout.write("\n".join(chain) + "\n")
PY
