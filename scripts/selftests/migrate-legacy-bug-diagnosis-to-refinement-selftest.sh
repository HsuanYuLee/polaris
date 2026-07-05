#!/usr/bin/env bash
# Verify legacy Bug RCA comments migrate into refinement Bug source artifacts safely.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/migrate-legacy-bug-diagnosis-to-refinement.py"
VALIDATE="$ROOT/scripts/validate-refinement-json.sh"
TMP="$(mktemp -d -t migrate-legacy-bug.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

cat >"$TMP/well-formed.md" <<'MD'
[ROOT_CAUSE]
The checkout step reads a stale field and hides the payment button.

[IMPACT]
Checkout users cannot complete payment for selected products.

[PROPOSED_FIX]
Read the canonical field and keep legacy fallback.

[SOURCE_PR]
https://github.example.local/pull/123

[SEVERITY]
high

[REGRESSION]
true

[REPRODUCTION_STEPS]
1. Open checkout
2. Select affected product
3. Observe missing payment button
MD

python3 "$SCRIPT" --ticket BUG-4190 --comment-file "$TMP/well-formed.md" --target-dir "$TMP/dry-run" >"$TMP/dry-run.out"
[[ ! -e "$TMP/dry-run/refinement.json" ]] || fail "dry-run wrote refinement.json"
grep -q "dry-run only" "$TMP/dry-run.out"

python3 "$SCRIPT" --ticket BUG-4190 --comment-file "$TMP/well-formed.md" --target-dir "$TMP/apply" --apply >"$TMP/apply.out"
[[ -f "$TMP/apply/refinement.json" ]] || fail "apply did not write refinement.json"
[[ -f "$TMP/apply/refinement.md" ]] || fail "apply did not write refinement.md"
bash "$VALIDATE" "$TMP/apply/refinement.json"
python3 - "$TMP/apply/refinement.json" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert data["source"]["type"] == "bug"
assert data["source"]["jira_key"] == "BUG-4190"
assert data["source_pr"].startswith("https://")
assert data["severity"] == "high"
assert data["regression"] is True
assert data["migration"]["needs_human_review"] is False
assert data["tasks"][0]["id"] == "BUG-4190-T1"
PY

cat >"$TMP/partial.md" <<'MD'
[ROOT_CAUSE]
The selected date is converted twice.
MD
python3 "$SCRIPT" --ticket BUG-4191 --comment-file "$TMP/partial.md" --target-dir "$TMP/partial" --apply >"$TMP/partial.out"
grep -q "partial legacy RCA comment" "$TMP/partial.out"
bash "$VALIDATE" "$TMP/partial/refinement.json"
python3 - "$TMP/partial/refinement.json" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert data["migration"]["needs_human_review"] is True
assert "IMPACT" in data["migration"]["missing_fields"]
assert data["reproduction_steps"]
PY

cat >"$TMP/malformed.md" <<'MD'
[IMPACT]
Only impact exists.
MD
python3 "$SCRIPT" --ticket BUG-4192 --comment-file "$TMP/malformed.md" --target-dir "$TMP/malformed" --apply >"$TMP/malformed.out"
grep -q "malformed RCA comment" "$TMP/malformed.out"
[[ ! -e "$TMP/malformed/refinement.json" ]] || fail "malformed comment wrote refinement.json"

mkdir -p "$TMP/existing"
printf 'original\n' >"$TMP/existing/refinement.json"
python3 "$SCRIPT" --ticket BUG-4193 --comment-file "$TMP/well-formed.md" --target-dir "$TMP/existing" --apply >"$TMP/existing.out"
grep -q "target refinement artifact exists" "$TMP/existing.out"
grep -qx "original" "$TMP/existing/refinement.json"

echo "PASS: migrate legacy Bug diagnosis to refinement selftest"
