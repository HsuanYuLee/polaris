#!/usr/bin/env bash
# review-packet-head-binding-selftest.sh — 量 review packet 有沒有把三步交代出去（DP-459 H-P5）。
#
# 被判定的對象是 build-review-prompt.sh **實際產出的文字**，不是它的原始碼。只 assertion 原始碼
# 的話，一個改了註解卻沒改 emit 內容的版本會全綠——而 sub-agent 讀到的只有產出的那份。
#
# 這一支住在 review-inbox 而不是跟 submit-pr-review-selftest.sh 放在一起：packet 是這支
# skill 的產物，寫在共用的那一支裡會讓它在 review-pr 底下指向一個不存在的 builder。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDER="$SCRIPT_DIR/build-review-prompt.sh"

EXPECTED=4
RAN=0
FAILED=0

pass() { RAN=$((RAN + 1)); printf 'PASS  %s\n' "$1"; }
fail() { RAN=$((RAN + 1)); FAILED=$((FAILED + 1)); printf 'FAIL  %s\n    %s\n' "$1" "${2:-}"; }

[[ -f "$BUILDER" ]] || { printf 'INCONCLUSIVE：量不到——%s 不在\n' "$BUILDER" >&2; exit 2; }

WORK="$(mktemp -d -t polaris-dp459-packet.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/candidates.json" <<'JSON'
[{"repo":"acme-web","number":101,"title":"t","url":"https://github.com/acme/acme-web/pull/101",
  "author":"alice","review_status":"needs_first_review","review_detail":"first review"}]
JSON

if ! bash "$BUILDER" --my-user tester --base-dir "$WORK" --workspace "$WORK" \
     --out-dir "$WORK/packets" --manifest "$WORK/manifest.json" \
     < "$WORK/candidates.json" >/dev/null 2>"$WORK/err.txt"; then
  printf 'INCONCLUSIVE：量不到——builder 跑不起來：\n%s\n' "$(cat "$WORK/err.txt")" >&2
  exit 2
fi

PACKET="$(cat "$WORK/packets"/*.txt 2>/dev/null)"
[[ -n "$PACKET" ]] || { printf 'INCONCLUSIVE：量不到——builder 回 0 但沒有產出 packet\n' >&2; exit 2; }

for flag in --print-head --print-diff --reviewed-head; do
  if [[ "$PACKET" == *"$flag"* ]]; then
    pass "packet 交代了 $flag"
  else
    fail "packet 交代了 $flag" "產出的文字裡沒有這個旗標"
  fi
done

# packet 裡的命令要能直接跑。owner/name 解不出來時 builder 會吐一個帶來源的字串，
# 那個字串過不了 helper 的 --repository 檢查——所以這一條同時是「有解出來」與
# 「解錯了會被看見」。
#
# assertion 的是那個旗標帶的值，不是「packet 裡有沒有 acme/acme-web」——後者在修正前的
# 版本上也是綠的，因為 PR URL 本來就含那一段。反向對照組實測過。
# 取第一個命中不行：內嵌進 packet 的 dispatch bundle 裡有一段示範用的 OWNER/REPO
# 佔位字串，而它排在前面。要問的是「有沒有一處帶著真的解出來的值」。
slugs="$(printf '%s' "$PACKET" | grep -o -- '--repository [^ ]*' | awk '{print $2}' | sort -u | tr '\n' ' ')"
if [[ " $slugs " == *" acme/acme-web "* ]]; then
  pass "packet 裡的 --repository 是從 PR URL 解出來的 owner/name"
else
  fail "packet 裡的 --repository 是從 PR URL 解出來的 owner/name" "出現過的值：${slugs:-（packet 裡沒有 --repository）}"
fi

printf -- '---\n'
if [[ "$RAN" -ne "$EXPECTED" ]]; then
  printf 'INCONCLUSIVE：預期 %s 條，實際跑了 %s 條——量不到不是通過。\n' "$EXPECTED" "$RAN" >&2
  exit 2
fi
printf 'review packet head binding：%s 條，紅 %s 條。\n' "$EXPECTED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
