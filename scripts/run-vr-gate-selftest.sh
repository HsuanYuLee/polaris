#!/usr/bin/env bash
# Selftest for conditional Layer C visual regression evidence gate.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT_DIR/scripts/gates/gate-evidence.sh"

tmpdir="$(mktemp -d -t polaris-vr-gate-selftest.XXXXXX)"
cleanup() {
  rm -rf "$tmpdir"
  rm -f /tmp/polaris-verified-VRG-* /tmp/polaris-vr-VRG-* 2>/dev/null || true
}
trap cleanup EXIT

repo="$tmpdir/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email "polaris@example.invalid"
git -C "$repo" config user.name "Polaris Selftest"
printf 'selftest\n' >"$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -q -m "init"
head_sha="$(git -C "$repo" rev-parse HEAD)"

write_verify_evidence() {
  local ticket="$1"
  python3 - "$ticket" "$head_sha" <<'PY'
import json
import sys
from datetime import datetime, timezone

ticket, head_sha = sys.argv[1:3]
payload = {
    "writer": "run-verify-command.sh",
    "ticket": ticket,
    "head_sha": head_sha,
    "exit_code": 0,
    "at": datetime.now(timezone.utc).isoformat(),
}
with open(f"/tmp/polaris-verified-{ticket}-{head_sha}.json", "w", encoding="utf-8") as handle:
    json.dump(payload, handle)
PY
}

write_vr_evidence() {
  local ticket="$1"
  local sha="$2"
  local status="$3"
  python3 - "$ticket" "$sha" "$status" <<'PY'
import json
import sys
from datetime import datetime, timezone

ticket, sha, status = sys.argv[1:4]
payload = {
    "writer": "run-visual-snapshot.sh",
    "ticket": ticket,
    "head_sha": sha,
    "mode": "compare",
    "status": status,
    "at": datetime.now(timezone.utc).isoformat(),
    "pages": [
        {
            "path": "/page.html",
            "diff_artifact": ".polaris/evidence/vr/artifacts/VRG/diff/page.html.json",
        }
    ],
}
with open(f"/tmp/polaris-vr-{ticket}-{sha}.json", "w", encoding="utf-8") as handle:
    json.dump(payload, handle)
PY
}

write_task() {
  local file="$1"
  local frontmatter="$2"
  mkdir -p "$(dirname "$file")"
  cat >"$file" <<EOF
---
title: "Work Order - T1: VR gate selftest (1 pt)"
description: "Fixture task for VR gate selftest."
${frontmatter}
---

# T1: VR gate selftest (1 pt)

> Source: DP-104 | Task: DP-104-T5 | JIRA: N/A | Repo: polaris-framework

## Test Environment

- **Level**: runtime
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: http://127.0.0.1/page.html
- **Env bootstrap command**: N/A
EOF
}

expect_gate_pass() {
  local ticket="$1"
  local task="$2"
  bash "$GATE" --repo "$repo" --ticket "$ticket" --task-md "$task" >/dev/null 2>"$tmpdir/$ticket.err"
}

expect_gate_fail_contains() {
  local ticket="$1"
  local task="$2"
  local needle="$3"
  set +e
  bash "$GATE" --repo "$repo" --ticket "$ticket" --task-md "$task" >"$tmpdir/$ticket.out" 2>"$tmpdir/$ticket.err"
  local rc=$?
  set -e
  if [[ "$rc" -ne 2 ]]; then
    echo "FAIL: expected $ticket gate to exit 2, got $rc" >&2
    cat "$tmpdir/$ticket.err" >&2
    exit 1
  fi
  if ! grep -q "$needle" "$tmpdir/$ticket.err"; then
    echo "FAIL: expected $ticket stderr to contain '$needle'" >&2
    cat "$tmpdir/$ticket.err" >&2
    exit 1
  fi
}

no_vr_task="$tmpdir/tasks/no-vr.md"
vr_task="$tmpdir/tasks/vr.md"
write_task "$no_vr_task" ""
write_task "$vr_task" 'verification:
  visual_regression:
    expected: none_allowed
    pages: ["/page.html"]'

write_verify_evidence "VRG-NOVR"
expect_gate_pass "VRG-NOVR" "$no_vr_task"

write_verify_evidence "VRG-MISSING"
expect_gate_fail_contains "VRG-MISSING" "$vr_task" "No Layer C VR evidence"

write_verify_evidence "VRG-STALE"
write_vr_evidence "VRG-STALE" "0000000000000000000000000000000000000000" "PASS"
expect_gate_fail_contains "VRG-STALE" "$vr_task" "stale Layer C VR evidence"

write_verify_evidence "VRG-BLOCK"
write_vr_evidence "VRG-BLOCK" "$head_sha" "BLOCK"
expect_gate_fail_contains "VRG-BLOCK" "$vr_task" "status must be PASS"

write_verify_evidence "VRG-PASS"
write_vr_evidence "VRG-PASS" "$head_sha" "PASS"
expect_gate_pass "VRG-PASS" "$vr_task"

grep -q 'C — VR (`run-visual-snapshot.sh`)' "$ROOT_DIR/.claude/skills/references/pr-body-builder.md"
grep -q '## VR Diff' "$ROOT_DIR/.claude/skills/references/pr-body-builder.md"

echo "PASS: VR gate selftest"
