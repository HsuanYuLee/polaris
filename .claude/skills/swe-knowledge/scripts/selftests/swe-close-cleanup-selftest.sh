#!/usr/bin/env bash
# Purpose: 證明一張單不做了之後，它自己的痕跡真的被收掉——而**還活著的東西一律不動**。
# Inputs:  mktemp 底下的真 git repo（刻意造出兩種 branch：已併入的、有未併入 commit 的），
#          加上 PATH 最前面一支記下 argv 的 gh 樁。
# Outputs: PASS 當已併入的 branch 被刪、有未併入 commit 的被留下並列出來且非 0、PR 被關掉
#          且帶了復原路徑、關不掉是量不到、沒有 gh 是量不到。
#
# 為什麼刻意造殘留（D-N5）：判準是「造出來的殘留被收掉了」，不是「這一輪剛好乾淨」。一個
# 沒有殘留的環境跟一個收尾壞掉的環境，在「現在沒有殘留」這件事上長得一模一樣。

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CLEANUP="$ROOT_DIR/scripts/swe-close-cleanup.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok  $*"; PASS=$((PASS + 1)); }

# gh 樁：`pr list` 回 $FAKE_GH_PRS 裡的號碼，`pr close` 把 argv 記下來並回 $FAKE_GH_CLOSE_RC。
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "pr list")  printf '%s' "${FAKE_GH_PRS:-}" ;;
  "pr close") printf '%s\n' "$*" >> "$FAKE_GH_LOG"; exit "${FAKE_GH_CLOSE_RC:-0}" ;;
esac
exit 0
EOF
chmod +x "$WORK/bin/gh"
export FAKE_GH_LOG="$WORK/gh.log"
: > "$FAKE_GH_LOG"

# Description: 造一個 repo，裡面有一條已併入 main 的 branch 與一條有未併入 commit 的。
# Args: $1 = 名字
# Prints: repo 路徑
new_repo() {
  local repo="$WORK/$1"
  git init -q -b main "$repo"
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name selftest
  git -C "$repo" remote add origin https://github.com/acme/thing.git
  echo seed > "$repo/seed.txt"
  git -C "$repo" add seed.txt
  git -C "$repo" commit -qm seed

  # 已經併進 main 的那一條：刪掉它不會丟掉任何東西。
  git -C "$repo" branch merged-branch

  # 有未併入 commit 的那一條：刪掉它跟丟掉它之間只差一個 reflog 到期。
  git -C "$repo" checkout -q -b live-branch
  echo work > "$repo/work.txt"
  git -C "$repo" add work.txt
  git -C "$repo" commit -qm '沒有人看過的工作'
  git -C "$repo" checkout -q main
  printf '%s' "$repo"
}

run() { RC=0; OUT="$(PATH="$WORK/bin:$PATH" bash "$CLEANUP" "$@" 2>&1)" || RC=$?; }

echo "swe-close-cleanup selftest"

# 已併入的 branch：刪掉，回 0。
repo="$(new_repo merged)"
FAKE_GH_PRS="" run "$repo" --identity 'thing:merged-branch'
[[ "$RC" -eq 0 ]] || fail "已併入的 branch 收乾淨了應該回 0；拿到 ${RC}：$OUT"
grep -q '^deleted	' <<<"$OUT" || fail "沒說出它被刪了：$OUT"
git -C "$repo" rev-parse --verify --quiet merged-branch >/dev/null \
  && fail "說刪了但它還在——這一條在量的就是它真的不見了"
ok "已併進預設分支的 branch 真的被刪掉，回 0"

# 有未併入 commit 的：留著、列出來、非 0。**這是 D-N4 的正面**：收尾寧可留下也不丟。
repo="$(new_repo live)"
FAKE_GH_PRS="" run "$repo" --identity 'thing:live-branch'
[[ "$RC" -eq 1 ]] || fail "有東西沒收掉應該回 1；拿到 ${RC}：$OUT"
grep -q '^kept	' <<<"$OUT" || fail "留下來的東西沒有被列出來——安靜的殘留下一次會被當成沒有殘留：$OUT"
git -C "$repo" rev-parse --verify --quiet live-branch >/dev/null \
  || fail "有未併入 commit 的 branch 被刪掉了"
# 先收進變數再比。`git log … | grep -q` 在 pipefail 之下會偶發紅：grep 比中就結束，git log
# 撞 SIGPIPE 回 141，整條管線就是 141——而那跟「commit 不見了」長得一模一樣。
subjects="$(git -C "$repo" log --format=%s live-branch)"
grep -Fq '沒有人看過的工作' <<<"$subjects" || fail "那個 commit 不見了"
ok "有未併入 commit 的 branch 留著、逐個列出來、非 0，commit 一個都沒少"

# PR：關掉，而且要帶著復原路徑——關掉不等於丟掉，commit 留在 refs/pull/<n>/head 上。
repo="$(new_repo withpr)"
: > "$FAKE_GH_LOG"
FAKE_GH_PRS="1109" run "$repo" --identity 'thing:merged-branch' --reason '被 DP-508 取代'
[[ "$RC" -eq 0 ]] || fail "PR 關掉、branch 也刪了應該回 0；拿到 ${RC}：$OUT"
grep -q '^closed	' <<<"$OUT" || fail "沒說出 PR 被關了：$OUT"
grep -Fq 'refs/pull/1109/head' <<<"$OUT" || fail "沒給復原路徑：$OUT"
grep -Fq -- '--delete-branch' "$FAKE_GH_LOG" || fail "遠端那條分支沒有被一起刪：$(cat "$FAKE_GH_LOG")"
grep -Fq '被 DP-508 取代' "$FAKE_GH_LOG" \
  || fail "關掉的理由沒有留在 PR 上——事後看起來會像沒有理由就被關了：$(cat "$FAKE_GH_LOG")"
ok "這張單的 PR 被關掉、遠端分支一起刪、理由與復原路徑都留下來了"

# 關不掉（不是自己開的、或沒有權限）：量不到，回 2，不得印綠。
repo="$(new_repo cantclose)"
FAKE_GH_PRS="2000" FAKE_GH_CLOSE_RC=1 run "$repo" --identity 'thing:merged-branch'
[[ "$RC" -eq 2 ]] || fail "關不掉應該回 2；拿到 ${RC}：$OUT"
grep -q '^unmeasurable	' <<<"$OUT" || fail "關不掉沒有被說出來：$OUT"
ok "PR 關不掉是量不到（2），不安靜跳過"

# 沒有 gh：PR 那一半量不到，回 2。跟「沒有 PR 要關」分得開。
repo="$(new_repo nogh)"
RC=0
OUT="$(PATH="/usr/bin:/bin" bash "$CLEANUP" "$repo" --identity 'thing:merged-branch' 2>&1)" || RC=$?
[[ "$RC" -eq 2 ]] || fail "沒有 gh 應該回 2；拿到 ${RC}：$OUT"
grep -Fq '沒有 gh' <<<"$OUT" || fail "沒說出是缺 gh：$OUT"
ok "沒裝 gh 時 PR 那一半是量不到，不當作沒有 PR"

# 落腳處不在這台機器上：量不到，不是收乾淨了。
run /nowhere/at/all --identity 'thing:merged-branch'
[[ "$RC" -eq 2 ]] || fail "落腳處不存在應該回 2；拿到 ${RC}：$OUT"
grep -Fq '不在這台機器上' <<<"$OUT" || fail "沒說出落腳處不見了：$OUT"
ok "落腳處不在這台機器上是量不到，不是沒有東西要收"

echo "PASS: swe-close-cleanup（$PASS 項）"
