#!/usr/bin/env bash
# record-outreach.sh — 問到這條流程以外去之前，先留下一份人看過的擬稿。
#
# 為什麼要有這一支
# ----------------
# 推不出來的困難總會出現，而唯一的解法是去問一個人。問題不在於該不該問，在於**問出去這件
# 事是不可逆的**：訊息一旦送到一個公開的地方，改不回來，而且送出去的是你以為的問題，不是
# 對方需要看到的問題。
#
# 所以順序是擬稿 → 人看過 → 才送。這不是這支腳本發明的規矩，它是〈風格與語言〉早就寫下的
# 三種例外之一（自己起意的對外寫入）。這支只是讓那條規矩有一個留得下痕跡的地方。
#
# 它管得到什麼、管不到什麼
# ------------------------
# **送出這個動作本身它管不到**——那由別的工具做，這支腳本攔不住。它管的是「留得下合法紀錄
# 的條件」：沒有人的原話就寫不進去。這跟 reset --authorization 是同一種形狀——機制讓謊變得
# 看得見，不是讓謊不可能。一句捏造的引言是一句捏造的引言，那比一個捏造的旗標顯眼得多。
#
# Usage:
#   record-outreach.sh draft   --issue <dir> --id <slug> --to <哪裡> --body <擬稿>
#   record-outreach.sh confirm --issue <dir> --id <slug> --by <人> --quote <人的原話>
#   record-outreach.sh sent    --issue <dir> --id <slug> [--link <URL>]
#   record-outreach.sh reply   --issue <dir> --id <slug> --body <回覆>
#   record-outreach.sh show    --issue <dir>
# Exit: 0 寫成 / 2 拒絕（訊息說出缺什麼）

set -uo pipefail

ISSUE=""; ID=""; TO=""; BODY=""; BY=""; QUOTE=""; LINK=""
CMD="${1:-}"; shift || true

die() {
  local marker="$1"; shift
  echo "$marker" >&2
  printf '%s\n' "$@" >&2
  exit 2
}

usage() {
  sed -n '/^# Usage:/,/^# Exit:/p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue) ISSUE="${2:-}"; shift 2 ;;
    --id)    ID="${2:-}"; shift 2 ;;
    --to)    TO="${2:-}"; shift 2 ;;
    --body)  BODY="${2:-}"; shift 2 ;;
    --by)    BY="${2:-}"; shift 2 ;;
    --quote) QUOTE="${2:-}"; shift 2 ;;
    --link)  LINK="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "不認得的參數：$1" >&2; usage ;;
  esac
done

[[ -n "$ISSUE" ]] || usage
[[ -d "$ISSUE" ]] || die "POLARIS_OUTREACH_NO_ISSUE" "找不到單目錄 $ISSUE"
command -v python3 >/dev/null 2>&1 || {
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
}

STORE="$ISSUE/.spine/outreach.json"

case "$CMD" in
  draft)
    [[ -n "$ID" && -n "$TO" && -n "$BODY" ]] \
      || die "POLARIS_OUTREACH_DRAFT_INCOMPLETE" "draft 要 --id、--to、--body（擬稿全文，不是摘要）"
    ;;
  confirm)
    [[ -n "$ID" && -n "$BY" && -n "$QUOTE" ]] \
      || die "POLARIS_OUTREACH_UNCONFIRMED" \
        "confirm 要 --id、--by、--quote。
--quote 是那個人**自己說的話**，原樣。沒有它就沒有確認——一個由 agent 代打的
「已確認」跟沒有確認在出事的時候長得一樣。"
    ;;
  sent|reply|show) [[ "$CMD" == "show" || -n "$ID" ]] || die "POLARIS_OUTREACH_NO_ID" "$CMD 要 --id" ;;
  *) usage ;;
esac

python3 - "$STORE" "$CMD" "$ID" "$TO" "$BODY" "$BY" "$QUOTE" "$LINK" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

store, cmd, ident, to, body, by, quote, link = sys.argv[1:9]


def refuse(marker, *lines):
    print(marker, file=sys.stderr)
    for line in lines:
        print(line, file=sys.stderr)
    sys.exit(2)


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


data = {"schema_version": 1, "producer": "record-outreach.sh", "entries": []}
if os.path.exists(store):
    try:
        data = json.load(open(store, encoding="utf-8"))
    except ValueError:
        refuse("POLARIS_OUTREACH_STORE_UNREADABLE", f"{store} 不是讀得動的 JSON")

entries = data.setdefault("entries", [])
found = next((e for e in entries if e.get("id") == ident), None)

if cmd == "show":
    if not entries:
        print("OUTREACH: 這張單還沒有問到外面去過")
    for entry in entries:
        state = ("已回覆" if entry.get("reply") else
                 "已送出" if entry.get("sent_at") else
                 "已確認待送" if entry.get("confirmed_quote") else "只有擬稿")
        print(f"  {entry['id']}  → {entry.get('to', '?')}  [{state}]")
    sys.exit(0)

if cmd == "draft":
    if found:
        refuse("POLARIS_OUTREACH_DRAFT_EXISTS",
               f"「{ident}」已經有一份擬稿了。改稿要換一個 id——",
               "一份被確認過的擬稿被就地改寫之後，那個確認就指向一段沒有人看過的文字。")
    entries.append({"id": ident, "to": to, "draft": body, "drafted_at": now()})
elif cmd == "confirm":
    if not found:
        refuse("POLARIS_OUTREACH_NO_DRAFT",
               f"「{ident}」沒有擬稿可以確認。先 draft 再 confirm——",
               "沒有稿的確認，確認的是空氣。")
    found["confirmed_by"] = by
    found["confirmed_quote"] = quote
    found["confirmed_at"] = now()
elif cmd == "sent":
    if not found:
        refuse("POLARIS_OUTREACH_NO_DRAFT", f"「{ident}」沒有這一筆")
    # 這一支唯一真正擋人的地方。送出動作本身它攔不到，但一次沒有人看過的送出，
    # 在這張單裡留不下合法紀錄——而一個留不下紀錄的動作，在事後看起來就是沒發生。
    if not found.get("confirmed_quote"):
        refuse("POLARIS_OUTREACH_UNCONFIRMED",
               f"「{ident}」還沒有人確認過，記不下送出。",
               "順序是擬稿 → 人看過 → 才送。訊息送出去是不可逆的，而送出去的是你以為的",
               "問題，不是對方需要看到的問題。",
               f"先跑：record-outreach.sh confirm --issue <dir> --id {ident} --by <人> --quote '<原話>'")
    found["sent_at"] = now()
    if link:
        found["link"] = link
elif cmd == "reply":
    if not found:
        refuse("POLARIS_OUTREACH_NO_DRAFT", f"「{ident}」沒有這一筆")
    if not found.get("sent_at"):
        refuse("POLARIS_OUTREACH_NOT_SENT", f"「{ident}」還沒送出去，不會有回覆")
    found["reply"] = body
    found["replied_at"] = now()

os.makedirs(os.path.dirname(os.path.abspath(store)) or ".", exist_ok=True)
with open(store, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
print(f"OUTREACH {cmd.upper()}: {ident} → {store}")
PY
