#!/usr/bin/env bash
# Selftest for annotate-review-candidates.py.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
annotator="$script_dir/annotate-review-candidates.py"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mapping="$tmp/mapping.json"
candidates="$tmp/candidates.json"
out="$tmp/annotated.json"

cat > "$mapping" <<'JSON'
{
  "https://github.com/acme/acme-api/pull/10": {"thread_ts": "1776130982.981829", "root_ticket_key": "GT-493"},
  "https://github.com/acme/acme-web/pull/20": {"thread_ts": "1776130982.981829", "root_ticket_key": "GT-493"},
  "https://github.com/acme/acme-ios/pull/30": {"thread_ts": "1776130982.981829", "root_ticket_key": "GT-493"}
}
JSON

cat > "$candidates" <<'JSON'
[
  {
    "repo": "acme-web",
    "number": 20,
    "title": "KB2CW-3854 web variant",
    "url": "https://github.com/acme/acme-web/pull/20",
    "author": "alice",
    "changed_files": 2,
    "additions": 300,
    "deletions": 20,
    "files": [{"filename": "src/web.ts", "additions": 300, "deletions": 20}]
  },
  {
    "repo": "acme-api",
    "number": 10,
    "title": "KB2CW-3857 api variant",
    "url": "https://github.com/acme/acme-api/pull/10",
    "author": "bob",
    "changed_files": 2,
    "additions": 280,
    "deletions": 15,
    "files": [{"filename": "src/api.ts", "additions": 280, "deletions": 15}]
  },
  {
    "repo": "acme-ios",
    "number": 30,
    "title": "KB2CW-3859 ios variant",
    "url": "https://github.com/acme/acme-ios/pull/30",
    "author": "cara",
    "changed_files": 2,
    "additions": 210,
    "deletions": 12,
    "files": [{"filename": "Sources/App.swift", "additions": 210, "deletions": 12}]
  },
  {
    "repo": "acme-web",
    "number": 40,
    "title": "favicon refresh",
    "url": "https://github.com/acme/acme-web/pull/40",
    "author": "drew",
    "changed_files": 1,
    "additions": 1,
    "deletions": 1,
    "files": [{"filename": "public/favicon.ico", "additions": 1, "deletions": 1}]
  },
  {
    "repo": "acme-web",
    "number": 50,
    "title": "checkout flow refactor",
    "url": "https://github.com/acme/acme-web/pull/50",
    "author": "erin",
    "changed_files": 4,
    "additions": 500,
    "deletions": 200,
    "files": [{"filename": "src/checkout.ts", "additions": 500, "deletions": 200}]
  }
]
JSON

"$annotator" --offline --mapping "$mapping" < "$candidates" > "$out"

python3 - "$out" <<'PY'
import json
import sys
from pathlib import Path

items = json.loads(Path(sys.argv[1]).read_text())
by_number = {item["number"]: item for item in items}

assert by_number[10]["cluster_role"] == "cluster_lead", by_number[10]
assert by_number[10]["model_tier"] == "standard_coding", by_number[10]
assert by_number[20]["cluster_role"] == "cluster_sibling", by_number[20]
assert by_number[20]["model_tier"] == "small_fast", by_number[20]
assert by_number[30]["cluster_role"] == "cluster_sibling", by_number[30]
assert by_number[30]["cluster_size"] == 3, by_number[30]
assert by_number[30]["cluster_lead_url"] == "https://github.com/acme/acme-api/pull/10", by_number[30]
assert by_number[30]["cluster_key"] == "1776130982.981829:GT-493", by_number[30]
assert by_number[30]["root_ticket_key"] == "GT-493", by_number[30]
assert by_number[40]["cluster_role"] == "standalone", by_number[40]
assert by_number[40]["model_tier"] == "small_fast", by_number[40]
assert by_number[50]["model_tier"] == "standard_coding", by_number[50]
assert by_number[50]["cluster_key"] == "", by_number[50]
PY

echo "annotate-review-candidates selftest: PASS"
