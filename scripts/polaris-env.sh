#!/usr/bin/env bash
# polaris-env.sh — One-click environment startup for Polaris
#
# Usage:
#   polaris-env.sh start {company} [--full | --vr | --e2e] [--project {name}]
#   polaris-env.sh stop {company}
#   polaris-env.sh status {company}
#
# Profiles:
#   --full (default)  Layer1(docker) + Layer3(all dev servers) + Layer4(verify)
#   --vr              Layer2(mockoon) + Layer3(first web/b2c project) + Layer4(verify)
#   --e2e             Layer1(docker) + Layer2(mockoon) + Layer3(all dev servers) + Layer4(verify)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PID_BASE="/tmp/polaris-env"

GREEN="\033[0;32m"; RED="\033[0;31m"; YELLOW="\033[0;33m"; RESET="\033[0m"
ok()   { echo -e "  ${GREEN}[✓]${RESET} $*"; }
fail() { echo -e "  ${RED}[✗]${RESET} $*"; }
warn() { echo -e "  ${YELLOW}[~]${RESET} $*"; }

pid_dir() { echo "$PID_BASE/$1"; }
save_pid() { mkdir -p "$(pid_dir "$1")"; echo "$3" > "$(pid_dir "$1")/$2.pid"; }
is_pid_running() { [[ -n "$1" ]] && kill -0 "$1" 2>/dev/null; }

parse_config() {
  python3 -c "
import yaml, json, sys
with open('$1') as f: print(json.dumps(yaml.safe_load(f)))
"
}

# Get a value from JSON by dotted path with optional [N] array index
jget() {
  echo "$1" | python3 -c "
import json, sys
cur = json.load(sys.stdin)
for part in '$2'.split('.'):
    if '[' in part:
        k, i = part.rstrip(']').split('[')
        cur = cur.get(k, [])[int(i)] if isinstance(cur, dict) else cur[int(i)]
    else:
        cur = (cur or {}).get(part, '') if isinstance(cur, dict) else ''
    if cur is None: cur = ''
if isinstance(cur, (list, dict)): print(json.dumps(cur))
else: print(cur)
" 2>/dev/null || echo ""
}

# Poll URL for HTTP 2xx; return 0 on success, 1 on timeout
wait_for_url() {
  local url="$1" timeout="${2:-60}" elapsed=0
  while [[ $elapsed -lt $timeout ]]; do
    local code; code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$url" 2>/dev/null || echo "000")
    [[ "$code" =~ ^2 ]] && return 0
    sleep 2; elapsed=$((elapsed + 2))
  done; return 1
}

port_listening() { lsof -i :"$1" -sTCP:LISTEN >/dev/null 2>&1; }

wait_for_ports() {
  local timeout=30 elapsed=0
  shift  # discard name
  while [[ $elapsed -lt $timeout ]]; do
    local all=true
    for p in "$@"; do port_listening "$p" || { all=false; break; }; done
    $all && return 0
    sleep 2; elapsed=$((elapsed + 2))
  done; return 1
}

# ── Layer 1: Infrastructure (Docker) ────────────────────────────────────────
start_infra() {
  local company="$1" cfg="$2"
  echo ""; echo "Layer 1: Infrastructure (Docker)"

  echo "$cfg" | python3 -c "
import json,sys
for p in json.load(sys.stdin).get('projects',[]):
    d=p.get('dev_environment',{})
    if d and 'docker' in p.get('tags',[]) and not d.get('requires'):
        print(p['name']+'|'+d['start_command']+'|'+d.get('health_check',''))
" | while IFS='|' read -r name cmd health; do
    if [[ -n "$health" ]] && wait_for_url "$health" 4 2>/dev/null; then
      ok "$name (already running)"; continue
    fi
    local log; log="$(pid_dir "$company")/$name.log"; mkdir -p "$(pid_dir "$company")"
    eval "$cmd" > "$log" 2>&1 &
    save_pid "$company" "$name" $!
    if [[ -n "$health" ]]; then
      wait_for_url "$health" 60 && ok "$name  ($health)" || fail "$name timed out — $log"
    else ok "$name started"; fi
  done
}

# ── Layer 2: Fixtures (Mockoon) ──────────────────────────────────────────────
start_fixtures() {
  local company="$1" cfg="$2"
  echo ""; echo "Layer 2: Fixtures (Mockoon)"

  local start_cmd; start_cmd=$(jget "$cfg" "visual_regression.domains[0].fixtures.start_command")
  local ports_json; ports_json=$(jget "$cfg" "visual_regression.domains[0].fixtures.health_ports")

  if [[ -z "$start_cmd" ]]; then warn "No fixtures config found"; return 0; fi

  local ports; ports=($(echo "$ports_json" | python3 -c "import json,sys; print(' '.join(str(p) for p in json.load(sys.stdin)))"))

  local all=true
  for p in "${ports[@]}"; do port_listening "$p" || { all=false; break; }; done
  if $all; then ok "Mockoon fixtures (ports ${ports[*]}, already running)"; return 0; fi

  local log; log="$(pid_dir "$company")/mockoon-fixtures.log"; mkdir -p "$(pid_dir "$company")"
  eval "${start_cmd/\~/$HOME}" > "$log" 2>&1 &
  save_pid "$company" "mockoon-fixtures" $!

  wait_for_ports "mockoon-fixtures" "${ports[@]}" \
    && ok "Mockoon fixtures (ports ${ports[*]})" \
    || fail "Mockoon fixtures timed out — $log"
}

# ── Layer 3: Dev Servers ─────────────────────────────────────────────────────
start_devservers() {
  local company="$1" cfg="$2" profile="$3" filter="$4"
  echo ""; echo "Layer 3: Dev Servers"

  echo "$cfg" | python3 -c "
import json,sys
filter_p='$filter'; profile='$profile'
rows=[]
for p in json.load(sys.stdin).get('projects',[]):
    d=p.get('dev_environment',{})
    if not d or 'docker' in p.get('tags',[]): continue
    rows.append({'name':p['name'],'tags':p.get('tags',[]),
        'cmd':d['start_command'],'sig':d.get('ready_signal',''),
        'health':d.get('health_check',''),'req':d.get('requires',[])})
if filter_p:
    rows=[r for r in rows if r['name']==filter_p]
elif profile=='--vr':
    web=[r for r in rows if 'b2c' in r['tags']]
    rows=web[:1] if web else rows[:1]
for r in rows:
    print(r['name']+'|'+r['cmd']+'|'+r['sig']+'|'+r['health']+'|'+','.join(r['req']))
" | while IFS='|' read -r name cmd sig health requires_csv; do

    # Check requires — skip in --vr profile (Mockoon replaces Docker dependencies)
    if [[ -n "$requires_csv" ]] && [[ "$profile" != "--vr" ]]; then
      local ok_reqs=true
      for req in ${requires_csv//,/ }; do
        local req_health; req_health=$(echo "$cfg" | python3 -c "
import json,sys
for p in json.load(sys.stdin).get('projects',[]):
    if p['name']=='$req': print(p.get('dev_environment',{}).get('health_check','')); break
" 2>/dev/null || echo "")
        if [[ -n "$req_health" ]] && ! wait_for_url "$req_health" 3 2>/dev/null; then
          ok_reqs=false; break
        fi
      done
      if ! $ok_reqs; then warn "$name skipped (requires $requires_csv not ready)"; continue; fi
    fi

    if [[ -n "$health" ]] && wait_for_url "$health" 4 2>/dev/null; then
      ok "$name (already running)"; continue
    fi

    local log; log="$(pid_dir "$company")/$name.log"; mkdir -p "$(pid_dir "$company")"
    local resolved_cmd="${cmd/\~/$HOME}"
    # If cmd starts with 'pnpm' and doesn't have -C, prepend -C {project_dir}
    local project_dir="$WORKSPACE_ROOT/$company/$name"
    if [[ "$resolved_cmd" == pnpm\ * ]] && [[ "$resolved_cmd" != *" -C "* ]]; then
      resolved_cmd="pnpm -C $project_dir ${resolved_cmd#pnpm }"
    elif [[ "$resolved_cmd" == npm\ * ]] && [[ ! -d "$project_dir/node_modules" ]]; then
      resolved_cmd="npm --prefix $project_dir ${resolved_cmd#npm }"
    fi
    eval "$resolved_cmd" > "$log" 2>&1 &
    save_pid "$company" "$name" $!

    if [[ -n "$sig" ]]; then
      local elapsed=0
      while [[ $elapsed -lt 120 ]]; do
        grep -q "$sig" "$log" 2>/dev/null && break
        sleep 2; elapsed=$((elapsed + 2))
      done
      [[ $elapsed -lt 120 ]] && ok "$name (${health:-$name})" || fail "$name timed out — $log"
    else ok "$name started"; fi
  done
}

# ── Layer 4: Verify ──────────────────────────────────────────────────────────
verify_all() {
  local cfg="$1"
  echo ""; echo "Layer 4: Verification"

  echo "$cfg" | python3 -c "
import json,sys
for p in json.load(sys.stdin).get('projects',[]):
    d=p.get('dev_environment',{})
    if d and d.get('health_check'): print(p['name']+'|'+d['health_check'])
" | while IFS='|' read -r name url; do
    local code; code=$(curl -sL -o /dev/null -w "%{http_code}" --max-time 15 "$url" 2>/dev/null || echo "000")
    [[ "$code" =~ ^2 ]] && ok "$(printf '%-28s' "$name")  $url" || fail "$(printf '%-28s' "$name")  $url  (HTTP $code)"
  done

  local ports_json; ports_json=$(jget "$cfg" "visual_regression.domains[0].fixtures.health_ports" 2>/dev/null || echo "[]")
  if [[ "$ports_json" != "[]" && -n "$ports_json" ]]; then
    local ports; ports=($(echo "$ports_json" | python3 -c "import json,sys; print(' '.join(str(p) for p in json.load(sys.stdin)))"))
    local all=true
    for p in "${ports[@]}"; do port_listening "$p" || { all=false; break; }; done
    $all && ok "$(printf '%-28s' "mockoon-fixtures")  ports ${ports[*]}" \
            || warn "$(printf '%-28s' "mockoon-fixtures")  ports ${ports[*]}  (not running)"
  fi
}

# ── Commands ─────────────────────────────────────────────────────────────────
cmd_start() {
  local company="$1"; shift
  local profile="--full" filter=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --full|--vr|--e2e) profile="$1"; shift ;;
      --project) filter="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  local cfg_path="$WORKSPACE_ROOT/$company/workspace-config.yaml"
  [[ -f "$cfg_path" ]] || { echo "ERROR: Config not found: $cfg_path" >&2; exit 1; }
  local cfg; cfg=$(parse_config "$cfg_path")

  echo "Starting $company environment  [profile: $profile]"
  mkdir -p "$(pid_dir "$company")"

  if [[ "$profile" == "--full" || "$profile" == "--e2e" ]]; then start_infra "$company" "$cfg"; fi
  if [[ "$profile" == "--vr"   || "$profile" == "--e2e" ]]; then start_fixtures "$company" "$cfg"; fi
  start_devservers "$company" "$cfg" "$profile" "$filter"
  verify_all "$cfg"
  echo ""; echo "Done. Logs: $(pid_dir "$company")/"
}

cmd_stop() {
  local company="$1"
  echo "Stopping $company environment..."

  local cfg_path="$WORKSPACE_ROOT/$company/workspace-config.yaml"
  if [[ -f "$cfg_path" ]]; then
    local cfg; cfg=$(parse_config "$cfg_path")
    local stop_cmd; stop_cmd=$(jget "$cfg" "visual_regression.domains[0].fixtures.stop_command")
    if [[ -n "$stop_cmd" ]]; then
      eval "${stop_cmd/\~/$HOME}" 2>/dev/null || true
      ok "Mockoon fixtures stopped"
    fi
  fi

  local dir; dir="$(pid_dir "$company")"
  if [[ -d "$dir" ]]; then
    for pid_file in "$dir"/*.pid; do
      [[ -f "$pid_file" ]] || continue
      local name pid
      name=$(basename "$pid_file" .pid); pid=$(cat "$pid_file")
      is_pid_running "$pid" && kill "$pid" 2>/dev/null && ok "Stopped $name (PID $pid)"
      rm -f "$pid_file" "$dir/$name.log"
    done
  fi
  echo "Done."
}

cmd_status() {
  local company="$1"
  local cfg_path="$WORKSPACE_ROOT/$company/workspace-config.yaml"
  [[ -f "$cfg_path" ]] || { echo "ERROR: Config not found: $cfg_path" >&2; exit 1; }
  local cfg; cfg=$(parse_config "$cfg_path")

  echo "$company environment status:"

  echo "$cfg" | python3 -c "
import json,sys
for p in json.load(sys.stdin).get('projects',[]):
    d=p.get('dev_environment',{})
    if not d: continue
    kind='Docker' if 'docker' in p.get('tags',[]) else 'Dev server'
    print(p['name']+'|'+d.get('health_check',d.get('base_url',''))+'|'+kind)
" | while IFS='|' read -r name url kind; do
    local code; code=$(curl -sL -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null || echo "000")
    [[ "$code" =~ ^2 ]] \
      && ok "$(printf '%-28s' "$name")  $url  ($kind)" \
      || fail "$(printf '%-28s' "$name")  $url  ($kind)"
  done

  local ports_json; ports_json=$(jget "$cfg" "visual_regression.domains[0].fixtures.health_ports" 2>/dev/null || echo "[]")
  if [[ "$ports_json" != "[]" && -n "$ports_json" ]]; then
    local ports; ports=($(echo "$ports_json" | python3 -c "import json,sys; print(' '.join(str(p) for p in json.load(sys.stdin)))"))
    local all=true
    for p in "${ports[@]}"; do port_listening "$p" || { all=false; break; }; done
    $all && ok "$(printf '%-28s' "mockoon-fixtures")  ports ${ports[*]}  (Mockoon)" \
            || fail "$(printf '%-28s' "mockoon-fixtures")  ports ${ports[*]}  (Not running)"
  fi
}

# ── Main ─────────────────────────────────────────────────────────────────────
if [[ $# -lt 2 ]]; then
  echo "Usage: $0 {start|stop|status} {company} [options]" >&2
  echo "  start {company} [--full|--vr|--e2e] [--project {name}]" >&2
  exit 1
fi

case "$1" in
  start)  cmd_start "$2" "${@:3}" ;;
  stop)   cmd_stop  "$2" ;;
  status) cmd_status "$2" ;;
  *) echo "Unknown command: $1" >&2; exit 1 ;;
esac
