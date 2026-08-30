#!/usr/bin/env bash
# Purpose: 驗「只有人知道的那幾項」在凍結之前真的都有答案，而且**空著與不適用長得不一樣**。
# Inputs:  mktemp 底下的 index.md fixture，不需要 git、不需要外部服務。
# Outputs: PASS 當齊備的放行、缺一項的被擋且指名、空著的被擋、標成不適用又不說理由的被擋、
#          source 不在三種裡的被擋、讀不懂的區塊被拒而不是被略過。

set -uo pipefail

CHECK="$(cd "$(dirname "$0")/.." && pwd)/check-plan-answers.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Description: 寫一份 index.md，plan 區塊內容由 stdin 給（不給就完全沒有 plan 區塊）。
# Args: $1 = 名字
# Prints: 檔案路徑
new_issue() {
  local path="$WORK/$1.md" block
  block="$(cat)"
  {
    echo "---"
    echo "title: fixture"
    echo "destination: workspace"
    [[ -n "$block" ]] && printf '%s\n' "$block"
    # DP-608 多了一格 `assumes`。既有的案子問的都是那四格，所以除非某個案子自己要講
    # 現況主張，否則替它補上「這張 fixture 不依賴任何現況」——那樣每一個案子仍然只在
    # 量它本來要量的東西，而不是全部一起變紅。
    if [[ -n "$block" && "$block" == *"plan:"* && "$block" != *"assumes"* ]]; then
      echo "  assumes:"
      echo "    not_applicable: \"fixture 不依賴任何別處的現況\""
    fi
    echo "---"
    echo
    echo "本文"
  } > "$path"
  printf '%s' "$path"
}

echo "check-plan-answers selftest"

full="$(new_issue full <<'EOF'
plan:
  what:
    answer: "做這個"
    source: inferred_confirmed
  when:
    answer: "下週二"
    source: human
  why:
    answer: "因為那個"
    source: human
  how:
    answer: "拿這筆測資"
    source: environment
    environments: none
EOF
)"
out="$(bash "$CHECK" "$full" 2>&1)" || fail "齊備的卻被擋：$out"
grep -q 'PLAN-ANSWERS-OK' <<<"$out" || fail "放行卻沒有正向證據：$out"
echo "  ok  四項都有答案時放行"

# 明講「這張單不需要它」是一個被記下來的決定，跟空著不是同一件事。
na="$(new_issue na <<'EOF'
plan:
  what:
    answer: "做這個"
    source: human
  when:
    not_applicable: "自用工具，沒有對外的時程"
  why:
    answer: "因為那個"
    source: human
  how:
    answer: "手動跑一次"
    source: human
    environments: none
EOF
)"
out="$(bash "$CHECK" "$na" 2>&1)" || fail "標成不適用的卻被擋：$out"
grep -q '1 項記為不適用' <<<"$out" || fail "不適用沒有被算成不適用：$out"
echo "  ok  明講不適用並說理由時放行，而且跟有答案分開算"

# 這一段是這支腳本唯一在防的形狀。空著看得出來，填過的看不出來——所以空著不得被吸收成
# 「這張單不需要它」。
empty="$(new_issue empty <<'EOF'
plan:
  what:
    answer: "做這個"
    source: human
  when:
    answer: ""
    source: human
  why:
    answer: "因為那個"
    source: human
  how:
    answer: "手動"
    source: human
    environments: none
EOF
)"
out="$(bash "$CHECK" "$empty" 2>&1)" && fail "空著的卻放行了"
grep -q 'POLARIS_PLAN_ANSWER_MISSING' <<<"$out" || fail "空著沒有 marker：$out"
grep -q 'when' <<<"$out" || fail "沒指名是哪一項空著：$out"
echo "  ok  空著被擋，而且指名是哪一項"

missing="$(new_issue missing <<'EOF'
plan:
  what:
    answer: "做這個"
    source: human
  why:
    answer: "因為那個"
    source: human
  how:
    answer: "手動"
    source: human
    environments: none
EOF
)"
out="$(bash "$CHECK" "$missing" 2>&1)" && fail "少一項卻放行了"
grep -q 'when: 沒有這一項' <<<"$out" || fail "少的那一項沒被指名：$out"
echo "  ok  整項不存在時被擋，且指名"

# 標了不適用卻不說為什麼，等於沒標：讀的人看不出這是想過之後的決定還是順手填的。
bare_na="$(new_issue barena <<'EOF'
plan:
  what:
    answer: "做這個"
    source: human
  when:
    not_applicable: ""
  why:
    answer: "因為那個"
    source: human
  how:
    answer: "手動"
    source: human
    environments: none
EOF
)"
out="$(bash "$CHECK" "$bare_na" 2>&1)" && fail "不適用沒說理由卻放行了"
grep -q '沒有說為什麼' <<<"$out" || fail "沒指出理由缺了：$out"
echo "  ok  標成不適用卻不說理由時被擋"

# source 是用來事後分辨「人決定的」與「編出來的」。它空著或亂寫，那個分辨就沒了。
badsrc="$(new_issue badsrc <<'EOF'
plan:
  what:
    answer: "做這個"
    source: guessed
  when:
    not_applicable: "沒有時程"
  why:
    answer: "因為那個"
    source: human
  how:
    answer: "手動"
    source: human
    environments: none
EOF
)"
out="$(bash "$CHECK" "$badsrc" 2>&1)" && fail "source 亂寫卻放行了"
grep -q 'source' <<<"$out" || fail "沒指出 source 的問題：$out"
echo "  ok  source 不在三種裡時被擋"

nothing="$(new_issue nothing </dev/null)"
out="$(bash "$CHECK" "$nothing" 2>&1)" && fail "完全沒有 plan 區塊卻放行了"
grep -q '沒有 plan 區塊' <<<"$out" || fail "沒說出整個區塊不在：$out"
grep -q '交一份草案' <<<"$out" || fail "拒絕沒有指向做法：$out"
echo "  ok  完全沒有 plan 區塊時被擋，並指向問法"

# 剖析器很窄，所以看不懂的要拒絕而不是略過——略過的話，一個縮排打錯的區塊會靜默地變成
# 「沒有這一項」，而那正是這道檢查要抓的東西。
weird="$(new_issue weird <<'EOF'
plan:
  what:
    answer: "做這個"
    source: human
   when:
     answer: "縮排壞掉"
EOF
)"
out="$(bash "$CHECK" "$weird" 2>&1)" && fail "讀不懂的區塊卻放行了"
grep -q 'POLARIS_PLAN_BLOCK_UNPARSEABLE' <<<"$out" || fail "讀不懂沒有專屬 marker：$out"
grep -q '讀不懂' <<<"$out" || fail "沒有指出是哪一行：$out"
echo "  ok  讀不懂的行被拒絕，不是被略過"

# ── 環境是列出來的，不是寫在句子裡 ──────────────────────────────────────────
#
# 「要起哪些東西」寫在自由文字裡，沒有任何東西讀得懂。列出來之後，「哪個環境還沒有人會
# 起」就算得出來——而那是「該沉澱一份領域知識了」唯一的機械訊號。

noenv="$(new_issue noenv <<'EOF'
plan:
  what:
    answer: "做這個"
    source: human
  when:
    not_applicable: "無"
  why:
    answer: "因為那個"
    source: human
  how:
    answer: "本機起兩個東西然後點一點"
    source: human
EOF
)"
out="$(bash "$CHECK" "$noenv" 2>&1)" && fail "how 沒有 environments 卻放行了"
grep -q 'environments' <<<"$out" || fail "沒指出缺的是 environments：$out"
grep -q 'environments: none' <<<"$out" || fail "沒說出不需要環境時該怎麼寫：$out"
echo "  ok  how 沒有 environments 時被擋，並說出不需要時怎麼寫"

# 沒有人會起的環境，要在凍結之前就被指名。這一段自己造一棵假的 skill 樹——量的是
# 「找不找得到宣告」，不是這台機器現在剛好裝了什麼。
SK="$WORK/skills"
mkdir -p "$SK/somepack" "$SK/refinement/scripts"
printf '%s\n' '---' 'name: somepack' '---' \
  '<!-- ANYPREFIX-ENVIRONMENT-known-env: bash start-known.sh -->' > "$SK/somepack/SKILL.md"

listed="$(new_issue listed <<'EOF'
plan:
  what:
    answer: "做這個"
    source: human
  when:
    not_applicable: "無"
  why:
    answer: "因為那個"
    source: human
  how:
    answer: "起兩個環境"
    source: human
    environments: [known-env, nobody-starts-this]
EOF
)"
out="$(bash "$CHECK" "$listed" --skills "$SK" 2>&1)" && fail "有環境沒人會起卻放行了"
grep -q 'POLARIS_PLAN_ENVIRONMENT_UNCLAIMED' <<<"$out" || fail "沒有專屬 marker：$out"
grep -q 'nobody-starts-this' <<<"$out" || fail "沒指名是哪個環境沒人會起：$out"
grep -q 'known-env→somepack' <<<"$out" || fail "沒說出已經有人會起的是哪些：$out"
grep -q 'ENVIRONMENT-' <<<"$out" || fail "拒絕沒說出宣告要怎麼寫：$out"
echo "  ok  沒人會起的環境被指名，並說出宣告怎麼寫"

# 反向：全部都有人會起就放行——否則上面那個結果只證明它會擋，不證明它會分辨。
allknown="$(new_issue allknown <<'EOF'
plan:
  what:
    answer: "做這個"
    source: human
  when:
    not_applicable: "無"
  why:
    answer: "因為那個"
    source: human
  how:
    answer: "起一個環境"
    source: human
    environments: [known-env]
EOF
)"
out="$(bash "$CHECK" "$allknown" --skills "$SK" 2>&1)" || fail "環境都有人會起卻被擋：$out"
grep -q '都有人會起' <<<"$out" || fail "放行卻沒說出環境對上了：$out"
echo "  ok  環境都有人會起時放行"

# `none` 是一個寫下來的答案，不是欄位不見——它不得被當成一個叫做 none 的環境去找。
out="$(bash "$CHECK" "$full" --skills "$SK" 2>&1)" || fail "environments: none 卻被當成一個環境去找：$out"
grep -q '不需要起任何環境' <<<"$out" || fail "none 沒有被讀成「不需要」：$out"
echo "  ok  environments: none 讀成不需要，不是一個叫 none 的環境"

echo "PASS: check-plan-answers"
