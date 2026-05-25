#!/usr/bin/env bash
# scan-template-leaks-workspace-exception-selftest.sh — DP-230 D21 (AC17).
#
# Verifies scripts/scan-template-leaks.sh skip_path() carve-out for workspace
# selftest fixtures (DP-226 P8 broken-fixture parity):
#   * scripts/selftests/fixtures/<anything>/* paths with synthetic company
#     prefixes (OPS-, WEB-) do NOT trigger blocking hits.
#   * The same prefix outside the carve-out (e.g. .claude/skills/references/)
#     DOES fail-stop and emits `POLARIS_TEMPLATE_LEAK` to stderr.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCAN="$ROOT/scripts/scan-template-leaks.sh"

if [[ ! -x "$SCAN" ]]; then
  echo "FAIL: scan-template-leaks.sh missing or not executable: $SCAN" >&2
  exit 1
fi

tmpdir="$(mktemp -d -t scan-leaks-workspace-exception.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# --- Build a synthetic workspace with an example company config so the
#     scanner derives live JIRA prefixes for this fixture only. ---
ws="$tmpdir/ws"
mkdir -p \
  "$ws/exampleco" \
  "$ws/scripts/selftests/fixtures/dp226-engineering" \
  "$ws/scripts/selftests/fixtures/other-fixture" \
  "$ws/.claude/skills/references"

cat >"$ws/exampleco/workspace-config.yaml" <<'YAML'
jira:
  instance: example.atlassian.net
  projects:
    - key: OPS
    - key: WEB
github:
  org: example-org
YAML

# Carve-out fixture: a tracked selftest fixture that legitimately stages live
# company-shaped slugs to exercise downstream engineering validators. This MUST
# NOT cause a blocking hit.
cat >"$ws/scripts/selftests/fixtures/dp226-engineering/task-fixture.md" <<'MD'
# DP-226 broken fixture
- ticket: WEB-3461
- epic: OPS-483
MD

# Sibling carve-out path with a different fixture name (validates the rule is
# path-prefix-based, not fixture-name-specific).
cat >"$ws/scripts/selftests/fixtures/other-fixture/payload.md" <<'MD'
ref WEB-9999 in synthetic payload.
MD

# Outside the carve-out: a reference doc that leaks the same prefix. This MUST
# block the scan.
cat >"$ws/.claude/skills/references/leaky.md" <<'MD'
Reviewer left a stale WEB-1234 example here.
MD

# --- Case A: leak outside fixtures → blocking fail + POLARIS_TEMPLATE_LEAK ---
set +e
"$SCAN" --workspace "$ws" --source workspace --blocking \
  >/tmp/scan-leaks-fixture-dirty.out 2>/tmp/scan-leaks-fixture-dirty.err
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: leak outside carve-out expected non-zero exit, got 0" >&2
  cat /tmp/scan-leaks-fixture-dirty.out >&2
  exit 1
fi
if ! grep -q "POLARIS_TEMPLATE_LEAK" /tmp/scan-leaks-fixture-dirty.err; then
  echo "FAIL: stderr missing POLARIS_TEMPLATE_LEAK token" >&2
  cat /tmp/scan-leaks-fixture-dirty.err >&2
  exit 1
fi
if ! grep -q "WEB-1234" /tmp/scan-leaks-fixture-dirty.out; then
  echo "FAIL: expected the .claude/skills/references leak to surface in output" >&2
  cat /tmp/scan-leaks-fixture-dirty.out >&2
  exit 1
fi
# The fixture paths must NOT appear in hits even when the scan is failing.
if grep -q "fixtures/dp226-engineering" /tmp/scan-leaks-fixture-dirty.out; then
  echo "FAIL: dp226-engineering fixture incorrectly flagged as a leak" >&2
  cat /tmp/scan-leaks-fixture-dirty.out >&2
  exit 1
fi
if grep -q "fixtures/other-fixture" /tmp/scan-leaks-fixture-dirty.out; then
  echo "FAIL: other-fixture path incorrectly flagged as a leak" >&2
  cat /tmp/scan-leaks-fixture-dirty.out >&2
  exit 1
fi

# --- Case B: remove the out-of-carve-out leak → scan should PASS even though
#     the dp226-engineering / other-fixture trees still carry live prefixes ---
rm -f "$ws/.claude/skills/references/leaky.md"

set +e
"$SCAN" --workspace "$ws" --source workspace --blocking \
  >/tmp/scan-leaks-fixture-clean.out 2>/tmp/scan-leaks-fixture-clean.err
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL: workspace with only fixture-tree prefixes expected exit 0, got $rc" >&2
  cat /tmp/scan-leaks-fixture-clean.err >&2
  cat /tmp/scan-leaks-fixture-clean.out >&2
  exit 1
fi

echo "PASS: scan-template-leaks workspace-exception selftest"
