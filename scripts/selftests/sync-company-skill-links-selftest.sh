#!/usr/bin/env bash
# sync-company-skill-links-selftest.sh
#
# 這支檢查存在的理由：資料夾模式的 skill 執行期看不到，而 routing 散文照樣會把工作分派
# 給它——看起來很順，實際上模型照著一份從未被讀取的程序辦事。所以「有沒有登記」必須是
# 機械可判的，不能靠人記得補 symlink。

set -uo pipefail

# 這支的主體是 git hook 呼叫的，住在 repo 根而不是某支 skill 底下，所以問 git。
ROOT_DIR="$(env -u GIT_DIR -u GIT_WORK_TREE git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/sync-company-skill-links.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fails=0
ok()   { echo "  ok  $1"; }
bad()  { echo "  FAIL  $1" >&2; fails=$((fails+1)); }

# 在暫存樹裡重建一份最小的 repo 形狀，腳本從自己的位置解析 root，所以要連 scripts/ 一起擺
setup_tree() {
  rm -rf "$WORK/repo"
  mkdir -p "$WORK/repo/scripts" "$WORK/repo/.claude/skills"
  cp "$SCRIPT" "$WORK/repo/scripts/"
}

add_skill() {  # $1=namespace/name
  mkdir -p "$WORK/repo/.claude/skills/$1"
  printf -- '---\nname: %s\n---\n內容\n' "$(basename "$1")" \
    > "$WORK/repo/.claude/skills/$1/SKILL.md"
}

run() { bash "$WORK/repo/scripts/sync-company-skill-links.sh" "$@" 2>&1; }

# --- 資料夾模式的 skill 會被登記 ------------------------------------------
setup_tree
add_skill "exampleco/log-search"
out="$(run --check)"; rc=$?
if [[ $rc -eq 2 && "$out" == *POLARIS_COMPANY_SKILL_LINK_DRIFT* ]]; then
  ok "資料夾模式但沒登記 -> DRIFT"
else
  bad "資料夾模式但沒登記，應該 DRIFT（rc=${rc}）"
fi

run >/dev/null
if [[ -L "$WORK/repo/.claude/skills/exampleco-log-search" ]]; then
  ok "apply 建立深度一 symlink"
else
  bad "apply 沒有建立 symlink"
fi

out="$(run --check)"; rc=$?
[[ $rc -eq 0 ]] && ok "補完之後 --check 綠" || bad "補完之後 --check 仍紅（rc=${rc}）"

# --- 別人只放資料夾，不需要知道有 symlink 這回事 ---------------------------
add_skill "exampleco/newcomer"
run >/dev/null
if [[ "$(readlink "$WORK/repo/.claude/skills/exampleco-newcomer")" == "exampleco/newcomer" ]]; then
  ok "新加的資料夾 skill 自動被登記"
else
  bad "新加的資料夾 skill 沒被登記"
fi

# --- 命名空間是自己描述的，不讀設定：換一間公司照樣成立 --------------------
add_skill "otherco/thing"
run >/dev/null
if [[ -L "$WORK/repo/.claude/skills/otherco-thing" ]]; then
  ok "沒登記過的命名空間照樣成立（不讀設定）"
else
  bad "換一個命名空間就失效——表示它在讀某份寫死的清單"
fi

# --- 深度一的實體 skill 不被當成命名空間 -----------------------------------
mkdir -p "$WORK/repo/.claude/skills/plain"
printf -- '---\nname: plain\n---\n' > "$WORK/repo/.claude/skills/plain/SKILL.md"
run >/dev/null
if [[ ! -e "$WORK/repo/.claude/skills/plain-plain" ]]; then
  ok "深度一的實體 skill 不被當命名空間"
else
  bad "深度一的實體 skill 被誤判成命名空間"
fi

# --- 來源消失，登記要跟著消失 ----------------------------------------------
rm -rf "$WORK/repo/.claude/skills/exampleco/newcomer"
run >/dev/null
if [[ ! -e "$WORK/repo/.claude/skills/exampleco-newcomer" ]]; then
  ok "來源刪掉後舊登記被清掉"
else
  bad "來源刪掉後仍留著指向不存在的登記"
fi

# --- references 不是命名空間 ------------------------------------------------
mkdir -p "$WORK/repo/.claude/skills/references"
printf 'x\n' > "$WORK/repo/.claude/skills/references/INDEX.md"
out="$(run)"; rc=$?
if [[ $rc -eq 0 && "$out" != *references-* ]]; then
  ok "references 不被當命名空間"
else
  bad "references 被當成命名空間處理"
fi

if [[ $fails -eq 0 ]]; then
  echo "PASS: sync-company-skill-links-selftest.sh"
  exit 0
fi
echo "FAIL: sync-company-skill-links-selftest.sh ($fails)" >&2
exit 1
