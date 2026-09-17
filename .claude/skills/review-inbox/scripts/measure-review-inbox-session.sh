#!/usr/bin/env bash
# measure-review-inbox-session.sh — emit review-inbox telemetry JSON.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

RUN_ID="review-inbox-$(date +%Y%m%d%H%M%S)"
CANDIDATE_COUNT=0
REVIEWED_COUNT=0
DURATION_SECONDS=0
SUB_AGENT_TOKENS=0
INPUT_FILE=""
OUTPUT_FILE=""
ARTIFACT_DIR=""
OUT_PATH=""
WRITE_LEARNINGS=false
VERIFY_DELIVERED=false
MY_USER=""
SINCE=""
MIN_BODY_CHARS=40
VERIFY_PRS=()
LEARNINGS_SCRIPT="$(dirname "${BASH_SOURCE[0]}")/polaris-learnings.sh"

usage() {
  cat >&2 <<'EOF'
Usage:
  # 1. telemetry（本來就有的那個模式）
  measure-review-inbox-session.sh [options]

  # 2. 輪次收尾對帳：這一輪派出去的 review，真的到了嗎
  measure-review-inbox-session.sh --verify-delivered --my-user USER --since ISO8601 \
    --pr OWNER/REPO#N [--pr OWNER/REPO#N]...

Options:
  --run-id ID
  --candidate-count N
  --reviewed-count N
  --duration-seconds N
  --sub-agent-tokens N
  --input-file PATH
  --output-file PATH
  --artifact-dir PATH
  --out PATH
  --write-learnings
  --learnings-script PATH

Verify-delivered options:
  --verify-delivered   對帳模式。只做對帳，不產 telemetry
  --my-user USER       要對帳的帳號（送出者）
  --since ISO8601      輪次起點；早於這個時間送出的不看
  --pr OWNER/REPO#N    這一輪派出的 PR，一顆給一次
  --min-body-chars N   保留給呼叫端，目前的判準不用它（見腳本裡那張表）
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id) RUN_ID="$2"; shift 2 ;;
    --candidate-count) CANDIDATE_COUNT="$2"; shift 2 ;;
    --reviewed-count) REVIEWED_COUNT="$2"; shift 2 ;;
    # DP-575：這個欄位記的是呼叫端自己傳進去的字串，10 筆歷史裡已經有一筆是假的。
    # 規定怎麼派的那一層不在了，欄位跟著走；舊的呼叫端傳過來時吃掉不報錯。
    --runtime-plan-kind) shift 2 ;;
    --duration-seconds) DURATION_SECONDS="$2"; shift 2 ;;
    --sub-agent-tokens) SUB_AGENT_TOKENS="$2"; shift 2 ;;
    --input-file) INPUT_FILE="$2"; shift 2 ;;
    --output-file) OUTPUT_FILE="$2"; shift 2 ;;
    --artifact-dir) ARTIFACT_DIR="$2"; shift 2 ;;
    --out) OUT_PATH="$2"; shift 2 ;;
    --write-learnings) WRITE_LEARNINGS=true; shift ;;
    --verify-delivered) VERIFY_DELIVERED=true; shift ;;
    --my-user) MY_USER="$2"; shift 2 ;;
    --since) SINCE="$2"; shift 2 ;;
    --pr) VERIFY_PRS+=("$2"); shift 2 ;;
    --min-body-chars) MIN_BODY_CHARS="$2"; shift 2 ;;
    --learnings-script) LEARNINGS_SCRIPT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

# ── 對帳模式：這一輪派出去的 review，真的到了嗎 ─────────────────────────────
#
# **送出去了不等於送到了，而這兩者在我們這一端長得一樣。** 2026-09-17 一則 review 的 body
# 是字面值 `@/dev/stdin`，正文從來沒到作者手上，靠對方兩個人各自提到才發現。
#
# **這一層為什麼在收尾、不在送出者手上**：那一則是繞過 `submit-pr-review.sh` 直接打
# `gh api -f body=@...` 送的，所以送出端的回讀從來沒跑到。這一層問的是 GitHub「我這個
# 帳號在這一輪送出了什麼」——**誰送的不影響它問得到什麼**。
#
# **判準是 `body 長度 > 0` 而且缺 `polaris-review-target` 標記。** 兩條腿缺一不可，各擋一種
# 誤報，兩種都是實測出來的：
#
#   | | body 長度 | 標記 | inline |
#   |---|---|---|---|
#   | 正常長 review（走腳本） | >0 | 有 | 0 或 n |
#   | 正常 inline-only | 0 | 無 | ≥1 |
#   | 2026-09-17 那則壞掉的 | 11 | 無 | 1 |
#
# 只看「body 短」：那則壞掉的帶著 1 則 inline comment，配上「而且沒有 inline comment」
# 之後就抓不到它了（實跑對帳回「可疑 0 則」而當下 body 是 11 字元）。
# 只看「缺標記」：GitHub 的正常 inline-only 形狀 body 本來就空，標記寫在 body 裡所以當然
# 不在——實測五顆 PR 上 16 則全是這一種。
#
# **空 body 是合法形狀，不進可疑；有 body 就一定經過腳本，就一定帶標記。**
#
# **第三條腿是日期下限。** 「有 body 就帶標記」只對標記上線之後送出的 review 成立——標記是
# DP-690（`16ca2f7d`，2026-09-07）才進腳本的，在那之前送的本來就沒有。實測三個 repo、
# 196 則我方 review：全窗有 56 則「有 body、無標記」，全部落在那一天之前，而分界零重疊
# （無標記的長 review 最晚 2026-09-07T07:45:05Z，帶標記的最早 2026-09-08T06:27:22Z）。
# 同一份資料只看 DP-690 之後的 110 則，「有 body 但無標記」是 0。
#
# **這條判準守不到的那一格要說出來**：那次編輯如果寫進去的是空字串，結果是 len=0 ＋ 有
# inline ＋ 無標記，跟上表第二列逐格相同，任何只看 review 本身的判準都分不開。真正分得開
# 的是「送出的時候 body 有多長」，而那個事實只活在送出端——所以回讀掛在送出與編輯兩條
# 路徑上（`submit-pr-review.sh`），這一層是事後的網，不是唯一的網。
if [[ "$VERIFY_DELIVERED" == "true" ]]; then
  [[ -n "$MY_USER" ]] || { echo "measure-review-inbox-session: --verify-delivered 要 --my-user" >&2; exit 2; }
  [[ -n "$SINCE" ]] || { echo "measure-review-inbox-session: --verify-delivered 要 --since" >&2; exit 2; }
  [[ "${#VERIFY_PRS[@]}" -gt 0 ]] || { echo "measure-review-inbox-session: --verify-delivered 要至少一個 --pr" >&2; exit 2; }
  GH_BIN="${POLARIS_GH_BIN:-gh}"
  # 標記上線的那一天。早於它送出的 review 沒有標記是正常的，不進可疑。
  MARKER_SINCE="${POLARIS_REVIEW_MARKER_SINCE:-2026-09-08T00:00:00Z}"
  if [[ "$SINCE" < "$MARKER_SINCE" ]]; then
    echo "REVIEW-DELIVERY: --since（${SINCE}）早於標記上線那一天（${MARKER_SINCE}）——" >&2
    echo "    那之前送出的 review 本來就沒有 polaris-review-target 標記，這一層不看它們。" >&2
  fi
  suspect=0
  unreadable=0
  checked=0
  for pr in "${VERIFY_PRS[@]}"; do
    repo="${pr%%#*}"
    number="${pr##*#}"
    if ! reviews="$("$GH_BIN" api "repos/${repo}/pulls/${number}/reviews" --paginate --slurp 2>/dev/null)"; then
      # **問不到不得讀成「這一顆沒問題」。** 那個方向會讓一次 API 失敗看起來像一次乾淨的對帳。
      echo "POLARIS_REVIEW_DELIVERY_UNREADABLE: ${pr} 的 review 清單問不到，這一顆這一趟沒有對到帳。" >&2
      unreadable=$((unreadable + 1))
      continue
    fi
    # **解析那一步自己也要能說出它失敗了。** 第一版用 process substitution 餵這個迴圈，
    # 而 python 在裡面炸掉的時候迴圈讀到 0 行——於是輸出是「對了 0 則、可疑 0 則」、
    # 離場碼 0。**一次完全失敗的對帳跟一次乾淨的對帳長得一模一樣**，正是這張單在講的病。
    rows="$(mktemp)"
    if ! printf '%s' "$reviews" | python3 -c '
import json, sys
me, since = sys.argv[1], sys.argv[2]
pages = json.load(sys.stdin)
for page in pages:
    for r in page:
        if (r.get("user") or {}).get("login") != me:
            continue
        if str(r.get("submitted_at") or "") < since:
            continue
        body = r.get("body") or ""
        head = body[:60].replace("\t", " ").replace("\n", "\u23ce")
        marked = "marked" if body.startswith("<!-- polaris-review-target:") else "unmarked"
        print("\t".join([str(r.get("id")), str(len(body)), marked, str(r.get("submitted_at") or ""), head]))
' "$MY_USER" "$SINCE" > "$rows" 2>/dev/null; then
      echo "POLARIS_REVIEW_DELIVERY_UNREADABLE: ${pr} 的 review 清單解不開，這一顆這一趟沒有對到帳。" >&2
      unreadable=$((unreadable + 1))
      rm -f "$rows"
      continue
    fi
    # **會空的那一格放最後。** read 在 IFS 是 tab 的時候會把中間的空欄位吃掉，於是
    # body 空的那一則整排往前錯位——判定用的日期那一格讀到空字串，而它看起來完全正常。
    while IFS=$'\t' read -r rid rbody_len rmarked rsubmitted rbody_head; do
      [[ -n "$rid" ]] || continue
      checked=$((checked + 1))
      # 空 body 是合法形狀（只帶 inline comment 的 review），不進可疑。
      [[ "$rbody_len" -gt 0 ]] || continue
      # 有 body 而沒有標記——它沒有經過 submit-pr-review.sh，或者經過了但之後被蓋掉。
      [[ "$rmarked" != "marked" ]] || continue
      # 標記上線之前送出的，沒有標記是正常的。
      [[ ! "$rsubmitted" < "$MARKER_SINCE" ]] || continue
      # 走到這裡就是可疑。再問 inline comment 只為了把現場講清楚，不改變判定。
      inline="$("$GH_BIN" api "repos/${repo}/pulls/${number}/reviews/${rid}/comments" --paginate --slurp 2>/dev/null \
        | python3 -c 'import json,sys
try: print(sum(len(page) for page in json.load(sys.stdin)))
except Exception: print("?")' 2>/dev/null)" || inline="?"
      suspect=$((suspect + 1))
      echo "POLARIS_REVIEW_DELIVERY_SUSPECT: ${pr} review ${rid}" >&2
      echo "    body ${rbody_len} 字元，而它沒有 polaris-review-target 標記——它沒有走" >&2
      echo "    submit-pr-review.sh，或者走了而之後被蓋掉。inline comment ${inline} 則，送出於 ${rsubmitted}。" >&2
      echo "    body 開頭：${rbody_head}" >&2
    done < "$rows"
    rm -f "$rows"
  done
  echo "REVIEW-DELIVERY: 對了 ${checked} 則（${#VERIFY_PRS[@]} 顆 PR，${MY_USER} 在 ${SINCE} 之後送出的）——可疑 ${suspect} 則、問不到 ${unreadable} 處。" >&2
  if [[ "$suspect" -gt 0 || "$unreadable" -gt 0 ]]; then
    exit 6
  fi
  exit 0
fi

for number in "$CANDIDATE_COUNT" "$REVIEWED_COUNT" "$DURATION_SECONDS" "$SUB_AGENT_TOKENS"; do
  if ! [[ "$number" =~ ^[0-9]+$ ]]; then
    echo "measure-review-inbox-session: numeric option expected, got '$number'" >&2
    exit 2
  fi
done

payload=$(python3 - "$RUN_ID" "$CANDIDATE_COUNT" "$REVIEWED_COUNT" \
  "$DURATION_SECONDS" "$SUB_AGENT_TOKENS" "$INPUT_FILE" "$OUTPUT_FILE" "$ARTIFACT_DIR" <<'PY'
import json
import math
import os
import sys
from pathlib import Path

(
    run_id,
    candidate_count,
    reviewed_count,
    duration_seconds,
    sub_agent_tokens,
    input_file,
    output_file,
    artifact_dir,
) = sys.argv[1:]

def text_stats(path: str) -> tuple[int, int, int]:
    if not path:
        return 0, 0, 0
    file_path = Path(path)
    if not file_path.is_file():
        return 0, 0, 0
    text = file_path.read_text(errors="replace")
    lines = 0 if text == "" else text.count("\n") + (0 if text.endswith("\n") else 1)
    chars = len(text)
    estimated_tokens = max(math.ceil(chars / 4), lines * 8)
    return lines, chars, estimated_tokens

def artifact_stats(path: str) -> tuple[int, int]:
    if not path:
        return 0, 0
    root = Path(path)
    if not root.exists():
        return 0, 0
    files = [item for item in root.rglob("*") if item.is_file()]
    return len(files), sum(item.stat().st_size for item in files)

input_lines, input_chars, input_tokens = text_stats(input_file)
output_lines, output_chars, output_tokens = text_stats(output_file)
artifact_count, artifact_bytes = artifact_stats(artifact_dir)

print(json.dumps({
    "run_id": run_id,
    "candidate_count": int(candidate_count),
    "reviewed_count": int(reviewed_count),
    "main_session_input_tokens": input_tokens,
    "main_session_output_tokens": output_tokens,
    "sub_agent_tokens": int(sub_agent_tokens),
    "duration_seconds": int(duration_seconds),
    "estimator_kind": "line_count_proxy",
    "artifact_count": artifact_count,
    "artifact_bytes": artifact_bytes,
    "input_line_count": input_lines,
    "output_line_count": output_lines,
    "input_char_count": input_chars,
    "output_char_count": output_chars,
}, ensure_ascii=False, sort_keys=True))
PY
)

if [[ -n "$OUT_PATH" ]]; then
  mkdir -p "$(dirname "$OUT_PATH")"
  printf '%s\n' "$payload" > "$OUT_PATH"
else
  printf '%s\n' "$payload"
fi

if [[ "$WRITE_LEARNINGS" == "true" ]]; then
  if [[ ! -x "$LEARNINGS_SCRIPT" ]]; then
    echo "measure-review-inbox-session: learnings script not executable: $LEARNINGS_SCRIPT" >&2
    exit 2
  fi
  "$LEARNINGS_SCRIPT" add \
    --key "review-inbox-run-$RUN_ID" \
    --type telemetry \
    --content "review-inbox telemetry run $RUN_ID" \
    --confidence 5 \
    --source review-inbox \
    --tag review-inbox \
    --metadata "{\"review_inbox_run\":$payload}" >/dev/null
fi
