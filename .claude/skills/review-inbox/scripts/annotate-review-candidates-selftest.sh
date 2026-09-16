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
  "https://github.com/acme/acme-api/pull/10": {"thread_ts": "1776130982.981829", "root_ticket_key": "DEMO-493"},
  "https://github.com/acme/acme-web/pull/20": {"thread_ts": "1776130982.981829", "root_ticket_key": "DEMO-493"},
  "https://github.com/acme/acme-ios/pull/30": {"thread_ts": "1776130982.981829", "root_ticket_key": "DEMO-493"},
  "https://github.com/acme/acme-api/pull/60": {"thread_ts": "1777000000.000000", "root_topic_key": "topic:jsbridgeutils-platform-case-insensitive"},
  "https://github.com/acme/acme-web/pull/70": {"thread_ts": "1777000000.000000", "root_topic_key": "topic:jsbridgeutils-platform-case-insensitive"},
  "https://github.com/acme/acme-ios/pull/80": {"thread_ts": "1777000000.000000", "root_topic_key": "topic:jsbridgeutils-platform-case-insensitive"},
  "https://github.com/acme/acme-web/pull/100": {"thread_ts": "1778000000.000000", "root_ticket_key": "DEMO-900"},
  "https://github.com/acme/acme-web/pull/101": {"thread_ts": "1778000000.000000", "root_ticket_key": "DEMO-900"},
  "https://github.com/acme/acme-web/pull/102": {"thread_ts": "1778000000.000000", "root_ticket_key": "DEMO-900"},
  "https://github.com/acme/acme-api/pull/200": {"thread_ts": "1779000000.000000", "root_ticket_key": "DEMO-901"},
  "https://github.com/acme/acme-api/pull/201": {"thread_ts": "1779000000.000000", "root_ticket_key": "DEMO-901"},
  "https://github.com/acme/acme-api/pull/202": {"thread_ts": "1779000000.000000", "root_ticket_key": "DEMO-901"}
}
JSON

cat > "$candidates" <<'JSON'
[
  {
    "repo": "acme-web",
    "number": 20,
    "title": "APP-3854 web variant",
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
    "title": "APP-3857 api variant",
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
    "title": "APP-3859 ios variant",
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
  },
  {
    "repo": "acme-web",
    "number": 70,
    "title": "APP-3983 JsBridgeUtils case insensitive web",
    "url": "https://github.com/acme/acme-web/pull/70",
    "author": "fran",
    "changed_files": 2,
    "additions": 40,
    "deletions": 2,
    "files": [{"filename": "src/js-bridge.ts", "additions": 40, "deletions": 2}]
  },
  {
    "repo": "acme-api",
    "number": 60,
    "title": "APP-3984 JsBridgeUtils case insensitive api",
    "url": "https://github.com/acme/acme-api/pull/60",
    "author": "fran",
    "changed_files": 2,
    "additions": 45,
    "deletions": 2,
    "files": [{"filename": "src/js-bridge.ts", "additions": 45, "deletions": 2}]
  },
  {
    "repo": "acme-ios",
    "number": 80,
    "title": "APP-3985 JsBridgeUtils case insensitive ios",
    "url": "https://github.com/acme/acme-ios/pull/80",
    "author": "fran",
    "changed_files": 2,
    "additions": 35,
    "deletions": 2,
    "files": [{"filename": "Sources/JsBridge.swift", "additions": 35, "deletions": 2}]
  },
  {
    "repo": "acme-web",
    "number": 100,
    "title": "DEMO-900 PR-1 建護欄",
    "url": "https://github.com/acme/acme-web/pull/100",
    "author": "gale",
    "base_ref": "main",
    "head_ref": "feat/demo-900-guardrail",
    "changed_files": 1,
    "additions": 120,
    "deletions": 4,
    "files": [{"filename": "src/guard.ts", "additions": 120, "deletions": 4, "hunks": [[10, 30]]}]
  },
  {
    "repo": "acme-web",
    "number": 101,
    "title": "DEMO-900 PR-2 踩在護欄上",
    "url": "https://github.com/acme/acme-web/pull/101",
    "author": "gale",
    "base_ref": "feat/demo-900-guardrail",
    "head_ref": "feat/demo-900-step-2",
    "changed_files": 12,
    "additions": 3155,
    "deletions": 60,
    "files": [{"filename": "src/guard.ts", "additions": 3155, "deletions": 60, "hunks": [[10, 30]]}]
  },
  {
    "repo": "acme-web",
    "number": 102,
    "title": "DEMO-900 PR-3 再疊一層",
    "url": "https://github.com/acme/acme-web/pull/102",
    "author": "gale",
    "base_ref": "feat/demo-900-step-2",
    "head_ref": "feat/demo-900-step-3",
    "changed_files": 20,
    "additions": 6578,
    "deletions": 120,
    "files": [{"filename": "src/guard.ts", "additions": 6578, "deletions": 120, "hunks": [[10, 30]]}]
  },
  {
    "repo": "acme-api",
    "number": 200,
    "title": "DEMO-901 同一段的第一顆",
    "url": "https://github.com/acme/acme-api/pull/200",
    "author": "hana",
    "base_ref": "main",
    "head_ref": "feat/demo-901-a",
    "changed_files": 1,
    "additions": 80,
    "deletions": 10,
    "files": [{"filename": "src/shared.ts", "additions": 80, "deletions": 10, "hunks": [[40, 60]]}]
  },
  {
    "repo": "acme-api",
    "number": 201,
    "title": "DEMO-901 同一段的第二顆",
    "url": "https://github.com/acme/acme-api/pull/201",
    "author": "hana",
    "base_ref": "main",
    "head_ref": "feat/demo-901-b",
    "changed_files": 1,
    "additions": 90,
    "deletions": 12,
    "files": [{"filename": "src/shared.ts", "additions": 90, "deletions": 12, "hunks": [[50, 70]]}]
  },
  {
    "repo": "acme-web",
    "number": 700,
    "title": "被疊的那一顆（沒有跟任何人成組）",
    "url": "https://github.com/acme/acme-web/pull/700",
    "author": "ivan",
    "base_ref": "develop",
    "head_ref": "task/A/main",
    "changed_files": 3,
    "additions": 300,
    "deletions": 10,
    "files": [{"filename": "src/list.ts", "additions": 300, "deletions": 10, "hunks": [[1, 40]]}]
  },
  {
    "repo": "acme-web",
    "number": 701,
    "title": "疊在 700 上面的第一顆",
    "url": "https://github.com/acme/acme-web/pull/701",
    "author": "ivan",
    "base_ref": "task/A/main",
    "head_ref": "task/B",
    "changed_files": 2,
    "additions": 120,
    "deletions": 8,
    "files": [{"filename": "src/list.ts", "additions": 120, "deletions": 8, "hunks": [[1, 40]]}]
  },
  {
    "repo": "acme-web",
    "number": 702,
    "title": "疊在 700 上面的第二顆",
    "url": "https://github.com/acme/acme-web/pull/702",
    "author": "ivan",
    "base_ref": "task/A/main",
    "head_ref": "task/C",
    "changed_files": 1,
    "additions": 20,
    "deletions": 2,
    "files": [{"filename": "src/list.ts", "additions": 20, "deletions": 2, "hunks": [[1, 40]]}]
  },
  {
    "repo": "acme-web",
    "number": 703,
    "title": "跟它們同一個 repo，但自己從預設分支長出來",
    "url": "https://github.com/acme/acme-web/pull/703",
    "author": "judy",
    "base_ref": "develop",
    "head_ref": "task/D",
    "changed_files": 1,
    "additions": 15,
    "deletions": 1,
    "files": [{"filename": "src/other.ts", "additions": 15, "deletions": 1, "hunks": [[5, 9]]}]
  },
  {
    "repo": "acme-api",
    "number": 202,
    "title": "DEMO-901 問不到 base 的那一顆",
    "url": "https://github.com/acme/acme-api/pull/202",
    "author": "hana",
    "head_ref": "feat/demo-901-c",
    "changed_files": 1,
    "additions": 70,
    "deletions": 8,
    "files": [{"filename": "src/shared.ts", "additions": 70, "deletions": 8, "hunks": [[50, 70]]}]
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
assert by_number[30]["cluster_key"] == "1776130982.981829:DEMO-493", by_number[30]
assert by_number[30]["root_ticket_key"] == "DEMO-493", by_number[30]
assert by_number[40]["cluster_role"] == "standalone", by_number[40]
assert by_number[40]["model_tier"] == "small_fast", by_number[40]
assert by_number[50]["model_tier"] == "standard_coding", by_number[50]
assert by_number[50]["cluster_key"] == "", by_number[50]
assert by_number[60]["cluster_role"] == "cluster_lead", by_number[60]
assert by_number[60]["root_topic_key"] == "topic:jsbridgeutils-platform-case-insensitive", by_number[60]
assert by_number[70]["cluster_role"] == "cluster_sibling", by_number[70]
assert by_number[70]["cluster_key"] == "1777000000.000000:topic:jsbridgeutils-platform-case-insensitive", by_number[70]
assert by_number[70]["model_tier"] == "small_fast", by_number[70]
assert by_number[80]["cluster_role"] == "cluster_sibling", by_number[80]
assert by_number[80]["cluster_size"] == 3, by_number[80]

# 同一個 repo 的串行堆疊：後面那幾顆疊在前一顆的 head 上，檔案交集恆為真，而它們各自
# 帶著沒有人讀過的改動。三顆都要走完整 review，整組不成立為 cluster。
for number in (100, 101, 102):
    assert by_number[number]["cluster_role"] == "standalone", by_number[number]
assert by_number[101]["cluster_reason"].startswith("stacked_on_group_member:"), by_number[101]
assert by_number[102]["cluster_reason"].startswith("stacked_on_group_member:"), by_number[102]
assert by_number[101]["model_tier"] == "standard_coding", by_number[101]
assert by_number[102]["model_tier"] == "standard_coding", by_number[102]

# 同一個 repo 裡真的平行的兩顆（各自從 main 長出來、改動區塊重疊）仍然是同一組。
assert by_number[200]["cluster_role"] == "cluster_lead", by_number[200]
assert by_number[201]["cluster_role"] == "cluster_sibling", by_number[201]
assert by_number[201]["cluster_reason"].startswith("same_repo_overlap"), by_number[201]

# 問不到 base 的那一顆分不出平行與串行，所以它不當附屬顆——量不到走完整 review。
assert by_number[202]["cluster_role"] == "standalone", by_number[202]
assert by_number[202]["cluster_reason"].startswith("same_repo_lineage_unmeasurable:"), by_number[202]

# 站在誰身上這一條邊不需要成組：700／701／702 的 cluster 鍵都是空的。
assert by_number[701]["stacked_on"]["number"] == 700, by_number[701]
assert by_number[702]["stacked_on"]["number"] == 700, by_number[702]
assert by_number[700]["stacked_on"] is None, by_number[700]
assert sorted(by_number[700]["stacked_by"]) == [701, 702], by_number[700]
assert by_number[703]["stacked_on"] is None, by_number[703]
assert by_number[703]["stacked_reason"].startswith("not_stacked:"), by_number[703]
for number in (700, 701, 702, 703):
    assert by_number[number]["cluster_key"] == "", by_number[number]
# 這條邊不改深度：702 只動一個檔、22 行，照舊是 small_fast。
assert by_number[702]["model_tier"] == "small_fast", by_number[702]
# 問不到 base 的那一顆不得被說成「沒有疊在別人身上」。
assert by_number[202]["stacked_on"] is None, by_number[202]
assert by_number[202]["stacked_reason"].startswith("unmeasurable:"), by_number[202]
PY

echo "annotate-review-candidates selftest: PASS"
