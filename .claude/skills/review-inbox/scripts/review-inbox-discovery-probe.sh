#!/usr/bin/env bash
# Purpose: Fail-closed discovery probe for review-inbox Slack channel scan. Given a raw
#          MCP "detailed" channel dump plus the parser-produced PR-URL candidate list,
#          classify the discovery result into one of four states and fail loud on the
#          three degraded states instead of silently falling back to an empty inbox.
# Inputs:  --raw-dump <file>        raw MCP detailed channel text (required)
#          --candidates <file>      parsed PR URLs, one per line (required; may be empty)
#          --stale-seconds <int>    staleness threshold in seconds (default 86400)
#          --now-epoch <int>        override "now" for deterministic testing (default: date +%s)
#          --source-available 0|1   1 = fetch succeeded / token set (default 1)
#          --window-seconds <int>   這一趟宣告的回溯時間窗（channel 模式必填，DP-681）
#          --mode channel|thread    thread 模式只讀一條討論串，不判涵蓋範圍（default channel）
# Outputs: stdout  one structured POLARIS_DISCOVERY_* marker line + human note
#          exit 0  legitimate-empty (or non-empty: candidates present)
#          exit 2  format-mismatch / stale / source-unavailable (fail-closed)
#          exit 1  usage / argument error
# Markers: POLARIS_DISCOVERY_SOURCE_UNAVAILABLE
#          POLARIS_DISCOVERY_NOT_NORMALIZED
#          POLARIS_DISCOVERY_FORMAT_MISMATCH
#          POLARIS_DISCOVERY_STALE
#          POLARIS_DISCOVERY_UNREAD_THREADS
#          POLARIS_DISCOVERY_UNPAGED
#          POLARIS_DISCOVERY_NO_PAGINATION_MARKER
#          POLARIS_DISCOVERY_DUMP_UNMEASURABLE
#          POLARIS_DISCOVERY_LEGITIMATE_EMPTY (exit 0, informational)
#          POLARIS_DISCOVERY_OK (exit 0, candidates present)
#
# DP-681：原本那四個降級態全部在問「這份資料讀不讀得懂」，沒有一個在問「這份資料讀完了
# 沒」。2026-09-04 兩輪 discovery 的 dump 都停在最新那一頁、一條 thread 都沒讀，而兩輪
# 的答案都是 POLARIS_DISCOVERY_OK——一份不完整的資料跟一份完整的資料，在那四態底下長得
# 一模一樣。涵蓋範圍的判定放在 STALE 之後、OK/LEGITIMATE_EMPTY 之前：那一趟有 82 個 URL
# 而 candidate 是 0，所以它非空也要被檢查，不能只在空的時候問。
#
# Decision order is load-bearing (AC5 adversarial enforce + AC-NEG1): rule out
# SOURCE_UNAVAILABLE, NOT_NORMALIZED and FORMAT_MISMATCH first, then STALE, and only a
# successfully parsed + fresh + genuinely empty channel reaches legitimate-empty (exit 0).
# This keeps a real empty inbox from being misclassified as a degraded state.
#
# 順序本身會讓一個判定變得不可達，而不可達的判定跟不存在的判定在出事的時候長得一樣。
# 2026-08-09 之前，`escaped 但完整` 這個輸入撞到的是上面那段無條件 `exit 2`，於是底下的
# FORMAT_MISMATCH 對它永遠到不了——它寫在這張清單上，看起來在守。所以這五個狀態各有一支
# selftest 餵已知輸入，見 selftests/review-inbox-discovery-probe-format-selftest.sh。

set -euo pipefail

# --- defaults -------------------------------------------------------------------------
RAW_DUMP=''
CANDIDATES=''
STALE_SECONDS='86400'
NOW_EPOCH=''
SOURCE_AVAILABLE='1'
WINDOW_SECONDS=''
MODE='channel'

usage() {
  cat <<'USAGE'
Usage: review-inbox-discovery-probe.sh --raw-dump <file> --candidates <file>
                                       [--stale-seconds <int>] [--now-epoch <int>]
                                       [--source-available 0|1] [--mode channel|thread]
                                       --window-seconds <int>   (channel 模式必填)

Classifies a review-inbox Slack discovery result into these states:
  - source-unavailable  (exit 2, POLARIS_DISCOVERY_SOURCE_UNAVAILABLE)
  - not-normalized      (exit 2, POLARIS_DISCOVERY_NOT_NORMALIZED)
  - format-mismatch     (exit 2, POLARIS_DISCOVERY_FORMAT_MISMATCH)
  - stale               (exit 2, POLARIS_DISCOVERY_STALE)
  - legitimate-empty    (exit 0, POLARIS_DISCOVERY_LEGITIMATE_EMPTY)
  - non-empty           (exit 0, POLARIS_DISCOVERY_OK)
USAGE
}

fail_usage() {
  printf 'POLARIS_DISCOVERY_USAGE_ERROR: %s\n' "$1" >&2
  usage >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --raw-dump)
      RAW_DUMP="${2:-}"
      shift 2
      ;;
    --candidates)
      CANDIDATES="${2:-}"
      shift 2
      ;;
    --stale-seconds)
      STALE_SECONDS="${2:-}"
      shift 2
      ;;
    --now-epoch)
      NOW_EPOCH="${2:-}"
      shift 2
      ;;
    --source-available)
      SOURCE_AVAILABLE="${2:-}"
      shift 2
      ;;
    --window-seconds)
      WINDOW_SECONDS="${2:-}"
      shift 2
      ;;
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      fail_usage "unknown argument: $1"
      ;;
  esac
done

[[ -n "$RAW_DUMP" ]] || fail_usage '--raw-dump is required'
[[ -n "$CANDIDATES" ]] || fail_usage '--candidates is required'

case "$STALE_SECONDS" in
  '' | *[!0-9]*) fail_usage "--stale-seconds must be a non-negative integer, got: '$STALE_SECONDS'" ;;
esac

case "$MODE" in
  channel | thread) ;;
  *) fail_usage "--mode must be channel or thread, got: '$MODE'" ;;
esac

# 時間窗是這一趟自己說出來的，不是這裡猜的：它由使用者的語意推導（未指定時是 7 天），
# 而那個推導只有呼叫的人知道。沒交進來就停——挑一個預設值等於讓「窗有多長」有兩個答案，
# 而其中一個沒有人看得到。
if [[ "$MODE" == 'channel' ]]; then
  case "$WINDOW_SECONDS" in
    '') fail_usage '--window-seconds is required in channel mode: 這一趟回溯多久只有呼叫的人知道（未指定時的預設是 7 天 = 604800）' ;;
    *[!0-9]*) fail_usage "--window-seconds must be a non-negative integer, got: '$WINDOW_SECONDS'" ;;
  esac
fi

if [[ -n "$NOW_EPOCH" ]]; then
  case "$NOW_EPOCH" in
    *[!0-9]*) fail_usage "--now-epoch must be a non-negative integer, got: '$NOW_EPOCH'" ;;
  esac
else
  NOW_EPOCH="$(date +%s)"
fi

# --- 1. SOURCE_UNAVAILABLE ------------------------------------------------------------
# Token unset / fetch nonzero exit collapses into --source-available 0. A missing or
# unreadable raw dump is also treated as source-unavailable: the upstream fetch never
# produced a parseable artifact (EC3).
if [[ "$SOURCE_AVAILABLE" != '1' ]]; then
  printf 'POLARIS_DISCOVERY_SOURCE_UNAVAILABLE\n'
  printf 'discovery source unavailable: fetch failed or token unset; fail loud, do not fall back to label scan\n'
  exit 2
fi

if [[ ! -r "$RAW_DUMP" ]]; then
  printf 'POLARIS_DISCOVERY_SOURCE_UNAVAILABLE\n'
  printf 'discovery source unavailable: raw dump %s missing or unreadable\n' "$RAW_DUMP"
  exit 2
fi

# Detailed-header parseability: the parser (extract-pr-urls.py channel mode) keys off
# `=== Message from ... ===` headers and `Message TS:` lines. If the raw dump has neither
# a message header nor a TS line, the detailed format could not be parsed at all → the
# source is effectively unavailable (cannot trust 0-URL as "empty"). EC3.
message_header_count="$(grep -c '^=== Message from ' "$RAW_DUMP" 2>/dev/null || true)"
message_header_count="${message_header_count:-0}"
ts_line_count="$(grep -c '^Message TS: ' "$RAW_DUMP" 2>/dev/null || true)"
ts_line_count="${ts_line_count:-0}"

if [[ "$message_header_count" -eq 0 && "$ts_line_count" -eq 0 ]]; then
  # 沒有 line-anchored header 有兩種原因，而它們的下一步完全相反。分開之前，這裡對兩種
  # 都回 SOURCE_UNAVAILABLE——於是一份**內容完整**的 dump 被說成「上游拿不到」，而排查
  # 的人被指去看 token 與網路。這個 runtime 的 MCP detailed 回的就是那一種：真換行被
  # escape 成字面的 `\n`，整份擠在一行裡，header 好端端地藏在字串內。
  #
  # 判準是**那些 header 在不在文字裡**，不是它們在不在行首。在的話這是格式問題，資料
  # 是好的，下一步是先 normalize；不在的話才是真的沒有東西可讀。
  #
  # 為什麼不能等到底下那段 FORMAT_MISMATCH：那一段排在這裡後面，而這裡 `exit 2`。一個
  # 排在無條件 exit 之後的判定，對這個形狀永遠到不了——它寫在檔頭的 Markers 清單裡，
  # 看起來在守，實際上不可達。
  if grep -q '=== Message from \|Message TS: ' "$RAW_DUMP" 2>/dev/null; then
    # 自己一個標記，不跟 FORMAT_MISMATCH 共用：兩者的下一步相反。這一個是「先把它轉過來」
    # （資料是好的），那一個是「轉過來了，但解析器跟這份文字對不上」（要去看解析器）。
    # 共用一個標記等於把兩條不同的排查路徑指向同一個方向。
    printf 'POLARIS_DISCOVERY_NOT_NORMALIZED\n'
    printf 'raw dump carries detailed headers but not on their own lines: it is still escaped (literal \\n), not normalized.\n'
    printf 'the data is intact — normalize it first, then probe the normalized file:\n'
    printf '  python3 %s/extract-pr-urls.py --emit-normalized <normalized_out> ... < %s\n' \
      "$(dirname "$0")" "$RAW_DUMP"
    exit 2
  fi
  printf 'POLARIS_DISCOVERY_SOURCE_UNAVAILABLE\n'
  printf 'discovery source unavailable: raw dump has no detailed headers (=== Message from / Message TS:) anywhere in the text; cannot parse channel\n'
  exit 2
fi

# Count parsed candidate URLs (ignore blank lines).
candidate_count=0
if [[ -r "$CANDIDATES" ]]; then
  candidate_count="$(grep -c '[^[:space:]]' "$CANDIDATES" 2>/dev/null || true)"
  candidate_count="${candidate_count:-0}"
fi

# --- 2. FORMAT_MISMATCH ---------------------------------------------------------------
# The incident root cause: a concise<->detailed parser mismatch makes a populated channel
# look empty. The honest discriminator from a genuinely-empty inbox is whether the *raw*
# dump still contains GitHub PR URL substrings that the parser failed to surface. If the
# raw text advertises PR URLs but the parser produced 0 candidates, the two disagree =>
# format mismatch (AC2). If the raw text contains no PR URL at all, this is not a mismatch
# (it routes onward to the stale/legitimate-empty decision so AC5/AC-NEG1 hold).
raw_pr_url_count="$(grep -coE 'https://github\.com/[^/[:space:]|>]+/[^/[:space:]|>]+/pull/[0-9]+' "$RAW_DUMP" 2>/dev/null || true)"
raw_pr_url_count="${raw_pr_url_count:-0}"

if [[ "$candidate_count" -eq 0 && "$raw_pr_url_count" -gt 0 ]]; then
  printf 'POLARIS_DISCOVERY_FORMAT_MISMATCH\n'
  printf 'format mismatch: raw channel advertises %s PR URL(s) across %s message header(s) but parser produced 0 candidate(s); likely concise/detailed parser mismatch\n' "$raw_pr_url_count" "$message_header_count"
  exit 2
fi

# --- 3. STALE -------------------------------------------------------------------------
# Source is available and (if empty) format-consistent. Now check freshness using the
# newest Message TS line. `Message TS:` values are epoch floats; compare integer seconds.
newest_ts_int=''
while IFS= read -r ts_raw; do
  [[ -n "$ts_raw" ]] || continue
  ts_int="${ts_raw%%.*}"
  case "$ts_int" in
    '' | *[!0-9]*) continue ;;
  esac
  if [[ -z "$newest_ts_int" || "$ts_int" -gt "$newest_ts_int" ]]; then
    newest_ts_int="$ts_int"
  fi
done < <(sed -n 's/^Message TS: \([0-9][0-9.]*\).*/\1/p' "$RAW_DUMP")

if [[ -z "$newest_ts_int" ]]; then
  # Headers exist but no usable TS line → cannot establish freshness; treat as
  # source-unavailable (degraded), never as legitimate-empty.
  printf 'POLARIS_DISCOVERY_SOURCE_UNAVAILABLE\n'
  printf 'discovery source unavailable: detailed headers present but no parseable Message TS line; cannot establish freshness\n'
  exit 2
fi

age_seconds=$((NOW_EPOCH - newest_ts_int))
if [[ "$age_seconds" -gt "$STALE_SECONDS" ]]; then
  printf 'POLARIS_DISCOVERY_STALE\n'
  printf 'stale: newest message is %ss old (threshold %ss); discovery data may be outdated, fail loud\n' "$age_seconds" "$STALE_SECONDS"
  exit 2
fi

# --- 3.5 涵蓋範圍：這份資料讀完了沒（DP-681） -------------------------------------------
# 判準都在 dump 自己身上（thread 那一行、cursor 那一行、thread 區段標記），所以這裡不再
# 打一次 Slack。thread 模式只讀一條討論串，沒有「翻完頻道」這回事，跳過。
if [[ "$MODE" == 'channel' ]]; then
  ANALYZER="$(dirname "$0")/analyze-channel-dump.py"
  if [[ ! -f "$ANALYZER" ]]; then
    printf 'POLARIS_DISCOVERY_DUMP_UNMEASURABLE\n'
    printf 'coverage analyzer missing: %s\n' "$ANALYZER"
    exit 2
  fi
  coverage_out=''
  coverage_rc=0
  coverage_out="$(python3 "$ANALYZER" --dump "$RAW_DUMP" \
    --window-seconds "$WINDOW_SECONDS" --now-epoch "$NOW_EPOCH" 2>&1)" || coverage_rc=$?
  if [[ "$coverage_rc" -ne 0 ]]; then
    printf '%s\n' "$coverage_out"
    exit 2
  fi
fi

# --- 4. legitimate-empty / non-empty (exit 0) -----------------------------------------
# Source available, format-consistent, and fresh. If there are candidates, discovery is
# healthy and non-empty; if there are zero candidates this is a genuine empty inbox that
# must NOT be misclassified as a degraded state (AC5 / AC-NEG1).
if [[ "$candidate_count" -gt 0 ]]; then
  printf 'POLARIS_DISCOVERY_OK\n'
  printf 'discovery healthy: %s candidate PR URL(s), source fresh (newest %ss old)\n' "$candidate_count" "$age_seconds"
  exit 0
fi

printf 'POLARIS_DISCOVERY_LEGITIMATE_EMPTY\n'
printf 'legitimate empty: source fresh (newest %ss old) and 0 review PR(s); genuinely empty inbox, not a degraded fallback\n' "$age_seconds"
exit 0
