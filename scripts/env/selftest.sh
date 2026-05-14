#!/usr/bin/env bash
# scripts/env/selftest.sh — End-to-end selftest for the D11 L2 primitives and
# the start-test-env L3 orchestrator.
#
# Exercises:
#   - health-check.sh: usage error / unreachable timeout / success on a real
#     localhost http.server
#   - fixtures-start.sh: usage / missing dir / empty dir / unsupported type
#   - start-command.sh: usage / unknown project / missing dev_environment /
#     fail-loud on missing start_command / launch + ready_signal
#   - ensure-dependencies.sh: usage / empty requires / missing requires field
#     (fail-loud) / dep with no config / chain success against a python http.server
#   - start-test-env.sh: usage / chain success / chain stop on first failure
#
# Run: bash scripts/env/selftest.sh   (set DEBUG=1 for verbose output)
#
# Exit 0 if every assertion passes, 1 otherwise.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(mktemp -d -t polaris-d11-selftest-XXXXXX)"
HC="$SCRIPT_DIR/health-check.sh"
FX="$SCRIPT_DIR/fixtures-start.sh"
SC="$SCRIPT_DIR/start-command.sh"
ED="$SCRIPT_DIR/ensure-dependencies.sh"
IPD="$SCRIPT_DIR/install-project-deps.sh"
SE="$(cd "$SCRIPT_DIR/.." && pwd)/start-test-env.sh"

: "${DEBUG:=0}"

PORT_HTTP=$(python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()')
PORT_HTTP2=$(python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()')
PORT_HC_PROBE=$(python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()')
PORT_DOCKER=$(python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()')
PORT_OVERRIDE=$(python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()')
PORT_SHORT_LIVED=$(python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()')
PORT_GROUP_CHILD=$(python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()')

TEST_CONFIG="$WORK_DIR/workspace-config.yaml"
cat > "$TEST_CONFIG" <<EOF
projects:
  - name: leaf-service
    dev_environment:
      start_command: "python3 -u -m http.server $PORT_HTTP --bind 127.0.0.1"
      ready_signal: "Serving HTTP on 127.0.0.1"
      base_url: "http://127.0.0.1:$PORT_HTTP"
      health_check: "http://127.0.0.1:$PORT_HTTP/"
      requires: []
  - name: app-service
    dev_environment:
      start_command: "python3 -u -m http.server $PORT_HTTP2 --bind 127.0.0.1"
      ready_signal: "Serving HTTP on 127.0.0.1"
      base_url: "http://127.0.0.1:$PORT_HTTP2"
      health_check: "http://127.0.0.1:$PORT_HTTP2/"
      requires: ["leaf-service"]
  - name: install-configured
    dev_environment:
      install_command: "python3 -c \"from pathlib import Path; Path('.deps-installed').write_text('ok')\""
      start_command: "true"
      health_check: "http://127.0.0.1:$PORT_HTTP/"
      requires: []
  - name: repo-override-service
    dev_environment:
      install_command: "python3 -c \"from pathlib import Path; Path('.repo-override-installed').write_text('ok')\""
      start_command: "python3 -u -m http.server $PORT_OVERRIDE --bind 127.0.0.1"
      ready_signal: "Serving HTTP on 127.0.0.1"
      health_check: "http://127.0.0.1:$PORT_OVERRIDE/"
      requires: []
  - name: short-lived-service
    dev_environment:
      start_command: "sh -lc 'python3 -u -m http.server $PORT_SHORT_LIVED --bind 127.0.0.1 >/dev/null 2>&1 & echo \$! > \"$WORK_DIR/short-lived-child.pid\"; echo READY; sleep 2'"
      ready_signal: "READY"
      health_check: "http://127.0.0.1:$PORT_SHORT_LIVED/"
      requires: []
  - name: sticky-service
    dev_environment:
      start_command: "sh -lc 'trap \"exit 9\" HUP; echo STARTED; while true; do sleep 1; done'"
      ready_signal: "STARTED"
      health_check: "http://127.0.0.1:$PORT_HTTP/"
      requires: []
  - name: group-child-service
    dev_environment:
      start_command: "sh -lc 'python3 -u -m http.server $PORT_GROUP_CHILD --bind 127.0.0.1 >/dev/null 2>&1 & echo \$! > \"$WORK_DIR/group-child.pid\"; echo STARTED; sleep 1000'"
      ready_signal: "STARTED"
      health_check: "http://127.0.0.1:$PORT_GROUP_CHILD/"
      requires: []
  - name: docker-dep
    tags: ["docker"]
    dev_environment:
      start_command: "python3 -u -m http.server $PORT_DOCKER --bind 127.0.0.1"
      ready_signal: "Serving HTTP on 127.0.0.1"
      health_check: "http://127.0.0.1:$PORT_DOCKER/"
      requires: []
  - name: app-with-docker-dep
    dev_environment:
      start_command: "true"
      health_check: "http://127.0.0.1:$PORT_HTTP/"
      requires: ["docker-dep"]
  - name: install-detected
    dev_environment:
      start_command: "true"
      health_check: "http://127.0.0.1:$PORT_HTTP/"
      requires: []
  - name: missing-requires
    dev_environment:
      start_command: "echo hi"
      health_check: "http://localhost:1/"
  - name: empty-deps
    dev_environment:
      start_command: "true"
      health_check: "http://127.0.0.1:$PORT_HTTP/"
      requires: []
  - name: bad-dep
    dev_environment:
      start_command: "true"
      health_check: "http://127.0.0.1:$PORT_HTTP/"
      requires: ["nonexistent-dep"]
  - name: no-dev-env
    # no dev_environment field at all
EOF

export POLARIS_WORKSPACE_CONFIG="$TEST_CONFIG"

PASS=0
FAIL=0

assert_eq() {
  local got="$1" want="$2" label="$3"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1))
    [[ "$DEBUG" == "1" ]] && printf "  \033[0;32m[ok]\033[0m %s (got=%s)\n" "$label" "$got"
  else
    FAIL=$((FAIL + 1))
    printf "  \033[0;31m[FAIL]\033[0m %s — want=%s got=%s\n" "$label" "$want" "$got"
  fi
}

cleanup() {
  # Kill any lingering http.server processes from start-command via PID files.
  for pid_file in \
    /tmp/polaris-env-d11/leaf-service.pid \
    /tmp/polaris-env-d11/app-service.pid \
    /tmp/polaris-env-d11/sticky-service.pid \
    /tmp/polaris-env-d11/group-child-service.pid \
    /tmp/polaris-env-d11/docker-dep.pid \
    /tmp/polaris-env-d11/repo-override-service.pid \
    /tmp/polaris-env-d11/short-lived-service.pid; do
    [[ -f "$pid_file" ]] || continue
    pid=$(cat "$pid_file" 2>/dev/null || true)
    if [[ -n "$pid" ]]; then
      kill "$pid" 2>/dev/null || true
      sleep 0.3
      kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$pid_file"
  done
  if [[ -f "$WORK_DIR/short-lived-child.pid" ]]; then
    child_pid=$(cat "$WORK_DIR/short-lived-child.pid" 2>/dev/null || true)
    if [[ -n "$child_pid" ]]; then
      kill "$child_pid" 2>/dev/null || true
      sleep 0.3
      kill -9 "$child_pid" 2>/dev/null || true
    fi
  fi
  if [[ -f "$WORK_DIR/group-child.pid" ]]; then
    group_child_pid=$(cat "$WORK_DIR/group-child.pid" 2>/dev/null || true)
    if [[ -n "$group_child_pid" ]]; then
      kill "$group_child_pid" 2>/dev/null || true
      sleep 0.3
      kill -9 "$group_child_pid" 2>/dev/null || true
    fi
  fi
  rm -rf "$WORK_DIR" 2>/dev/null || true
}
trap cleanup EXIT

run_silent() {
  if [[ "$DEBUG" == "1" ]]; then
    "$@"
  else
    "$@" >/dev/null 2>&1
  fi
}

echo "=== health-check.sh ==="
run_silent "$HC"; assert_eq "$?" "2" "usage error"
run_silent "$HC" "http://127.0.0.1:1/" --timeout 2 --interval 1; assert_eq "$?" "1" "timeout on unreachable"
# Bring up a server inline for the success case (separate port from
# leaf-service / app-service to avoid TIME_WAIT collisions later).
python3 -u -m http.server "$PORT_HC_PROBE" --bind 127.0.0.1 >/dev/null 2>&1 &
SERVER_PID=$!
sleep 1
run_silent "$HC" "http://127.0.0.1:$PORT_HC_PROBE/" --timeout 5; assert_eq "$?" "0" "PASS on real localhost"
kill "$SERVER_PID" 2>/dev/null || true
sleep 0.5

echo ""
echo "=== fixtures-start.sh ==="
run_silent "$FX"; assert_eq "$?" "2" "usage error"
run_silent "$FX" "$WORK_DIR/nonexistent"; assert_eq "$?" "2" "missing dir"
mkdir -p "$WORK_DIR/empty-fx"
run_silent "$FX" "$WORK_DIR/empty-fx"; assert_eq "$?" "1" "empty fixtures dir"
run_silent "$FX" "$WORK_DIR/empty-fx" --type wiremock; assert_eq "$?" "2" "unsupported type"

echo ""
echo "=== start-command.sh ==="
run_silent "$SC"; assert_eq "$?" "2" "usage error"
run_silent "$SC" --project ghost; assert_eq "$?" "1" "unknown project"
run_silent "$SC" --project no-dev-env; assert_eq "$?" "1" "no dev_environment"
sc_out="$("$SC" --project install-configured 2>/dev/null)"
RC_SC_COMPLETE=$?
assert_eq "$RC_SC_COMPLETE" "0" "instant success start_command exits 0"
echo "$sc_out" | grep -q '"status": "completed"'
assert_eq "$?" "0" "instant success start_command emits completed status"
# Real launch: leaf-service starts a python http.server, ready_signal fires
run_silent "$SC" --project leaf-service --ready-timeout 10
RC_LEAF=$?
assert_eq "$RC_LEAF" "0" "leaf-service launched (ready_signal observed)"
# Verify the server actually responds
run_silent "$HC" "http://127.0.0.1:$PORT_HTTP/" --timeout 5
assert_eq "$?" "0" "leaf-service responds to health-check"
sticky_out="$("$SC" --project sticky-service --ready-timeout 10 2>/dev/null)"
RC_STICKY=$?
assert_eq "$RC_STICKY" "0" "sticky-service launched (ready_signal observed)"
sticky_pid=$(printf '%s' "$sticky_out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["pid"])')
sleep 1
kill -0 "$sticky_pid" 2>/dev/null
assert_eq "$?" "0" "sticky-service survives after start-command exits"
sticky_pgid=$(ps -p "$sticky_pid" -o pgid= 2>/dev/null | tr -d '[:space:]' || true)
self_pgid=$(ps -p "$$" -o pgid= 2>/dev/null | tr -d '[:space:]' || true)
if [[ -n "$sticky_pgid" && -n "$self_pgid" && "$sticky_pgid" != "$self_pgid" ]]; then
  RC_STICKY_SESSION=0
else
  RC_STICKY_SESSION=1
fi
assert_eq "$RC_STICKY_SESSION" "0" "sticky-service runs in detached process group"
group_out="$("$SC" --project group-child-service --ready-timeout 10 2>/dev/null)"
RC_GROUP_FIRST=$?
assert_eq "$RC_GROUP_FIRST" "0" "group-child-service first launch"
group_child_pid="$(cat "$WORK_DIR/group-child.pid" 2>/dev/null || true)"
kill -0 "$group_child_pid" 2>/dev/null
assert_eq "$?" "0" "group-child-service child started"
group_out="$("$SC" --project group-child-service --ready-timeout 10 2>/dev/null)"
RC_GROUP_SECOND=$?
assert_eq "$RC_GROUP_SECOND" "0" "group-child-service restart"
kill -0 "$group_child_pid" 2>/dev/null
RC_GROUP_OLD_CHILD_ALIVE=$?
if [[ "$RC_GROUP_OLD_CHILD_ALIVE" -eq 0 ]]; then
  RC_GROUP_CLEANUP=1
else
  RC_GROUP_CLEANUP=0
fi
assert_eq "$RC_GROUP_CLEANUP" "0" "group-child-service restart cleans old child process"
run_silent "$HC" "http://127.0.0.1:$PORT_GROUP_CHILD/" --timeout 5
assert_eq "$?" "0" "group-child-service responds after restart"

echo ""
echo "=== install-project-deps.sh ==="
run_silent "$IPD"; assert_eq "$?" "2" "usage error"
mkdir -p "$WORK_DIR/install-configured" "$WORK_DIR/install-detected" "$WORK_DIR/bin"
cat > "$WORK_DIR/bin/npm" <<EOF
#!/usr/bin/env bash
mkdir -p "$WORK_DIR/install-detected/node_modules"
exit 0
EOF
chmod +x "$WORK_DIR/bin/npm"
touch "$WORK_DIR/install-detected/package-lock.json"
run_silent "$IPD" --project install-configured --cwd "$WORK_DIR/install-configured"
assert_eq "$?" "0" "configured install command"
[[ -f "$WORK_DIR/install-configured/.deps-installed" ]]
assert_eq "$?" "0" "configured install wrote marker"
PATH="$WORK_DIR/bin:$PATH" run_silent "$IPD" --project install-detected --cwd "$WORK_DIR/install-detected"
assert_eq "$?" "0" "detected install command"
[[ -d "$WORK_DIR/install-detected/node_modules" ]]
assert_eq "$?" "0" "detected install created node_modules"
STATIC_TASK="$WORK_DIR/static-task.md"
cat > "$STATIC_TASK" <<'EOF'
---
title: "Work Order - T1: static no-op selftest (1 pt)"
description: "Selftest fixture."
---

# T1: static no-op selftest (1 pt)

> Source: DP-999 | Task: DP-999-T1 | JIRA: N/A | Repo: framework

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Verify Command

```bash
echo ok
```
EOF
ipd_static_out="$("$IPD" --task-md "$STATIC_TASK" --cwd "$WORK_DIR" 2>/dev/null)"
RC_IPD_STATIC=$?
assert_eq "$RC_IPD_STATIC" "0" "static task install no-op exits 0"
printf '%s' "$ipd_static_out" | python3 -c 'import json, sys; d=json.load(sys.stdin); assert d["status"] == "PASS"; assert d["mode"] == "noop_static"; assert d["level"] == "static"'
assert_eq "$?" "0" "static task no-op emits PASS JSON"
run_silent "$IPD" --project install-configured --task-md "$STATIC_TASK" --cwd "$WORK_DIR/install-configured"
assert_eq "$?" "2" "--project and --task-md are mutually exclusive"

echo ""
echo "=== ensure-dependencies.sh ==="
run_silent "$ED"; assert_eq "$?" "2" "usage error"
run_silent "$ED" --project empty-deps; assert_eq "$?" "0" "empty requires (no-op)"
run_silent "$ED" --project missing-requires; assert_eq "$?" "1" "missing requires field (fail-loud)"
run_silent "$ED" --project bad-dep; assert_eq "$?" "1" "dep with no config"
# leaf-service is already up from start-command test; ensure-deps for app-service
# should detect leaf is healthy (action=already-healthy)
ed_out="$("$ED" --project app-service 2>/dev/null)"
echo "$ed_out" | grep -q '"already-healthy"'
assert_eq "$?" "0" "app-service deps detected leaf-service as already-healthy"

# Stop leaf-service and re-run; ensure-deps must start it
PID=$(cat /tmp/polaris-env-d11/leaf-service.pid 2>/dev/null || true)
if [[ -n "$PID" ]]; then
  kill "$PID" 2>/dev/null || true
  sleep 0.5
fi
rm -f /tmp/polaris-env-d11/leaf-service.pid
ed_out="$("$ED" --project app-service --ready-timeout 10 2>/dev/null)"
echo "$ed_out" | grep -q '"started"'
assert_eq "$?" "0" "ensure-deps started leaf-service from cold"

# Docker-tagged dependencies still support port-level health when the configured
# URL is only the origin/root.
run_silent "$SC" --project docker-dep --ready-timeout 10
assert_eq "$?" "0" "docker-tag dep launched"
ed_out="$("$ED" --project app-with-docker-dep --ready-timeout 10 2>/dev/null)"
echo "$ed_out" | grep -q '"already-healthy"'
assert_eq "$?" "0" "docker-tag dep uses root URL port fallback"

# Cleanup leaf
PID=$(cat /tmp/polaris-env-d11/leaf-service.pid 2>/dev/null || true)
if [[ -n "$PID" ]]; then
  kill "$PID" 2>/dev/null || true
  sleep 0.5
fi
rm -f /tmp/polaris-env-d11/leaf-service.pid

echo ""
echo "=== start-test-env.sh ==="
run_silent "$SE"; assert_eq "$?" "2" "usage error"
# Full chain success: app-service depends on leaf-service; both come up via
# python http.server. Sleep to let ports fully release if anything from the
# previous tests is still holding them.
sleep 1
se_err="$WORK_DIR/se.err"
se_out="$("$SE" --project app-service --ready-timeout 10 2>"$se_err")"
RC_SE=$?
if [[ "$RC_SE" != "0" ]]; then
  echo "    se stderr:"; sed 's/^/      /' "$se_err"
  echo "    se stdout:"; printf '      %s\n' "$se_out"
fi
assert_eq "$RC_SE" "0" "full chain (ensure-deps → start → health-check)"
echo "$se_out" | grep -q '"step":"ensure-dependencies","status":"PASS"'
assert_eq "$?" "0" "step 1 evidence emitted"
echo "$se_out" | grep -q '"step":"install-project-deps","status":"PASS"'
assert_eq "$?" "0" "step 2 install-project-deps evidence emitted"
echo "$se_out" | grep -q '"step":"start-command","status":"PASS"'
assert_eq "$?" "0" "step 3 start-command evidence emitted"
echo "$se_out" | grep -q '"step":"health-check","status":"PASS"'
assert_eq "$?" "0" "step 4 health-check evidence emitted"
echo "$se_out" | grep -q '"step":"fixtures-start","status":"SKIP"'
assert_eq "$?" "0" "step 5 SKIP without --with-fixtures"
echo "$se_out" | grep -q '"summary":true.*"status":"PASS"'
assert_eq "$?" "0" "final summary PASS"

short_err="$WORK_DIR/short-lived.err"
short_out="$("$SE" --project short-lived-service --ready-timeout 10 2>"$short_err")"
RC_SHORT=$?
if [[ "$RC_SHORT" == "0" ]]; then
  echo "    short-lived stdout:"; printf '      %s\n' "$short_out"
fi
assert_eq "$RC_SHORT" "1" "short-lived runtime fails liveness finalizer"
grep -q "runtime liveness finalizer FAILED" "$short_err"
assert_eq "$?" "0" "short-lived runtime failure mentions liveness finalizer"

# Cleanup app/leaf services
for s in leaf-service app-service short-lived-service; do
  PID=$(cat "/tmp/polaris-env-d11/${s}.pid" 2>/dev/null || true)
  if [[ -n "$PID" ]]; then
    kill "$PID" 2>/dev/null || true
    sleep 0.3
    kill -9 "$PID" 2>/dev/null || true
  fi
  rm -f "/tmp/polaris-env-d11/${s}.pid"
done

repo_override_dir="$WORK_DIR/repo-override-service"
mkdir -p "$repo_override_dir"
se_out="$("$SE" --project repo-override-service --repo "$repo_override_dir" --ready-timeout 10 2>"$WORK_DIR/se-repo.err")"
RC_SE_REPO=$?
if [[ "$RC_SE_REPO" != "0" ]]; then
  echo "    se --repo stderr:"; sed 's/^/      /' "$WORK_DIR/se-repo.err"
  echo "    se --repo stdout:"; printf '      %s\n' "$se_out"
fi
assert_eq "$RC_SE_REPO" "0" "start-test-env --repo full chain"
[[ -f "$repo_override_dir/.repo-override-installed" ]]
assert_eq "$?" "0" "start-test-env --repo runs install in override cwd"

echo ""
echo "=== Summary ==="
echo "PASS=$PASS  FAIL=$FAIL"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
echo "All assertions passed."
exit 0
