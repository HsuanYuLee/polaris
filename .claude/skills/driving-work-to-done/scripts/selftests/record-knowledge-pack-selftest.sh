#!/usr/bin/env bash
# Purpose: 證明「指名的 pack 載不到就停」是真的擋得住，而不是一句期許。
# Inputs:  mktemp 底下的假 loop state。
# Outputs: PASS 當解析不到的 pack 被拒、none 沒帶理由被拒、check 在沒記過時回非 0、
#          記過之後 check 變綠，而且被拒的那幾次一個位元組都沒寫進 state。

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
REC="$ROOT_DIR/scripts/record-knowledge-pack.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()  { echo "PASS $*"; PASS=$((PASS + 1)); }
bad() { echo "FAIL $*" >&2; FAIL=$((FAIL + 1)); }

STATE="$WORK/loop-state.json"
fresh_state() {
  printf '%s\n' '{"schema_version": 1, "station": "refinement", "rounds": []}' > "$STATE"
}

fresh_state

# 沒記過的時候 check 要紅。欄位空著跟「沒有適用的領域」不能長得一樣。
if bash "$REC" check --state "$STATE" >/dev/null 2>&1; then
  bad "沒記過領域知識，check 卻是綠的"
else
  ok "沒記過時 check 回非 0"
fi

# 解析不到的 pack。這是整支腳本存在的理由：散文指向一個不存在的東西時完全是安靜的。
before="$(cat "$STATE")"
out="$(bash "$REC" record --state "$STATE" --pack no-such-pack 2>&1 || true)"
if bash "$REC" record --state "$STATE" --pack no-such-pack >/dev/null 2>&1; then
  bad "解析不到的 pack 被接受了"
elif ! printf '%s' "$out" | grep -q 'no-such-pack'; then
  bad "拒絕了但沒說出是哪個 pack：$out"
elif [[ "$(cat "$STATE")" != "$before" ]]; then
  bad "拒絕的那一次還是寫了東西進 state"
else
  ok "解析不到的 pack 被拒，而且沒寫任何東西"
fi

# none 沒帶理由。一個沒有理由的 none 跟忘記記，在檔案裡長得一樣。
if bash "$REC" record --state "$STATE" --pack none >/dev/null 2>&1; then
  bad "--pack none 沒帶 --why 卻被接受"
else
  ok "--pack none 沒帶 --why 被拒"
fi

# none 帶了理由：這是一個被記下來的選擇，要記得下去。
if bash "$REC" record --state "$STATE" --pack none --why '這是一份報告，不產生程式碼變更' >/dev/null 2>&1; then
  recorded="$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["knowledge_pack"]["pack"], d["knowledge_pack"].get("why",""))' "$STATE")"
  if [[ "$recorded" == none*報告* ]]; then
    ok "none 帶理由記得下去，理由也留著"
  else
    bad "none 記下去了但內容不對：$recorded"
  fi
else
  bad "none 帶了理由還是被拒"
fi

# 真的存在的 pack：要解析成一個真的檔案路徑，不是把名字抄進去了事。
fresh_state
if bash "$REC" record --state "$STATE" --pack swe-knowledge >/dev/null 2>&1; then
  skill="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["knowledge_pack"].get("skill",""))' "$STATE")"
  if [[ -f "$skill" ]]; then
    ok "存在的 pack 被解析成真的 SKILL.md：${skill##*/skills/}"
  else
    bad "記下來的 skill 路徑不存在：$skill"
  fi
else
  bad "swe-knowledge 這個真的存在的 pack 被拒了"
fi

if bash "$REC" check --state "$STATE" >/dev/null 2>&1; then
  ok "記過之後 check 變綠"
else
  bad "記過了 check 還是紅的"
fi

# 一張單只有一筆。重新判定領域是覆蓋，兩筆並存等於兩個「怎麼算 done」。
bash "$REC" record --state "$STATE" --pack none --why '重新判定：這張單其實不改程式碼' >/dev/null 2>&1
count="$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(1 if isinstance(d.get("knowledge_pack"), dict) else 0)' "$STATE")"
current="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["knowledge_pack"]["pack"])' "$STATE")"
if [[ "$count" == "1" && "$current" == "none" ]]; then
  ok "重新判定是覆蓋，不是追加"
else
  bad "重新判定之後不只一筆或內容不對：count=$count current=$current"
fi

echo "record-knowledge-pack selftest: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
