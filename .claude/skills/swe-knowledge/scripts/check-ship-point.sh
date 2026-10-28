#!/usr/bin/env bash
# Purpose: 出貨動作之前，問那張單判過了沒（DP-865 A-P5）。
# Inputs:  --issues <單的根目錄>
#          --action merge|tag|deploy
#          [--branch <要併的那條 branch 名>] [--head <要出去的 commit>]... [--tag <tag 名>]...
#          [--text <命令或訊息本文>] [--text-file <檔>]
# Outputs: 擋下時 stderr 說出是哪一張單、站別是什麼、要怎麼走；放行時什麼都不印。
# Exit:    0 放行（對不到任何本地單、或對到的都判過）/ 1 擋下 / 2 用法錯
#
# 這是〈五條〉第 3 條「判定過才進預設分支」第一次有東西守。它守的三種動作都收不回來、都會
# 出這個 repo，而看 diff 的人看不出那張單有沒有被判過——那寫在單的 loop-state 裡，不在 diff 裡。
#
# 對不對得到一張單，只看這幾樣，任何一樣中了就算對到：
#   - branch 名或本文裡出現一個本地單的號（目錄名開頭那一段，例如 ABC-123）
#   - 要出去的 commit 等於某張單 delivery.json 或證據記的 head
#   - 本文（去尾端空白）的 sha256 等於某張單 deploy-requests.json 記的那一筆
# 對不到就放行，而且不印任何東西：別人的 PR、別人的發佈、沒有走過這套流程的工作，不是這一道
# 管的事。以前那一道（訊息雜湊在紀錄裡找不到就擋）把「對不到」當成「沒驗過」，那是一條沒有
# 人定義過的規則。
#
# 對到了，要那張單的站別是 delivered。併的時候還要 head 是交付紀錄記的那一個——不是的話，
# 交付之後又改過，那一站要量的是改完之後的東西。
#
# 例外是只上 stage 的 tag（DP-907）：名字帶 beta 或 rc 段的，站別到 engineering 就放行。stage
# 驗收在 verify-ac 之前，那種 tag 不是進預設分支的出貨。一次給的 tag 有一個不是、或一個名字
# 都沒給，就照正式的判。
#
# 擋不到的，明講：人自己在網頁上按的；跑在一支腳本裡面、沒有經過呼叫這一支的那些動作
# （釋出尾段自己讀交付紀錄）；對不到單的那些。
set -uo pipefail

ISSUES="" ACTION="" BRANCH="" TEXT="" HEADS=() TAGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --issues)    ISSUES="${2:-}"; shift 2 ;;
    --action)    ACTION="${2:-}"; shift 2 ;;
    --branch)    BRANCH="${2:-}"; shift 2 ;;
    --head)      HEADS+=("${2:-}"); shift 2 ;;
    --tag)       TAGS+=("${2:-}"); shift 2 ;;
    --text)      TEXT="${2:-}"; shift 2 ;;
    --text-file) TEXT="$(cat "${2:-/dev/null}")"; shift 2 ;;
    -h|--help)   sed -n '2,10p' "$0" >&2; exit 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
case "$ACTION" in merge|tag|deploy) ;; *) echo "--action 要是 merge、tag 或 deploy（拿到 '$ACTION'）" >&2; exit 2 ;; esac
[[ -n "$ISSUES" ]] || { echo "--issues 是必填" >&2; exit 2; }
[[ -d "$ISSUES" ]] || exit 0

python3 - "$ISSUES" "$ACTION" "$BRANCH" "$TEXT" "$(printf '%s\n' "${TAGS[@]+"${TAGS[@]}"}")" \
  "${HEADS[@]+"${HEADS[@]}"}" <<'PY'
import glob, hashlib, json, os, re, sys

root, action, branch, text, tag_lines = sys.argv[1:6]
heads = {h for h in sys.argv[6:] if h}
tags = [t for t in tag_lines.splitlines() if t]
# 名字裡有一段是 beta 或 rc（前面是開頭或 _ . -，後面是結尾、分隔字元或數字）。
STAGE_ONLY = re.compile(r"(?:^|[_.-])(?:beta|rc)(?:[_.-]|\d|$)", re.I)
stage_only = action == "tag" and bool(tags) and all(STAGE_ONLY.search(t) for t in tags)
passing = {"engineering", "verify-ac", "delivered"} if stage_only else {"delivered"}
KEY = re.compile(r"(?<![A-Za-z0-9])([A-Z][A-Z0-9]*-\d+)(?![0-9])")

def read(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None

tickets = {}
for state_path in glob.glob(os.path.join(root, "**", ".spine", "loop-state.json"), recursive=True):
    ticket = os.path.dirname(os.path.dirname(state_path))
    match = KEY.match(os.path.basename(ticket))
    if match:
        tickets.setdefault(match.group(1), []).append(ticket)

def recorded_heads(ticket):
    found = set()
    delivery = read(os.path.join(ticket, ".spine", "delivery.json")) or {}
    found.add(delivery.get("head_sha"))
    for row in delivery.get("heads") or []:
        if isinstance(row, dict):
            found.add(row.get("head_sha"))
    for evidence in glob.glob(os.path.join(ticket, ".spine", "evidence", "*.json")):
        found.add((read(evidence) or {}).get("head_sha"))
    return {h for h in found if h}

def delivery_heads(ticket):
    delivery = read(os.path.join(ticket, ".spine", "delivery.json"))
    if not delivery:
        return set()
    found = {delivery.get("head_sha")}
    found.update(row.get("head_sha") for row in delivery.get("heads") or [] if isinstance(row, dict))
    return {h for h in found if h}

def matches_head(recorded):
    return any(h.startswith(r) or r.startswith(h) for h in heads for r in recorded if len(h) >= 7)

mapped = {}
for key in KEY.findall(branch + "\n" + text):
    for ticket in tickets.get(key, []):
        mapped[ticket] = "號 " + key
body_sha = hashlib.sha256(text.rstrip().encode()).hexdigest() if text.strip() else None
for group in tickets.values():
    for ticket in group:
        if ticket in mapped:
            continue
        if heads and matches_head(recorded_heads(ticket)):
            mapped[ticket] = "head"
        elif body_sha and any(r.get("message_sha256") == body_sha
                              for r in read(os.path.join(ticket, ".spine", "deploy-requests.json")) or []
                              if isinstance(r, dict)):
            mapped[ticket] = "部署請求紀錄"

blocked = []
for ticket, why in sorted(mapped.items()):
    state = read(os.path.join(ticket, ".spine", "loop-state.json")) or {}
    station = state.get("station") or "?"
    name = os.path.relpath(ticket, root)
    if station not in passing and stage_only:
        blocked.append(f"{name}（靠{why}對到）站別是 {station}：只上 stage 的 tag 要等這張單開了輪次、站別到 engineering。")
    elif station not in passing:
        blocked.append(f"{name}（靠{why}對到）站別是 {station}，還沒判過。先走 verify-ac，交付紀錄寫成時站別會自己記成 delivered。")
    elif action == "merge" and heads and not matches_head(delivery_heads(ticket)):
        blocked.append(f"{name}（靠{why}對到）判過，但要併的 head 不是交付紀錄記的那一個：交付之後又改過了，重走 verify-ac。")

if blocked:
    print(f"已擋下：這是一次出貨動作（{action}），而它對到的單還不能出去：", file=sys.stderr)
    for line in blocked:
        print("  - " + line, file=sys.stderr)
    sys.exit(1)
PY
