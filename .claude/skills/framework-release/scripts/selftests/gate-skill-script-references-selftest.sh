#!/usr/bin/env bash
# gate-skill-script-references.sh 的 selftest。
#
# 正負兩向都要驗：只驗「乾淨的 repo 會綠」的話，一支永遠回 0 的閘也會全綠。

set -uo pipefail

GATE="$(cd "$(dirname "$0")/.." && pwd)/gate-skill-script-references.sh"
WORK="$(mktemp -d -t polaris-gate-refs-XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

# Description: 比對實際 exit code 與期望值，印一行結果。
# Args: $1 = actual, $2 = expected, $3 = case name
assert_eq() {
  if [[ "$1" == "$2" ]]; then
    echo "  ok  $3"; pass=$((pass + 1))
  else
    echo "  FAIL $3 — want=$2 got=$1"; fail=$((fail + 1))
  fi
}

# Description: 造一個只有 .claude/skills/ 的最小 repo。
# Args: $1 = repo path
make_repo() {
  local repo="$1"
  mkdir -p "$repo/.claude/skills/probe/scripts/lib"
  git -C "$repo" init -q
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name t
}

repo="$WORK/clean"
make_repo "$repo"
cat > "$repo/.claude/skills/probe/scripts/main.sh" <<'EOF'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/helper.sh"
. "$SCRIPT_DIR/lib/shared.sh"
EOF
touch "$repo/.claude/skills/probe/scripts/helper.sh" \
      "$repo/.claude/skills/probe/scripts/lib/shared.sh"
git -C "$repo" add -A && git -C "$repo" commit -qm init
bash "$GATE" --repo "$repo" >/dev/null 2>&1
assert_eq "$?" "0" "引用都在時回 0"

# 反例一：同目錄的檔案不見了
rm "$repo/.claude/skills/probe/scripts/helper.sh"
git -C "$repo" add -A && git -C "$repo" commit -qm "drop helper"
out="$(bash "$GATE" --repo "$repo" 2>&1)"
assert_eq "$?" "1" "同目錄引用斷掉時回 1"
printf '%s' "$out" | grep -q 'helper.sh'
assert_eq "$?" "0" "訊息指名斷掉的那個檔"

# 反例二：lib/ 底下的檔案不見了
repo2="$WORK/broken-lib"
make_repo "$repo2"
cat > "$repo2/.claude/skills/probe/scripts/main.sh" <<'EOF'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/tool-resolution.sh"
EOF
git -C "$repo2" add -A && git -C "$repo2" commit -qm init
bash "$GATE" --repo "$repo2" >/dev/null 2>&1
assert_eq "$?" "1" "lib/ 引用斷掉時回 1"

# 未被版控的檔案不算——閘看的是會被送出去的東西
repo3="$WORK/untracked"
make_repo "$repo3"
touch "$repo3/.claude/skills/probe/scripts/placeholder.sh"
git -C "$repo3" add -A && git -C "$repo3" commit -qm init
cat > "$repo3/.claude/skills/probe/scripts/scratch.sh" <<'EOF'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/nowhere.sh"
EOF
bash "$GATE" --repo "$repo3" >/dev/null 2>&1
assert_eq "$?" "0" "未版控的檔案不參與判定"

# heredoc 裡的東西是要寫到別處的資料，不是這個檔自己的引用——不排掉的話這道閘會擋下
# 自己的 selftest。
repo4="$WORK/heredoc"
make_repo "$repo4"
cat > "$repo4/.claude/skills/probe/scripts/writer.sh" <<'OUTER'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cat > /tmp/generated.sh <<'INNER'
bash "$SCRIPT_DIR/does-not-exist.sh"
INNER
OUTER
git -C "$repo4" add -A && git -C "$repo4" commit -qm init
bash "$GATE" --repo "$repo4" >/dev/null 2>&1
assert_eq "$?" "0" "heredoc 內容不算這個檔的引用"

echo ""

# 變數用 `/..` 定義時，指的是上一層，不是自己那一層。selftest 幾乎都長這樣。
# 這一版之前會把一批寫得完全正確的 selftest 判紅，而那個錯誤被一份重複的檔遮著。
repo="$WORK/parentdir_ok"
make_repo "$repo"
mkdir -p "$repo/.claude/skills/probe/scripts/selftests"
cat > "$repo/.claude/skills/probe/scripts/selftests/x-selftest.sh" <<'EOF'
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resolver="$script_dir/resolver.sh"
EOF
touch "$repo/.claude/skills/probe/scripts/resolver.sh"
git -C "$repo" add -A && git -C "$repo" commit -qm init
bash "$GATE" --repo "$repo" >/dev/null 2>&1
assert_eq "$?" 0 "變數帶 /.. 時往上一層解析，正確的引用不判紅"

# 但往上退之後還是找不到的，仍然要紅——修掉假紅不可以順手修成瞎的。
repo="$WORK/parentdir_broken"
make_repo "$repo"
mkdir -p "$repo/.claude/skills/probe/scripts/selftests"
cat > "$repo/.claude/skills/probe/scripts/selftests/x-selftest.sh" <<'EOF'
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resolver="$script_dir/gone.sh"
EOF
git -C "$repo" add -A && git -C "$repo" commit -qm init
bash "$GATE" --repo "$repo" >/dev/null 2>&1
assert_eq "$?" 1 "往上退之後仍然不存在的引用，還是要紅"

# `--skill` 是 L-P1 的機制：這道閘量的東西有擁有者（一支 skill 的腳本指向自己目錄裡的
# 檔案），所以那一支要能單獨叫它檢查自己。範圍收得對不對要驗兩向——只驗「單支會綠」的話，
# 一個把範圍收成空集合的實作也會綠。
repo="$WORK/skill_scope"
make_repo "$repo"
mkdir -p "$repo/.claude/skills/clean/scripts" "$repo/.claude/skills/broken/scripts"
cat > "$repo/.claude/skills/clean/scripts/ok.sh" <<'EOF'
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/there.sh"
EOF
touch "$repo/.claude/skills/clean/scripts/there.sh"
cat > "$repo/.claude/skills/broken/scripts/bad.sh" <<'EOF'
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/gone.sh"
EOF
git -C "$repo" add -A && git -C "$repo" commit -qm init
bash "$GATE" --repo "$repo" >/dev/null 2>&1
assert_eq "$?" 1 "全掃會看到壞掉的那一支"
bash "$GATE" --repo "$repo" --skill clean >/dev/null 2>&1
assert_eq "$?" 0 "--skill 只看那一支，乾淨的那支是綠的"
bash "$GATE" --repo "$repo" --skill broken >/dev/null 2>&1
assert_eq "$?" 1 "--skill 指到壞掉的那支要紅——範圍不是被收成空集合"
bash "$GATE" --repo "$repo" --skill nosuch >/dev/null 2>&1
assert_eq "$?" 2 "--skill 指到不存在的 skill 是量不到，不是綠"

echo "PASS=$pass FAIL=$fail"
[[ "$fail" -eq 0 ]] || exit 1
echo "PASS: gate-skill-script-references-selftest.sh"
