#!/usr/bin/env bash
# 啟動 Polaris docs-manager browser viewer。
# Usage: polaris-viewer.sh [--port 8080] [--host 127.0.0.1] [--no-open] [--preview|--mode dev|preview] [--detach|--status|--stop]
#
# Dev mode 直接讀 canonical specs；preview mode 會先 build 再提供 search/production 檢查。

set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PORT=8080
OPEN_BROWSER=true
HOST=127.0.0.1
MODE=dev
ACTION=start

usage() {
  cat <<EOF
Usage:
  scripts/polaris-viewer.sh [--port 8080] [--host 127.0.0.1] [--no-open] [--preview|--mode dev|preview]
  scripts/polaris-viewer.sh --detach [--port 8080] [--host 127.0.0.1] [--no-open] [--preview|--mode dev|preview]
  scripts/polaris-viewer.sh --status [--port 8080] [--host 127.0.0.1]
  scripts/polaris-viewer.sh --stop [--port 8080]

Modes:
  default      前景啟動 docs-manager。
  --detach    啟動或重用持久 docs-manager session，啟動後離開 shell。
  --status    回報指定 port 的 listener / session 狀態。
  --stop      停止受管理的 docs-manager session 或健康 docs-manager listener。
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --host) HOST="$2"; shift 2 ;;
    --no-open) OPEN_BROWSER=false; shift ;;
    --preview) MODE=preview; shift ;;
    --detach) ACTION=detach; OPEN_BROWSER=false; shift ;;
    --status) ACTION=status; OPEN_BROWSER=false; shift ;;
    --stop) ACTION=stop; OPEN_BROWSER=false; shift ;;
    --help|-h) usage; exit 0 ;;
    --mode)
      MODE="${2:-}"
      if [[ "$MODE" != "dev" && "$MODE" != "preview" ]]; then
        echo "無效的 --mode 值：$MODE（預期 dev 或 preview）" >&2
        exit 1
      fi
      shift 2
      ;;
    *) echo "未知選項：$1" >&2; usage >&2; exit 1 ;;
  esac
done

ORIGIN="http://$HOST:$PORT"
MANAGER_URL="$ORIGIN/docs-manager/"
export POLARIS_DOCS_MANAGER_SITE="$ORIGIN"
SESSION_NAME="polaris-docs-manager-$PORT"
LOG_FILE="/tmp/$SESSION_NAME.log"
PID_FILE="/tmp/$SESSION_NAME.pid"

docs_manager_available() {
  local url="$1"
  local body
  body="$(curl -fsS --max-time 5 "$url" 2>/dev/null || true)"
  [[ "$body" == *"Polaris Specs"* && "$body" == *"starlight"* ]]
}

listener_pid() {
  lsof -tiTCP:"$PORT" -sTCP:LISTEN -n -P 2>/dev/null | head -n1 || true
}

screen_session_exists() {
  command -v screen >/dev/null 2>&1 && screen -list 2>/dev/null | grep -q "$SESSION_NAME"
}

wait_for_docs_manager() {
  local deadline=$((SECONDS + 60))
  while (( SECONDS < deadline )); do
    if docs_manager_available "$MANAGER_URL"; then
      return 0
    fi
    sleep 1
  done
  echo "等待 $MANAGER_URL 逾時" >&2
  echo "Log: $LOG_FILE" >&2
  return 1
}

print_status() {
  local pid
  pid="$(listener_pid)"
  if [[ -n "$pid" ]] && docs_manager_available "$MANAGER_URL"; then
    echo "docs-manager: healthy"
    echo "URL: $MANAGER_URL"
    echo "PID: $pid"
  elif [[ -n "$pid" ]]; then
    echo "docs-manager: unavailable"
    echo "Port $PORT listener PID: $pid"
    echo "URL 檢查失敗：$MANAGER_URL"
    return 1
  else
    echo "docs-manager: stopped"
    echo "URL: $MANAGER_URL"
  fi

  if screen_session_exists; then
    echo "Session: $SESSION_NAME"
  fi
  if [[ -f "$LOG_FILE" ]]; then
    echo "Log: $LOG_FILE"
  fi
}

stop_docs_manager() {
  local stopped=false
  if screen_session_exists; then
    screen -S "$SESSION_NAME" -X quit >/dev/null 2>&1 || true
    stopped=true
  fi

  local pid=""
  if [[ -f "$PID_FILE" ]]; then
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      stopped=true
    fi
    rm -f "$PID_FILE"
  fi

  pid="$(listener_pid)"
  if [[ -n "$pid" ]]; then
    if docs_manager_available "$MANAGER_URL"; then
      kill "$pid" 2>/dev/null || true
      stopped=true
    else
      echo "Port $PORT 已被使用，但 $MANAGER_URL 不是 Polaris docs-manager；拒絕停止未知 process。" >&2
      return 1
    fi
  fi

  local deadline=$((SECONDS + 15))
  while (( SECONDS < deadline )); do
    if [[ -z "$(listener_pid)" ]]; then
      break
    fi
    sleep 1
  done

  if [[ -n "$(listener_pid)" ]]; then
    echo "docs-manager 在 port $PORT 沒有乾淨停止。" >&2
    return 1
  fi

  if [[ "$stopped" == "true" ]]; then
    echo "已停止 port $PORT 的 docs-manager。"
  else
    echo "port $PORT 沒有 docs-manager 在執行。"
  fi
}

if [[ ! -d "$WORKSPACE_ROOT/docs-manager" ]]; then
  echo "$WORKSPACE_ROOT 底下找不到 docs-manager 目錄" >&2
  exit 1
fi

case "$ACTION" in
  status)
    print_status
    exit $?
    ;;
  stop)
    stop_docs_manager
    exit $?
    ;;
esac

# shellcheck source=lib/specs-root.sh
. "$SCRIPT_DIR/lib/specs-root.sh"
SPECS_ROOT="$(resolve_specs_root "$WORKSPACE_ROOT" 2>/dev/null || true)"
if [[ -n "$SPECS_ROOT" && -d "$SPECS_ROOT" ]]; then
  export POLARIS_WORKSPACE_ROOT="$WORKSPACE_ROOT"
else
  # gitignored specs 只存在 main checkout；linked worktree 會由 loader 回主 checkout 解析。
  echo "WARN: 找不到 $WORKSPACE_ROOT/docs-manager/src/content/docs/specs；docs-manager 會在可行時從 main checkout 解析 canonical specs。" >&2
fi

if lsof -i :"$PORT" -sTCP:LISTEN &>/dev/null; then
  if ! docs_manager_available "$MANAGER_URL"; then
    echo "Port $PORT 已被使用，但 $MANAGER_URL 不是 Polaris docs-manager。" >&2
    echo "請用 --port <port> 選其他 port，或先停止既有服務。" >&2
    exit 1
  fi
  echo "Port $PORT 已有 Polaris docs-manager，重用既有 server。"
  [ "$OPEN_BROWSER" = true ] && open "$MANAGER_URL"
  exit 0
fi

if [[ "$ACTION" == "detach" ]]; then
  echo "啟動持久 $MODE docs-manager：$MANAGER_URL"
  mkdir -p "$(dirname "$LOG_FILE")"
  : >"$LOG_FILE"

  if command -v screen >/dev/null 2>&1; then
    launch_cmd=$(printf 'cd %q && exec bash scripts/polaris-viewer.sh --port %q --host %q --no-open --mode %q >>%q 2>&1' \
      "$WORKSPACE_ROOT" "$PORT" "$HOST" "$MODE" "$LOG_FILE")
    screen -dmS "$SESSION_NAME" bash -lc "$launch_cmd"
    echo "Session: $SESSION_NAME"
  else
    echo "WARN: 找不到 screen；改用 nohup background process。" >&2
    (
      cd "$WORKSPACE_ROOT"
      nohup bash scripts/polaris-viewer.sh --port "$PORT" --host "$HOST" --no-open --mode "$MODE" >>"$LOG_FILE" 2>&1 &
      echo $! >"$PID_FILE"
    )
    echo "PID file: $PID_FILE"
  fi

  wait_for_docs_manager
  echo "URL: $MANAGER_URL"
  echo "Log: $LOG_FILE"
  echo "Stop: bash scripts/polaris-viewer.sh --stop --port $PORT"
  exit 0
fi

echo "啟動 $MODE server：$MANAGER_URL"
if [ "$OPEN_BROWSER" = true ]; then
  (sleep 1 && open "$MANAGER_URL") &
fi

cd "$WORKSPACE_ROOT/docs-manager"
if [ ! -d node_modules ]; then
  echo "安裝 docs-manager dependencies..."
  npm install
fi

if [ "$MODE" = "preview" ]; then
  npm run build
  npm run preview -- --host "$HOST" --port "$PORT" --strictPort
else
  npm run dev -- --host "$HOST" --port "$PORT" --strictPort
fi
