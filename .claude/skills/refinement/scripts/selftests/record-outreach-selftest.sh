#!/usr/bin/env bash
# Purpose: 驗一次問到流程以外去的動作，沒有人看過就留不下合法紀錄。
# Inputs:  mktemp 底下的單目錄。
# Outputs: PASS 當擬稿→確認→送出→回覆走得通、沒確認就記不下送出、沒稿就確認不了、
#          確認缺原話被拒、已確認的稿不得就地改寫、沒送出就記不了回覆。

set -uo pipefail

REC="$(cd "$(dirname "$0")/.." && pwd)/record-outreach.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

new_issue() {
  local path="$WORK/$1"
  mkdir -p "$path/.spine"
  printf '%s' "$path"
}

echo "record-outreach selftest"

issue="$(new_issue happy)"
bash "$REC" draft --issue "$issue" --id ask-owner --to '#some-place' \
  --body '這一段推不出來，想確認 X' >/dev/null || fail "擬稿寫不進去"
bash "$REC" confirm --issue "$issue" --id ask-owner --by someone \
  --quote '可以，就這樣問' >/dev/null || fail "確認寫不進去"
bash "$REC" sent --issue "$issue" --id ask-owner --link https://example.com/1 >/dev/null \
  || fail "確認過了卻記不下送出"
bash "$REC" reply --issue "$issue" --id ask-owner --body '答案是 Y' >/dev/null \
  || fail "回覆寫不進去"
python3 -c '
import json, sys
e = json.load(open(sys.argv[1]))["entries"][0]
for k in ("draft", "confirmed_by", "confirmed_quote", "sent_at", "link", "reply"):
    assert e.get(k), (k, e)
' "$issue/.spine/outreach.json" || fail "一輪走完卻沒把每一段都記下來"
echo "  ok  擬稿→確認→送出→回覆一路記得下來"

# 這是這支腳本唯一真正擋人的地方。
issue="$(new_issue unconfirmed)"
bash "$REC" draft --issue "$issue" --id q1 --to '#x' --body '想問' >/dev/null
out="$(bash "$REC" sent --issue "$issue" --id q1 2>&1)" && fail "沒人看過卻記下了送出"
grep -q 'POLARIS_OUTREACH_UNCONFIRMED' <<<"$out" || fail "沒有 marker：$out"
grep -q 'confirm --issue' <<<"$out" || fail "拒絕沒說出怎麼往下走：$out"
python3 -c '
import json, sys
e = json.load(open(sys.argv[1]))["entries"][0]
assert "sent_at" not in e, e
' "$issue/.spine/outreach.json" || fail "被拒的送出還是留下了痕跡"
echo "  ok  沒有人看過就記不下送出"

# --quote 是人自己說的話。少了它，「已確認」就只是 agent 打的一個字串。
issue="$(new_issue noquote)"
bash "$REC" draft --issue "$issue" --id q1 --to '#x' --body '想問' >/dev/null
out="$(bash "$REC" confirm --issue "$issue" --id q1 --by someone 2>&1)" \
  && fail "沒有原話卻確認成功"
grep -q 'POLARIS_OUTREACH_UNCONFIRMED' <<<"$out" || fail "沒有 marker：$out"
echo "  ok  確認少了人的原話時被拒"

issue="$(new_issue nodraft)"
out="$(bash "$REC" confirm --issue "$issue" --id ghost --by someone --quote 'ok' 2>&1)" \
  && fail "沒有稿卻確認成功"
grep -q 'POLARIS_OUTREACH_NO_DRAFT' <<<"$out" || fail "沒有 marker：$out"
echo "  ok  沒有稿就確認不了"

# 一份被確認過的稿被就地改寫之後，那個確認指向的是一段沒有人看過的文字。
issue="$(new_issue rewrite)"
bash "$REC" draft --issue "$issue" --id q1 --to '#x' --body '第一版' >/dev/null
out="$(bash "$REC" draft --issue "$issue" --id q1 --to '#x' --body '偷偷換掉' 2>&1)" \
  && fail "同一個 id 的稿被就地改寫了"
grep -q 'POLARIS_OUTREACH_DRAFT_EXISTS' <<<"$out" || fail "沒有 marker：$out"
echo "  ok  已存在的擬稿不得就地改寫"

issue="$(new_issue noreply)"
bash "$REC" draft --issue "$issue" --id q1 --to '#x' --body '想問' >/dev/null
bash "$REC" confirm --issue "$issue" --id q1 --by someone --quote 'ok' >/dev/null
out="$(bash "$REC" reply --issue "$issue" --id q1 --body '回覆' 2>&1)" \
  && fail "還沒送出就記下了回覆"
grep -q 'POLARIS_OUTREACH_NOT_SENT' <<<"$out" || fail "沒有 marker：$out"
echo "  ok  還沒送出就不會有回覆"

echo "PASS: record-outreach"
