#!/usr/bin/env bash
# Purpose: Selftest for scripts/auto-pass-pr-ownership-gate.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$ROOT/scripts/auto-pass-pr-ownership-gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

write_state() {
  local path="$1"
  local draft="$2"
  local publisher="$3"
  local completion="$4"
  local freshness="$5"
  python3 - "$path" "$draft" "$publisher" "$completion" "$freshness" <<'PY'
import json
import sys
from pathlib import Path

path, draft, publisher, completion, freshness = sys.argv[1:6]
payload = {
    "pr_url": "https://github.com/org/repo/pull/123",
    "isDraft": draft == "true",
    "publisher": publisher,
    "engineering_completion_marker": completion,
    "base_freshness": freshness,
}
Path(path).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

expect_pass() {
  local label="$1"
  local file="$2"
  if ! "$GATE" --state-file "$file" >/dev/null; then
    echo "FAIL: $label expected PASS" >&2
    exit 1
  fi
}

expect_fail_marker() {
  local label="$1"
  local marker="$2"
  local file="$3"
  local err="$TMP/$label.err"
  if "$GATE" --state-file "$file" >/dev/null 2>"$err"; then
    echo "FAIL: $label expected failure" >&2
    exit 1
  fi
  if ! grep -Fq "$marker" "$err"; then
    echo "FAIL: $label expected marker $marker" >&2
    cat "$err" >&2
    exit 1
  fi
}

write_state "$TMP/pass.json" false polaris-pr-create.sh PASS fresh
expect_pass "valid ownership payload" "$TMP/pass.json"

python3 - "$TMP/nested-pass.json" <<'PY'
import json, sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps({
    "readiness_state": "mergeable_ready",
    "auto_pass_pr_ownership": {
        "pr_url": "https://github.com/org/repo/pull/124",
        "is_draft": False,
        "provenance": {"writer": "scripts/polaris-pr-create.sh"},
        "completion_gate": {"status": "PASS"},
        "readiness": {"base_freshness": "current"}
    }
}, indent=2) + "\n", encoding="utf-8")
PY
expect_pass "nested ownership payload" "$TMP/nested-pass.json"

write_state "$TMP/draft.json" true polaris-pr-create.sh PASS fresh
expect_fail_marker "draft" "POLARIS_AUTO_PASS_PR_DRAFT_BLOCKED" "$TMP/draft.json"

write_state "$TMP/generic.json" false generic-github-publisher PASS fresh
expect_fail_marker "generic-publisher" "POLARIS_AUTO_PASS_PR_OWNERSHIP_BLOCKED" "$TMP/generic.json"

write_state "$TMP/no-completion.json" false polaris-pr-create.sh IN_PROGRESS fresh
expect_fail_marker "missing-completion" "POLARIS_AUTO_PASS_PR_OWNERSHIP_BLOCKED" "$TMP/no-completion.json"

write_state "$TMP/stale-base.json" false polaris-pr-create.sh PASS stale
expect_fail_marker "stale-base" "POLARIS_AUTO_PASS_PR_OWNERSHIP_BLOCKED" "$TMP/stale-base.json"

echo "PASS: auto-pass PR ownership gate selftest"
