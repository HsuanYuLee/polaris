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
#
# **第二個軸（DP-523）：零檔案。** 上面那一組守的是「一個樣式都沒有」，而同一個形狀還有
# 另一半——樣式齊全，但一個檔案都沒讀到。兩條路走到那裡：範圍限在一個不存在的路徑上，或者
# 沒有人告訴它工作區在哪而它自己算錯了根。2026-08-13 實測：同一棵樹、同一份注入的外洩，
# 不帶 `--workspace` 印 `hits: 0` 並 exit 0，帶著正確的根印 `hits: 1` 並擋下來。這一支是
# 外洩閘，所以它的假綠方向是放行。

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

# ══ 第二個軸：零檔案（DP-523） ═════════════════════════════════════
# Description: 把受測腳本複製進假工作區的 skill 目錄，讓它自己解根——真腳本住在真 repo 裡，
# 從那裡解永遠解得到真的根，那樣測不到解根這件事。$1 = 假工作區的根。
plant_script() {
  mkdir -p "$1/.claude/skills/framework-release/scripts"
  cp "$SCRIPT" "$1/.claude/skills/framework-release/scripts/scan-template-leaks.sh"
  printf '%s' "$1/.claude/skills/framework-release/scripts/scan-template-leaks.sh"
}

# Description: 在假工作區裡注入一份帶著公司字串的檔案。$1 = 根，$2 = 公司名。
inject_leak() { printf -- '# probe\n\n%s\n' "$2" > "$1/.claude/skills/one/leak.md"; }

# ── K-P1 沒有人告訴它工作區在哪的時候，它解出來的是工作區的根 ──────
root="$(new_workspace selfroot acme)"
planted="$(plant_script "$root")"
inject_leak "$root" acme
# macOS 的 $TMPDIR 是一條 symlink，而腳本解根用的是 `cd ... && pwd`——比字串要比解開之後
# 的那一個，不然這個 case 會在一個跟解根無關的地方紅。
real_root="$(cd "$root" && pwd -P)"
out="$(bash "$planted" --blocking 2>&1)" && rc=0 || rc=$?
if [[ "$rc" == 1 && "$out" == *"workspace: $real_root"* && "$out" == *"hits: 1"* ]]; then
  echo "PASS 不帶工作區參數時解出來的是工作區的根"; pass=$((pass+1))
else
  echo "FAIL 不帶工作區參數時解出來的是工作區的根: exit=${rc}"; echo "$out" | sed 's/^/     /'; fail=$((fail+1))
fi

# K-N1 同一棵樹、同一份外洩，帶著明確工作區的那條路判一樣的東西。
out2="$(bash "$planted" --workspace "$root" --blocking 2>&1)" && rc2=0 || rc2=$?
if [[ "$rc2" == "$rc" && "$out2" == *"hits: 1"* ]]; then
  echo "PASS 帶著明確工作區的呼叫端行為不變"; pass=$((pass+1))
else
  echo "FAIL 帶著明確工作區的呼叫端行為不變: exit=${rc2}（自己解根時是 ${rc}）"; echo "$out2" | sed 's/^/     /'; fail=$((fail+1))
fi

# ── K-P2 解不出根就停，不拿一個猜出來的根去掃 ──────────────────────
mkdir -p "$tmp/noroot/scripts"
cp "$SCRIPT" "$tmp/noroot/scripts/scan-template-leaks.sh"
out="$(bash "$tmp/noroot/scripts/scan-template-leaks.sh" --blocking 2>&1)" && rc=0 || rc=$?
if [[ "$rc" == 2 && "$out" == *"POLARIS_TEMPLATE_LEAK_SCAN_NO_ROOT"* ]]; then
  echo "PASS 往上找不到工作區的根 → 停，不猜一個"; pass=$((pass+1))
else
  echo "FAIL 往上找不到工作區的根 → 停，不猜一個: exit=${rc}"; echo "$out" | sed 's/^/     /'; fail=$((fail+1))
fi

# ── K-P3 掃了幾個檔案要說出來，綠的那一趟也印 ──────────────────────
root="$(new_workspace counted acme)"
out="$(bash "$SCRIPT" --workspace "$root" --blocking 2>&1)" && rc=0 || rc=$?
if [[ "$rc" == 0 && "$out" =~ scanned:\ [1-9] ]]; then
  echo "PASS 綠的那一趟也說出掃了幾個檔案"; pass=$((pass+1))
else
  echo "FAIL 綠的那一趟也說出掃了幾個檔案: exit=${rc}"; echo "$out" | sed 's/^/     /'; fail=$((fail+1))
fi

# ── K-P4 三種輸入各有可分辨的答案 ──────────────────────────────────
root="$(new_workspace threeways acme)"
bash "$SCRIPT" --workspace "$root" --blocking >/dev/null 2>&1 && clean=0 || clean=$?
inject_leak "$root" acme
bash "$SCRIPT" --workspace "$root" --blocking >/dev/null 2>&1 && leaky=0 || leaky=$?
out="$(bash "$SCRIPT" --workspace "$root" --only-path .claude/skills/nowhere --blocking 2>&1)" && nofiles=0 || nofiles=$?
if [[ "$clean" != "$leaky" && "$leaky" != "$nofiles" && "$clean" != "$nofiles" \
      && "$out" == *"POLARIS_TEMPLATE_LEAK_SCAN_NO_FILES"* ]]; then
  echo "PASS 乾淨／有外洩／一個都沒掃到，三種答案分辨得出來（${clean} / ${leaky} / ${nofiles}）"; pass=$((pass+1))
else
  echo "FAIL 三種答案分辨得出來: 乾淨=${clean} 有外洩=${leaky} 沒掃到=${nofiles}"; echo "$out" | sed 's/^/     /'; fail=$((fail+1))
fi

# ── K-N2 不新開第二份「工作區在哪」的答案 ──────────────────────────
# 解根的判準沿用樹裡既有的那一個（帶著 .claude/skills 的祖先）。新開一個環境變數或設定檔
# 就是第二份答案，而兩份會漂。
resolver="$(sed -n '/^resolve_workspace_root()/,/^}/p' "$SCRIPT")"
if [[ "$resolver" == *".claude/skills"* ]] \
   && ! grep -qE '\$\{?(POLARIS_WORKSPACE|WORKSPACE_ROOT|POLARIS_ROOT)\b' "$SCRIPT"; then
  echo "PASS 解根沿用既有判準，沒有新開第二份答案"; pass=$((pass+1))
else
  echo "FAIL 解根沿用既有判準，沒有新開第二份答案"; echo "$resolver" | sed 's/^/     /'; fail=$((fail+1))
fi

echo "scan-template-leaks vacuous selftest: PASS=$pass FAIL=$fail"
[[ "$fail" == 0 ]]
