#!/usr/bin/env bash
# release-tail-resumability-selftest.sh — 量釋出尾段被打斷之後接不接得回去（DP-500）。
#
# 兩件事在 2026-08-10 釋出 v4.23.0 那一趟真的發生，而它們的形狀跟 DP-499 那三件一樣：
# 一個狀態被回報成另一個狀態，然後那句話會讓讀的人去做一件沒有用的事。
#
#   呼叫者站的地方不是 repo 根 → 「這張單沒有 index.md」
#   這條分支已經併進去了       → 「你還沒開 PR」
#
# 所以這裡量的是**訊息說的是不是實際發生的那件事**，以及交出去的那條路徑換一個工作目錄
# 開不開得到。不打真實 remote，不呼叫 gh。
set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE="$SCRIPTS/spine-release.sh"

EXPECTED=6
RAN=0
FAILED=0
pass() { RAN=$((RAN + 1)); printf 'PASS  %s\n' "$1"; }
fail() { RAN=$((RAN + 1)); FAILED=$((FAILED + 1)); printf 'FAIL  %s\n    %s\n' "$1" "${2:-}"; }

[[ -f "$RELEASE" ]] || { printf 'INCONCLUSIVE：量不到——%s 不在\n' "$RELEASE" >&2; exit 2; }

# `-P`：macOS 的 mktemp 給 /var/…，那是 /private/var/… 的 symlink。這一支比的是路徑字面。
WORK="$(cd "$(mktemp -d -t polaris-dp500.XXXXXX)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

# Description: build a repo with a main branch, an origin that tracks it, and a fixture ticket.
# Args:        $1 = directory to create the repo in.
# Side effects: creates the repo, a bare origin, and issues/ns/TICKET/index.md.
build_repo() {
  local repo="$1" bare="$1.git"
  git init -q --bare "$bare"
  mkdir -p "$repo/issues/ns/TICKET"
  printf 'a ticket\n' > "$repo/issues/ns/TICKET/index.md"
  git -C "$repo" init -q
  git -C "$repo" config user.email selftest@example.test
  git -C "$repo" config user.name "Self Test"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m base
  git -C "$repo" branch -M main
  git -C "$repo" remote add origin "$bare"
  git -C "$repo" push -q -u origin main
}

REPO="$WORK/repo"
build_repo "$REPO"

# ── S-P1：交出去的那條路徑，換一個工作目錄照樣開得到 ────────────────────────
# 從一個跟 repo 無關的目錄問尾段「你會把哪一條路徑交出去」，然後真的拿它去開檔案。
handed="$( (cd "$WORK" && bash "$RELEASE" --repo "$REPO" --issue issues/ns/TICKET --issue-path) 2>&1 )"
if [[ "$handed" == /* ]]; then
  pass "S-P1 交出去的是一條絕對路徑，不是相對於呼叫者的"
else
  fail "S-P1 交出去的是一條絕對路徑，不是相對於呼叫者的" "拿到的是：${handed:-（空的）}"
fi

if (cd / && [[ -f "$handed/index.md" ]]); then
  pass "S-P1 從一個完全無關的工作目錄，那條路徑照樣開得到那張單"
else
  fail "S-P1 從一個完全無關的工作目錄，那條路徑照樣開得到那張單" "$handed/index.md 開不到"
fi

# S-N2：交出去的東西不得靠呼叫者站的地方補位——換一個 cwd 再問一次，答案必須一模一樣。
elsewhere="$( (cd "$REPO" && bash "$RELEASE" --repo "$REPO" --issue issues/ns/TICKET --issue-path) 2>&1 )"
# 「兩次一樣」單獨拿出來是會空過的：兩次都吐同一句錯誤訊息也一樣。所以連同「它是一條
# 開得到的路徑」一起要求——不然這一條在什麼都沒改的樹上也是綠的。
if [[ "$elsewhere" == "$handed" && -f "$elsewhere/index.md" ]]; then
  pass "S-N2 換一個工作目錄再問一次，交出去的路徑不變（而且仍然開得到）"
else
  fail "S-N2 換一個工作目錄再問一次，交出去的路徑不變（而且仍然開得到）" "$handed vs $elsewhere"
fi

# ── S-P2 / S-N1：已經併進去的分支不是「還沒開 PR」 ──────────────────────────
# 造一條真的併進 main 也推上去的分支，再造一條沒有的。
git -C "$REPO" checkout -q -b merged-branch
printf 'x\n' > "$REPO/x.txt"
git -C "$REPO" add -A && git -C "$REPO" commit -q -m x
git -C "$REPO" checkout -q main
git -C "$REPO" merge -q --no-ff -m merge merged-branch
git -C "$REPO" push -q origin main

git -C "$REPO" checkout -q -b unmerged-branch
printf 'y\n' > "$REPO/y.txt"
git -C "$REPO" add -A && git -C "$REPO" commit -q -m y
git -C "$REPO" checkout -q main

out="$(bash "$RELEASE" --repo "$REPO" --branch-in-base merged-branch 2>&1)"
if [[ "$out" == "yes" ]]; then
  pass "S-P2 已經併進 origin/main 的分支，尾段答得出「它已經在裡面了」"
else
  fail "S-P2 已經併進 origin/main 的分支，尾段答得出「它已經在裡面了」" "拿到的是：$out"
fi

out="$(bash "$RELEASE" --repo "$REPO" --branch-in-base unmerged-branch 2>&1)"
if [[ "$out" == "no" ]]; then
  pass "S-N1 沒有併進去的分支不會被說成已經在裡面了"
else
  fail "S-N1 沒有併進去的分支不會被說成已經在裡面了" "拿到的是：$out"
fi

# S-N1 的另一半：那個判斷真的接在拒絕的那條路徑上，而不是只有 probe 問得到它。
# 兩者都要——只有 probe 的話，尾段自己那一段可以完全沒改而這支全綠。
if grep -q 'if branch_in_base "\$BRANCH" "origin/main"; then' "$RELEASE" \
   && grep -q '既沒有 open PR，內容也不在 origin/main 裡' "$RELEASE"; then
  pass "S-N1 沒有 open PR 時的拒絕路徑上真的接了那個判斷"
else
  fail "S-N1 沒有 open PR 時的拒絕路徑上真的接了那個判斷" "找不到那個分支"
fi

printf -- '---\n'
if [[ "$RAN" -ne "$EXPECTED" ]]; then
  printf 'INCONCLUSIVE：預期 %s 條，實際跑了 %s 條——量不到不是通過。\n' "$EXPECTED" "$RAN" >&2
  exit 2
fi
printf 'release tail resumability：%s 條，紅 %s 條。\n' "$EXPECTED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
