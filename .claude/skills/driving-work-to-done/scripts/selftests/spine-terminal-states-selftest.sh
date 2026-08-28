#!/usr/bin/env bash
# Purpose: 證明一張單的終局不只有一種來源說得出口——`released` 讀那份知識宣告的訊號，
#          `close` 讀它宣告的收尾，而核心兩者都不認得內容。
# Inputs:  mktemp 底下一棵假的 repo：複製一份 driving-work-to-done，旁邊放一個假 pack，
#          那個 pack 的訊號與收尾都是可以被換掉的 stub。不碰真的 repo。
# Outputs: PASS 當「訊號說出去了才寫紀錄」「日期由訊號給」「沒宣告是問不到不是出去了」
#          「已經有紀錄就不重寫」「收尾的話原樣轉出來」「收不乾淨不讓 close 失敗」都成立。
#
# 為什麼要有假 pack：核心不該認得 PR、merge、branch。用真的 swe-knowledge 去驗，量到的是
# 「gh 今天回什麼」，而那不是這裡要問的問題。換掉 stub 印什麼就能把每一種答案都走一次。

set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  exit 2
fi

SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok  $*"; PASS=$((PASS + 1)); }

REPO="$WORK/repo"
mkdir -p "$REPO/.claude/skills"
cp -R "$SKILL_DIR" "$REPO/.claude/skills/driving-work-to-done"
STATE_SH="$REPO/.claude/skills/driving-work-to-done/scripts/spine-loop-state.sh"
PACK="$REPO/.claude/skills/fakepack"
mkdir -p "$PACK"
# 單的目錄樹要是自己的 git repo：位置重算從 repo 根解「這張單屬於哪棵樹」，解不出來就整段不做，
# 而那會讓下面每一條位置斷言都在一個從來沒被重算過的樹上量。
git init -q "$REPO/issues"

# Description: 寫假 pack 的 SKILL.md。給空字串就不宣告那一項。
# Args: $1 = DELIVERED 命令, $2 = CLOSE-CLEANUP 命令
write_pack() {
  {
    echo "# fakepack"
    [[ -n "$1" ]] && echo "<!-- FAKE-DELIVERED: $1 -->"
    [[ -n "$2" ]] && echo "<!-- FAKE-CLOSE-CLEANUP: $2 -->"
  } > "$PACK/SKILL.md"
}

# Description: 造一張走過主流程的單，回傳它的狀態檔路徑。
# Args: $1 = 單名, $2 = status（converged / open）
new_ticket() {
  local name="$1" status="$2" dir="$REPO/issues/ns/backlog/$1/.spine"
  mkdir -p "$dir"
  python3 - "$dir/loop-state.json" "$status" <<'PY'
import json, sys
path, status = sys.argv[1:3]
json.dump({
    "schema_version": 2, "station": "verify-ac", "status": status,
    "rounds": [], "stops": [], "stop": None,
    "knowledge_pack": {"pack": "fakepack"},
    "workspace_identity": {"kind": "ok", "values": ["repo:feat/x"],
                           "declared_landing": ["/nowhere/repo"]},
}, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
  printf '%s' "$dir/loop-state.json"
}

run() { RC=0; OUT="$(bash "$STATE_SH" "$@" 2>&1)" || RC=$?; }

echo "spine terminal states selftest"

# ── released ─────────────────────────────────────────────────────────────────
# 訊號說出去了，而且說了是哪一天。日期刻意選一個很舊的：核心若偷填「今天」，
# released/ 底下那一格的名字會當場不一樣。
printf '#!/usr/bin/env bash\nprintf "delivered\\t2020-01-02\\t樁：出去了\\n"\n' > "$PACK/yes.sh"
printf '#!/usr/bin/env bash\nprintf "not-yet\\t-\\t樁：還沒\\n"\nexit 1\n' > "$PACK/no.sh"
printf '#!/usr/bin/env bash\nprintf "unmeasurable\\t-\\t樁：問不到\\n"\nexit 2\n' > "$PACK/dunno.sh"
chmod +x "$PACK"/*.sh
write_pack "bash .claude/skills/fakepack/yes.sh" ""

state="$(new_ticket T-out converged)"
run released --state "$state" --by selftest
[[ "$RC" -eq 0 ]] || fail "訊號說出去了，應該寫得下紀錄；拿到 ${RC}：$OUT"
moved="$(find "$REPO/issues" -name release.json -path '*T-out*' | head -1)"
[[ -n "$moved" ]] || fail "沒有寫下釋出紀錄：$OUT"
grep -Fq '"released_on": "2020-01-02"' "$moved" \
  || fail "釋出日不是訊號給的那一天——核心自己填了日期：$(cat "$moved")"
grep -Fq '"released_on_source": "signal"' "$moved" || fail "沒說出日期是哪裡來的"
[[ "$moved" == *"/released/2020-01-02/"* ]] \
  || fail "位置沒有跟著訊號的日期走：$moved"
ok "訊號說出去了就寫得下紀錄，日期用訊號給的那一天，位置跟著走"

run released --state "${moved%/release.json}/loop-state.json" --by selftest
[[ "$RC" -eq 0 ]] || fail "已經有紀錄時應該安靜地成功；拿到 ${RC}：$OUT"
grep -Fq '不重寫' <<<"$OUT" || fail "沒說出它為什麼沒寫：$OUT"
ok "已經有釋出紀錄就不重寫（兩個地方都能宣稱的話，日期遲早會不一樣）"

# 訊號說還沒 → 不寫，而且 exit code 原樣往上傳。
write_pack "bash .claude/skills/fakepack/no.sh" ""
state="$(new_ticket T-pending converged)"
run released --state "$state" --by selftest
[[ "$RC" -eq 1 ]] || fail "訊號說還沒，應該回 1；拿到 ${RC}：$OUT"
[[ -z "$(find "$REPO/issues" -name release.json -path '*T-pending*')" ]] \
  || fail "還沒出去卻寫了釋出紀錄"
grep -Fq '樁：還沒' <<<"$OUT" || fail "沒有把訊號說的話原樣轉出來：$OUT"
ok "訊號說還沒就不寫紀錄，回 1，而且原樣轉述"

# 問不到 → 2，跟「還沒」分得開。塌成同一個 exit code 的話，一次 API 逾時就跟一張還在
# review 的單長得一樣。
write_pack "bash .claude/skills/fakepack/dunno.sh" ""
state="$(new_ticket T-dunno converged)"
run released --state "$state" --by selftest
[[ "$RC" -eq 2 ]] || fail "問不到應該回 2，跟還沒（1）分得開；拿到 ${RC}：$OUT"
[[ -z "$(find "$REPO/issues" -name release.json -path '*T-dunno*')" ]] \
  || fail "問不到卻寫了釋出紀錄"
ok "問不到是第三種，有自己的 exit code，而且不寫紀錄"

# 沒有宣告 → 拒絕。**沒問到不是出去了**：這是這一整支最重要的一條。
write_pack "" ""
state="$(new_ticket T-silent converged)"
run released --state "$state" --by selftest
[[ "$RC" -ne 0 ]] || fail "pack 沒宣告終局訊號時不得放行；拿到 0：$OUT"
[[ -z "$(find "$REPO/issues" -name release.json -path '*T-silent*')" ]] \
  || fail "沒有人回答過，卻寫了釋出紀錄"
grep -Fq 'UNDECLARED' <<<"$OUT" || fail "沒說出是宣告不見了：$OUT"
ok "pack 沒宣告訊號是問不到，不是出去了——不寫紀錄、非 0"

# ── close ────────────────────────────────────────────────────────────────────
printf '#!/usr/bin/env bash\nprintf "kept\\t樁：有東西沒收掉\\n"\nexit 1\n' > "$PACK/dirty.sh"
chmod +x "$PACK/dirty.sh"
write_pack "" "bash .claude/skills/fakepack/dirty.sh"
state="$(new_ticket T-close open)"
run close --state "$state" --note '不做了' --by selftest
[[ "$RC" -eq 0 ]] || fail "收不乾淨不該讓 close 失敗——單已經關了；拿到 ${RC}：$OUT"
grep -Fq '樁：有東西沒收掉' <<<"$OUT" || fail "收尾說的話沒有被轉出來：$OUT"
grep -Fq '沒收乾淨' <<<"$OUT" || fail "留下來的東西沒有被說出來：$OUT"
ok "close 會跑宣告的收尾，收不乾淨照樣關單但一定說出來"

write_pack "" ""
state="$(new_ticket T-close-quiet open)"
run close --state "$state" --note '不做了' --by selftest
[[ "$RC" -eq 0 ]] || fail "沒有宣告收尾時 close 應該照常；拿到 ${RC}：$OUT"
grep -Fq '沒有宣告收尾' <<<"$OUT" || fail "沒說出這個 pack 沒有收尾要做：$OUT"
ok "沒有宣告收尾時說出來，不假裝收過"

# ── 身分不從命名空間推 ───────────────────────────────────────────────────────
# 同一張單換一個命名空間，答案必須一模一樣。核心不認得 `framework` 也不認得任何公司名字：
# 從位置推身分是這套框架一路禁止的形狀，而它壞掉的樣子是安靜的——換一家公司才會發現。
write_pack "bash .claude/skills/fakepack/yes.sh" ""
mkdir -p "$REPO/issues/acme-inc/backlog/T-elsewhere/.spine"
cp "$REPO/issues/ns/released/2020-01-02/T-out/.spine/loop-state.json" \
   "$REPO/issues/acme-inc/backlog/T-elsewhere/.spine/loop-state.json"
run released --state "$REPO/issues/acme-inc/backlog/T-elsewhere/.spine/loop-state.json" --by selftest
[[ "$RC" -eq 0 ]] || fail "換一個命名空間就換一個答案；拿到 ${RC}：$OUT"
[[ -f "$REPO/issues/acme-inc/released/2020-01-02/T-elsewhere/.spine/release.json" ]] \
  || fail "命名空間影響了判定：$(find "$REPO/issues/acme-inc" -name release.json)"
ok "換一個命名空間，同一張單走到同一個終局——身分從單自己身上讀"

# ── 位置仍然只是投影 ─────────────────────────────────────────────────────────
# 一張還沒收斂的單，就算身上被放了一份釋出紀錄，也不得因此被判成釋出過。釋出紀錄不是
# 第二個能宣稱「這張單結束了」的地方——狀態才是。
placer="$REPO/.claude/skills/driving-work-to-done/scripts/place-issues-by-state.sh"
state="$(new_ticket T-openrec open)"
printf '{"schema_version":1,"released_on":"2020-01-02"}\n' > "$(dirname "$state")/release.json"
bash "$placer" --issues "$REPO/issues" --execute --spine-only >/dev/null \
  || fail "位置重算失敗了"
[[ -z "$(find "$REPO/issues" -path '*/released/*/T-openrec/*' -name release.json)" ]] \
  || fail "一份釋出紀錄就讓一張沒收斂的單被判成釋出過——位置變成了第二個權威"
ok "沒收斂的單放一份釋出紀錄也不算釋出過——位置仍然只是狀態的投影"

echo "PASS: spine terminal states（$PASS 項）"
