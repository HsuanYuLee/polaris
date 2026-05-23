#!/usr/bin/env bash
# gate-template-leaks-selftest.sh — DP-228 recurrence prevention selftest.
#
# Verifies scripts/gates/gate-template-leaks.sh:
#   * exits 0 on a clean workspace fixture (no company config, no leaks),
#   * exits non-zero on a workspace fixture that plants a live JIRA prefix in
#     a tracked .claude/skills/references/* path.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/scripts/gates/gate-template-leaks.sh"
SCAN="$ROOT/scripts/scan-template-leaks.sh"

if [[ ! -x "$GATE" ]]; then
  echo "FAIL: gate missing at $GATE" >&2
  exit 1
fi
if [[ ! -x "$SCAN" ]]; then
  echo "FAIL: scan-template-leaks.sh missing at $SCAN" >&2
  exit 1
fi

tmpdir="$(mktemp -d -t gate-template-leaks.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

clean_ws="$tmpdir/clean"
mkdir -p "$clean_ws/scripts" "$clean_ws/.claude/skills/references"
cp "$SCAN" "$clean_ws/scripts/scan-template-leaks.sh"
cat >"$clean_ws/.claude/skills/references/sample.md" <<'MD'
Use EXAMPLE-123 in shared template fixtures.
MD

set +e
bash "$GATE" --repo "$clean_ws" >/tmp/gate-template-leaks-clean.out 2>/tmp/gate-template-leaks-clean.err
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL: clean workspace gate expected exit 0, got $rc" >&2
  cat /tmp/gate-template-leaks-clean.err >&2
  exit 1
fi

# Plant a leak: create an acme company workspace-config + leak in a reference.
dirty_ws="$tmpdir/dirty"
mkdir -p "$dirty_ws/scripts" "$dirty_ws/.claude/skills/references" "$dirty_ws/acme"
cp "$SCAN" "$dirty_ws/scripts/scan-template-leaks.sh"
cat >"$dirty_ws/acme/workspace-config.yaml" <<'YAML'
jira:
  instance: acme.atlassian.net
  projects:
    - key: ACME
YAML
cat >"$dirty_ws/.claude/skills/references/leaky.md" <<'MD'
This file references ACME-9999 which must be flagged by the gate.
MD

set +e
bash "$GATE" --repo "$dirty_ws" >/tmp/gate-template-leaks-dirty.out 2>/tmp/gate-template-leaks-dirty.err
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: dirty workspace gate expected non-zero exit, got 0" >&2
  exit 1
fi
if ! grep -q "BLOCKED" /tmp/gate-template-leaks-dirty.err; then
  echo "FAIL: dirty workspace gate stderr missing BLOCKED marker" >&2
  cat /tmp/gate-template-leaks-dirty.err >&2
  exit 1
fi

echo "PASS: gate-template-leaks selftest"
