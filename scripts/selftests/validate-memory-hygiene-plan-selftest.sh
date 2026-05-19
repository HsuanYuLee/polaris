#!/usr/bin/env bash
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

invalid_nested="$TMP/invalid-nested.json"
cat >"$invalid_nested" <<'JSON'
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

bash "$VALIDATOR" --input "$valid_legacy" >/dev/null
bash "$VALIDATOR" --input "$valid_additive" >/dev/null
if bash "$VALIDATOR" --input "$invalid_nested" >/tmp/invalid-nested.out 2>&1; then
  echo "expected invalid nested fixture to fail" >&2
  exit 1
fi
grep -q "nested_frontmatter" /tmp/invalid-nested.out
if bash "$VALIDATOR" --input "$invalid_pinned" >/tmp/invalid-pinned.out 2>&1; then
  echo "expected invalid pinned fixture to fail" >&2
  exit 1
fi
grep -q "missing_pinned_reason" /tmp/invalid-pinned.out

cat "$valid_additive" | bash "$VALIDATOR" >/dev/null
bash "$VALIDATOR" --input "$valid_additive" --format json | grep -q '"passed": true'

echo "PASS: validate-memory-hygiene-plan selftest"
