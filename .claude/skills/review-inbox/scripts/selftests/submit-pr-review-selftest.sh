#!/usr/bin/env bash
# submit-pr-review-selftest.sh — 量 submit-pr-review.sh 的 head 綁定行為（DP-459）。
#
# 這支的判準是「送出去的那顆 commit_id 是不是呼叫者宣告的那一顆」，以及「讀 diff 的
# 那條路釘不釘得住同一顆」。兩者分開量：只量綁定的話，一個讀舊內容、綁新 sha 的
# 實作照樣全綠，而 2026-07-27 那次事故錯的正是內容那一半。
#
# 不打真實網路。gh 由 POLARIS_GH_BIN 換成 stub，stub 記下每一次呼叫的完整參數，所以
# 「打了哪個 endpoint」與「POST 了幾次」是量得到的，不是用結果反推的。
set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$(cd "$SCRIPTS/.." && pwd)"
SKILLS_ROOT="$(cd "$SKILL/.." && pwd)"

# 紅控用：把被量的那一支換成修正前的版本，其餘一切不動。沒有這個口的話，紅控只能
# 另寫一支腳本，而另寫的那一支證明不了「這一支量得到」。
SUBJECT_OVERRIDE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --subject) SUBJECT_OVERRIDE="${2:-}"; shift 2 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done
SUBJECT="${SUBJECT_OVERRIDE:-$SCRIPTS/submit-pr-review.sh}"

# 這支腳本在兩支 skill 底下各有一份副本，而副本沒有任何關卡在守（見 DP-459 活區）。
SIBLING_SKILLS=(review-pr review-inbox)

EXPECTED=14
RAN=0
SKIPPED=0
FAILED=0

pass() { RAN=$((RAN + 1)); printf 'PASS  %s\n' "$1"; }
fail() { RAN=$((RAN + 1)); FAILED=$((FAILED + 1)); printf 'FAIL  %s\n    %s\n' "$1" "${2:-}"; }
skip() { SKIPPED=$((SKIPPED + 1)); printf 'SKIP  %s\n    %s\n' "$1" "$2"; }

[[ -f "$SUBJECT" ]] || { printf 'INCONCLUSIVE：量不到——被量的對象不在 %s\n' "$SUBJECT" >&2; exit 2; }

WORK="$(mktemp -d -t polaris-dp459.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"

CURRENT_HEAD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
BASE_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
REVIEWED_OLD=cccccccccccccccccccccccccccccccccccccccc

cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
# stub gh：記下每一次呼叫，依 endpoint 分派。不連網。
printf '%s\n' "$*" >> "$STUB_LOG"
for arg in "$@"; do
  case "$arg" in
    */pulls/*/reviews)
      cp "${!#}" "$STUB_POST_PAYLOAD" 2>/dev/null || true
      printf 'POST\n' >> "$STUB_LOG"
      if [[ "${STUB_POST_RC:-0}" -ne 0 ]]; then
        printf 'gh: Unprocessable Entity (HTTP 422)\ncommit_id is not part of the pull request\n' >&2
        exit "${STUB_POST_RC}"
      fi
      printf '{"id":1,"state":"COMMENTED"}\n'
      exit 0
      ;;
    */compare/*) printf 'diff-pinned-to %s\n' "$arg"; exit 0 ;;
    repos/*/pulls/*)
      [[ "${STUB_PR_READ_RC:-0}" -eq 0 ]] || { printf 'gh: Not Found (HTTP 404)\n' >&2; exit "${STUB_PR_READ_RC}"; }
      cat "$STUB_PR_JSON"
      exit 0
      ;;
  esac
done
exit 1
STUB
chmod +x "$WORK/bin/gh"

printf '{"head":{"sha":"%s"},"base":{"sha":"%s"}}\n' "$CURRENT_HEAD" "$BASE_SHA" > "$WORK/pr.json"
printf '這是一則審查意見，指出兩個需要處理的問題。\n' > "$WORK/body.txt"

export STUB_LOG="$WORK/log.txt"
export STUB_PR_JSON="$WORK/pr.json"
export STUB_POST_PAYLOAD="$WORK/posted.json"

# Description: run the subject with the gh stub, capturing stdout/stderr/rc.
# Args:        $@ = arguments passed straight to submit-pr-review.sh.
# Side effects: resets the stub log and posted payload; sets OUT/ERR/RC.
run_subject() {
  : > "$STUB_LOG"
  rm -f "$STUB_POST_PAYLOAD"
  OUT="$(POLARIS_GH_BIN="${GH_OVERRIDE:-$WORK/bin/gh}" bash "$SUBJECT" "$@" 2>"$WORK/err.txt")"
  RC=$?
  ERR="$(cat "$WORK/err.txt")"
}

posted_commit_id() {
  [[ -f "$STUB_POST_PAYLOAD" ]] || { printf ''; return; }
  python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("commit_id",""))' "$STUB_POST_PAYLOAD"
}

# `grep -c` 數到 0 時以 1 離開，所以 `grep -c ... || printf 0` 會印出兩個 0。
post_count() { grep -c '^POST$' "$STUB_LOG" 2>/dev/null | head -1; }

# ── H-P1：head 只從 REST 那一條路取 ──────────────────────────────────────────
hits="$(grep -c 'gh pr view' "$SUBJECT" || true)"
[[ "$hits" -eq 0 ]] && pass "H-P1 helper 原始碼不含 gh pr view" \
                    || fail "H-P1 helper 原始碼不含 gh pr view" "命中 $hits 次"

hits="$(grep -c 'headRefOid' "$SUBJECT" || true)"
[[ "$hits" -eq 0 ]] && pass "H-P1 helper 原始碼不含 headRefOid" \
                    || fail "H-P1 helper 原始碼不含 headRefOid" "命中 $hits 次"

run_subject --repository o/r --pull-number 12 --print-head
if [[ "$RC" -eq 0 && "$OUT" == "$CURRENT_HEAD" ]] && grep -q '^api repos/o/r/pulls/12$' "$STUB_LOG"; then
  pass "H-P1 --print-head 打的是 REST repos/{o}/{r}/pulls/{n}"
else
  fail "H-P1 --print-head 打的是 REST repos/{o}/{r}/pulls/{n}" "rc=$RC out=$OUT log=$(tr '\n' '|' < "$STUB_LOG")"
fi

# ── H-P2：綁定即為所見，三種輸入 ─────────────────────────────────────────────
run_subject --repository o/r --pull-number 12 --reviewed-head "$CURRENT_HEAD" \
  --event COMMENT --body-file "$WORK/body.txt" --submit
[[ "$RC" -eq 0 && "$(posted_commit_id)" == "$CURRENT_HEAD" ]] \
  && pass "H-P2 宣告值等於當下 head 時，commit_id 是宣告值" \
  || fail "H-P2 宣告值等於當下 head 時，commit_id 是宣告值" "rc=$RC commit_id=$(posted_commit_id)"

run_subject --repository o/r --pull-number 12 --reviewed-head "$REVIEWED_OLD" \
  --event COMMENT --body-file "$WORK/body.txt" --submit
posted="$(posted_commit_id)"
if [[ "$posted" == "$REVIEWED_OLD" ]]; then
  pass "H-P2 宣告值早於當下 head 時，commit_id 仍是宣告值（不是當下 head）"
else
  fail "H-P2 宣告值早於當下 head 時，commit_id 仍是宣告值（不是當下 head）" "commit_id=$posted"
fi

STUB_PR_READ_RC=1 run_subject --repository o/r --pull-number 12 --reviewed-head "$REVIEWED_OLD" \
  --event COMMENT --body-file "$WORK/body.txt" --submit
posted="$(posted_commit_id)"
if [[ "$RC" -eq 0 && "$posted" == "$REVIEWED_OLD" && "$ERR" == *POLARIS_PR_HEAD_UNRESOLVED* ]]; then
  pass "H-P2 那一趟 REST 取不到值時，仍綁宣告值並說出沒問到"
else
  fail "H-P2 那一趟 REST 取不到值時，仍綁宣告值並說出沒問到" "rc=$RC commit_id=$posted err=$ERR"
fi

# ── H-P3：head 前進只揭露、不攔截 ────────────────────────────────────────────
run_subject --repository o/r --pull-number 12 --reviewed-head "$REVIEWED_OLD" \
  --event COMMENT --body-file "$WORK/body.txt" --submit
if [[ "$RC" -eq 0 && "$ERR" == *"POLARIS_PR_HEAD_ADVANCED: $REVIEWED_OLD -> $CURRENT_HEAD"* && "$(post_count)" -eq 1 ]]; then
  pass "H-P3 head 前進時照常送出，並在 stderr 印出宣告值與當下值"
else
  fail "H-P3 head 前進時照常送出，並在 stderr 印出宣告值與當下值" "rc=$RC posts=$(post_count) err=$ERR"
fi

# ── H-P4：diff 與綁定是同一顆 sha ────────────────────────────────────────────
run_subject --repository o/r --pull-number 12 --reviewed-head "$REVIEWED_OLD" --print-diff
if [[ "$RC" -eq 0 && "$OUT" == *"...$REVIEWED_OLD"* ]]; then
  pass "H-P4 --print-diff 釘在宣告的那顆 sha 上"
else
  fail "H-P4 --print-diff 釘在宣告的那顆 sha 上" "rc=$RC out=$OUT"
fi
# 只斷言「輸出裡有宣告值」不夠：一個對當下 head 取 diff、卻把宣告值印在別處的實作
# 也會滿足它。要斷言的是當下 head 沒有出現在那條 compare 路徑上。
#
# 而「不含當下 head」單獨拿出來是空話：一個什麼都沒印的實作也滿足它——紅控實測修正
# 前的版本在這一條上是綠的，因為它根本不認得 --print-diff。所以先要求真的取到了一份
# 釘住的 diff，再問它有沒有用當下 head。
if [[ "$OUT" == *compare/* && "$OUT" != *"$CURRENT_HEAD"* ]]; then
  pass "H-P4 --print-diff 真的取到 diff，且沒有用當下 head"
else
  fail "H-P4 --print-diff 真的取到 diff，且沒有用當下 head" "out=$OUT"
fi

# ── H-N1：什麼都不宣告就不准送 ───────────────────────────────────────────────
run_subject --repository o/r --pull-number 12 --event COMMENT --body-file "$WORK/body.txt" --submit
if [[ "$RC" -ne 0 && "$(post_count)" -eq 0 && "$ERR" == *POLARIS_PR_REVIEW_REVIEWED_HEAD_REQUIRED* ]]; then
  pass "H-N1 沒宣告 head 就送出時，一次 POST 都沒有發出且說出缺什麼"
else
  fail "H-N1 沒宣告 head 就送出時，一次 POST 都沒有發出且說出缺什麼" "rc=$RC posts=$(post_count) err=$ERR"
fi

# ── H-N2：被拒絕不自己改綁 ───────────────────────────────────────────────────
STUB_POST_RC=1 run_subject --repository o/r --pull-number 12 --reviewed-head "$REVIEWED_OLD" \
  --event COMMENT --body-file "$WORK/body.txt" --submit
if [[ "$RC" -ne 0 && "$(post_count)" -eq 1 && "$ERR" == *"HTTP 422"* ]]; then
  pass "H-N2 POST 被拒絕時恰送一次、非 0 離開、API 錯誤原樣輸出"
else
  fail "H-N2 POST 被拒絕時恰送一次、非 0 離開、API 錯誤原樣輸出" "rc=$RC posts=$(post_count) err=$ERR"
fi

# ── H-N3：工具不在就不假裝 ───────────────────────────────────────────────────
GH_OVERRIDE="$WORK/no-such-gh" run_subject --repository o/r --pull-number 12 --print-head
if [[ "$RC" -eq 2 && "$ERR" == *POLARIS_TOOL_MISSING:gh* ]]; then
  pass "H-N3 gh 不在時 exit 2 並印 POLARIS_TOOL_MISSING:gh"
else
  fail "H-N3 gh 不在時 exit 2 並印 POLARIS_TOOL_MISSING:gh" "rc=$RC err=$ERR"
fi

# ── H-N4：兩份副本不得漂 ─────────────────────────────────────────────────────
# 單獨下載一支 skill 的人手上只有一份，這一格量不到——那要說出來，不能安靜地算通過。
missing=()
for s in "${SIBLING_SKILLS[@]}"; do
  [[ -d "$SKILLS_ROOT/$s/scripts" ]] || missing+=("$s")
done
if [[ "${#missing[@]}" -gt 0 ]]; then
  skip "H-N4 兩支 skill 的同名腳本逐位元組相同" \
       "旁邊沒有這幾支 skill：${missing[*]}——單獨下載時只有一份副本，沒有可以漂的對象。"
else
  a="$SKILLS_ROOT/${SIBLING_SKILLS[0]}"
  b="$SKILLS_ROOT/${SIBLING_SKILLS[1]}"
  drifted=()
  # 比三處：scripts/、selftests/、references/。
  # selftests/ 要比，因為這支儀器自己就是兩份副本，漏掉它等於量測本身可以安靜地漂。
  # references/ 這一輪只剩兩邊都有的那幾份會被比到——DP-575 把 review-inbox 底下那 6 份
  # review-pr 的副本刪了，只有一份的東西沒有可以漂的對象，下面那個 -f 判斷自己會跳過。
  for f in "$a"/scripts/*.sh "$a"/scripts/selftests/*.sh "$a"/references/*.md; do
    [[ -f "$f" ]] || continue
    rel="${f#"$a"/}"
    [[ -f "$b/$rel" ]] || continue
    cmp -s "$f" "$b/$rel" || drifted+=("$rel")
  done
  if [[ "${#drifted[@]}" -eq 0 ]]; then
    pass "H-N4 兩支 skill 的同名腳本與 reference 逐位元組相同"
  else
    fail "H-N4 兩支 skill 的同名腳本與 reference 逐位元組相同" "漂掉的：${drifted[*]}"
  fi
fi

# ── H-P5：consumer 的 submit 面對稱改線 ──────────────────────────────────────
# 散文那一半只有一份，住在 review-pr 那一支（DP-575 把 review-inbox 底下的副本刪了）。
# 兩支的這份 selftest 逐位元組相同，所以路徑一律指到那一份——在 review-pr 這一側它就是
# 自己。旁邊沒有 review-pr 時量不到，那要說出來，不能安靜地算通過。
FLOW="$SKILLS_ROOT/review-pr/references/review-pr-submit-flow.md"
if [[ ! -f "$FLOW" ]]; then
  skip "H-P5 submit flow 寫出取 head、對它取 diff、綁同一顆送出" \
       "這一側沒有 submit flow，旁邊也沒有 review-pr——單獨下載時量不到這一格。"
else
  flow_text="$(cat "$FLOW")"
  missing=()
  [[ "$flow_text" == *"--print-head"* ]] || missing+=("--print-head")
  [[ "$flow_text" == *"--print-diff"* ]] || missing+=("--print-diff")
  [[ "$flow_text" == *"--reviewed-head"* ]] || missing+=("--reviewed-head")
  [[ "$flow_text" == *"POLARIS_PR_HEAD_ADVANCED"* ]] || missing+=("POLARIS_PR_HEAD_ADVANCED")
  if [[ "${#missing[@]}" -eq 0 ]]; then
    pass "H-P5 submit flow 寫出取 head、對它取 diff、綁同一顆送出"
  else
    fail "H-P5 submit flow 寫出取 head、對它取 diff、綁同一顆送出" "缺：${missing[*]}"
  fi
fi

# H-P5 的另一半——「產出的 packet 帶著同一套三步」——住在 review-inbox 自己那一側
# （review-packet-head-binding-selftest.sh），因為 packet 是那支 skill 的產物。寫在這裡
# 的話，這支腳本會在 review-pr 底下指向一個不存在的東西，而那正是斷指標。

printf -- '---\n'
if [[ $((RAN + SKIPPED)) -ne "$EXPECTED" ]]; then
  printf 'INCONCLUSIVE：預期 %s 條，實際跑了 %s 條、跳過 %s 條——量不到不是通過。\n' \
    "$EXPECTED" "$RAN" "$SKIPPED" >&2
  exit 2
fi
printf 'submit-pr-review：%s 條，紅 %s 條，跳過 %s 條（都已具名）。\n' "$EXPECTED" "$FAILED" "$SKIPPED"
[[ "$FAILED" -eq 0 ]]
