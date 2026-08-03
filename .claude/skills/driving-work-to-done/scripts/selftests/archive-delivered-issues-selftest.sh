#!/usr/bin/env bash
# Selftest for archive-delivered-issues.sh —— 每個 case 都先做出一個已知的落差再看它抓不抓得到。

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/archive-delivered-issues.sh"
tmp="$(mktemp -d)"
trap 'status=$?; rm -rf "$tmp"; exit $status' EXIT

pass=0
fail=0

# fixture：兩個命名空間。ns-a 有一張還開著的 A、一張已收斂的 B；ns-b 只有一張開著的 C。
# 命名空間刻意取不帶意義的名字——判定不該從名字推導任何東西。
reset_fixture() {
  rm -rf "$tmp/issues"
  mkdir -p "$tmp/issues/ns-a/A/.spine" "$tmp/issues/ns-a/B/.spine" "$tmp/issues/ns-b/C/.spine"
  echo '# A' > "$tmp/issues/ns-a/A/index.md"
  echo '# B' > "$tmp/issues/ns-a/B/index.md"
  echo '# C' > "$tmp/issues/ns-b/C/index.md"
  echo '{"status": "open"}'      > "$tmp/issues/ns-a/A/.spine/loop-state.json"
  echo '{"status": "converged"}' > "$tmp/issues/ns-a/B/.spine/loop-state.json"
  echo '{"status": "open"}'      > "$tmp/issues/ns-b/C/.spine/loop-state.json"
  git -C "$tmp/issues" init -q
  git -C "$tmp/issues" config user.email t@t; git -C "$tmp/issues" config user.name t
  git -C "$tmp/issues" add -A; git -C "$tmp/issues" commit -qm init
}

check() {
  local name="$1" want="$2" needle="${3:-}" mode="${4:---check}"
  local out rc
  out="$(bash "$SCRIPT" --issues "$tmp/issues" $mode 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" != "$want" ]]; then
    echo "FAIL $name: 期待 exit ${want}，實際 ${rc}"; echo "$out" | sed 's/^/     /'; fail=$((fail+1)); return
  fi
  if [[ -n "$needle" && "$out" != *"$needle"* ]]; then
    echo "FAIL $name: 訊息裡沒有 '${needle}'"; echo "$out" | sed 's/^/     /'; fail=$((fail+1)); return
  fi
  echo "PASS $name"; pass=$((pass+1))
}

reset_fixture
check "已收斂卻還在活躍區時 --check 回 1" 1 "ns-a/B 已經收斂，卻還在活躍區"

reset_fixture
bash "$SCRIPT" --issues "$tmp/issues" >/dev/null
check "搬過之後 --check 回 0" 0 "ARCHIVE-IN-SYNC"
[[ -f "$tmp/issues/ns-a/archive/B/index.md" ]] && { echo "PASS B 進了自己命名空間的 archive/"; pass=$((pass+1)); } \
  || { echo "FAIL B 沒進 ns-a/archive/"; fail=$((fail+1)); }
[[ -f "$tmp/issues/ns-a/A/index.md" && -f "$tmp/issues/ns-b/C/index.md" ]] \
  && { echo "PASS 沒收斂的兩張都留在原處"; pass=$((pass+1)); } \
  || { echo "FAIL 動到了沒收斂的單"; fail=$((fail+1)); }
[[ ! -d "$tmp/issues/ns-b/archive" ]] && { echo "PASS 沒東西要歸檔的命名空間不會被建出空 archive/"; pass=$((pass+1)); } \
  || { echo "FAIL ns-b 被建了不必要的 archive/"; fail=$((fail+1)); }

# 反向：沒收斂的東西被手動放進 archive/，位置與狀態就對不上了。
reset_fixture
mkdir -p "$tmp/issues/ns-a/archive"
git -C "$tmp/issues" mv ns-a/A ns-a/archive/A
check "archive 裡有還沒收斂的東西時 --check 回 1" 1 "ns-a/archive/A 還沒收斂"

reset_fixture
mkdir -p "$tmp/issues/ns-a/archive"
git -C "$tmp/issues" mv ns-a/A ns-a/archive/A
bash "$SCRIPT" --issues "$tmp/issues" >/dev/null
[[ -f "$tmp/issues/ns-a/A/index.md" ]] && { echo "PASS A 被搬回自己命名空間的活躍區"; pass=$((pass+1)); } \
  || { echo "FAIL A 沒被搬回去"; fail=$((fail+1)); }

# 沒有輪次狀態的目錄不參與判定——舊層搬進來的知識與還沒開輪次的種子都長這樣。
reset_fixture
mkdir -p "$tmp/issues/ns-a/archive/legacy" "$tmp/issues/ns-b/seed"
echo '# legacy' > "$tmp/issues/ns-a/archive/legacy/index.md"
echo '# seed'   > "$tmp/issues/ns-b/seed/index.md"
bash "$SCRIPT" --issues "$tmp/issues" >/dev/null
[[ -d "$tmp/issues/ns-a/archive/legacy" && -d "$tmp/issues/ns-b/seed" ]] \
  && { echo "PASS 沒有輪次狀態的目錄兩邊都沒被動到"; pass=$((pass+1)); } \
  || { echo "FAIL 動到了不參與判定的目錄"; fail=$((fail+1)); }

# 第三態不可以安靜：不參與判定的數量一定要印出來。
reset_fixture
mkdir -p "$tmp/issues/ns-a/archive/legacy"
echo '# legacy' > "$tmp/issues/ns-a/archive/legacy/index.md"
bash "$SCRIPT" --issues "$tmp/issues" >/dev/null
check "不參與判定的數量有被印出來" 0 "archive 1 個"

# 傳錯一層的根要在動任何東西之前被擋下來。2026-08-03 沒擋，於是 archive 被當成一個命名
# 空間，底下每一張已歸檔的單都被搬進 archive/archive/——103 個檔案，全程沒有一個字。
reset_fixture
mkdir -p "$tmp/issues/ns-a/archive/A2"
echo '# a2' > "$tmp/issues/ns-a/archive/A2/index.md"
mkdir -p "$tmp/issues/ns-a/archive/A2/.spine"
echo '{"status":"converged","rounds":[]}' > "$tmp/issues/ns-a/archive/A2/.spine/loop-state.json"
rc=0; out="$(bash "$SCRIPT" --issues "$tmp/issues/ns-a" 2>&1)" || rc=$?
if [[ "$rc" -ne 0 && "$out" == *"這不是 issues 根"* && ! -d "$tmp/issues/ns-a/archive/archive" ]]; then
  echo "PASS 傳進命名空間當根時擋下來，而且沒有搬任何東西"; pass=$((pass+1))
else
  # 中文全形括號緊接變數時要用 ${}，不然 bash 會把它吃進變數名。
  echo "FAIL 錯的根沒被擋（rc=${rc}）：$out"; fail=$((fail+1))
fi

echo "archive-delivered-issues selftest: PASS=$pass FAIL=$fail"
[[ "$fail" == 0 ]]
