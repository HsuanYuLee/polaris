#!/usr/bin/env bash
# Selftest for scan-template-leaks.sh 的零樣式行為 —— 一次什麼都沒掃的執行，不得跟一次
# 掃過而且乾淨的執行長得一樣。
#
# 這件事以前是安靜的：外洩掃描的樣式全部來自 `{公司}/workspace-config.yaml`，一個公司都
# 沒有的時候它印 `hits: 0` 然後 exit 0，而消費它的 gate-template-leaks 兩種都印 ✅。
# 於是「掃不到東西」與「掃過了沒問題」在輸出與結束狀態上完全相同。
#
# 走得完的那條路是宣告，不是零這個數字——所以這裡四個 case 分成兩組：沒有宣告時要停，
# 有宣告時要走得完；而宣告與實際對不上的時候，兩邊都不算。

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scan-template-leaks.sh"
GATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/gate-template-leaks.sh"
tmp="$(mktemp -d)"
trap 'status=$?; rm -rf "$tmp"; exit $status' EXIT

pass=0
fail=0

# Description: 造一棵假工作區。$1 = case 名，$2 = 公司名（空字串表示一家都沒有）。
new_workspace() {
  local name="$1"
  local company="${2:-}"
  local root="$tmp/$name"
  rm -rf "$root"
  mkdir -p "$root/.claude/skills/one"
  echo '# one：一支乾淨的 skill。' > "$root/.claude/skills/one/SKILL.md"
  if [[ -n "$company" ]]; then
    mkdir -p "$root/$company"
    printf 'name: %s\n' "$company" > "$root/$company/workspace-config.yaml"
  fi
  git init -q "$root"
  git -C "$root" config user.email t@t; git -C "$root" config user.name t
  git -C "$root" add -A
  git -C "$root" commit -qm init
  printf '%s' "$root"
}

check() {
  local name="$1" want="$2" needle="$3" root="$4"; shift 4
  local out rc
  out="$(bash "$SCRIPT" --workspace "$root" --source workspace --blocking 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" != "$want" ]]; then
    echo "FAIL $name: 期待 exit ${want}，實際 ${rc}"; echo "$out" | sed 's/^/     /'; fail=$((fail+1)); return
  fi
  if [[ -n "$needle" && "$out" != *"$needle"* ]]; then
    echo "FAIL $name: 訊息裡沒有 '${needle}'"; echo "$out" | sed 's/^/     /'; fail=$((fail+1)); return
  fi
  echo "PASS $name"; pass=$((pass+1))
}

# ── 一個樣式都沒有而且沒有宣告：停 ─────────────────────────────────
root="$(new_workspace vacuous)"
check "零樣式又沒有宣告時不判綠" 2 "POLARIS_TEMPLATE_LEAK_SCAN_VACUOUS" "$root"

# ── 把公司拿掉買不到綠：同一棵樹，有公司時綠，拿掉之後停 ───────────
root="$(new_workspace shrink acme)"
check "有公司時正常判定" 0 "companies: acme" "$root"
rm -rf "$root/acme"
check "把公司拿掉之後停下來，不是變綠" 2 "POLARIS_TEMPLATE_LEAK_SCAN_VACUOUS" "$root"

# ── 按設計沒有公司的環境，靠宣告走得完 ─────────────────────────────
root="$(new_workspace declared)"
printf 'companies: none\n' > "$root/workspace-config.yaml"
check "宣告了就走得完，而且說出這一趟沒量東西" 0 "這一趟沒有量任何東西" "$root"

# ── 宣告與實際對不上，兩邊都不算 ───────────────────────────────────
root="$(new_workspace contradiction acme)"
printf 'companies: none\n' > "$root/workspace-config.yaml"
check "宣告 none 但實際有公司時不判定" 2 "宣告與實際對不上" "$root"

# ── 閘不得把「量不到」講成「有外洩」 ───────────────────────────────
root="$(new_workspace gatevacuous)"
mkdir -p "$root/.claude/skills/framework-release/scripts"
cp "$SCRIPT" "$root/.claude/skills/framework-release/scripts/scan-template-leaks.sh"
out="$(bash "$GATE" --repo "$root" 2>&1)" && rc=0 || rc=$?
if [[ "$rc" == 2 && "$out" == *"量不到"* && "$out" != *"BLOCKED"* ]]; then
  echo "PASS 閘把量不到跟有外洩分開講"; pass=$((pass+1))
else
  echo "FAIL 閘把量不到跟有外洩分開講: exit=${rc}"; echo "$out" | sed 's/^/     /'; fail=$((fail+1))
fi

echo "scan-template-leaks vacuous selftest: PASS=$pass FAIL=$fail"
[[ "$fail" == 0 ]]
