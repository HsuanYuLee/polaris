#!/usr/bin/env bash
# Purpose: 這支探針把五種輸入分成五種答案，而它以前把其中兩種收成同一個。
#
# 2026-08-09 之前，一份**內容完整**、只是還沒 normalize 的 dump 會被判成
# `POLARIS_DISCOVERY_SOURCE_UNAVAILABLE`——排查的人被指去看 token 與網路，而資料一直都在。
# 這支探針在那之前一支 selftest 都沒有，所以那三行是它第一次被餵過已知的輸入。
#
# Inputs:  mktemp 底下造出來的五種 dump。
# Outputs: PASS 當每一種輸入拿到它自己的標記，而且沒有任何一種被放行成 exit 0。

set -euo pipefail

PROBE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/review-inbox-discovery-probe.sh"
[[ -x "$PROBE" || -f "$PROBE" ]] || { echo "POLARIS_SELFTEST_TARGET_MISSING:$PROBE" >&2; exit 2; }

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

python3 - "$WORK" <<'PY'
import json
import sys

work = sys.argv[1]
# 上游真的回的內容：兩個 header 行、一個 PR URL。
detailed = ("=== Message from Alice ===\n"
            "Message TS: 1717000000.100000\n"
            "please review https://github.com/acme/web/pull/123\n")
# 這個 runtime 的 MCP detailed 就是這一種：整份擠成一行，真換行 escape 成字面的 \n。
open(f"{work}/escaped.txt", "w", encoding="utf-8").write(json.dumps({"messages": detailed}))
open(f"{work}/normalized.txt", "w", encoding="utf-8").write(detailed)
open(f"{work}/no-headers.txt", "w", encoding="utf-8").write("something entirely unrelated\n")
open(f"{work}/empty.txt", "w", encoding="utf-8").write("")
open(f"{work}/cand-empty.txt", "w", encoding="utf-8").write("")
open(f"{work}/cand-one.txt", "w", encoding="utf-8").write(
    "https://github.com/acme/web/pull/123\n")
PY

PASS=0
FAIL=0

# Description: 餵一種輸入，斷言標記與結束狀態。
# Args: $1 = case 名, $2 = raw dump, $3 = candidates, $4 = 期待的標記, $5 = 期待的 exit
expect() {
  local name="$1" raw="$2" cand="$3" want_marker="$4" want_exit="$5"
  local out rc=0
  out="$(bash "$PROBE" --raw-dump "$WORK/${raw}.txt" --candidates "$WORK/${cand}.txt" \
    --now-epoch 1717000100 2>&1)" || rc=$?
  local marker
  marker="$(printf '%s' "$out" | head -1)"
  if [[ "$rc" != "$want_exit" ]]; then
    echo "FAIL $name: 期待 exit ${want_exit}，實際 ${rc}"; printf '%s\n' "$out" | sed 's/^/     /'
    FAIL=$((FAIL + 1)); return
  fi
  if [[ "$marker" != "$want_marker" ]]; then
    echo "FAIL $name: 期待 ${want_marker}，實際 ${marker}"
    FAIL=$((FAIL + 1)); return
  fi
  echo "PASS $name"; PASS=$((PASS + 1))
}

# 一、資料完整、只是還沒轉換。這是每一次 Slack mode 都會踩到的那一個。
expect "還沒 normalize 的完整 dump 說得出「先轉」，不是「拿不到」" \
  escaped cand-empty POLARIS_DISCOVERY_NOT_NORMALIZED 2

# 而且它要說得出下一步——一個沒有下一步的 fail-closed 只是擋人。
out="$(bash "$PROBE" --raw-dump "$WORK/escaped.txt" --candidates "$WORK/cand-empty.txt" 2>&1 || true)"
if printf '%s' "$out" | grep -q 'emit-normalized'; then
  echo "PASS 它說得出怎麼轉"; PASS=$((PASS + 1))
else
  echo "FAIL 它沒說怎麼轉：$out"; FAIL=$((FAIL + 1))
fi

# 二、轉換過了，但解析器空手而文字裡有 PR URL：兩邊對不上，去看解析器。
expect "轉換過而解析器空手是格式不合" \
  normalized cand-empty POLARIS_DISCOVERY_FORMAT_MISMATCH 2

# 三、兩者不得共用同一個標記：它們的下一步相反。
a="$(bash "$PROBE" --raw-dump "$WORK/escaped.txt" --candidates "$WORK/cand-empty.txt" 2>&1 || true)"
b="$(bash "$PROBE" --raw-dump "$WORK/normalized.txt" --candidates "$WORK/cand-empty.txt" 2>&1 || true)"
# 只斷言「兩者不同」是不夠的：壞掉的那一版給的是 SOURCE_UNAVAILABLE 與 FORMAT_MISMATCH，
# 那也是兩個不同的字串，於是這一條在它身上照樣是綠的。要斷言的是那一對具體的值。
if [[ "$(printf '%s' "$a" | head -1)" == "POLARIS_DISCOVERY_NOT_NORMALIZED" \
   && "$(printf '%s' "$b" | head -1)" == "POLARIS_DISCOVERY_FORMAT_MISMATCH" ]]; then
  echo "PASS 兩種格式問題各自是它該有的那一個標記"; PASS=$((PASS + 1))
else
  echo "FAIL 標記對不上：$(printf '%s' "$a" | head -1) / $(printf '%s' "$b" | head -1)"
  FAIL=$((FAIL + 1))
fi

# 四、真的沒有 header：這才是拿不到。轉換的修法不得掩蓋它。
expect "文字裡完全沒有 header 仍然是來源不可得" \
  no-headers cand-empty POLARIS_DISCOVERY_SOURCE_UNAVAILABLE 2
expect "空檔案仍然是來源不可得" \
  empty cand-empty POLARIS_DISCOVERY_SOURCE_UNAVAILABLE 2

# 五、正常的那一條要還在。只驗紅的那幾種，等於沒有驗到「它還能放行」。
expect "轉換過而且解析器有產出，走正常的路" \
  normalized cand-one POLARIS_DISCOVERY_OK 0

echo "review-inbox-discovery-probe format selftest: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
