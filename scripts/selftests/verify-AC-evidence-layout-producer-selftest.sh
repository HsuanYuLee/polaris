#!/usr/bin/env bash
# verify-AC-evidence-layout-producer-selftest.sh — DP-230 T12 / D31 / AC31.
#
# Verifies that verify-AC evidence layout writes are gated by the canonical
# producer registry contract:
#
#   AC31  scripts/write-producer-owned-artifact.sh --producer-token
#         verify-AC:evidence-layout writes verification/V*/verify-report.md,
#         links.json, publication-manifest.json successfully and dispatches
#         the verify evidence layout validator on the containing V* dir.
#   AC31  no-direct-evidence-write.sh denies a Write to verification/V*/*
#         when no POLARIS_PRODUCER token is set, emitting stderr token
#         POLARIS_EVIDENCE_PRODUCER_TOKEN_REQUIRED:<path>.
#   AC31  no-direct-evidence-write.sh denies a Write to verification/V*/* with
#         a token belonging to a different producer (e.g. auto-pass:source),
#         also emitting POLARIS_EVIDENCE_PRODUCER_TOKEN_REQUIRED.
#   AC31  no-direct-evidence-write.sh accepts a Write to verification/V*/*
#         when POLARIS_PRODUCER=verify-AC:evidence-layout.
#
# Exit 0 → PASS; non-zero exit prints diagnostic.

set -euo pipefail

if ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)" && [[ -n "$ROOT_DIR" ]]; then
  :
else
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
HOOK="$ROOT_DIR/.claude/hooks/no-direct-evidence-write.sh"
WRITER="$ROOT_DIR/scripts/write-producer-owned-artifact.sh"
PRODUCERS_JSON="$ROOT_DIR/scripts/lib/evidence-producers.json"
WORKDIR="$(mktemp -d -t dp230-t12-verify-ac.XXXXXX)"
trap 'rm -rf "$WORKDIR"; rm -rf "$ROOT_DIR/docs-manager/src/content/docs/specs/design-plans/__dp230_t12_fixture_verify_ac__"' EXIT

if [[ ! -x "$HOOK" ]]; then
  echo "FAIL: hook not executable: $HOOK" >&2
  exit 1
fi
if [[ ! -x "$WRITER" ]]; then
  echo "FAIL: writer not executable: $WRITER" >&2
  exit 1
fi
if [[ ! -f "$PRODUCERS_JSON" ]]; then
  echo "FAIL: producers table missing: $PRODUCERS_JSON" >&2
  exit 1
fi

# Contract sanity check: producer_tokens[] must include verify-AC:evidence-layout
python3 - <<PY
import json, sys
data = json.load(open("$PRODUCERS_JSON"))
tokens = set()
for p in data.get("producers", []):
    for t in (p.get("producer_tokens") or []):
        if t in tokens:
            print(f"FAIL: duplicate token in producer_tokens[]: {t}", file=sys.stderr)
            sys.exit(2)
        tokens.add(t)
if "verify-AC:evidence-layout" not in tokens:
    print("FAIL: verify-AC:evidence-layout token missing from producer_tokens[]", file=sys.stderr)
    sys.exit(2)
PY

run_hook() {
  local payload="$1"
  local expected_exit="$2"
  local label="$3"
  local env_var="${4:-}"
  local out_file="$WORKDIR/${label}.out"
  set +e
  if [[ -n "$env_var" ]]; then
    env $env_var bash -c 'printf "%s" "$1" | "$2" >"$3" 2>&1' _ "$payload" "$HOOK" "$out_file"
  else
    printf '%s' "$payload" | "$HOOK" >"$out_file" 2>&1
  fi
  local rc=$?
  set -e
  if [[ "$rc" -ne "$expected_exit" ]]; then
    echo "FAIL ($label): expected exit $expected_exit, got $rc" >&2
    cat "$out_file" >&2
    exit 1
  fi
}

fixture_root="$ROOT_DIR/docs-manager/src/content/docs/specs/design-plans/__dp230_t12_fixture_verify_ac__/verification/V1"
report_path="$fixture_root/verify-report.md"
links_path="$fixture_root/links.json"
manifest_path="$fixture_root/publication-manifest.json"

# AC31 hook NEG (no token): writing verification/V*/links.json must fail-stop
# with POLARIS_EVIDENCE_PRODUCER_TOKEN_REQUIRED.
payload_neg1=$(python3 -c "
import json
print(json.dumps({
  'tool_name': 'Write',
  'tool_input': {
    'file_path': '$links_path',
    'content': '[]'
  }
}))
")
run_hook "$payload_neg1" 2 ac31-neg-no-token
grep -q 'POLARIS_EVIDENCE_PRODUCER_TOKEN_REQUIRED' "$WORKDIR/ac31-neg-no-token.out"
grep -q 'BLOCKED' "$WORKDIR/ac31-neg-no-token.out"

# AC31 hook NEG (wrong token): auto-pass:source token writing verification/V*/*.json
# also fails with POLARIS_EVIDENCE_PRODUCER_TOKEN_REQUIRED.
payload_neg2=$(python3 -c "
import json
print(json.dumps({
  'tool_name': 'Write',
  'tool_input': {
    'file_path': '$manifest_path',
    'content': '{}'
  }
}))
")
run_hook "$payload_neg2" 2 ac31-neg-wrong-token "POLARIS_PRODUCER=auto-pass:source"
grep -q 'POLARIS_EVIDENCE_PRODUCER_TOKEN_REQUIRED' "$WORKDIR/ac31-neg-wrong-token.out"

# AC31 hook POSITIVE (correct token): verify-AC:evidence-layout token writing
# a verification/V*/links.json is accepted (bypass).
payload_pos=$(python3 -c "
import json
print(json.dumps({
  'tool_name': 'Write',
  'tool_input': {
    'file_path': '$links_path',
    'content': '[]'
  }
}))
")
run_hook "$payload_pos" 0 ac31-pos-token-bypass "POLARIS_PRODUCER=verify-AC:evidence-layout"
grep -q 'producer=verify-AC:evidence-layout' "$WORKDIR/ac31-pos-token-bypass.out"

# AC31 writer happy path: build a valid layout in stages via the canonical writer.
mkdir -p "$fixture_root/assets/raw" "$fixture_root/assets/images" \
         "$fixture_root/assets/screenshots" "$fixture_root/assets/videos" \
         "$fixture_root/assets/files"

# verify-report.md body
report_body="$WORKDIR/verify-report.md"
cat >"$report_body" <<'MD'
---
title: "Fixture verify-report"
description: "DP-230 T12 selftest verify-AC layout fixture"
draft: true
sidebar:
  hidden: true
---

# Verify Report Fixture
PASS
MD

# links.json body
links_body="$WORKDIR/links.json"
printf '[]' >"$links_body"

# publication-manifest.json body
manifest_body="$WORKDIR/publication-manifest.json"
cat >"$manifest_body" <<'JSON'
{
  "schema_version": 1,
  "artifacts": []
}
JSON

# Write all three artifacts via the canonical writer with the new token.
set +e
"$WRITER" \
  --producer-token verify-AC:evidence-layout \
  --path "$report_path" \
  --body-file "$report_body" >"$WORKDIR/writer-report.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL (writer verify-report.md): expected exit 0, got $rc" >&2
  cat "$WORKDIR/writer-report.out" >&2
  exit 1
fi

set +e
"$WRITER" \
  --producer-token verify-AC:evidence-layout \
  --path "$links_path" \
  --body-file "$links_body" >"$WORKDIR/writer-links.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL (writer links.json): expected exit 0, got $rc" >&2
  cat "$WORKDIR/writer-links.out" >&2
  exit 1
fi

set +e
"$WRITER" \
  --producer-token verify-AC:evidence-layout \
  --path "$manifest_path" \
  --body-file "$manifest_body" >"$WORKDIR/writer-manifest.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL (writer publication-manifest.json): expected exit 0, got $rc" >&2
  cat "$WORKDIR/writer-manifest.out" >&2
  exit 1
fi
grep -q 'artifact_kind=verify_evidence_layout' "$WORKDIR/writer-manifest.out" || {
  echo "FAIL (writer): expected artifact_kind=verify_evidence_layout in stderr trace" >&2
  cat "$WORKDIR/writer-manifest.out" >&2
  exit 1
}

# Sanity: layout validator passes on the assembled directory.
if ! "$ROOT_DIR/scripts/validate-verify-evidence-layout.sh" "$fixture_root" >"$WORKDIR/layout.out" 2>&1; then
  echo "FAIL: layout validator did not pass on fixture" >&2
  cat "$WORKDIR/layout.out" >&2
  exit 1
fi

# AC-NEG12 carry: existing token (auto-pass:source) still resolves to its
# canonical producer entry. The ledger validator may reject a minimal fixture
# payload — that is acceptable here; the AC-NEG12 contract is purely about
# producer token resolution staying intact post D31/D32 expansion. So write
# the body to a path OUTSIDE that producer's path_globs[] and assert the
# writer emits "not covered by producer" rather than "not registered".
oos_ledger_path="$WORKDIR/some-non-ledger-path.json"
printf '{}' >"$WORKDIR/dummy.json"
set +e
"$WRITER" \
  --producer-token auto-pass:source \
  --path "$oos_ledger_path" \
  --body-file "$WORKDIR/dummy.json" >"$WORKDIR/writer-ledger.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL (AC-NEG12 auto-pass:source token resolution): expected exit 2 with path glob diagnostic, got $rc" >&2
  cat "$WORKDIR/writer-ledger.out" >&2
  exit 1
fi
if ! grep -q 'not covered by producer' "$WORKDIR/writer-ledger.out"; then
  echo "FAIL (AC-NEG12): existing token auto-pass:source did not resolve (got 'not registered' or unknown)" >&2
  cat "$WORKDIR/writer-ledger.out" >&2
  exit 1
fi
# breakdown:initial-create token uniqueness check.
set +e
"$WRITER" \
  --producer-token breakdown:initial-create \
  --path "$WORKDIR/oos-breakdown.md" \
  --body-file "$WORKDIR/dummy.json" >"$WORKDIR/writer-breakdown.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL (AC-NEG12 breakdown:initial-create): expected exit 2" >&2
  cat "$WORKDIR/writer-breakdown.out" >&2
  exit 1
fi
if ! grep -q 'not covered by producer' "$WORKDIR/writer-breakdown.out"; then
  echo "FAIL (AC-NEG12 breakdown:initial-create resolution broke)" >&2
  cat "$WORKDIR/writer-breakdown.out" >&2
  exit 1
fi

echo "PASS"
