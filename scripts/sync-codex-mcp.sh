#!/usr/bin/env bash
set -euo pipefail

# sync-codex-mcp.sh
#
# Sync baseline MCP servers for Codex so Polaris skills can use Jira/Slack tools.
#
# Default mode is dry-run (no changes).
#
# Usage:
#   bash scripts/sync-codex-mcp.sh --dry-run
#   bash scripts/sync-codex-mcp.sh --apply
#   bash scripts/sync-codex-mcp.sh --apply --login
#   bash scripts/sync-codex-mcp.sh --apply \
#     --with-google-calendar-url "https://gcal.mcp.claude.com/mcp" \
#     --google-calendar-token-env GOOGLE_CALENDAR_MCP_TOKEN

APPLY=false
LOGIN=false
GOOGLE_CALENDAR_URL=""
GOOGLE_CALENDAR_TOKEN_ENV=""

ATLASSIAN_NAME="claude_ai_Atlassian"
SLACK_NAME="claude_ai_Slack"
GOOGLE_CALENDAR_NAME="claude_ai_Google_Calendar"

ATLASSIAN_URL_DEFAULT="https://mcp.atlassian.com/v1/mcp"
SLACK_URL_DEFAULT="https://mcp.slack.com/mcp"

usage() {
  cat <<'EOF'
Usage:
  sync-codex-mcp.sh [options]

Options:
  --dry-run                         Preview changes only (default)
  --apply                           Apply changes via `codex mcp add`
  --login                           Run `codex mcp login` after add (OAuth)
  --with-google-calendar-url URL    Add Google Calendar MCP as streamable HTTP server
  --google-calendar-token-env ENV   Bearer token env var for Google Calendar MCP URL
  -h, --help                        Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) APPLY=false; shift ;;
    --apply) APPLY=true; shift ;;
    --login) LOGIN=true; shift ;;
    --with-google-calendar-url) GOOGLE_CALENDAR_URL="${2:-}"; shift 2 ;;
    --google-calendar-token-env) GOOGLE_CALENDAR_TOKEN_ENV="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if ! command -v codex >/dev/null 2>&1; then
  echo "ERROR: codex command not found. Install Codex CLI first." >&2
  exit 1
fi

if [[ -n "$GOOGLE_CALENDAR_TOKEN_ENV" && -z "$GOOGLE_CALENDAR_URL" ]]; then
  echo "ERROR: --google-calendar-token-env requires --with-google-calendar-url." >&2
  exit 1
fi

have_server() {
  local name="$1"
  codex mcp list 2>/dev/null | awk 'NR>1 && NF>0 {print $1}' | grep -Fxq "$name"
}

existing_transport_type() {
  local name="$1"
  codex mcp get "$name" --json 2>/dev/null | jq -r '.transport.type // ""'
}

existing_streamable_url() {
  local name="$1"
  codex mcp get "$name" --json 2>/dev/null | jq -r '.transport.url // ""'
}

print_header() {
  echo "Codex MCP Sync"
  echo "Mode: $([[ "$APPLY" == true ]] && echo "APPLY" || echo "DRY-RUN")"
  echo
}

add_stdio_server() {
  # Deprecated path kept intentionally to avoid hard break if reused by older callers.
  # New baseline servers should use add_streamable_server.
  local name="$1"
  local npm_pkg="$2"

  if have_server "$name"; then
    echo "✓ $name already exists"
    return 0
  fi

  if [[ "$APPLY" == false ]]; then
    echo "→ would add $name"
    echo "  codex mcp add $name -- npx -y $npm_pkg"
    return 0
  fi

  echo "→ adding $name"
  codex mcp add "$name" -- npx -y "$npm_pkg"
}

add_streamable_server() {
  local name="$1"
  local url="$2"
  local token_env="$3"

  if have_server "$name"; then
    local current_type current_url
    current_type="$(existing_transport_type "$name")"
    current_url="$(existing_streamable_url "$name")"

    if [[ "$current_type" == "streamable_http" && "$current_url" == "$url" ]]; then
      echo "✓ $name already exists (url match)"
      return 0
    fi

    if [[ "$APPLY" == false ]]; then
      echo "→ would replace $name"
      echo "  current: type=$current_type url=$current_url"
      echo "  target : type=streamable_http url=$url"
      return 0
    fi

    echo "→ replacing $name"
    codex mcp remove "$name"
  fi

  if [[ "$APPLY" == false ]]; then
    echo "→ would add $name"
    if [[ -n "$token_env" ]]; then
      echo "  codex mcp add $name --url $url --bearer-token-env-var $token_env"
    else
      echo "  codex mcp add $name --url $url"
    fi
    return 0
  fi

  echo "→ adding $name"
  if [[ -n "$token_env" ]]; then
    codex mcp add "$name" --url "$url" --bearer-token-env-var "$token_env"
  else
    codex mcp add "$name" --url "$url"
  fi
}

login_server() {
  local name="$1"
  if [[ "$LOGIN" == false ]]; then
    return 0
  fi

  if ! have_server "$name"; then
    return 0
  fi

  local transport_type
  transport_type="$(codex mcp get "$name" --json 2>/dev/null | jq -r '.transport.type // ""')"
  if [[ "$transport_type" != "streamable_http" ]]; then
    echo "ℹ skip login $name (transport=$transport_type, OAuth login only supports streamable_http)"
    return 0
  fi

  if [[ "$APPLY" == false ]]; then
    echo "→ would login $name"
    echo "  codex mcp login $name"
    return 0
  fi

  echo "→ login $name (interactive OAuth may open browser)"
  codex mcp login "$name" || {
    echo "⚠ login failed for $name (you can retry manually)." >&2
  }
}

print_header

add_streamable_server "$ATLASSIAN_NAME" "$ATLASSIAN_URL_DEFAULT" ""
add_streamable_server "$SLACK_NAME" "$SLACK_URL_DEFAULT" ""

if [[ -n "$GOOGLE_CALENDAR_URL" ]]; then
  add_streamable_server "$GOOGLE_CALENDAR_NAME" "$GOOGLE_CALENDAR_URL" "$GOOGLE_CALENDAR_TOKEN_ENV"
else
  echo "ℹ skip $GOOGLE_CALENDAR_NAME (no --with-google-calendar-url)"
fi

login_server "$ATLASSIAN_NAME"
login_server "$SLACK_NAME"
if [[ -n "$GOOGLE_CALENDAR_URL" ]]; then
  login_server "$GOOGLE_CALENDAR_NAME"
fi

echo
echo "Current MCP servers:"
codex mcp list

echo
if [[ "$APPLY" == false ]]; then
  echo "Dry-run complete. Re-run with --apply to make changes."
else
  echo "Apply complete."
fi
