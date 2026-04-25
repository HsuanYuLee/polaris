#!/usr/bin/env bash
# scripts/env/health-check.sh — D11 L2 primitive.
#
# Polls a URL until it returns HTTP 2xx or until the timeout expires.
# Tool-agnostic: accepts the URL as a direct arg; reads no config.
#
# Usage:
#   health-check.sh URL [--timeout SECONDS] [--interval SECONDS] [--accept-codes "200 301 302"]
#
# Exit codes:
#   0  HTTP 2xx (or matched --accept-codes) within timeout
#   1  Timeout exhausted, last status printed to stderr
#   2  Usage error (missing URL, malformed flag)
#
# Stdout (on success): one line summary "PASS HTTP {code} {url}".
# Stderr: progress / failure detail.
#
# Defaults: --timeout 60, --interval 2, --accept-codes "2xx".
#
# Composable: ensure-dependencies.sh / start-command.sh / start-test-env.sh
# all call back into this primitive — keep the contract minimal and stable.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

usage() {
  cat <<EOF >&2
Usage: $(basename "$0") URL [--timeout SECONDS] [--interval SECONDS] [--accept-codes "200 301 302"]

Polls URL until HTTP 2xx (default) or one of --accept-codes is observed.

Exit:  0 = healthy, 1 = timeout, 2 = usage error.
EOF
}

# ── Args ────────────────────────────────────────────────────────────────────
URL=""
TIMEOUT=60
INTERVAL=2
ACCEPT_CODES=""   # empty means "any 2xx"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout) TIMEOUT="${2:-}"; shift 2 ;;
    --interval) INTERVAL="${2:-}"; shift 2 ;;
    --accept-codes) ACCEPT_CODES="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) env_lib_log_fail "unknown flag: $1"; usage; exit 2 ;;
    *)
      if [[ -z "$URL" ]]; then URL="$1"; else
        env_lib_log_fail "unexpected positional arg: $1"; usage; exit 2
      fi
      shift ;;
  esac
done

if [[ -z "$URL" ]]; then
  env_lib_log_fail "URL is required"; usage; exit 2
fi
if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]]; then
  env_lib_log_fail "--timeout must be an integer (got: $TIMEOUT)"; exit 2
fi
if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [[ "$INTERVAL" -lt 1 ]]; then
  env_lib_log_fail "--interval must be a positive integer (got: $INTERVAL)"; exit 2
fi

# ── Poll loop ───────────────────────────────────────────────────────────────
elapsed=0
last_code="000"
while [[ $elapsed -lt $TIMEOUT ]]; do
  raw=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$URL" 2>/dev/null || echo "000")
  code=$(echo "$raw" | tr -cd '0-9' | sed -E 's/^([0-9]{3}).*/\1/')
  [[ -z "$code" ]] && code="000"
  last_code="$code"

  matched=false
  if [[ -n "$ACCEPT_CODES" ]]; then
    for ac in $ACCEPT_CODES; do
      if [[ "$code" == "$ac" ]]; then matched=true; break; fi
    done
  else
    [[ "$code" =~ ^2[0-9][0-9]$ ]] && matched=true
  fi

  if $matched; then
    env_lib_log_pass "HTTP $code $URL"
    echo "PASS HTTP $code $URL"
    exit 0
  fi

  sleep "$INTERVAL"
  elapsed=$((elapsed + INTERVAL))
done

env_lib_log_fail "HTTP $last_code $URL after ${TIMEOUT}s (accept=${ACCEPT_CODES:-2xx})"
exit 1
