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
echo "PASS=$pass FAIL=$fail"
[[ "$fail" -eq 0 ]] || exit 1
echo "PASS: gate-skill-script-references-selftest.sh"
