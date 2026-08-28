#!/usr/bin/env bash
# Purpose: 證明這支 skill 的散文指名的每一個入口都真的跑得起來——用執行的，不是用讀的。
# Inputs:  這支 skill 自己的 scripts/ 底下每一支 .sh，以及 references/ 裡指名它們的那些行。
# Outputs: 每支腳本各印一筆 PASS / FAIL；有任何一支非 0 就整體非 0。
#
# 為什麼需要這一支：這些腳本自己在執行期算出「工作區根在哪」，路徑是變數，靜態的關卡讀不到
# ——樹上那道掃引用的關卡自己就把這一類列在「判不了」的那一格。所以它們壞掉的時候沒有任何
# 東西會紅。
#
# 2026-08-12（DP-518）實測到的就是這件事：這支 skill 的 preflight／capture reference 指名的
# 兩個入口全部 exit 1，而整段存在期間沒有一次被執行過（這個目錄那時候還不存在）。
#   polaris-env.sh status <company>  → ERROR: Config not found: …/visual-regression/<company>/…
#   polaris-toolchain.sh doctor      → ERROR: cannot locate Polaris workspace root
# 前者是 `$SCRIPT_DIR/..` 在搬家之後停錯了一層；後者的 parser 在搬家那次被刪掉、沒跟著搬，
# 已經退場。
#
# 判準刻意寫得寬：這裡不驗一支腳本做對了它的事（那是它自己的測試），只驗**它找得到它要的
# 東西**。所以看的是「輸出裡有沒有解析失敗的痕跡」，不是 exit code——很多入口沒給參數時
# 印 usage 並回非 0，那是對的行為。
#
# Usage: entry-points-selftest.sh
# Exit:  0 每支都解析得到 / 1 有解析不到的 / 2 量不到（找不到 scripts/、一支都沒有）

set -uo pipefail

SKILL_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPTS_DIR="$SKILL_ROOT/scripts"

# 這支 skill 可能被單獨帶到別的地方，所以工作區根用找的，不用寫死的深度。
find_workspace_root() {
  local dir="$SKILL_ROOT"
  while [[ "$dir" != "/" ]]; do
    [[ -d "$dir/.claude/skills" ]] && { echo "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  return 1
}
WORKSPACE_ROOT="$(find_workspace_root || true)"

echo "entry-points selftest"
echo "  skill:     $SKILL_ROOT"
echo "  workspace: ${WORKSPACE_ROOT:-<找不到，只跑不需要工作區的那幾支>}"

[[ -d "$SCRIPTS_DIR" ]] || { echo "FAIL 找不到 $SCRIPTS_DIR" >&2; exit 2; }

# 解析失敗長什麼樣。這幾個字串是實際量到的，不是想像的。
UNRESOLVED='Config not found|cannot locate|No such file or directory|command not found|not readable|does not exist'

PASS=0
FAIL=0

# run_entry <名字> <命令...>
# 跑一次，看輸出裡有沒有解析失敗的痕跡。exit code 不判——沒給參數時印 usage 回非 0 是對的。
run_entry() {
  local name="$1"; shift
  local out
  out="$("$@" 2>&1)"
  if printf '%s' "$out" | grep -qE "$UNRESOLVED"; then
    echo "  FAIL $name — 輸出裡有解析失敗的痕跡" >&2
    printf '%s\n' "$out" | grep -E "$UNRESOLVED" | head -3 | sed 's/^/         /' >&2
    FAIL=$((FAIL + 1))
  else
    echo "  PASS $name"
    PASS=$((PASS + 1))
  fi
}

shopt -s nullglob
entries=("$SCRIPTS_DIR"/*.sh)
shopt -u nullglob

if [[ ${#entries[@]} -eq 0 ]]; then
  echo "FAIL $SCRIPTS_DIR 底下一支 .sh 都沒有——那不是通過，是量不到" >&2
  exit 2
fi

for entry in "${entries[@]}"; do
  run_entry "$(basename "$entry")" bash "$entry"
done

# polaris-env.sh 光看 usage 不夠：它壞掉的地方在「拿到 company 之後去哪裡找那份 config」，
# 而那條路只有帶著一個真的存在的 company 才走得到。company 從工作區裡自己有
# workspace-config.yaml 的那幾個目錄推出來——這裡不寫死任何一家公司的名字。
if [[ -n "$WORKSPACE_ROOT" && -f "$SCRIPTS_DIR/polaris-env.sh" ]]; then
  companies=()
  for cfg in "$WORKSPACE_ROOT"/*/workspace-config.yaml; do
    [[ -f "$cfg" ]] || continue
    companies+=("$(basename "$(dirname "$cfg")")")
  done
  if [[ ${#companies[@]} -eq 0 ]]; then
    echo "  SKIP polaris-env.sh status <company> — 這個工作區底下沒有任何 */workspace-config.yaml"
  else
    for company in "${companies[@]}"; do
      run_entry "polaris-env.sh status $company" bash "$SCRIPTS_DIR/polaris-env.sh" status "$company"
    done
  fi
fi

echo "entry-points selftest: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
