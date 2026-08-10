#!/usr/bin/env bash
# Purpose: 兩件事。(1) 接上閘的方式是 core.hooksPath 指向版控裡的目錄——git 真的執行的
#          是那份檔案，而不是安裝器複製出去的副本；接上會讓 .git/hooks/ 失效，所以那裡
#          有別人手寫的東西時要指名並停下來。(2) 說 pre-commit／pre-push 各跑什麼的文字，
#          要跟那兩個檔案真的執行的對得上。
# Inputs:  mktemp 底下的假 repo（(1)）與這個 repo 自己（(2)）。
# Outputs: 一行一個 PASS/FAIL，最後一行是總計；有 FAIL 就 exit 1。
#
# 為什麼 (2) 要有機器在看：2026-08-10 量到安裝器寫出來的 pre-push 只跑 run-gates.sh，
# 而 SKILL.md 寫著「全套留給 push」、run-selftests.sh 的 usage 寫著「--all……pre-push 用
# 這個」。一道被兩處文件宣稱存在、實際不存在的檢查，比沒有那道檢查糟——沒有人會去補它。

set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
INSTALLER="$SKILL_DIR/scripts/install-git-hooks.sh"
HOOKS_REL=".claude/skills/framework-release/githooks"
WORK="$(cd "$(mktemp -d -t polaris-dp471.XXXXXX)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()  { echo "PASS $*"; pass=$((pass + 1)); }
bad() { echo "FAIL $*" >&2; fail=$((fail + 1)); }

# Description: 造一棵帶著版控 hook 目錄與安裝器的樹。
# Args: $1 = 名字
# Outputs: repo 路徑
new_repo() {
  local repo="$WORK/$1"
  mkdir -p "$repo/$HOOKS_REL" "$repo/.claude/skills/framework-release/scripts"
  cp "$INSTALLER" "$repo/.claude/skills/framework-release/scripts/"
  cp "$SKILL_DIR/githooks/pre-commit" "$SKILL_DIR/githooks/pre-push" "$repo/$HOOKS_REL/"
  chmod +x "$repo/$HOOKS_REL"/pre-commit "$repo/$HOOKS_REL"/pre-push
  git init -q -b main "$repo"
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name t
  git -C "$repo" add -A
  git -C "$repo" commit -qm base --no-verify
  printf '%s' "$repo"
}

run() {
  RC=0
  OUT="$(bash "$1/.claude/skills/framework-release/scripts/install-git-hooks.sh" \
    --repo "$1" "${@:2}" 2>&1)" || RC=$?
}
hookspath() { git -C "$1" config --get core.hooksPath || echo "（沒設）"; }

# ── 接上：git 用的是版控裡那個目錄，不是 .git/hooks 的副本 ───────────────────
repo="$(new_repo plain)"
run "$repo"
if [[ "$RC" -eq 0 && "$(hookspath "$repo")" == "$HOOKS_REL" ]]; then
  ok "接上之後 core.hooksPath 指向版控裡的目錄"
else
  bad "接上失敗：rc=$RC hooksPath=$(hookspath "$repo") $OUT"
fi
[[ ! -f "$repo/.git/hooks/pre-commit" ]] \
  && ok "沒有把內容複製進 .git/hooks——只有一份，而它在版控裡" \
  || bad "還是往 .git/hooks 寫了一份副本"
run "$repo" --status
printf '%s' "$OUT" | grep -q '已接上' && ok "--status 說得出已接上" || bad "--status 沒說接上狀態：$OUT"

# ── V-P2 的行為面：改版控裡那份，git 下一次跑的就是改後的 ───────────────────
repo="$(new_repo live)"
printf '#!/usr/bin/env bash\necho v1 > "$(git rev-parse --show-toplevel)/witness"\n' \
  > "$repo/$HOOKS_REL/pre-commit"
chmod +x "$repo/$HOOKS_REL/pre-commit"
git -C "$repo" add -A; git -C "$repo" commit -qm v1 --no-verify
run "$repo"
echo a > "$repo/a.txt"; git -C "$repo" add -A
git -C "$repo" commit -qm a >/dev/null 2>&1
[[ "$(cat "$repo/witness" 2>/dev/null)" == v1 ]] \
  && ok "接上之後，版控裡那份真的被 git 執行" || bad "版控裡那份沒有被執行"

printf '#!/usr/bin/env bash\necho v2 > "$(git rev-parse --show-toplevel)/witness"\n' \
  > "$repo/$HOOKS_REL/pre-commit"
chmod +x "$repo/$HOOKS_REL/pre-commit"
git -C "$repo" add -A; git -C "$repo" commit -qm v2 --no-verify
echo b > "$repo/b.txt"; git -C "$repo" add -A
git -C "$repo" commit -qm b >/dev/null 2>&1
[[ "$(cat "$repo/witness" 2>/dev/null)" == v2 ]] \
  && ok "改了版控裡那份就換它跑，不必重跑安裝器" || bad "改了版控裡那份卻還在跑舊的"

# 一個新 clone 接上一次就拿到當前的版本。
git clone -q "$repo" "$WORK/cloned"
git -C "$WORK/cloned" config user.email t@example.com
git -C "$WORK/cloned" config user.name t
rm -f "$WORK/cloned/witness"
run "$WORK/cloned"
echo c > "$WORK/cloned/c.txt"; git -C "$WORK/cloned" add -A
git -C "$WORK/cloned" commit -qm c >/dev/null 2>&1
[[ "$(cat "$WORK/cloned/witness" 2>/dev/null)" == v2 ]] \
  && ok "新 clone 接上一次就拿到當前的版本" || bad "新 clone 拿到的不是當前的版本"

# ── V-N3：接上會讓 .git/hooks 失效，所以別人手寫的東西要被指名並擋下 ─────────
repo="$(new_repo foreign)"
printf '#!/usr/bin/env bash\nexit 0\n' > "$repo/.git/hooks/pre-commit"
chmod +x "$repo/.git/hooks/pre-commit"
run "$repo"
if [[ "$RC" -eq 1 ]] && printf '%s' "$OUT" | grep -q 'pre-commit'; then
  ok "有別人手寫的 hook 就指名並停下來"
else
  bad "別人手寫的 hook 沒有擋：rc=$RC $OUT"
fi
[[ "$(hookspath "$repo")" == "（沒設）" ]] \
  && ok "擋下來的時候什麼都沒改" || bad "擋下來了卻還是設了 core.hooksPath"

# 不是只管 pre-commit / pre-push 那兩個名字——core.hooksPath 讓整個目錄失效。
repo="$(new_repo foreign_other)"
printf '#!/usr/bin/env bash\nexit 0\n' > "$repo/.git/hooks/commit-msg"
chmod +x "$repo/.git/hooks/commit-msg"
run "$repo"
if [[ "$RC" -eq 1 ]] && printf '%s' "$OUT" | grep -q 'commit-msg'; then
  ok "別人手寫的是 commit-msg 也一樣被指名"
else
  bad "只擋了自己管的那兩個名字：rc=$RC $OUT"
fi

# git 自己的 .sample 不算別人手寫的，不然沒有一個新 clone 接得上。
repo="$(new_repo samples_only)"
ls "$repo/.git/hooks"/*.sample >/dev/null 2>&1 || printf '#!/bin/sh\n' > "$repo/.git/hooks/pre-commit.sample"
run "$repo"
[[ "$RC" -eq 0 ]] && ok ".sample 不算別人手寫的" || bad ".sample 被當成別人手寫的：$OUT"

# 這一套自己以前寫進 .git/hooks 的那份接上之後不會被執行，留著會讓人以為閘有兩份。
repo="$(new_repo legacy)"
printf '#!/usr/bin/env bash\n# [polaris-git-hooks]\nexit 0\n' > "$repo/.git/hooks/pre-push"
run "$repo"
if [[ "$RC" -eq 0 && ! -f "$repo/.git/hooks/pre-push" ]]; then
  ok "帶標記的舊層那份會被清掉"
else
  bad "舊層那份沒被清掉：rc=$RC $(ls "$repo/.git/hooks")"
fi

# ── 沒有執行位元的 hook，git 是安靜地跳過——接上去等於什麼都沒接 ─────────────
repo="$(new_repo not_exec)"
chmod -x "$repo/$HOOKS_REL/pre-push"
run "$repo"
if [[ "$RC" -eq 1 ]] && printf '%s' "$OUT" | grep -q 'chmod'; then
  ok "沒有執行位元就拒絕接上，並說得出修法"
else
  bad "沒有執行位元卻接上了：rc=$RC $OUT"
fi
[[ "$(hookspath "$repo")" == "（沒設）" ]] \
  && ok "拒絕的時候 core.hooksPath 沒被設" || bad "拒絕了卻還是設了"

# ── 版控裡沒有那幾個檔＝量不到，不是通過 ────────────────────────────────────
repo="$(new_repo missing)"
rm -f "$repo/$HOOKS_REL/pre-push"
run "$repo"
[[ "$RC" -eq 2 ]] && ok "版控裡少了 hook 時 exit 2（量不到）" || bad "少了 hook 卻不是量不到：rc=$RC $OUT"

# ── 拆掉 ────────────────────────────────────────────────────────────────────
repo="$(new_repo removal)"
run "$repo"
run "$repo" --remove
[[ "$(hookspath "$repo")" == "（沒設）" ]] \
  && ok "--remove 把 core.hooksPath 取消掉" || bad "--remove 沒有取消：$(hookspath "$repo")"

# ── V-N1：說它跑什麼的文字，要跟它真的跑的對得上 ────────────────────────────
# 這一段量的是這個 repo 自己，不是 fixture——會漂的就是這裡的散文。
MODES='--(all|staged|since-base|changed)'

# Description: 一個 hook 檔案真的傳給 run-selftests.sh 的模式旗標。
# Args: $1 = hook 檔案路徑
# Outputs: 一行一個旗標
hook_modes() { grep -oE -e "$MODES" "$1" | sort -u; }

for h in pre-commit pre-push; do
  hook="$SKILL_DIR/githooks/$h"
  modes="$(hook_modes "$hook")"
  if [[ -z "$modes" ]]; then
    bad "${h} 沒有跑 run-selftests.sh 的任何模式——那正是這條要擋的形狀"
    continue
  fi
  for m in $modes; do
    if grep -q "githooks/${h}\`.*${m}" "$SKILL_DIR/SKILL.md"; then
      ok "SKILL.md 說 ${h} 跑 ${m}，而它真的跑 ${m}"
    else
      bad "${h} 真的跑 ${m}，但 SKILL.md 那一列沒有說"
    fi
  done
  # 反過來：那一列上不得出現它其實沒在跑的模式。
  claimed="$(grep "githooks/${h}\`" "$SKILL_DIR/SKILL.md" | grep -oE -e "$MODES" | sort -u)"
  for c in $claimed; do
    printf '%s\n' $modes | grep -qx -e "$c" \
      && ok "SKILL.md 對 ${h} 宣稱的 ${c} 對得上" \
      || bad "SKILL.md 說 ${h} 跑 ${c}，但它沒有"
  done
done

# usage 那一面同一件事：「pre-push 用這個」不得掛在一個 pre-push 沒在用的旗標旁邊。
while IFS= read -r line; do
  who="$(printf '%s' "$line" | grep -oE 'pre-(commit|push) 用這個' | grep -oE 'pre-(commit|push)')"
  flag="$(printf '%s' "$line" | grep -oE -e "$MODES" | head -1)"
  if [[ -z "$flag" ]]; then
    bad "usage 有一行說「${who} 用這個」卻沒有旗標：$line"
  elif hook_modes "$SKILL_DIR/githooks/$who" | grep -qx -e "$flag"; then
    ok "usage 把 ${flag} 標給 ${who}，而 ${who} 真的用它"
  else
    bad "usage 把 ${flag} 標給 ${who}，但 ${who} 沒有用它：$line"
  fi
done < <(grep -E 'pre-(commit|push) 用這個' "$SKILL_DIR/scripts/run-selftests.sh")

# ── V-P4：說明要指名它擋不住什麼，以及誰才是真的在擋 ────────────────────────
# 這一段是靜態檢視那一層（見 verify-ac 的強度表）：它量的是「那一節還在不在、有沒有被寫成
# 安全網」，不是「那幾條列得對不對」——後者只有人讀得出來。它擋的是整節被刪掉或被改寫成
# 一句「本機這一層會擋住問題」的那一種漂移。
SECTION="$(sed -n '/### 它擋不住的那幾條/,/^## /p' "$SKILL_DIR/SKILL.md")"
# 分隔列（`|---|---|`）沒有空白，比不中；比中的是標題列加上每一條，所以條數是 ROWS - 1。
ROWS="$(printf '%s\n' "$SECTION" | grep -c '^| .* | .* |$')"
if [[ "$ROWS" -ge 4 ]]; then
  ok "擋不住的那幾條列了 $((ROWS - 1)) 條"
else
  bad "擋不住的那一節不見了或只剩表頭（表格行數 ${ROWS}）"
fi
printf '%s' "$SECTION" | grep -q -e '--no-verify' \
  && ok "指名了 --no-verify" || bad "沒有指名 --no-verify"
grep -q '不是安全網' "$SKILL_DIR/SKILL.md" \
  && ok "說出它不是安全網" || bad "沒有說出它不是安全網"
grep -q '真正在擋的是' "$SKILL_DIR/SKILL.md" \
  && ok "說得出誰才是真正在擋的那一步" || bad "沒有說出誰才是真正在擋的"

echo "githooks selftest: PASS=${pass} FAIL=${fail}"
[[ "$fail" -eq 0 ]]
