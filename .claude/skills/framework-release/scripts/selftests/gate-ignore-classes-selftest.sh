#!/usr/bin/env bash
# Selftest for gate-ignore-classes.sh —— 每個 case 都先把 fixture 做壞再看它會不會紅。
# 一支新寫的檢查第一次就綠是「規則太窄」的訊號，不是好消息。

set -euo pipefail

GATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/gate-ignore-classes.sh"
tmp="$(mktemp -d)"
trap 'status=$?; rm -rf "$tmp"; exit $status' EXIT

pass=0
fail=0

# 每個 case 都從同一份乾淨 fixture 出發：一個被版控的檔、一個被忽略且歸得到類的檔。
reset_fixture() {
  rm -rf "$tmp/repo"
  mkdir -p "$tmp/repo/cache"
  git -C "$tmp/repo" init -q
  git -C "$tmp/repo" config user.email t@t; git -C "$tmp/repo" config user.name t
  echo hi > "$tmp/repo/kept.txt"
  echo junk > "$tmp/repo/cache/out.bin"
  cat > "$tmp/repo/.gitignore" <<'GI'
# === class: regenerable ===
/cache/
GI
  git -C "$tmp/repo" add kept.txt .gitignore
  git -C "$tmp/repo" commit -qm init
}

# 跑一次閘，比對 exit code 與（可選的）訊息片段。
check() {
  local name="$1" want="$2" needle="${3:-}"
  local out rc
  out="$(bash "$GATE" --repo "$tmp/repo" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" != "$want" ]]; then
    echo "FAIL $name: 期待 exit ${want}，實際 ${rc}"; echo "$out" | sed 's/^/     /'; fail=$((fail+1)); return
  fi
  if [[ -n "$needle" && "$out" != *"$needle"* ]]; then
    echo "FAIL $name: 訊息裡沒有 '${needle}'"; echo "$out" | sed 's/^/     /'; fail=$((fail+1)); return
  fi
  echo "PASS $name"; pass=$((pass+1))
}

reset_fixture
check "乾淨的 fixture 回 0" 0

reset_fixture
printf '/gone-mechanism/\n' >> "$tmp/repo/.gitignore"
check "規則指向不存在的東西時回 1" 1 "gone-mechanism"

reset_fixture
# 要放在第一個標頭「之前」才是無分類——接在最後一個標頭後面等於歸進那一類。
mkdir -p "$tmp/repo/cache2"; echo x > "$tmp/repo/cache2/f"
printf '/cache2/\n%s' "$(cat "$tmp/repo/.gitignore")" > "$tmp/repo/.gitignore.new"
mv "$tmp/repo/.gitignore.new" "$tmp/repo/.gitignore"
check "規則不在分類標頭底下時回 1" 1 "不在任何分類標頭底下"

reset_fixture
printf '# === class: whatever ===\n/cache/\n' >> "$tmp/repo/.gitignore"
check "未宣告的分類名回 1" 1 "未宣告的分類"

reset_fixture
printf '# === class: recurring ===\n.DS_Store\n' >> "$tmp/repo/.gitignore"
check "recurring 的規則不需要目標存在" 0

reset_fixture
mkdir -p "$tmp/repo/hidden"; echo x > "$tmp/repo/hidden/f"
printf 'hidden/\n' >> "$tmp/repo/.git/info/exclude"
check "被 .gitignore 以外的來源藏起來時回 1" 1 "不在 .gitignore 的分類裡"

echo "gate-ignore-classes selftest: PASS=$pass FAIL=$fail"
[[ "$fail" == 0 ]]
