#!/usr/bin/env bash
# Selftest for validate-memory-hygiene-plan.sh.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validator="$script_dir/validate-memory-hygiene-plan.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

assert_pass() {
  local label="$1"
  shift
  if ! "$@" >/tmp/validate-memory-plan.out 2>/tmp/validate-memory-plan.err; then
    echo "ASSERT FAIL [$label]: expected pass" >&2
    cat /tmp/validate-memory-plan.out >&2 || true
    cat /tmp/validate-memory-plan.err >&2 || true
    exit 1
  fi
}

assert_fail() {
  local label="$1"
  shift
  if "$@" >/tmp/validate-memory-plan.out 2>/tmp/validate-memory-plan.err; then
    echo "ASSERT FAIL [$label]: expected fail" >&2
    cat /tmp/validate-memory-plan.out >&2 || true
    exit 1
  fi
}

good="$tmp/good.json"
cat > "$good" <<'EOF'
{
  "date": "2026-05-09",
  "hot_days": 30,
  "warm_days": 90,
  "trigger_threshold": 5,
  "classifications": [
    {
      "file": "fresh-memory.md",
      "tier": "hot",
      "topic": null,
      "reason": "last_triggered 2d ago",
      "last_triggered": "2026-05-07",
      "mtime": "2026-05-07",
      "trigger_count": 1,
      "pinned": false,
      "archived_in_index": false
    },
    {
      "file": "warm-memory.md",
      "tier": "warm",
      "topic": "polaris-framework",
      "reason": "warm (40d since last_triggered), topic=polaris-framework",
      "last_triggered": "2026-03-30",
      "mtime": "2026-03-30",
      "trigger_count": 0,
      "pinned": false,
      "archived_in_index": false
    },
    {
      "file": "cold-memory.md",
      "tier": "cold",
      "topic": null,
      "reason": "stale (180d since last_triggered)",
      "last_triggered": "2025-11-10",
      "mtime": "2025-11-10",
      "trigger_count": 0,
      "pinned": false,
      "archived_in_index": true
    }
  ]
}
EOF

assert_pass "valid-plan" "$validator" --input "$good"

dup="$tmp/dup.json"
python3 - <<'PY' "$good" "$dup"
import json, sys
src, dst = sys.argv[1:]
data = json.load(open(src))
data["classifications"].append(dict(data["classifications"][0]))
json.dump(data, open(dst, "w"))
PY
assert_fail "duplicate-file" "$validator" --input "$dup"
grep -q "duplicate_file" /tmp/validate-memory-plan.out

bad_tier="$tmp/bad-tier.json"
python3 - <<'PY' "$good" "$bad_tier"
import json, sys
src, dst = sys.argv[1:]
data = json.load(open(src))
data["classifications"][0]["tier"] = "lava"
json.dump(data, open(dst, "w"))
PY
assert_fail "invalid-tier" "$validator" --input "$bad_tier"
grep -q "invalid_tier" /tmp/validate-memory-plan.out

bad_pinned="$tmp/bad-pinned.json"
python3 - <<'PY' "$good" "$bad_pinned"
import json, sys
src, dst = sys.argv[1:]
data = json.load(open(src))
data["classifications"][2]["pinned"] = True
json.dump(data, open(dst, "w"))
PY
assert_fail "pinned-not-hot" "$validator" --input "$bad_pinned"
grep -q "pinned_not_hot" /tmp/validate-memory-plan.out

bad_topic="$tmp/bad-topic.json"
python3 - <<'PY' "$good" "$bad_topic"
import json, sys
src, dst = sys.argv[1:]
data = json.load(open(src))
data["classifications"][2]["topic"] = "should-not-be-here"
json.dump(data, open(dst, "w"))
PY
assert_fail "non-warm-topic" "$validator" --input "$bad_topic"
grep -q "non_warm_topic_present" /tmp/validate-memory-plan.out

echo "validate-memory-hygiene-plan selftest: PASS"
