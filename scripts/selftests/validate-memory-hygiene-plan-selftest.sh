#!/usr/bin/env bash
# Purpose: selftest for validate-memory-hygiene-plan.sh — pins the DP-277 T2
#   transparent pipe gate contract (PASS -> validated plan JSON on stdout +
#   verdict on stderr; FAIL -> empty stdout + non-zero exit) and the
#   nested_frontmatter warnings-only / missing_pinned_reason fixtures.
# Inputs:  none (builds plan fixtures in a tmpdir).
# Outputs: "PASS: validate-memory-hygiene-plan selftest" on stdout; non-zero
#   exit on any contract violation.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-memory-hygiene-plan.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

valid_legacy="$TMP/valid-legacy.json"
cat >"$valid_legacy" <<'JSON'
{
  "date": "2026-05-19",
  "classifications": [
    {
      "file": "example.md",
      "tier": "warm",
      "topic": null,
      "reason": "fixture",
      "trigger_count": 0,
      "pinned": false,
      "archived_in_index": false
    }
  ]
}
JSON

valid_additive="$TMP/valid-additive.json"
cat >"$valid_additive" <<'JSON'
{
  "date": "2026-05-19",
  "summary": {
    "stale_snapshot": 0,
    "graduated_feedback": 0,
    "nested_frontmatter": 0,
    "fresh_write_hot": 1,
    "created_backfill": 1
  },
  "hot_order": ["fresh.md"],
  "classifications": [
    {
      "file": "fresh.md",
      "tier": "hot",
      "topic": null,
      "reason": "fresh-write",
      "last_triggered": null,
      "mtime": "2026-05-19",
      "trigger_count": 0,
      "pinned": false,
      "pinned_reason": null,
      "archived_in_index": false,
      "flags": {
        "stale_snapshot": false,
        "graduated_feedback": false,
        "nested_frontmatter": false,
        "fresh_write_hot": true,
        "grace_baseline": "created"
      },
      "created_backfill": "2026-05-19"
    }
  ]
}
JSON

# DP-213: nested_frontmatter is warnings-only (not a hard issue) — the validator
# PASSES this plan but must surface a nested_frontmatter warning.
warn_nested="$TMP/warn-nested.json"
cat >"$warn_nested" <<'JSON'
{
  "date": "2026-05-19",
  "classifications": [
    {
      "file": "nested.md",
      "tier": "hot",
      "topic": null,
      "reason": "nested",
      "trigger_count": 1,
      "pinned": false,
      "archived_in_index": false,
      "flags": {
        "stale_snapshot": false,
        "graduated_feedback": false,
        "nested_frontmatter": true,
        "fresh_write_hot": false,
        "grace_baseline": "created"
      }
    }
  ]
}
JSON

invalid_pinned="$TMP/invalid-pinned.json"
cat >"$invalid_pinned" <<'JSON'
{
  "date": "2026-05-19",
  "classifications": [
    {
      "file": "pinned.md",
      "tier": "hot",
      "topic": null,
      "reason": "pinned",
      "trigger_count": 0,
      "pinned": true,
      "archived_in_index": false
    }
  ]
}
JSON

# DP-277 T2 transparent pipe gate: on PASS the validator re-emits the validated
# plan JSON verbatim on stdout and writes the verdict to stderr; on FAIL stdout
# is empty and exit is non-zero. These assertions pin that contract.
bash "$VALIDATOR" --input "$valid_legacy" >/dev/null
bash "$VALIDATOR" --input "$valid_additive" >"$TMP/additive-stdout.json" 2>/dev/null
# AC6: PASS stdout must equal the input plan byte-for-byte (transparent pass-through).
if ! diff -q "$valid_additive" "$TMP/additive-stdout.json" >/dev/null; then
  echo "FAIL: PASS stdout did not re-emit the input plan verbatim (AC6 transparent gate)" >&2
  exit 1
fi

# nested_frontmatter is warnings-only (DP-213): validator PASSES (exit 0) but the
# verdict on stderr must carry the nested_frontmatter warning.
bash "$VALIDATOR" --input "$warn_nested" >/dev/null 2>"$TMP/warn-nested.err"
grep -q "nested_frontmatter" "$TMP/warn-nested.err"

# missing_pinned_reason is a hard issue: validator FAILS, stdout is empty, the
# issue detail is reported on stderr.
if bash "$VALIDATOR" --input "$invalid_pinned" >"$TMP/pinned-stdout" 2>"$TMP/pinned-stderr"; then
  echo "expected invalid pinned fixture to fail" >&2
  exit 1
fi
if [[ -s "$TMP/pinned-stdout" ]]; then
  echo "FAIL: validator must not emit plan JSON on stdout when the plan is invalid (AC6)" >&2
  exit 1
fi
grep -q "missing_pinned_reason" "$TMP/pinned-stderr"

# stdin form is also a transparent pass-through.
cat "$valid_additive" | bash "$VALIDATOR" >/dev/null
# --format json selects the stderr verdict representation; stdout stays reserved
# for the plan pass-through.
bash "$VALIDATOR" --input "$valid_additive" --format json >/dev/null 2>"$TMP/additive-verdict.json"
grep -q '"passed": true' "$TMP/additive-verdict.json"

echo "PASS: validate-memory-hygiene-plan selftest"
