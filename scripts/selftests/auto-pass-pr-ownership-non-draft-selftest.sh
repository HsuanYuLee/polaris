#!/usr/bin/env bash
# Purpose: Regression test that draft PRs cannot satisfy auto-pass ownership.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$ROOT/scripts/auto-pass-pr-ownership-gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

write_state() {
  local path="$1"
  local draft="$2"
  python3 - "$path" "$draft" <<'PY'
import json
import sys
from pathlib import Path

path, draft = sys.argv[1:3]
Path(path).write_text(json.dumps({
    "pr_url": "https://github.com/org/repo/pull/321",
    "isDraft": draft == "true",
    "publisher": "polaris-pr-create.sh",
    "engineering_completion_marker": True,
    "base_freshness": "fresh"
}, indent=2) + "\n", encoding="utf-8")
PY
}

write_state "$TMP/non-draft.json" false
"$GATE" --state-file "$TMP/non-draft.json" >/dev/null

write_state "$TMP/draft.json" true
if POLARIS_AUTO_PASS_PR_OWNERSHIP_BYPASS=1 "$GATE" --state-file "$TMP/draft.json" >/dev/null 2>"$TMP/draft.err"; then
  echo "FAIL: draft PR passed even with bypass-looking env set" >&2
  exit 1
fi
grep -Fq "POLARIS_AUTO_PASS_PR_DRAFT_BLOCKED" "$TMP/draft.err" || {
  echo "FAIL: missing draft marker" >&2
  cat "$TMP/draft.err" >&2
  exit 1
}

python3 - "$TMP/missing-draft-field.json" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps({
    "pr_url": "https://github.com/org/repo/pull/322",
    "publisher": "polaris-pr-create.sh",
    "engineering_completion_marker": True,
    "base_freshness": "fresh"
}, indent=2) + "\n", encoding="utf-8")
PY
if "$GATE" --state-file "$TMP/missing-draft-field.json" >/dev/null 2>"$TMP/missing.err"; then
  echo "FAIL: missing isDraft/is_draft field passed" >&2
  exit 1
fi
grep -Fq "POLARIS_AUTO_PASS_PR_OWNERSHIP_BLOCKED" "$TMP/missing.err" || {
  echo "FAIL: missing ownership marker for absent draft field" >&2
  cat "$TMP/missing.err" >&2
  exit 1
}

echo "PASS: auto-pass PR non-draft ownership selftest"
