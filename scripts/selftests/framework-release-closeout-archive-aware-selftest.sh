#!/usr/bin/env bash
# Purpose: Regression selftest for framework-release archive-aware task lookup and
#          already-advanced V task closeout idempotency.
# Inputs:  none; delegates to existing hermetic resolver / closeout fixtures and
#          checks the focused archive-aware contract text remains wired.
# Outputs: exit 0 + PASS line, or non-zero with a focused diagnostic.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESOLVER="${ROOT}/scripts/resolve-task-md-by-branch.sh"
CLOSEOUT_SELFTEST="${ROOT}/scripts/framework-release-closeout-selftest.sh"
CLOSEOUT="${ROOT}/scripts/framework-release-closeout.sh"

[[ -x "$RESOLVER" || -f "$RESOLVER" ]] || {
  echo "FAIL: resolver missing: $RESOLVER" >&2
  exit 1
}
[[ -x "$CLOSEOUT_SELFTEST" || -f "$CLOSEOUT_SELFTEST" ]] || {
  echo "FAIL: closeout selftest missing: $CLOSEOUT_SELFTEST" >&2
  exit 1
}
[[ -f "$CLOSEOUT" ]] || {
  echo "FAIL: closeout script missing: $CLOSEOUT" >&2
  exit 1
}

# Resolver selftest includes an archive-only stale task fixture and asserts the
# active branch lookup does not return it.
RESOLVE_TASK_MD_SELFTEST=1 bash "$RESOLVER"

# The full closeout selftest includes archived pr-release task closeout and the
# delayed archive path. Keep it in this focused wrapper so framework-release
# archive behavior cannot regress without tripping the T2 verify command.
bash "$CLOSEOUT_SELFTEST"

# Focused canary for DP-404 AC4: already-advanced V entries under pr-release are
# idempotent confirms only. This checks the production closeout carries the
# explicit pr-release/V enumeration and never routes that branch through the
# task-level writer.
python3 - "$CLOSEOUT" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(
    r'for entry in "\$tasks_dir"/pr-release/V\*; do(?P<body>.*?)^}',
    text,
    flags=re.MULTILINE | re.DOTALL,
)
if not match:
    raise SystemExit("FAIL: closeout missing pr-release/V already-advanced enumeration")
body = match.group("body")
if "idempotent confirm (NOOP)" not in body:
    raise SystemExit("FAIL: pr-release/V enumeration does not state idempotent NOOP")
if "mark-spec-implemented.sh" in body:
    raise SystemExit("FAIL: pr-release/V already-advanced path must not call mark-spec-implemented")
PY

echo "[framework-release-closeout-archive-aware-selftest] PASS"
