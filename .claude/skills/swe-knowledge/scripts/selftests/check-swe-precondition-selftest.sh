#!/usr/bin/env bash
# Purpose: 證明開工條件不會把「量不到」讀成「沒問題」，而且它認的是 remote 說的預設分支，
#          不是寫死的 main。
# Inputs:  mktemp 底下的假 repo。
# Outputs: PASS 當站在預設分支上變紅、換到 branch 上變綠、解不出預設分支變紅、
#          detached HEAD 變紅、非 git 目錄變紅，而且預設分支叫 develop 時一樣判得出來。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK="$ROOT_DIR/scripts/check-swe-precondition.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()  { echo "PASS $*"; PASS=$((PASS + 1)); }
bad() { echo "FAIL $*" >&2; FAIL=$((FAIL + 1)); }

# Description: 造一個 repo，預設分支叫 $2，並把 origin/HEAD 指過去。
# Args: $1 = case 名字, $2 = 預設分支名
new_repo() {
  local repo="$WORK/$1" default="$2"
  mkdir -p "$repo"
  git init -q -b "$default" "$repo"
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name t
  echo x > "$repo/f.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -qm base
  git -C "$repo" remote add origin "$repo"
  git -C "$repo" symbolic-ref refs/remotes/origin/HEAD "refs/heads/$default"
  printf '%s' "$repo"
}

run() { RC=0; OUT="$(bash "$CHECK" "$@" 2>&1)" || RC=$?; }

repo="$(new_repo on_default main)"
run --repo "$repo"
if [[ "$RC" -eq 0 ]]; then
  bad "站在預設分支上卻放行"
elif printf '%s' "$OUT" | grep -q '開工條件不成立'; then
  ok "站在預設分支上被擋"
else
  bad "擋了但沒說清楚：$OUT"
fi
printf '%s' "$OUT" | grep -q 'git switch -c' \
  && ok "拒絕的訊息說得出修法" || bad "拒絕沒有說修法：$OUT"

git -C "$repo" switch -q -c feat/x
run --repo "$repo"
[[ "$RC" -eq 0 ]] && ok "換到 branch 上就放行" || bad "在 branch 上卻被擋：$OUT"

# 預設分支寫死 main 的話，這個 repo 會一路綠而其實一條都沒查。
repo="$(new_repo develop_default develop)"
run --repo "$repo"
if [[ "$RC" -eq 0 ]]; then
  bad "預設分支叫 develop 時放行了——這一版把 main 寫死了"
else
  ok "預設分支叫 develop 一樣判得出來"
fi

# 解不出預設分支＝量不到。負向斷言的儀器天生會把它讀成沒問題。
repo="$(new_repo no_head main)"
git -C "$repo" symbolic-ref -d refs/remotes/origin/HEAD
run --repo "$repo"
if [[ "$RC" -eq 0 ]]; then
  bad "解不出預設分支卻放行——量不到被讀成沒問題了"
elif printf '%s' "$OUT" | grep -q '量不到'; then
  ok "解不出預設分支時說出自己量不到，並且不放行"
else
  bad "沒說出是量不到：$OUT"
fi

repo="$(new_repo detached main)"
git -C "$repo" switch -q -c tmp && git -C "$repo" switch -q --detach HEAD
run --repo "$repo"
[[ "$RC" -ne 0 ]] && ok "detached HEAD 不放行" || bad "detached HEAD 放行了"

mkdir -p "$WORK/not_a_repo"
run --repo "$WORK/not_a_repo"
if [[ "$RC" -ne 0 ]] && printf '%s' "$OUT" | grep -q '不在 git repo'; then
  ok "不在 git repo 裡不放行，而且說得出原因"
else
  bad "非 git 目錄的處理不對：rc=$RC $OUT"
fi

# 有幾個落腳處就判幾次。核心把這張單宣告的那幾個地方原樣接在宣告的命令後面，所以位置參數
# 與 --repo 等價。少了這一段的話，一張改三個產品 repo 的單會被拿 workspace 自己的分支去判
# ——那個判定跟改動落在哪裡完全無關（同事在一張跨 repo 的單上撞到）。
multi_a="$(new_repo multi_a main)"; git -C "$multi_a" switch -q -c feat/a
multi_b="$(new_repo multi_b main)"; git -C "$multi_b" switch -q -c feat/b

RC=0; OUT="$(bash "$CHECK" "$multi_a" "$multi_b" 2>&1)" || RC=$?
if [[ "$RC" -eq 0 ]] && [[ "$(printf '%s\n' "$OUT" | grep -c 'SWE-PRECONDITION-OK')" -eq 2 ]]; then
  ok "指名幾個就判幾個，每一個各印一行"
else
  bad "多個落腳處沒有逐個判：rc=$RC $OUT"
fi

RC=0; OUT="$(bash "$CHECK" --repo "$multi_a" --repo "$multi_b" 2>&1)" || RC=$?
[[ "$RC" -eq 0 ]] && ok "--repo 給很多次與位置參數等價" \
  || bad "--repo 給很多次卻不通過：rc=$RC $OUT"

# 有一個站在預設分支上就要整體紅。放行「三個裡有兩個對」，等於第三個地方的改動從第一個
# commit 起就沒被任何條件管過。
multi_c="$(new_repo multi_c main)"
RC=0; OUT="$(bash "$CHECK" "$multi_a" "$multi_c" 2>&1)" || RC=$?
[[ "$RC" -ne 0 ]] && ok "有一個站在預設分支上就整體不放行" \
  || bad "有一個站在預設分支上卻放行了：$OUT"

# 其中一個根本不是 repo，或處在 detached HEAD——都是「量不到」，而量不到不是通過。
RC=0; OUT="$(bash "$CHECK" "$multi_a" "$WORK/not-a-repo-at-all" 2>&1)" || RC=$?
[[ "$RC" -ne 0 ]] && ok "其中一個不是 git repo 就整體不放行" \
  || bad "其中一個不是 git repo 卻放行了：$OUT"

multi_d="$(new_repo multi_d main)"; git -C "$multi_d" checkout -q --detach
RC=0; OUT="$(bash "$CHECK" "$multi_a" "$multi_d" 2>&1)" || RC=$?
[[ "$RC" -ne 0 ]] && ok "其中一個是 detached HEAD 就整體不放行" \
  || bad "其中一個是 detached HEAD 卻放行了：$OUT"

# 一個地方都沒被指名時要說「量不到」，不得改用「我現在站在哪」當答案。退回 pwd 的那一版
# 對「單住在 A、程式碼落在 B」的單永遠在判 A，而 A 幾乎總是通過。
RC=0; OUT="$(bash "$CHECK" 2>&1)" || RC=$?
if [[ "$RC" -ne 0 ]] && printf '%s' "$OUT" | grep -q '沒有任何地方被指名'; then
  ok "一個地方都沒被指名就回非 0，不從 cwd 猜"
else
  bad "沒有指名任何地方卻自己找了一個來判：rc=$RC $OUT"
fi

# ── 第二條：宣告出來的版控 hook 目錄，git 真的在用嗎 ─────────────────────────
# 沒接上的 checkout，它的每個 commit 與每次 push 一道閘都不會跑，而且不會有任何東西說。
# 這是只有開工前擋得住的那一種——發現的時候那些 commit 已經在歷史裡了。

HOOKS_REL="scripts/githooks"

# Description: 造一個宣告了版控 hook 目錄的 repo（已經站在 feature 分支上）。
# Args: $1 = case 名字
# Outputs: repo 路徑
new_declared_repo() {
  local repo; repo="$(new_repo "$1" main)"
  mkdir -p "$repo/$HOOKS_REL" "$repo/.claude/skills/framework-release"
  printf '# framework-release\n<!-- POLARIS-GIT-HOOKS: %s | bash 接上它的那支腳本 -->\n' \
    "$HOOKS_REL" > "$repo/.claude/skills/framework-release/SKILL.md"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$repo/$HOOKS_REL/pre-commit"
  chmod +x "$repo/$HOOKS_REL/pre-commit"
  git -C "$repo" switch -q -c feat/hooks
  printf '%s' "$repo"
}

repo="$(new_declared_repo hooks_connected)"
git -C "$repo" config core.hooksPath "$HOOKS_REL"
run --repo "$repo"
if [[ "$RC" -eq 0 ]] && printf '%s' "$OUT" | grep -q 'hook：已接上'; then
  ok "接上了就放行，並且說出接的是哪一個目錄"
else
  bad "接上了卻沒放行或沒說：rc=$RC $OUT"
fi

repo="$(new_declared_repo hooks_unset)"
run --repo "$repo"
if [[ "$RC" -ne 0 ]] && printf '%s' "$OUT" | grep -q '沒有在用它'; then
  ok "宣告了卻沒接上：不開輪次"
else
  bad "沒接上卻放行了：rc=$RC $OUT"
fi
printf '%s' "$OUT" | grep -q '修法：bash 接上它的那支腳本' \
  && ok "拒絕的訊息說得出怎麼接上（命令來自宣告，不是寫死的）" \
  || bad "拒絕沒有說怎麼接上：$OUT"

repo="$(new_declared_repo hooks_elsewhere)"
git -C "$repo" config core.hooksPath /tmp/somewhere-else
run --repo "$repo"
[[ "$RC" -ne 0 ]] && ok "core.hooksPath 指到別的地方也不算接上" \
  || bad "指到別的地方卻放行了：$OUT"

# 沒有執行位元的 hook，git 是安靜地跳過——接上了跟沒接一樣。
repo="$(new_declared_repo hooks_not_exec)"
git -C "$repo" config core.hooksPath "$HOOKS_REL"
chmod -x "$repo/$HOOKS_REL/pre-commit"
run --repo "$repo"
if [[ "$RC" -ne 0 ]] && printf '%s' "$OUT" | grep -q '執行位元'; then
  ok "hook 沒有執行位元＝沒接上，指名那個檔並不放行"
else
  bad "沒有執行位元卻放行了：rc=$RC $OUT"
fi

# 問不到閘的狀態就拒絕。宣告指向一個不存在的目錄，是這一類裡唯一在 fixture 裡造得出來的
# 形狀——另一種（core.hooksPath 讀不出來）需要一份壞掉的 .git/config，而那會讓更前面的
# rev-parse 先炸掉，所以它在程式碼裡守著、但這裡量不到它。
repo="$(new_declared_repo hooks_dir_gone)"
git -C "$repo" config core.hooksPath "$HOOKS_REL"
rm -rf "$repo/$HOOKS_REL"
run --repo "$repo"
if [[ "$RC" -ne 0 ]] && printf '%s' "$OUT" | grep -q '量不到'; then
  ok "宣告指向不存在的目錄：說出量不到，並且不放行"
else
  bad "宣告指向空氣卻放行了：rc=$RC $OUT"
fi

# 沒有宣告的工作區（多數產品 repo）這一條不適用，而且要把不適用印出來——一個安靜的第三態
# 下一次會被當成查過了。
repo="$(new_repo no_declaration main)"; git -C "$repo" switch -q -c feat/x
run --repo "$repo"
if [[ "$RC" -eq 0 ]] && printf '%s' "$OUT" | grep -q '這一條不適用'; then
  ok "沒有宣告 hook 目錄的工作區：放行，而且說出這一條不適用"
else
  bad "不適用沒有被印出來：rc=$RC $OUT"
fi

echo "check-swe-precondition selftest: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
