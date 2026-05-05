#!/usr/bin/env bash
# scripts/run-verify-command.sh — DP-032 Wave β D15
#
# Atomic execution of task.md `## Verify Command` + writes head_sha-bound
# evidence file. Replaces the multi-step LLM ritual (read task.md → start env →
# run verify → write evidence) with a single deterministic invocation.
#
# Contract:
#   run-verify-command.sh --task-md PATH [--ticket KEY] [--repo PATH]
#
# Behavior:
#   1. Parse Verify Command from task.md (fenced shell block)
#   2. Parse Test Environment Level (static / build / runtime)
#   3. Parse ticket key from task.md (if not given via --ticket)
#   4. Per-level env preparation:
#        static  → no env prep
#        build   → invoke scripts/env/run-test-prep.sh when present; otherwise
#                  warn and run the Verify Command against current repo state
#        runtime → invoke scripts/start-test-env.sh --task-md (idempotent)
#   5. Compute head_sha = git rev-parse HEAD (in repo derived from task.md)
#   6. Execute verify command in repo/worktree cwd, capture stdout/stderr/exit_code
#   7. If the primary Verify Command fails and task.md explicitly declares
#      `## Verify Fallback Command`, execute that fallback command in the same cwd
#   8. Write /tmp/polaris-verified-{TICKET}-{HEAD_SHA}.json
#   9. Exit 0 only when the effective verify exit == 0 AND evidence write succeeds
#
# Evidence schema (DP-032 D15, schema-loose new format):
#   {
#     "ticket": "TASK-3788",
#     "head_sha": "abc1234...",
#     "command": "<verify_command full text>",
#     "exit_code": 0,
#     "stdout_hash": "<sha256>",
#     "writer": "run-verify-command.sh",
#     "execution_cwd": "/path/to/repo-or-worktree",
#     "at": "2026-04-26T12:34:56Z",
#     "level": "runtime",
#     "results": [
#       { "url": "...", "http_status": 200, "command": "<line>", "stdout_hash": "...", "writer": "run-verify-command.sh" }
#     ],
#     "runtime_contract": { "level": "runtime", "runtime_verify_target": "...", ... }  # runtime only
#   }
#
# No bypass env var: this script mirrors the orchestrator policy.
# Script bugs are fixed in the script, not bypassed.
#
# Exit codes:
#   0  Verify command exit 0 + evidence file landed and valid
#   1  Verify command failed, env prep failed, parse failed, or evidence write failed
#   2  Usage error

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_TASK_MD="$SCRIPT_DIR/parse-task-md.sh"
RUN_TEST_PREP="$SCRIPT_DIR/env/run-test-prep.sh"
START_TEST_ENV="$SCRIPT_DIR/start-test-env.sh"
BOOTSTRAP_PIDS=()
TMP_OUT=""
TMP_ERR=""
TMP_FALLBACK_OUT=""
TMP_FALLBACK_ERR=""

if [[ -f "$SCRIPT_DIR/lib/main-checkout.sh" ]]; then
  # shellcheck source=lib/main-checkout.sh
  . "$SCRIPT_DIR/lib/main-checkout.sh"
fi

usage() {
  cat <<EOF >&2
Usage:
  $(basename "$0") --task-md PATH [--ticket KEY] [--repo PATH]

Atomically prepares env, executes task.md \`## Verify Command\`, and writes
head_sha-bound evidence to /tmp/polaris-verified-{TICKET}-{HEAD_SHA}.json.

Exit:  0 = PASS (verify + evidence both succeed), 1 = FAIL, 2 = usage error.
EOF
}

# --- Args -------------------------------------------------------------------
TASK_MD=""
TICKET=""
REPO_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --ticket)  TICKET="${2:-}";  shift 2 ;;
    --repo)    REPO_OVERRIDE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "run-verify-command: unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$TASK_MD" ]]; then
  echo "run-verify-command: --task-md is required" >&2
  usage
  exit 2
fi
if [[ ! -f "$TASK_MD" ]]; then
  echo "run-verify-command: --task-md path not found: $TASK_MD" >&2
  exit 1
fi
if [[ ! -x "$PARSE_TASK_MD" ]]; then
  echo "run-verify-command: parse-task-md.sh not executable at $PARSE_TASK_MD" >&2
  exit 1
fi

# --- Parse fields from task.md ---------------------------------------------
parse_field() {
  local field="$1"
  "$PARSE_TASK_MD" --field "$field" "$TASK_MD" 2>/dev/null || true
}

VERIFY_COMMAND="$(parse_field verify_command)"
VERIFY_FALLBACK_COMMAND="$(parse_field verify_fallback_command)"
LEVEL="$(parse_field level)"
REPO_NAME="$(parse_field repo)"
TASK_TICKET="$(parse_field task_jira_key)"
DEV_ENV_CONFIG="$(parse_field dev_env_config)"
ENV_BOOTSTRAP_COMMAND="$(parse_field env_bootstrap_command)"
RUNTIME_VERIFY_TARGET="$(parse_field runtime_verify_target)"

if [[ -z "$TICKET" ]]; then
  TICKET="$TASK_TICKET"
fi

if [[ -z "$VERIFY_COMMAND" ]]; then
  echo "run-verify-command: failed to parse 'verify_command' from $TASK_MD" >&2
  exit 1
fi
if [[ -z "$LEVEL" ]]; then
  echo "run-verify-command: failed to parse 'level' from $TASK_MD" >&2
  exit 1
fi
case "$LEVEL" in
  static|build|runtime) ;;
  *) echo "run-verify-command: invalid level '$LEVEL' (expected static|build|runtime)" >&2; exit 1 ;;
esac
if [[ -z "$TICKET" ]]; then
  echo "run-verify-command: ticket key not provided and not parseable from task.md" >&2
  exit 1
fi
if [[ -z "$REPO_NAME" ]]; then
  echo "run-verify-command: failed to parse 'repo' from $TASK_MD" >&2
  exit 1
fi

# --- Resolve repo path ------------------------------------------------------
# Heuristic: walk up from task.md until we find a directory containing the repo
# (i.e., {ancestor}/{REPO_NAME} exists and is a git working tree).
resolve_repo_path() {
  local repo_name="$1"
  local td
  td="$(cd "$(dirname "$TASK_MD")" && pwd)"
  local probe
  while [[ "$td" != "/" ]]; do
    probe="$td/$repo_name"
    if [[ -d "$probe/.git" ]] || [[ -f "$probe/.git" ]]; then
      printf '%s\n' "$probe"
      return 0
    fi
    td="$(dirname "$td")"
  done
  return 1
}

if [[ -n "$REPO_OVERRIDE" ]]; then
  if [[ ! -d "$REPO_OVERRIDE" ]]; then
    echo "run-verify-command: --repo path not found: $REPO_OVERRIDE" >&2
    exit 1
  fi
  REPO_PATH="$(cd "$REPO_OVERRIDE" && pwd)"
else
  REPO_PATH="$(resolve_repo_path "$REPO_NAME" || true)"
fi
if [[ -z "$REPO_PATH" ]]; then
  echo "run-verify-command: could not locate repo '$REPO_NAME' as ancestor of $TASK_MD" >&2
  echo "  search walks ancestors of task.md looking for {ancestor}/$REPO_NAME with .git" >&2
  exit 1
fi

HEAD_SHA="$(git -C "$REPO_PATH" rev-parse HEAD 2>/dev/null || true)"
if [[ -z "$HEAD_SHA" ]]; then
  echo "run-verify-command: git rev-parse HEAD failed in $REPO_PATH" >&2
  exit 1
fi

WORKTREE_STATUS="$(git -C "$REPO_PATH" -c core.quotePath=false status --porcelain --untracked-files=all -- . ':(exclude).polaris/evidence/verify' 2>/dev/null || true)"
if [[ -n "$WORKTREE_STATUS" ]]; then
  echo "run-verify-command: repo has uncommitted changes; refusing to write HEAD-bound evidence" >&2
  echo "$WORKTREE_STATUS" >&2
  exit 1
fi

is_na_value() {
  local value
  value="$(printf '%s' "${1:-}" | xargs 2>/dev/null || true)"
  [[ -z "$value" || "$value" == "N/A" || "$value" == "n/a" || "$value" == "-" || "$value" == "none" ]]
}

cleanup_bootstrap() {
  local pid
  for pid in "${BOOTSTRAP_PIDS[@]:-}"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
}

cleanup_tmp() {
  [[ -n "${TMP_OUT:-}" ]] && rm -f "$TMP_OUT" 2>/dev/null || true
  [[ -n "${TMP_ERR:-}" ]] && rm -f "$TMP_ERR" 2>/dev/null || true
  [[ -n "${TMP_FALLBACK_OUT:-}" ]] && rm -f "$TMP_FALLBACK_OUT" 2>/dev/null || true
  [[ -n "${TMP_FALLBACK_ERR:-}" ]] && rm -f "$TMP_FALLBACK_ERR" 2>/dev/null || true
}

cleanup_all() {
  cleanup_bootstrap
  cleanup_tmp
}
trap cleanup_all EXIT

resolve_durable_evidence_file() {
  local repo_path="$1"
  local ticket="$2"
  local head_sha="$3"
  local evidence_root="${POLARIS_EVIDENCE_ROOT:-}"
  local main_checkout=""

  if [[ -z "$evidence_root" ]]; then
    if declare -F resolve_main_checkout >/dev/null 2>&1; then
      main_checkout="$(resolve_main_checkout "$repo_path" 2>/dev/null || true)"
    fi
    if [[ -z "$main_checkout" ]]; then
      main_checkout="$repo_path"
    fi
    evidence_root="${main_checkout}/.polaris/evidence"
  fi

  printf '%s/verify/polaris-verified-%s-%s.json\n' "$evidence_root" "$ticket" "$head_sha"
}

wait_for_runtime_target() {
  local target="$1"
  local timeout="${2:-120}"
  local elapsed=0

  if ! printf '%s' "$target" | grep -Eq '^https?://'; then
    return 0
  fi

  while [[ "$elapsed" -lt "$timeout" ]]; do
    if curl -fsS "$target" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  echo "run-verify-command: timed out waiting for runtime target: $target" >&2
  return 1
}

run_env_bootstrap_command() {
  local command="$1"
  local target="$2"
  local log_file="/tmp/polaris-verify-bootstrap-${TICKET}-${HEAD_SHA}.log"
  local pid

  echo "run-verify-command: starting Env bootstrap command" >&2
  (
    cd "$REPO_PATH" || exit 1
    bash -c "$command"
  ) >"$log_file" 2>&1 &
  pid="$!"
  BOOTSTRAP_PIDS+=("$pid")

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid"
      local rc="$?"
      if [[ "$rc" -ne 0 ]]; then
        echo "run-verify-command: Env bootstrap command failed ($rc); log: $log_file" >&2
        cat "$log_file" >&2 || true
        return 1
      fi
      echo "run-verify-command: Env bootstrap command completed" >&2
      return 0
    fi
    sleep 0.2
  done

  echo "run-verify-command: Env bootstrap command is still running (pid=$pid); log: $log_file" >&2
  wait_for_runtime_target "$target" 120
}

# --- Env preparation per level ---------------------------------------------
case "$LEVEL" in
  static)
    : # no env prep
    ;;
  build)
    if [[ ! -x "$RUN_TEST_PREP" ]]; then
      echo "run-verify-command: WARN build-level prep primitive missing; running Verify Command against current repo state" >&2
    elif ! "$RUN_TEST_PREP" --task-md "$TASK_MD" --repo "$REPO_PATH" >&2; then
      echo "run-verify-command: scripts/env/run-test-prep.sh failed (build-level prep)" >&2
      exit 1
    fi
    ;;
  runtime)
    if printf '%s' "$DEV_ENV_CONFIG" | grep -q 'projects\[[^]]*\]\.dev_environment'; then
      if [[ ! -x "$START_TEST_ENV" ]]; then
        echo "run-verify-command: runtime-level requires scripts/start-test-env.sh — orchestrator missing" >&2
        exit 1
      fi
      if ! "$START_TEST_ENV" --task-md "$TASK_MD" --repo "$REPO_PATH" >&2; then
        echo "run-verify-command: scripts/start-test-env.sh failed (runtime-level env start)" >&2
        exit 1
      fi
    elif ! is_na_value "$ENV_BOOTSTRAP_COMMAND"; then
      if ! run_env_bootstrap_command "$ENV_BOOTSTRAP_COMMAND" "$RUNTIME_VERIFY_TARGET"; then
        echo "run-verify-command: Env bootstrap command failed (runtime-level env start)" >&2
        exit 1
      fi
    else
      echo "run-verify-command: runtime-level task has no projects[...] dev env config and no Env bootstrap command" >&2
      exit 1
    fi
    ;;
esac

# --- Execute verify command -------------------------------------------------
TMP_OUT="$(mktemp -t polaris-verify-stdout.XXXXXX)"
TMP_ERR="$(mktemp -t polaris-verify-stderr.XXXXXX)"

(
  cd "$REPO_PATH" || exit 1
  bash -c "$VERIFY_COMMAND"
) >"$TMP_OUT" 2>"$TMP_ERR"
VERIFY_EXIT=$?
PRIMARY_EXIT=$VERIFY_EXIT
EFFECTIVE_COMMAND="$VERIFY_COMMAND"
EFFECTIVE_EXIT="$VERIFY_EXIT"
EFFECTIVE_STDOUT_FILE="$TMP_OUT"
EFFECTIVE_STDERR_FILE="$TMP_ERR"
VERIFICATION_MODE="primary"

if [[ "$VERIFY_EXIT" -ne 0 && -n "$VERIFY_FALLBACK_COMMAND" ]]; then
  TMP_FALLBACK_OUT="$(mktemp -t polaris-verify-fallback-stdout.XXXXXX)"
  TMP_FALLBACK_ERR="$(mktemp -t polaris-verify-fallback-stderr.XXXXXX)"
  (
    cd "$REPO_PATH" || exit 1
    bash -c "$VERIFY_FALLBACK_COMMAND"
  ) >"$TMP_FALLBACK_OUT" 2>"$TMP_FALLBACK_ERR"
  FALLBACK_EXIT=$?
  EFFECTIVE_COMMAND="$VERIFY_FALLBACK_COMMAND"
  EFFECTIVE_EXIT="$FALLBACK_EXIT"
  EFFECTIVE_STDOUT_FILE="$TMP_FALLBACK_OUT"
  EFFECTIVE_STDERR_FILE="$TMP_FALLBACK_ERR"
  VERIFICATION_MODE="fallback"
else
  FALLBACK_EXIT=""
fi

# --- Compute runtime contract (if level == runtime) ------------------------
# Extract first URL from verify command for host comparison.

# --- Write evidence file ---------------------------------------------------
EVIDENCE_FILE="/tmp/polaris-verified-${TICKET}-${HEAD_SHA}.json"
DURABLE_EVIDENCE_FILE="$(resolve_durable_evidence_file "$REPO_PATH" "$TICKET" "$HEAD_SHA")"
AT_TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Pass everything to python via env to avoid quoting hell.
export RVC_TICKET="$TICKET"
export RVC_HEAD_SHA="$HEAD_SHA"
export RVC_COMMAND="$VERIFY_COMMAND"
export RVC_EFFECTIVE_COMMAND="$EFFECTIVE_COMMAND"
export RVC_EXIT_CODE="$EFFECTIVE_EXIT"
export RVC_PRIMARY_EXIT_CODE="$PRIMARY_EXIT"
export RVC_FALLBACK_COMMAND="$VERIFY_FALLBACK_COMMAND"
export RVC_FALLBACK_EXIT_CODE="$FALLBACK_EXIT"
export RVC_VERIFICATION_MODE="$VERIFICATION_MODE"
export RVC_AT="$AT_TS"
export RVC_LEVEL="$LEVEL"
export RVC_RUNTIME_TARGET="$RUNTIME_VERIFY_TARGET"
export RVC_OUTPUT_FILE="$EVIDENCE_FILE"
export RVC_STDOUT_FILE="$EFFECTIVE_STDOUT_FILE"
export RVC_STDERR_FILE="$EFFECTIVE_STDERR_FILE"
export RVC_PRIMARY_STDOUT_FILE="$TMP_OUT"
export RVC_PRIMARY_STDERR_FILE="$TMP_ERR"
export RVC_FALLBACK_STDOUT_FILE="$TMP_FALLBACK_OUT"
export RVC_FALLBACK_STDERR_FILE="$TMP_FALLBACK_ERR"
export RVC_EXECUTION_CWD="$REPO_PATH"

python3 - <<'PY'
import hashlib, json, os, re
from urllib.parse import urlparse

ticket = os.environ["RVC_TICKET"]
head_sha = os.environ["RVC_HEAD_SHA"]
command = os.environ["RVC_COMMAND"]
effective_command = os.environ["RVC_EFFECTIVE_COMMAND"]
exit_code = int(os.environ["RVC_EXIT_CODE"])
primary_exit_code = int(os.environ["RVC_PRIMARY_EXIT_CODE"])
fallback_command = os.environ.get("RVC_FALLBACK_COMMAND", "") or ""
fallback_exit_raw = os.environ.get("RVC_FALLBACK_EXIT_CODE", "") or ""
fallback_exit_code = int(fallback_exit_raw) if fallback_exit_raw else None
verification_mode = os.environ["RVC_VERIFICATION_MODE"]
at = os.environ["RVC_AT"]
level = os.environ["RVC_LEVEL"]
runtime_target = os.environ.get("RVC_RUNTIME_TARGET", "") or ""
output_file = os.environ["RVC_OUTPUT_FILE"]
stdout_file = os.environ["RVC_STDOUT_FILE"]
stderr_file = os.environ["RVC_STDERR_FILE"]
primary_stdout_file = os.environ["RVC_PRIMARY_STDOUT_FILE"]
primary_stderr_file = os.environ["RVC_PRIMARY_STDERR_FILE"]
fallback_stdout_file = os.environ.get("RVC_FALLBACK_STDOUT_FILE", "") or ""
fallback_stderr_file = os.environ.get("RVC_FALLBACK_STDERR_FILE", "") or ""
execution_cwd = os.environ["RVC_EXECUTION_CWD"]

def read_bytes(path):
    if not path:
        return b""
    with open(path, "rb") as f:
        return f.read()

stdout_bytes = read_bytes(stdout_file)
stderr_bytes = read_bytes(stderr_file)
primary_stdout_bytes = read_bytes(primary_stdout_file)
primary_stderr_bytes = read_bytes(primary_stderr_file)
fallback_stdout_bytes = read_bytes(fallback_stdout_file)
fallback_stderr_bytes = read_bytes(fallback_stderr_file)

stdout_hash = hashlib.sha256(stdout_bytes).hexdigest()
stderr_hash = hashlib.sha256(stderr_bytes).hexdigest()
primary_stdout_hash = hashlib.sha256(primary_stdout_bytes).hexdigest()
primary_stderr_hash = hashlib.sha256(primary_stderr_bytes).hexdigest()
fallback_stdout_hash = hashlib.sha256(fallback_stdout_bytes).hexdigest() if fallback_stdout_file else None
fallback_stderr_hash = hashlib.sha256(fallback_stderr_bytes).hexdigest() if fallback_stderr_file else None
stdout_text = stdout_bytes.decode("utf-8", errors="replace")

# Best-effort URL extraction: scan command for `curl ... <url>` patterns,
# pair each with an HTTP status code from stdout (if present near the URL).
results = []
url_re = re.compile(r"https?://[^\s\"'<>)]+")
status_re = re.compile(r"\b(\d{3})\b")
# Split command into logical lines (preserve original line for evidence).
lines = []
for raw in effective_command.splitlines():
    s = raw.strip()
    if s:
        lines.append(s)

for ln in lines:
    if "curl" not in ln:
        continue
    m = url_re.search(ln)
    if not m:
        continue
    url = m.group(0).rstrip(",;)")
    # Look for an HTTP status near the URL in stdout (best-effort).
    http_status = None
    for sm in status_re.finditer(stdout_text):
        cand = int(sm.group(1))
        if 100 <= cand < 600:
            http_status = cand
            break
    line_hash = hashlib.sha256(ln.encode("utf-8")).hexdigest()
    results.append({
        "url": url,
        "http_status": http_status,
        "command": ln,
        "stdout_hash": line_hash,
        "writer": "run-verify-command.sh",
    })

evidence = {
    "ticket": ticket,
    "head_sha": head_sha,
    "command": command,
    "effective_command": effective_command,
    "exit_code": exit_code,
    "stdout_hash": stdout_hash,
    "stderr_hash": stderr_hash,
    "writer": "run-verify-command.sh",
    "execution_cwd": execution_cwd,
    "at": at,
    "level": level,
    "verification_mode": verification_mode,
    "primary": {
        "command": command,
        "exit_code": primary_exit_code,
        "stdout_hash": primary_stdout_hash,
        "stderr_hash": primary_stderr_hash,
    },
    "results": results,
}

if verification_mode == "fallback":
    evidence["fallback"] = {
        "command": fallback_command,
        "exit_code": fallback_exit_code,
        "stdout_hash": fallback_stdout_hash,
        "stderr_hash": fallback_stderr_hash,
        "reason": "primary_verify_command_failed",
    }

if level == "runtime":
    target = runtime_target.strip()
    target_host = ""
    if target.startswith("http"):
        target_host = (urlparse(target).hostname or "").lower()
    verify_url = ""
    verify_host = ""
    m_url = url_re.search(command)
    if m_url:
        verify_url = m_url.group(0).rstrip(",;)")
        verify_host = (urlparse(verify_url).hostname or "").lower()
    evidence["runtime_contract"] = {
        "level": level,
        "runtime_verify_target": target,
        "verify_command_url": verify_url,
        "runtime_verify_target_host": target_host,
        "verify_command_url_host": verify_host,
    }
else:
    evidence["runtime_contract"] = {"level": level}

with open(output_file, "w") as f:
    json.dump(evidence, f, indent=2, ensure_ascii=False)
PY
PY_EXIT=$?

if [[ "$PY_EXIT" -ne 0 ]]; then
  echo "run-verify-command: failed to write evidence file ($PY_EXIT)" >&2
  exit 1
fi

# --- Validate evidence file landed correctly --------------------------------
if [[ ! -f "$EVIDENCE_FILE" ]]; then
  echo "run-verify-command: evidence file did not materialize at $EVIDENCE_FILE" >&2
  exit 1
fi

VALID="$(python3 -c "
import json, sys
try:
    with open('$EVIDENCE_FILE') as f:
        d = json.load(f)
    assert d['ticket'] == '$TICKET', 'ticket mismatch'
    assert d['head_sha'] == '$HEAD_SHA', 'head_sha mismatch'
    assert d['writer'] == 'run-verify-command.sh', 'writer mismatch'
    assert d['execution_cwd'] == '$REPO_PATH', 'execution_cwd mismatch'
    assert 'exit_code' in d, 'missing exit_code'
    assert d['at'], 'missing at'
    print('valid')
except Exception as e:
    print('invalid: ' + str(e))
")"

if [[ "$VALID" != "valid" ]]; then
  echo "run-verify-command: evidence file failed validation: $VALID" >&2
  exit 1
fi

if ! mkdir -p "$(dirname "$DURABLE_EVIDENCE_FILE")"; then
  echo "run-verify-command: failed to create durable evidence directory: $(dirname "$DURABLE_EVIDENCE_FILE")" >&2
  exit 1
fi
if ! cp "$EVIDENCE_FILE" "$DURABLE_EVIDENCE_FILE"; then
  echo "run-verify-command: failed to mirror evidence to $DURABLE_EVIDENCE_FILE" >&2
  exit 1
fi
if ! cmp -s "$EVIDENCE_FILE" "$DURABLE_EVIDENCE_FILE"; then
  echo "run-verify-command: durable evidence mirror differs from /tmp evidence: $DURABLE_EVIDENCE_FILE" >&2
  exit 1
fi

# --- Surface stdout/stderr from verify command (after evidence write) ------
if [[ -s "$TMP_OUT" ]]; then
  cat "$TMP_OUT"
fi
if [[ -s "$TMP_ERR" ]]; then
  cat "$TMP_ERR" >&2
fi
if [[ "$VERIFICATION_MODE" == "fallback" ]]; then
  echo "run-verify-command: primary Verify Command failed ($PRIMARY_EXIT); executing explicit Verify Fallback Command" >&2
  if [[ -s "$TMP_FALLBACK_OUT" ]]; then
    cat "$TMP_FALLBACK_OUT"
  fi
  if [[ -s "$TMP_FALLBACK_ERR" ]]; then
    cat "$TMP_FALLBACK_ERR" >&2
  fi
fi

# --- Final disposition ------------------------------------------------------
if [[ "$EFFECTIVE_EXIT" -ne 0 ]]; then
  echo "run-verify-command: effective verify command exited $EFFECTIVE_EXIT (mode=$VERIFICATION_MODE; evidence at $EVIDENCE_FILE; mirror at $DURABLE_EVIDENCE_FILE)" >&2
  exit 1
fi

echo "run-verify-command: PASS — mode=$VERIFICATION_MODE evidence at $EVIDENCE_FILE"
echo "run-verify-command: durable evidence mirror at $DURABLE_EVIDENCE_FILE"
exit 0
