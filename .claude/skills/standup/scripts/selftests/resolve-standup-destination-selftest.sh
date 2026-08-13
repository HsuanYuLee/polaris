#!/usr/bin/env bash
# resolve-standup-destination-selftest.sh — 餵紅 resolve-standup-destination.sh。
#
# 這一支守的是 DP-519 E-P2／E-P3：**三種輸入不得長成同一句「找不到」**。一個把「宣告齊全」
# 以外全部收斂成一個錯誤的解析器，會讓「這台機器沒設定過」與「有人設定了一半」變成同一個
# 問題，而那兩件事的修法完全不同。
#
# 正負兩表都跑：只驗反例的話，一個永遠回 4 的解析器也全綠。
#
# Usage: resolve-standup-destination-selftest.sh
# Exit:  0 全部如預期 / 1 有一種沒被分辨出來

set -uo pipefail

SELFTEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SELFTEST_DIR/.." && pwd)"
RESOLVER="$SCRIPTS_DIR/resolve-standup-destination.sh"

PREFIX="[selftest resolve-standup-destination]"
PASS=0
FAIL=0

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [[ ! -f "$RESOLVER" ]]; then
  echo "$PREFIX 量不到：$RESOLVER 不在。" >&2
  exit 2
fi

# case <名字> <設定檔> <預期離場碼> <預期輸出裡要出現的字串>
case_is() {
  local label="$1" config="$2" want_code="$3" want_text="$4"
  local out code
  out="$(bash "$RESOLVER" --config "$config" 2>&1)"
  code=$?
  if [[ "$code" == "$want_code" ]] && [[ "$out" == *"$want_text"* ]]; then
    PASS=$((PASS + 1))
    echo "$PREFIX PASS ${label}（exit=${code}）"
  else
    FAIL=$((FAIL + 1))
    echo "$PREFIX FAIL ${label}：預期 exit=$want_code 且輸出含「${want_text}」" >&2
    echo "$PREFIX       實際 exit=$code" >&2
    echo "$out" | sed "s/^/$PREFIX       /" >&2
  fi
}

# ── 正向：宣告齊全 ───────────────────────────────────────────────────────────
cat > "$WORK/full.yaml" <<'YAML'
jira:
  instance: "example.invalid"
standup:
  destination:
    name: "some-board"
    url: "https://example.invalid/standup"
    shape: "epic-three-cells"
    publish: manual
YAML
case_is "宣告齊全 → 0 並印出四格" "$WORK/full.yaml" 0 "shape=epic-three-cells"
case_is "宣告齊全 → 送出方式也印出來" "$WORK/full.yaml" 0 "publish=manual"

# 選填的 name 不在，不影響成立——必填的是 url / shape / publish。
cat > "$WORK/noname.yaml" <<'YAML'
standup:
  destination:
    url: "https://example.invalid/standup"
    shape: "epic-three-cells"
    publish: api
YAML
case_is "name 是選填的" "$WORK/noname.yaml" 0 "name=(未命名)"

# ── 負向一：宣告在，但缺必要欄位 ─────────────────────────────────────────────
cat > "$WORK/partial.yaml" <<'YAML'
standup:
  destination:
    name: "some-board"
    url: "https://example.invalid/standup"
YAML
case_is "缺必要欄位 → 3" "$WORK/partial.yaml" 3 "INCOMPLETE"
case_is "缺哪幾格要指名" "$WORK/partial.yaml" 3 "missing=shape,publish"

# 空字串跟沒有那一行是同一件事——一個填了引號但沒填內容的欄位不算宣告過。
cat > "$WORK/empty.yaml" <<'YAML'
standup:
  destination:
    url: ""
    shape: "epic-three-cells"
    publish: manual
YAML
case_is "填了空字串仍算缺" "$WORK/empty.yaml" 3 "missing=url"

# ── 負向二：沒有宣告 ─────────────────────────────────────────────────────────
cat > "$WORK/noblock.yaml" <<'YAML'
jira:
  instance: "example.invalid"
confluence:
  space: "XX"
YAML
case_is "設定檔在但沒有 standup 區塊 → 4" "$WORK/noblock.yaml" 4 "reason=no-standup-block"

cat > "$WORK/nodest.yaml" <<'YAML'
standup:
  something_else: true
YAML
case_is "有 standup 但沒有 destination → 4 且理由不一樣" "$WORK/nodest.yaml" 4 "reason=no-standup-destination-block"

case_is "設定檔整個不在 → 4 且理由不一樣" "$WORK/does-not-exist.yaml" 4 "reason=config-not-found"

# ── 三種不得長成同一句 ───────────────────────────────────────────────────────
# 上面每一條各自比對過自己的字串了，這一條問的是另一件事：三種的**第一行**互不相同。
# 只逐條比對的話，三種都印同一句而各自剛好含著不同的子字串仍然會全綠。
first_line() { bash "$RESOLVER" --config "$1" 2>&1 | head -1; }
A="$(first_line "$WORK/full.yaml")"
B="$(first_line "$WORK/partial.yaml")"
C="$(first_line "$WORK/does-not-exist.yaml")"
if [[ "$A" != "$B" && "$B" != "$C" && "$A" != "$C" ]]; then
  PASS=$((PASS + 1))
  echo "$PREFIX PASS 三種輸入的第一行互不相同"
else
  FAIL=$((FAIL + 1))
  echo "$PREFIX FAIL 三種輸入裡有兩種印出同一句：" >&2
  printf '%s\n' "$A" "$B" "$C" | sed "s/^/$PREFIX       /" >&2
fi

# ── 量不到要用 2，不要走進判定 ───────────────────────────────────────────────
out="$(bash "$RESOLVER" 2>&1)"; code=$?
if [[ "$code" == 2 ]]; then
  PASS=$((PASS + 1))
  echo "$PREFIX PASS 兩個參數都沒給 → 2（量不到，不是「沒有宣告」）"
else
  FAIL=$((FAIL + 1))
  echo "$PREFIX FAIL 兩個參數都沒給時 exit=${code}，應該是 2" >&2
fi

echo "$PREFIX PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" == 0 ]] || exit 1
