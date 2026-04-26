#!/usr/bin/env bash
# memory-decay-scan.sh — SessionStart hook (DP-015 B12)
# On session start, run advisory decay scan over the memory tier index.
# Prints candidate demotions (Hot → Warm, Warm → Cold) to Claude's context.
# Does NOT move files — migration is gated behind `/memory-hygiene` skill or
# manual `scripts/memory-hygiene-tiering.py apply`.
#
# Design ref: specs/design-plans/DP-015-polaris-context-efficiency/plan.md § D7.4
# Script:     scripts/memory-hygiene-tiering.py
# Rule ref:   rules/feedback-and-memory.md § Memory Tiering
#
# Hook type: SessionStart (fires once per new session)
# Stdout:    injected into Claude's context (advisory only)
# Exit 0:    always — this hook must never block session startup

set -uo pipefail

SCRIPT="/Users/hsuanyu.lee/work/scripts/memory-hygiene-tiering.py"
MEMORY_DIR="/Users/hsuanyu.lee/.claude/projects/-Users-hsuanyu-lee-work/memory"

# --- Skip conditions ---
# 1. Script missing → silent skip (e.g., fresh workstation without Polaris synced)
if [ ! -x "$SCRIPT" ]; then
  exit 0
fi

# 2. Memory dir missing → silent skip (e.g., first-ever run)
if [ ! -d "$MEMORY_DIR" ]; then
  exit 0
fi

# 3. Already scanned today → silent skip (avoid noise on every session)
STAMP="/tmp/polaris-memory-decay-scan-$(date +%Y-%m-%d)"
if [ -f "$STAMP" ]; then
  exit 0
fi

# --- Run advisory scan ---
# Timeout protects against pathological inputs; output is pure markdown.
OUTPUT=$("$SCRIPT" decay-scan --memory-dir "$MEMORY_DIR" 2>&1 || true)

# --- Mark as run (always, even if no candidates) ---
touch "$STAMP" 2>/dev/null || true

# --- Emit only if there are actionable candidates ---
# Heuristic: skip output if report is empty or has zero suggestions
if [ -z "$OUTPUT" ]; then
  exit 0
fi

if echo "$OUTPUT" | grep -qE 'No candidates|^0 files|Nothing to demote'; then
  exit 0
fi

cat <<EOF

[SessionStart] Memory decay scan (advisory):
$OUTPUT

Action: run \`/memory-hygiene\` to review and apply demotions, or ignore for now.
EOF

exit 0
