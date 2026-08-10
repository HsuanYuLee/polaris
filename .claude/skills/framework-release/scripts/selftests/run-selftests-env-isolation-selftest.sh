#!/usr/bin/env bash
# Purpose: 證明 run-selftests.sh 借來的環境寫不到借出的那個 repo。git 跑 hook 時環境裡一定
#          有 GIT_DIR，而**顯式的 GIT_DIR 蓋過 `-C`**——一支 selftest 對自己的 fixture 樹下
#          `git -C "$d" config ...`，寫進去的會是真的那個 repo 的 .git/config。
# Inputs:  mktemp 底下兩個一次性的 repo（借出方）與一棵假的 skill 樹（借用方），不碰真 repo。
# Outputs: PASS 當「不設防的時候真的會弄髒」與「經過 run-selftests 就弄不髒」兩件事都成立。
#
# 為什麼要先證明會弄髒：一個根本沒注入成功的環境，跟一個注入了但被擋住的環境，在「repo 沒
# 被動到」這件事上長得一模一樣。少了正向控制，這支永遠是綠的，而它什麼都沒量到。
# 2026-08-10 的實際損害：32 個 commit 的作者被寫成 `t <t@t>`，工作區索引從 499 個檔清成 2 個。

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT_DIR/scripts/run-selftests.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
fail() { echo "FAIL: $*" >&2; exit 1; }
unmeasurable() { echo "UNMEASURABLE: $*" >&2; exit 2; }
ok()   { echo "  ok  $*"; PASS=$((PASS + 1)); }

# Description: 造一個乾淨的一次性 repo 當「借出方」，回傳它的路徑。
# Args: $1 = 名字
new_victim() {
  local dir="$WORK/$1"
  git init -q "$dir"
  git -C "$dir" config user.email victim@example.com
  git -C "$dir" config user.name victim
  echo seed > "$dir/seed.txt"
  git -C "$dir" add seed.txt
  git -C "$dir" commit -qm seed
  printf '%s' "$dir"
}

# Description: 借出方現在的樣子——設定、HEAD、索引三樣一起。回一行指紋。
# Args: $1 = repo 路徑
fingerprint() {
  local dir="$1"
  {
    shasum "$dir/.git/config" | awk '{print $1}'
    git -C "$dir" rev-parse HEAD
    shasum "$dir/.git/index" 2>/dev/null | awk '{print $1}'
  } | shasum | awk '{print $1}'
}

# 借用方：一棵最小的 skill 樹，裡面一支刻意做那件會出事的事的 selftest。
CANARY_MARK="canary-should-never-land-here@example.com"
FAKE="$WORK/fake-workspace"
mkdir -p "$FAKE/.claude/skills/canary/scripts/selftests"
cat > "$FAKE/.claude/skills/canary/scripts/selftests/canary-selftest.sh" <<EOF
#!/usr/bin/env bash
# 這支刻意複製 2026-08-10 出事的那個形狀：開一棵自己的 fixture 樹，然後對它寫 git 設定。
# 環境裡有 GIT_DIR 的時候，這幾行寫進去的是 GIT_DIR 指到的那個 repo，不是 \$d。
set -uo pipefail
d="\$(mktemp -d)"
git init -q "\$d" 2>/dev/null
git -C "\$d" config user.email '$CANARY_MARK'
git -C "\$d" config user.name canary
rm -rf "\$d"
exit 0
EOF
chmod +x "$FAKE/.claude/skills/canary/scripts/selftests/canary-selftest.sh"
CANARY="$FAKE/.claude/skills/canary/scripts/selftests/canary-selftest.sh"

echo "run-selftests env isolation selftest"

# 一、正向控制：不設防的時候，那支 canary 真的弄髒借出方。
# 這一步不成立的話整支是量不到，不是通過——注入沒發生的話，下面那一步的綠燈不承載資訊。
victim="$(new_victim victim-unprotected)"
before="$(fingerprint "$victim")"
GIT_DIR="$victim/.git" GIT_WORK_TREE="$victim" bash "$CANARY" >/dev/null 2>&1
after="$(fingerprint "$victim")"
if [[ "$before" == "$after" ]]; then
  unmeasurable "注入沒有生效：直接跑 canary 也沒弄髒 $victim。這一輪什麼都沒量到，" \
    "不是通過——可能是這個 git 版本不再讓顯式 GIT_DIR 蓋過 -C，那樣的話這支要重寫。"
fi
# 指紋變了還不夠：`git init -q "$d"` 在 GIT_DIR 之下自己就會去重初始化借出方，所以光看
# 指紋分不出「設定被寫進去了」與「只是被 re-init 了」。要看到那個標記才算注入成形。
grep -Fq "$CANARY_MARK" "$victim/.git/config" \
  || unmeasurable "借出方變了，但變的不是那個 canary 標記——注入的形狀跟預期的不一樣"
ok "注入是真的：不設防的時候，一支 selftest 的 fixture 設定落進了借出方的 .git/config"

# 二、真正要問的事：同一支 canary 經過 run-selftests.sh，借出方一個位元都不能變。
victim="$(new_victim victim-protected)"
before="$(fingerprint "$victim")"
out="$(GIT_DIR="$victim/.git" GIT_WORK_TREE="$victim" \
       bash "$RUNNER" --repo "$FAKE" --all 2>&1)"
rc=$?
after="$(fingerprint "$victim")"

[[ "$rc" -eq 0 ]] || fail "run-selftests 應該把那支 canary 跑成綠的；拿到 ${rc}：$out"
grep -Fq '跑了 1 支 selftest' <<<"$out" \
  || fail "那支 canary 沒有真的被跑到——沒跑過的東西擋不擋得住量不出來：$out"
# 判準是「那支刻意會寫的 fixture 被擋住了」，不是「這一輪跑到的 selftest 剛好都沒寫」。
# 假的 skill 樹裡只有 canary 一支，所以「跑了 1 支」就是它被跑到了。
ok "那支刻意會弄髒的 canary 真的被跑到了"
grep -Fq "$CANARY_MARK" "$victim/.git/config" \
  && fail "canary 的設定落進了借出方的 .git/config——保護沒有生效"
[[ "$before" == "$after" ]] \
  || fail "借出方被動到了（設定、HEAD 或索引其中之一變了）"
ok "經過 run-selftests，借出方的設定、HEAD 與索引一個位元都沒變"

echo "PASS: run-selftests env isolation（$PASS 項）"
