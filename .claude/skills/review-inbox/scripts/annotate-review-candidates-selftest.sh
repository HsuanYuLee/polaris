#!/usr/bin/env bash
# Selftest for annotate-review-candidates.py.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
annotator="$script_dir/annotate-review-candidates.py"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mapping="$tmp/mapping.json"
open_prs="$tmp/open-prs.json"
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
  "https://github.com/acme/acme-web/pull/810": {"thread_ts": "1778000000.000000", "root_ticket_key": "DEMO-900"},
  "https://github.com/acme/acme-web/pull/811": {"thread_ts": "1778000000.000000", "root_ticket_key": "DEMO-900"},
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
    "repo": "acme-web",
    "number": 810,
    "title": "DEMO-900 疊在一顆「我投過票、這一輪沒進候選集」的 open PR 上",
    "url": "https://github.com/acme/acme-web/pull/810",
    "author": "gale",
    "base_ref": "task/E-not-in-this-round",
    "head_ref": "task/E-child",
    "changed_files": 44,
    "additions": 900,
    "deletions": 300,
    "files": [{"filename": "src/guard.ts", "additions": 900, "deletions": 300, "hunks": [[10, 30]]}]
  },
  {
    "repo": "acme-web",
    "number": 811,
    "title": "DEMO-900 疊在一顆 draft 的 open PR 上，而且自己只動一個小檔",
    "url": "https://github.com/acme/acme-web/pull/811",
    "author": "gale",
    "base_ref": "task/F-not-in-this-round",
    "head_ref": "task/F-child",
    "changed_files": 1,
    "additions": 12,
    "deletions": 2,
    "files": [{"filename": "src/guard.ts", "additions": 12, "deletions": 2, "hunks": [[10, 30]]}]
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

# **這份表取的是濾網之前那一份**：#800 是 draft、#801 我方投過票，兩顆都不會出現在候選集
# 裡，但它們真的是別人的 base。真跑那一輪的形狀（2026-09-17 的 9 層 stack）就是這樣。
cat > "$open_prs" <<'JSON'
{
  "acme-web": {
    "default_branch": "develop",
    "heads": {
      "task/A/main": {"number": 700, "url": "https://github.com/acme/acme-web/pull/700"},
      "task/B": {"number": 701, "url": "https://github.com/acme/acme-web/pull/701"},
      "task/C": {"number": 702, "url": "https://github.com/acme/acme-web/pull/702"},
      "task/D": {"number": 703, "url": "https://github.com/acme/acme-web/pull/703"},
      "task/E-not-in-this-round": {"number": 800, "url": "https://github.com/acme/acme-web/pull/800"},
      "task/F-not-in-this-round": {"number": 801, "url": "https://github.com/acme/acme-web/pull/801"}
    }
  },
  "acme-api": {"default_branch": "main", "heads": {}},
  "acme-ios": {"default_branch": "main", "heads": {}}
}
JSON

"$annotator" --offline --mapping "$mapping" --open-prs "$open_prs" < "$candidates" > "$out"

# 同一份候選，這一趟不給表：判定要退成「問不到」，不得說成沒有疊。
out_no_table="$tmp/annotated-no-open-prs.json"
"$annotator" --offline --mapping "$mapping" < "$candidates" > "$out_no_table"

python3 - "$out" "$out_no_table" <<'PY'
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
assert by_number[101]["cluster_reason"].startswith("stacked_on_pr:"), by_number[101]
assert by_number[102]["cluster_reason"].startswith("stacked_on_pr:"), by_number[102]
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
assert by_number[703]["stacked_reason"].startswith("not_stacked:base 是這個 repo 的預設分支"), by_number[703]
for number in (700, 701, 702, 703):
    assert by_number[number]["cluster_key"] == "", by_number[number]
# 這條邊不改深度：702 只動一個檔、22 行，照舊是 small_fast。
assert by_number[702]["model_tier"] == "small_fast", by_number[702]
# 問不到 base 的那一顆不得被說成「沒有疊在別人身上」。
assert by_number[202]["stacked_on"] is None, by_number[202]
assert by_number[202]["stacked_reason"].startswith("unmeasurable:"), by_number[202]

# ── parent 是 open PR，但這一輪不在候選集 ──────────────────────────────────
# 2026-09-17 真跑撞到的形狀：#3225 疊在 #3224（我投過票）、#3222 疊在 #3133（draft）。
# 候選集決定誰被派，不決定誰算 parent——所以這兩顆帶得出 parent。
for number, parent in ((810, 800), (811, 801)):
    edge = by_number[number]["stacked_on"]
    assert edge is not None, by_number[number]
    assert edge["number"] == parent, by_number[number]
    assert edge["in_this_round"] is False, by_number[number]
    assert by_number[number]["stacked_reason"].startswith("stacked_on_open_pr:"), by_number[number]

# **而 parent 在這一輪的那幾顆，理由要跟上面那一句分得開。**
assert by_number[101]["stacked_on"]["in_this_round"] is True, by_number[101]
assert by_number[101]["stacked_reason"].startswith("stacked_on_candidate:"), by_number[101]

# 那兩顆不因為 cluster 鍵相同、檔案交集恆真而被判成附屬顆——串行的第 N 顆走完整 review。
for number in (810, 811):
    assert by_number[number]["cluster_role"] == "standalone", by_number[number]
    assert by_number[number]["cluster_reason"].startswith("stacked_on_pr:"), by_number[number]

# **#811 只動一個 12 行的小檔，所以它照舊是 small_fast。** 這條邊帶的是「你站在誰身上」，
# 不是深度——把 stacked 一律升級成完整深度，等於拿掉 tier 這個功能。
assert by_number[811]["model_tier"] == "small_fast", by_number[811]

# ── 同一份候選，沒給 open PR 表 ────────────────────────────────────────────
# **問不到不得說成沒有疊。** 沒有表就分不出「base 不是任何人的 head」與「parent 在候選集
# 之外」，所以這兩顆落在問不到那一格，走完整 review。
no_table = {item["number"]: item for item in json.loads(Path(sys.argv[2]).read_text())}
for number in (810, 811):
    assert no_table[number]["stacked_on"] is None, no_table[number]
    assert no_table[number]["stacked_reason"].startswith("unmeasurable:"), no_table[number]
    assert no_table[number]["cluster_role"] != "cluster_sibling", no_table[number]

# 而 parent 在候選集的那幾顆不需要表就答得出來——那份表是加的，不是換的。
assert no_table[101]["stacked_on"]["number"] == 100, no_table[101]
PY

echo "annotate-review-candidates selftest: PASS"
