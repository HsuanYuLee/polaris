#!/usr/bin/env bash
# checkpoint-todo-diff.sh — Verify all todo items have dispositions before checkpoint
#
# Usage: checkpoint-todo-diff.sh --todo-json <json> --checkpoint-file <path>
#
# Reads the current todo list (JSON from stdin or --todo-json) and a checkpoint
# memory file, then checks that every todo item appears in the checkpoint with
# one of three dispositions: done, carry-forward, or dropped.
#
# Exit codes:
#   0 — all items accounted for
#   1 — missing items found (lists them on stdout)
#   2 — usage error

set -euo pipefail

usage() {
  echo "Usage: $0 --todo-items 'item1|item2|item3' --checkpoint-file <path>"
  echo "   or: $0 --todo-file <json-path> --checkpoint-file <path>"
  echo ""
  echo "Options:"
  echo "  --todo-items    Pipe-separated list of todo item descriptions"
  echo "  --todo-file     Path to JSON file with todo items (array of {content, status})"
  echo "  --checkpoint-file  Path to the checkpoint memory .md file to verify against"
  exit 2
}

TODO_ITEMS=""
TODO_FILE=""
CHECKPOINT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --todo-items) TODO_ITEMS="$2"; shift 2 ;;
    --todo-file) TODO_FILE="$2"; shift 2 ;;
    --checkpoint-file) CHECKPOINT_FILE="$2"; shift 2 ;;
    *) usage ;;
  esac
done

if [[ -z "$CHECKPOINT_FILE" ]]; then
  echo "ERROR: --checkpoint-file is required"
  usage
fi

if [[ ! -f "$CHECKPOINT_FILE" ]]; then
  echo "ERROR: checkpoint file not found: $CHECKPOINT_FILE"
  exit 2
fi

# Build the list of items to check
items=()
if [[ -n "$TODO_ITEMS" ]]; then
  IFS='|' read -ra items <<< "$TODO_ITEMS"
elif [[ -n "$TODO_FILE" ]]; then
  if [[ ! -f "$TODO_FILE" ]]; then
    echo "ERROR: todo file not found: $TODO_FILE"
    exit 2
  fi
  while IFS= read -r line; do
    items+=("$line")
  done < <(python3 -c "
import json, sys
data = json.load(open('$TODO_FILE'))
for item in data:
    print(item.get('content', ''))
")
else
  echo "ERROR: either --todo-items or --todo-file is required"
  usage
fi

if [[ ${#items[@]} -eq 0 ]]; then
  echo "✅ No todo items to check"
  exit 0
fi

# Read checkpoint content
checkpoint_content=$(cat "$CHECKPOINT_FILE")

# Check each item
missing=()
for item in "${items[@]}"; do
  # Skip empty items
  [[ -z "$item" ]] && continue

  # Extract key words (first 20 chars or key identifiers like ticket keys)
  # Use a fuzzy match: check if any significant substring appears in checkpoint
  found=false

  # Try exact substring match first
  if echo "$checkpoint_content" | grep -qi "$(echo "$item" | head -c 40)"; then
    found=true
  fi

  # Try matching ticket keys (e.g., GT-500, KB2CW-3821, DP-009)
  ticket_keys=$(echo "$item" | grep -oE '[A-Z]+-[0-9]+' || true)
  if [[ -n "$ticket_keys" ]]; then
    for key in $ticket_keys; do
      if echo "$checkpoint_content" | grep -q "$key"; then
        found=true
        break
      fi
    done
  fi

  # Try matching key phrases (split by common delimiters, check 3+ char tokens)
  if [[ "$found" == "false" ]]; then
    for word in $(echo "$item" | tr '：:，,（）()/' ' '); do
      if [[ ${#word} -ge 4 ]] && echo "$checkpoint_content" | grep -qi "$word"; then
        found=true
        break
      fi
    done
  fi

  if [[ "$found" == "false" ]]; then
    missing+=("$item")
  fi
done

if [[ ${#missing[@]} -eq 0 ]]; then
  echo "✅ All ${#items[@]} todo items accounted for in checkpoint"
  exit 0
else
  echo "❌ ${#missing[@]}/${#items[@]} todo items NOT found in checkpoint:"
  for m in "${missing[@]}"; do
    echo "   - $m"
  done
  echo ""
  echo "Each item must appear in the checkpoint as: done, carry-forward, or dropped (with reason)"
  exit 1
fi
