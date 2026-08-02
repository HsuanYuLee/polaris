#!/usr/bin/env bash
# Polaris Session Timeline — append-only JSONL event log.
# Schema: skills/references/session-timeline.md
# Storage: skills/references/polaris-project-dir.md
set -euo pipefail

: "${POLARIS_WORKSPACE_ROOT:?POLARIS_WORKSPACE_ROOT must be set}"
SLUG="${POLARIS_PROJECT_SLUG:-$(basename "$POLARIS_WORKSPACE_ROOT")}"
PROJECT_DIR="$HOME/.polaris/projects/$SLUG"
TIMELINE_FILE="$PROJECT_DIR/timeline.jsonl"
mkdir -p "$PROJECT_DIR"
touch "$TIMELINE_FILE"

usage() {
  cat <<'EOF'
Usage: polaris-timeline.sh <command> [options]

Commands:
  append        Append an event
  query         Emit events, optionally filtered by --since / --event / --last
  checkpoints   Shortcut for 'query --event checkpoint --last N'
  help          Show this help

Env:
  POLARIS_WORKSPACE_ROOT   Workspace root (required)
  POLARIS_PROJECT_SLUG     Override slug (default: basename of root)

Run '<command> --help' for command-specific flags.
EOF
}

die() { echo "polaris-timeline: $*" >&2; exit 2; }

# ISO-8601 UTC with Z suffix, e.g. 2026-04-22T07:30:00Z
# (UTC + Z is what jq's fromdateiso8601 expects natively.)
iso_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# Resolve --since to epoch seconds. Accepts: today, YYYY-MM-DD, <N>h
resolve_since_epoch() {
  local since="$1"
  case "$since" in
    today)
      # start of today
      date -j -f "%Y-%m-%d" "$(date +%Y-%m-%d)" +%s 2>/dev/null \
        || date -d "$(date +%Y-%m-%d)" +%s
      ;;
    *[hH])
      local n="${since%[hH]}"
      [[ "$n" =~ ^[0-9]+$ ]] || die "invalid --since: $since"
      echo $(( $(date +%s) - n * 3600 ))
      ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
      date -j -f "%Y-%m-%d" "$since" +%s 2>/dev/null \
        || date -d "$since" +%s
      ;;
    *)
      die "invalid --since: $since (expected today | Nh | YYYY-MM-DD)"
      ;;
  esac
}

cmd_append() {
  local event="" skill="" ticket="" branch="" pr_url=""
  local outcome="" duration="" note="" company="" text="" session_id=""
  # Allow arbitrary extra fields via --field key=value (JSON-encoded value)
  local -a extra_fields=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --event) event="$2"; shift 2 ;;
      --skill) skill="$2"; shift 2 ;;
      --ticket) ticket="$2"; shift 2 ;;
      --branch) branch="$2"; shift 2 ;;
      --pr-url) pr_url="$2"; shift 2 ;;
      --outcome) outcome="$2"; shift 2 ;;
      --duration) duration="$2"; shift 2 ;;
      --note) note="$2"; shift 2 ;;
      --company) company="$2"; shift 2 ;;
      --text) text="$2"; shift 2 ;;
      --session-id) session_id="$2"; shift 2 ;;
      --field) extra_fields+=("$2"); shift 2 ;;
      --help)
        echo "append --event E [--skill S] [--ticket T] [--branch B] [--pr-url U]"
        echo "       [--outcome success|fail|partial|skipped] [--duration N] [--note N]"
        echo "       [--company C] [--text T] [--session-id ID] [--field key=jsonvalue ...]"
        echo ""
        echo "Dedup: when --event session_summary is combined with --session-id,"
        echo "       prior entries sharing the same (event, session_id) are removed"
        echo "       before the new entry is appended (latest summary wins per session)."
        return 0 ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  [[ -z "$event" ]] && die "required: --event"
  if [[ -n "$duration" ]]; then
    [[ "$duration" =~ ^[0-9]+$ ]] || die "--duration must be integer seconds"
  fi

  local ts
  ts=$(iso_now)

  local obj
  obj=$(jq -cn --arg ts "$ts" --arg event "$event" \
    --arg skill "$skill" --arg ticket "$ticket" --arg branch "$branch" \
    --arg pr_url "$pr_url" --arg outcome "$outcome" --arg duration "$duration" \
    --arg note "$note" --arg company "$company" --arg text "$text" \
    --arg session_id "$session_id" '
    {ts: $ts, event: $event}
    | (if $skill != "" then . + {skill: $skill} else . end)
    | (if $ticket != "" then . + {ticket: $ticket} else . end)
    | (if $branch != "" then . + {branch: $branch} else . end)
    | (if $pr_url != "" then . + {pr_url: $pr_url} else . end)
    | (if $outcome != "" then . + {outcome: $outcome} else . end)
    | (if $duration != "" then . + {duration_s: ($duration | tonumber)} else . end)
    | (if $note != "" then . + {note: $note} else . end)
    | (if $company != "" then . + {company: $company} else . end)
    | (if $text != "" then . + {text: $text} else . end)
    | (if $session_id != "" then . + {session_id: $session_id} else . end)
  ')

  # Merge extra fields (format: key=jsonvalue)
  for kv in "${extra_fields[@]:-}"; do
    [[ -z "$kv" ]] && continue
    local k="${kv%%=*}" v="${kv#*=}"
    [[ "$k" == "$kv" ]] && die "--field expects key=jsonvalue (got: $kv)"
    echo "$v" | jq -e . >/dev/null 2>&1 || die "--field '$k' value is not valid JSON: $v"
    obj=$(echo "$obj" | jq -c --arg k "$k" --argjson v "$v" '. + {($k): $v}')
  done

  # Dedup session_summary by session_id: rewrite file removing prior matching entries.
  # Rationale (DP-024 D4): one PreCompact + one Stop may fire in the same session;
  # the later narrative is always the authoritative one. Non-session_summary events
  # keep append-only semantics.
  if [[ "$event" == "session_summary" && -n "$session_id" && -s "$TIMELINE_FILE" ]]; then
    local tmp="${TIMELINE_FILE}.tmp"
    jq -c --arg sid "$session_id" '
      select(.event != "session_summary" or (.session_id // "") != $sid)
    ' "$TIMELINE_FILE" > "$tmp"
    mv "$tmp" "$TIMELINE_FILE"
  fi

  echo "$obj" >> "$TIMELINE_FILE"
  echo "appended: event=$event"
}

cmd_query() {
  local since="" event_filter="" last=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --since) since="$2"; shift 2 ;;
      --event) event_filter="$2"; shift 2 ;;
      --last) last="$2"; shift 2 ;;
      --help) echo "query [--since today|Nh|YYYY-MM-DD] [--event E] [--last N]"; return 0 ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  [[ ! -s "$TIMELINE_FILE" ]] && return 0

  local since_epoch=0
  if [[ -n "$since" ]]; then
    since_epoch=$(resolve_since_epoch "$since")
  fi

  local output
  output=$(jq -c --argjson since_epoch "$since_epoch" --arg event_filter "$event_filter" '
    # Parse ts tolerant of UTC Z, +HHMM, and +HH:MM offsets (legacy entries).
    def ts_epoch:
      . as $ts
      | if test("Z$") then
          $ts | fromdateiso8601
        else
          ($ts | capture("^(?<dt>.*?)(?<sign>[+-])(?<h>[0-9]{2}):?(?<m>[0-9]{2})$")) as $p
          | (($p.dt + "Z") | fromdateiso8601) as $base
          | (($p.h | tonumber) * 3600 + ($p.m | tonumber) * 60) as $off
          | (if $p.sign == "+" then $base - $off else $base + $off end)
        end;
    select($event_filter == "" or .event == $event_filter)
    | select($since_epoch == 0 or ((.ts | ts_epoch) >= $since_epoch))
  ' "$TIMELINE_FILE")

  if [[ -n "$last" ]]; then
    [[ "$last" =~ ^[0-9]+$ ]] || die "--last must be integer"
    echo "$output" | tail -n "$last"
  else
    echo "$output"
  fi
}

cmd_checkpoints() {
  local last=5
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --last) last="$2"; shift 2 ;;
      --help) echo "checkpoints [--last N]  (default 5)"; return 0 ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  [[ "$last" =~ ^[0-9]+$ ]] || die "--last must be integer"
  [[ ! -s "$TIMELINE_FILE" ]] && return 0
  jq -c 'select(.event == "checkpoint")' "$TIMELINE_FILE" | tail -n "$last"
}

cmd="${1:-help}"
[[ $# -gt 0 ]] && shift
case "$cmd" in
  append)       cmd_append "$@" ;;
  query)        cmd_query "$@" ;;
  checkpoints)  cmd_checkpoints "$@" ;;
  help|--help|-h) usage ;;
  *) echo "unknown command: $cmd" >&2; usage; exit 2 ;;
esac
