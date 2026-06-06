#!/usr/bin/env bash
# Purpose: Stop (session-end) advisory hook for DP-290. Prints a one-line reminder to
#          refresh the active-thread anchor (scripts/update-active-thread.sh) so the next
#          session's SessionStart hook injects a current 「下一步」 handoff. Advisory only.
# Inputs:  Stop JSON payload on stdin (drained, not inspected).
# Outputs: One advisory line on stdout. ALWAYS exit 0 — never blocks the session stop.

set -uo pipefail 2>/dev/null || true

# Drain stdin so the caller's pipe does not block; payload content is not needed.
cat >/dev/null 2>&1 || true

echo "[stop-active-thread-reminder] advisory: 更新 active-thread 錨點 (bash scripts/update-active-thread.sh) 以便下個 session 的 SessionStart hook 注入最新「下一步」。"

exit 0
