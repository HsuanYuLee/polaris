#!/usr/bin/env bash
# Purpose: DP-231 T9 regression — engineering PR readiness/completion cannot
#          bypass task lineage, resolver lock, baseline, boundary, or completion.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$ROOT/scripts/auto-pass-pr-ownership-gate.sh"
DOC="$ROOT/.claude/skills/references/engineering-entry-resolution.md"
TMP="$(mktemp -d -t engineering-no-bypass-pr.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

write_state() {
  local path="$1"
  local omit="$2"
  python3 - "$path" "$omit" <<'PY'
import json
import sys
from pathlib import Path

path, omit = sys.argv[1:3]
payload = {
    "engineering_no_bypass_required": True,
    "pr_url": "https://github.com/org/repo/pull/456",
    "isDraft": False,
    "publisher": "polaris-pr-create.sh",
    "engineering_completion_marker": True,
    "base_freshness": "fresh",
    "task_md_lineage": True,
    "resolver_lock": {"status": "PASS"},
    "readiness_pack_snapshot": {"present": True},
    "skill_boundary_marker": "PASS",
}
if omit != "__none__":
    payload.pop(omit)
Path(path).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

expect_pass() {
  local file="$1"
  "$GATE" --state-file "$file" >/dev/null
}

expect_block() {
  local label="$1"
  local file="$2"
  if "$GATE" --state-file "$file" >/dev/null 2>"$TMP/$label.err"; then
    echo "FAIL: $label unexpectedly passed" >&2
    exit 1
  fi
  grep -Fq "POLARIS_AUTO_PASS_PR_OWNERSHIP_BLOCKED" "$TMP/$label.err" || {
    echo "FAIL: $label missing ownership marker" >&2
    cat "$TMP/$label.err" >&2
    exit 1
  }
}

write_state "$TMP/pass.json" "__none__"
expect_pass "$TMP/pass.json"

for field in task_md_lineage resolver_lock readiness_pack_snapshot skill_boundary_marker engineering_completion_marker; do
  write_state "$TMP/missing-$field.json" "$field"
  expect_block "missing-$field" "$TMP/missing-$field.json"
done

grep -Fq "No-Bypass Contract" "$DOC"
grep -Fq "resolver lock" "$DOC"
grep -Fq "baseline snapshot" "$DOC"
grep -Fq "boundary marker" "$DOC"
grep -Fq "POLARIS_PR_WORKFLOW=1" "$DOC"

echo "PASS: engineering no-bypass PR selftest"
