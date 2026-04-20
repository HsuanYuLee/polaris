#!/usr/bin/env bash
# slack-webapi.sh — Slack MCP fallback CLI via Slack Web API
#
# Requires:
#   - SLACK_BOT_TOKEN (xoxb-...)
#   - jq
#
# Usage:
#   ./slack-webapi.sh read-channel --channel-id C123 --oldest 1712841600 --limit 100
#   ./slack-webapi.sh read-thread --channel-id C123 --thread-ts 1776130982.981829
#   ./slack-webapi.sh send-message --channel-id C123 --thread-ts 1776130982.981829 --message "hello"

set -euo pipefail

require_token() {
  if [[ -z "${SLACK_BOT_TOKEN:-}" ]]; then
    echo "ERROR: SLACK_BOT_TOKEN is required for Slack CLI fallback." >&2
    exit 1
  fi
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required." >&2
    exit 1
  fi
}

api_post() {
  local endpoint="$1"
  shift
  curl -sS "https://slack.com/api/${endpoint}" \
    -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
    -H "Content-Type: application/json; charset=utf-8" \
    -d "$*"
}

assert_ok() {
  local resp="$1"
  local ok
  ok="$(echo "$resp" | jq -r '.ok // false')"
  if [[ "$ok" != "true" ]]; then
    local err
    err="$(echo "$resp" | jq -r '.error // "unknown_error"')"
    echo "ERROR: Slack API failed: ${err}" >&2
    exit 1
  fi
}

cmd="${1:-}"
if [[ -z "$cmd" ]]; then
  echo "Usage: $0 <read-channel|read-thread|send-message> [args]" >&2
  exit 1
fi
shift

require_token
require_jq

case "$cmd" in
  read-channel)
    channel_id=""
    oldest=""
    limit="100"

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --channel-id) channel_id="${2:-}"; shift 2 ;;
        --oldest) oldest="${2:-}"; shift 2 ;;
        --limit) limit="${2:-}"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done

    if [[ -z "$channel_id" ]]; then
      echo "ERROR: --channel-id is required" >&2
      exit 1
    fi

    payload="$(jq -n \
      --arg channel "$channel_id" \
      --arg oldest "$oldest" \
      --argjson limit "$limit" \
      '{channel: $channel, limit: $limit}
       + (if $oldest != "" then {oldest: $oldest} else {} end)')"
    resp="$(api_post "conversations.history" "$payload")"
    assert_ok "$resp"
    echo "$resp"
    ;;

  read-thread)
    channel_id=""
    thread_ts=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --channel-id) channel_id="${2:-}"; shift 2 ;;
        --thread-ts) thread_ts="${2:-}"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done

    if [[ -z "$channel_id" || -z "$thread_ts" ]]; then
      echo "ERROR: --channel-id and --thread-ts are required" >&2
      exit 1
    fi

    payload="$(jq -n --arg channel "$channel_id" --arg ts "$thread_ts" '{channel: $channel, ts: $ts, limit: 200}')"
    resp="$(api_post "conversations.replies" "$payload")"
    assert_ok "$resp"
    echo "$resp"
    ;;

  send-message)
    channel_id=""
    thread_ts=""
    message=""
    message_file=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --channel-id) channel_id="${2:-}"; shift 2 ;;
        --thread-ts) thread_ts="${2:-}"; shift 2 ;;
        --message) message="${2:-}"; shift 2 ;;
        --message-file) message_file="${2:-}"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done

    if [[ -z "$channel_id" ]]; then
      echo "ERROR: --channel-id is required" >&2
      exit 1
    fi
    if [[ -z "$message" && -z "$message_file" ]]; then
      echo "ERROR: either --message or --message-file is required" >&2
      exit 1
    fi
    if [[ -n "$message_file" ]]; then
      message="$(cat "$message_file")"
    fi

    payload="$(jq -n \
      --arg channel "$channel_id" \
      --arg text "$message" \
      --arg thread_ts "$thread_ts" \
      '{channel: $channel, text: $text}
       + (if $thread_ts != "" then {thread_ts: $thread_ts} else {} end)')"
    resp="$(api_post "chat.postMessage" "$payload")"
    assert_ok "$resp"
    echo "$resp"
    ;;

  *)
    echo "Unknown command: $cmd" >&2
    exit 1
    ;;
esac
