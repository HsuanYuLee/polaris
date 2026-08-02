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
# Outputs: stdout  one structured POLARIS_DISCOVERY_* marker line + human note
#          exit 0  legitimate-empty (or non-empty: candidates present)
#          exit 2  format-mismatch / stale / source-unavailable (fail-closed)
#          exit 1  usage / argument error
# Markers: POLARIS_DISCOVERY_SOURCE_UNAVAILABLE
#          POLARIS_DISCOVERY_FORMAT_MISMATCH
#          POLARIS_DISCOVERY_STALE
#          POLARIS_DISCOVERY_LEGITIMATE_EMPTY (exit 0, informational)
#          POLARIS_DISCOVERY_OK (exit 0, candidates present)
#
# Decision order is load-bearing (AC5 adversarial enforce + AC-NEG1): rule out
# SOURCE_UNAVAILABLE and FORMAT_MISMATCH first, then STALE, and only a successfully
# parsed + fresh + genuinely empty channel reaches legitimate-empty (exit 0). This keeps
# a real empty inbox from being misclassified as a degraded state.

set -euo pipefail

# --- defaults -------------------------------------------------------------------------
RAW_DUMP=''
CANDIDATES=''
STALE_SECONDS='86400'
NOW_EPOCH=''
SOURCE_AVAILABLE='1'

usage() {
  cat <<'USAGE'
Usage: review-inbox-discovery-probe.sh --raw-dump <file> --candidates <file>
                                       [--stale-seconds <int>] [--now-epoch <int>]
                                       [--source-available 0|1]

Classifies a review-inbox Slack discovery result into four states:
  - source-unavailable  (exit 2, POLARIS_DISCOVERY_SOURCE_UNAVAILABLE)
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
  printf 'POLARIS_DISCOVERY_SOURCE_UNAVAILABLE\n'
  printf 'discovery source unavailable: raw dump has no detailed headers (=== Message from / Message TS:); cannot parse channel\n'
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
