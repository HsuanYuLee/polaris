#!/usr/bin/env bash
# Purpose: 證明「它出去了沒有」這一問答得出三種答案，而且**approve 與 merge 都算走完**。
# Inputs:  mktemp 底下的假 repo，加上 PATH 最前面一支餵定值的 gh stub。
# Outputs: PASS 當 merge 算走完、approve 也算走完、日期取自 PR 而不是今天、還沒 approve 是
#          not-yet、沒裝 gh 是 unmeasurable，而且三者的 exit code 彼此分得開。
#
# 為什麼要用 stub 而不是真的 gh：拿真 PR 量到的是「GitHub 今天回什麼」，那不是這裡要問的問題，
# 而且同一支 selftest 明天會給出不同的答案。stub 是刻意的、寫在這裡看得到的 fixture。

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK="$ROOT_DIR/scripts/check-swe-delivered.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok  $*"; PASS=$((PASS + 1)); }

# gh stub：把要回的東西放在檔案裡，一個 case 換一次。
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-} ${2:-}" == "pr list" ]] || exit 0
cat "$FAKE_GH_PR_LIST"
EOF
chmod +x "$WORK/bin/gh"
export FAKE_GH_PR_LIST="$WORK/pr.json"

REPO="$WORK/repo"
git init -q -b main "$REPO"
git -C "$REPO" remote add origin https://github.com/acme/thing.git

# Description: 換掉 stub 要回的 PR，然後問一次。結果放進 RC / OUT。
# Args: $1 = stub 要回的 JSON, 其餘 = 傳給檢查的參數
answer() {
  printf '%s' "$1" > "$FAKE_GH_PR_LIST"; shift
  RC=0
  OUT="$(PATH="$WORK/bin:$PATH" bash "$CHECK" "$@" 2>&1)" || RC=$?
}

echo "check-swe-delivered selftest"

# merge 了：走完，日期是 merge 的那一天。日期刻意用一個不是今天的——核心會拿它當釋出日，
# 而填今天的那一版，一張上週就 merge 的單會被記進今天那一格。
answer '[{"latestReviews":[],"mergedAt":"2026-08-04T01:49:23Z","number":285,"reviewDecision":"APPROVED","state":"MERGED"}]' \
  "$REPO" --identity 'thing:feat/x'
[[ "$RC" -eq 0 ]] || fail "merge 了應該回 0；拿到 ${RC}：$OUT"
grep -q '^delivered	2026-08-04	' <<<"$OUT" || fail "merge 的日期沒有被讀出來：$OUT"
ok "merge 了就是走完，日期取自那個 PR 不是今天"

# approve 但還沒 merge：一樣算走完。按 merge 的時機常常是別人的排程，等它等於把這條流程的
# 終點交給一個我們不管的節奏。日期取最後一則 review 的時間。
answer '[{"latestReviews":[{"submittedAt":"2026-07-01T10:00:00Z"},{"submittedAt":"2026-07-02T11:00:00Z"}],"mergedAt":null,"number":42,"reviewDecision":"APPROVED","state":"OPEN"}]' \
  "$REPO" --identity 'thing:feat/x'
[[ "$RC" -eq 0 ]] || fail "approve 了也該算走完，回 0；拿到 ${RC}：$OUT"
grep -q '^delivered	2026-07-02	' <<<"$OUT" \
  || fail "approve 的日期不是最後一則 review 的時間：$OUT"
ok "approve 也算走完，日期是最後一則 review 的時間"

# 還沒 approve 也還沒 merge：not-yet，回 1。
answer '[{"latestReviews":[],"mergedAt":null,"number":43,"reviewDecision":"REVIEW_REQUIRED","state":"OPEN"}]' \
  "$REPO" --identity 'thing:feat/x'
[[ "$RC" -eq 1 ]] || fail "還沒被接受應該回 1；拿到 ${RC}：$OUT"
grep -q '^not-yet	' <<<"$OUT" || fail "沒說出它還沒出去：$OUT"
ok "還沒 approve 也還沒 merge 是 not-yet，回 1"

answer '[]' "$REPO" --identity 'thing:feat/x'
[[ "$RC" -eq 1 ]] || fail "連 PR 都還沒有應該回 1；拿到 ${RC}：$OUT"
grep -Fq '還沒有 PR' <<<"$OUT" || fail "沒說出連 PR 都還沒開：$OUT"
ok "連 PR 都還沒開是 not-yet，而且說得出是這一種"

# 沒裝 gh：unmeasurable，回 2。**這一條跟 not-yet 分得開才有意義**——混成同一種的話，一台
# 沒裝 gh 的機器會把每一張已經 merge 的單讀成「還沒出去」，然後它們安靜地停在待辦裡。
RC=0
OUT="$(PATH="/usr/bin:/bin" bash "$CHECK" "$REPO" --identity 'thing:feat/x' 2>&1)" || RC=$?
[[ "$RC" -eq 2 ]] || fail "沒有 gh 應該回 2；拿到 ${RC}：$OUT"
grep -Fq 'unmeasurable' <<<"$OUT" || fail "沒說出這一趟是量不到：$OUT"
ok "沒裝 gh 是量不到（2），跟還沒出去（1）分得開"

# 身分裡沒有分支名：問不出要查哪一個 PR。拿「現在站在哪」去猜的那一版會問到別人的 PR。
answer '[]' "$REPO" --identity 'no-colon-here'
[[ "$RC" -eq 2 ]] || fail "身分殘缺應該回 2；拿到 ${RC}：$OUT"
grep -Fq '沒有分支名' <<<"$OUT" || fail "沒指名是身分殘缺：$OUT"
ok "身分字串裡沒有分支名是量不到，不去猜一個"

# 落腳處與身分對不起來：停，不猜哪個配哪個。多 repo 的單上猜錯會安靜地問錯 repo。
answer '[]' "$REPO" "$REPO" --identity 'thing:feat/x'
[[ "$RC" -eq 2 ]] || fail "落腳處與身分數量對不上應該回 2；拿到 ${RC}：$OUT"
grep -Fq '對不起來' <<<"$OUT" || fail "沒說出是對不起來：$OUT"
ok "落腳處與身分數量對不上就停，不猜配對"

echo "PASS: check-swe-delivered（$PASS 項）"
