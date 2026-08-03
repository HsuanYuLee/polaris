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
EOF
)"
out="$(bash "$CHECK" "$badsrc" 2>&1)" && fail "source 亂寫卻放行了"
grep -q 'source' <<<"$out" || fail "沒指出 source 的問題：$out"
echo "  ok  source 不在三種裡時被擋"

nothing="$(new_issue nothing </dev/null)"
out="$(bash "$CHECK" "$nothing" 2>&1)" && fail "完全沒有 plan 區塊卻放行了"
grep -q '沒有 plan 區塊' <<<"$out" || fail "沒說出整個區塊不在：$out"
grep -q '一次一題' <<<"$out" || fail "拒絕沒有指向問法：$out"
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

echo "PASS: check-plan-answers"
