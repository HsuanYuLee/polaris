#!/usr/bin/env bash
# scripts/run-verify-command-selftest.sh — DP-032 Wave β D15 selftest
#
# Coverage:
#   - usage / missing args
#   - static level: direct exec of mock command + evidence schema
#   - build level: mock run-test-prep.sh on PATH
#   - runtime level: mock start-test-env.sh + python http server
#   - evidence file fields (ticket / head_sha / writer / filename pattern)
#   - exit code propagation (verify fail → script exit 1, evidence still written)
#   - idempotency / overwrite on same head_sha
#   - URL extraction in results[]
#
# Run: bash scripts/run-verify-command-selftest.sh   (DEBUG=1 for verbose)
# Exit 0 if all assertions pass.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RVC="$SCRIPT_DIR/run-verify-command.sh"
WORK_DIR="$(mktemp -d -t polaris-rvc-selftest-XXXXXX)"
: "${DEBUG:=0}"

PASS=0
FAIL=0

assert_eq() {
  local got="$1" want="$2" label="$3"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1))
    [[ "$DEBUG" == "1" ]] && printf "  [ok] %s (got=%s)\n" "$label" "$got"
  else
    FAIL=$((FAIL + 1))
    printf "  [FAIL] %s — want=%s got=%s\n" "$label" "$want" "$got"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    PASS=$((PASS + 1))
    [[ "$DEBUG" == "1" ]] && printf "  [ok] %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    printf "  [FAIL] %s — needle=%s\n" "$label" "$needle"
    printf "    haystack: %s\n" "$haystack" | head -5
  fi
}

assert_file_exists() {
  local f="$1" label="$2"
  if [[ -f "$f" ]]; then
    PASS=$((PASS + 1))
    [[ "$DEBUG" == "1" ]] && printf "  [ok] %s exists\n" "$label"
  else
    FAIL=$((FAIL + 1))
    printf "  [FAIL] %s — file missing: %s\n" "$label" "$f"
  fi
}

cleanup() {
  # Kill any lingering python3 http.server processes from runtime tests
  for pid_file in "$WORK_DIR"/*.pid; do
    [[ -f "$pid_file" ]] || continue
    pid=$(cat "$pid_file" 2>/dev/null || true)
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done
  rm -rf "$WORK_DIR" 2>/dev/null || true
  # Clean evidence files we wrote
  rm -f /tmp/polaris-verified-RVC*-*.json 2>/dev/null || true
}
trap cleanup EXIT

# ────────────────────────────────────────────────────────────────────────────
# Build a minimal fake repo + task.md harness
# ────────────────────────────────────────────────────────────────────────────
make_fake_task_md() {
  local repo_dir="$1"        # directory representing the repo (must have .git)
  local repo_name="$2"
  local task_path="$3"
  local level="$4"
  local verify_command="$5"
  local ticket="$6"
  local extra_runtime_target="${7:-}"

  mkdir -p "$(dirname "$task_path")"

  # frontmatter + minimal sections matching parse-task-md.sh's expected format:
  #   header line: # T{n}: summary (N pt)
  #   metadata quote line: > Epic: ... | JIRA: KEY | Repo: NAME
  #   Operational Context: pipe table with `Task JIRA key` etc.
  cat > "$task_path" <<EOF
---
status: PLANNED
---

# T1: rvc selftest task ${level} (1 pt)

> Epic: SELFTEST-001 | JIRA: ${ticket} | Repo: ${repo_name}

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | ${ticket} |
| Parent Epic | SELFTEST-001 |
| AC 驗收單 | SELFTEST-100 |
| Base branch | main |
| Task branch | task/${ticket}-rvc-selftest |

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| \`README.md\` | modify | selftest |

## 估點理由

selftest

## Test Environment

- **Level**: ${level}
- **Dev env config**: \`workspace-config.yaml\` → \`projects[${repo_name}].dev_environment\`
- **Fixtures**: N/A
EOF

  if [[ -n "$extra_runtime_target" ]]; then
    cat >> "$task_path" <<EOF
- **Runtime verify target**: ${extra_runtime_target}
EOF
  fi

  cat >> "$task_path" <<EOF

## Test Command

\`\`\`bash
echo "test command placeholder"
\`\`\`

## Verify Command

\`\`\`bash
${verify_command}
\`\`\`

## Allowed Files

- \`README.md\`
EOF
}

setup_fake_repo() {
  local parent="$1" repo_name="$2"
  local repo_dir="$parent/$repo_name"
  mkdir -p "$repo_dir"
  git -C "$repo_dir" init -q -b main
  git -C "$repo_dir" -c user.email=t@t.t -c user.name=t commit --allow-empty -q -m init
  printf '%s\n' "$repo_dir"
}

# ────────────────────────────────────────────────────────────────────────────
echo "=== usage ==="
"$RVC" >/dev/null 2>&1; assert_eq "$?" "2" "usage error: no args"
"$RVC" --task-md /nonexistent/path >/dev/null 2>&1; assert_eq "$?" "1" "missing task.md → exit 1"

# ────────────────────────────────────────────────────────────────────────────
echo "=== static level ==="
PARENT_S="$WORK_DIR/static"
mkdir -p "$PARENT_S/specs/SELFTEST-001/tasks"
REPO_S="$(setup_fake_repo "$PARENT_S" "myrepo")"
TASK_S="$PARENT_S/specs/SELFTEST-001/tasks/T1.md"
make_fake_task_md "$REPO_S" "myrepo" "$TASK_S" "static" 'echo HELLO_STATIC' "RVC-1"

OUT_S="$WORK_DIR/static.out"; ERR_S="$WORK_DIR/static.err"
"$RVC" --task-md "$TASK_S" >"$OUT_S" 2>"$ERR_S"
RC_S=$?
assert_eq "$RC_S" "0" "static level exits 0 on PASS"
assert_contains "$(cat "$OUT_S")" "HELLO_STATIC" "static stdout surfaced from verify command"

HEAD_S="$(git -C "$REPO_S" rev-parse HEAD)"
EV_S="/tmp/polaris-verified-RVC-1-${HEAD_S}.json"
assert_file_exists "$EV_S" "static evidence file"

EV_TICKET="$(python3 -c "import json; print(json.load(open('$EV_S'))['ticket'])" 2>/dev/null)"
assert_eq "$EV_TICKET" "RVC-1" "evidence: ticket field"

EV_HEAD="$(python3 -c "import json; print(json.load(open('$EV_S'))['head_sha'])" 2>/dev/null)"
assert_eq "$EV_HEAD" "$HEAD_S" "evidence: head_sha field"

EV_WRITER="$(python3 -c "import json; print(json.load(open('$EV_S'))['writer'])" 2>/dev/null)"
assert_eq "$EV_WRITER" "run-verify-command.sh" "evidence: writer field"

EV_EXIT="$(python3 -c "import json; print(json.load(open('$EV_S'))['exit_code'])" 2>/dev/null)"
assert_eq "$EV_EXIT" "0" "evidence: exit_code reflects PASS"

EV_LEVEL="$(python3 -c "import json; print(json.load(open('$EV_S'))['level'])" 2>/dev/null)"
assert_eq "$EV_LEVEL" "static" "evidence: level field"

EV_EXEC_CWD="$(python3 -c "import json; print(json.load(open('$EV_S'))['execution_cwd'])" 2>/dev/null)"
assert_eq "$EV_EXEC_CWD" "$REPO_S" "evidence: execution_cwd field"

# --repo must also be the Verify Command cwd. This catches cases where HEAD is
# read from --repo but the command still runs from the caller cwd.
echo "repo-cwd-ok" > "$REPO_S/repo-only.txt"
TASK_CWD="$PARENT_S/specs/SELFTEST-001/tasks/T_cwd.md"
make_fake_task_md "$REPO_S" "myrepo" "$TASK_CWD" "static" 'test -f repo-only.txt && cat repo-only.txt' "RVC-CWD"
(
  cd "$WORK_DIR" || exit 1
  "$RVC" --task-md "$TASK_CWD" --repo "$REPO_S"
) >"$WORK_DIR/cwd.out" 2>"$WORK_DIR/cwd.err"
RC_CWD=$?
assert_eq "$RC_CWD" "0" "--repo executes Verify Command in repo cwd"
assert_contains "$(cat "$WORK_DIR/cwd.out")" "repo-cwd-ok" "repo cwd verify sees repo-only file"
EV_CWD="/tmp/polaris-verified-RVC-CWD-${HEAD_S}.json"
assert_file_exists "$EV_CWD" "repo cwd evidence file"
EV_CWD_FIELD="$(python3 -c "import json; print(json.load(open('$EV_CWD'))['execution_cwd'])" 2>/dev/null)"
assert_eq "$EV_CWD_FIELD" "$REPO_S" "repo cwd evidence records execution_cwd"

# ────────────────────────────────────────────────────────────────────────────
echo "=== verify command FAIL → exit 1, evidence still written ==="
TASK_F="$PARENT_S/specs/SELFTEST-001/tasks/T_fail.md"
make_fake_task_md "$REPO_S" "myrepo" "$TASK_F" "static" 'exit 7' "RVC-FAIL"

"$RVC" --task-md "$TASK_F" >"$WORK_DIR/fail.out" 2>"$WORK_DIR/fail.err"
RC_F=$?
assert_eq "$RC_F" "1" "verify exit 7 → script exit 1"

EV_F="/tmp/polaris-verified-RVC-FAIL-${HEAD_S}.json"
assert_file_exists "$EV_F" "evidence file written even on FAIL"

EV_F_EXIT="$(python3 -c "import json; print(json.load(open('$EV_F'))['exit_code'])" 2>/dev/null)"
assert_eq "$EV_F_EXIT" "7" "evidence: exit_code reflects FAIL"

# ────────────────────────────────────────────────────────────────────────────
echo "=== --ticket override ==="
TASK_T="$PARENT_S/specs/SELFTEST-001/tasks/T_override.md"
make_fake_task_md "$REPO_S" "myrepo" "$TASK_T" "static" 'echo override' "RVC-IGNORED"

"$RVC" --task-md "$TASK_T" --ticket "RVC-OVERRIDE" >/dev/null 2>&1
RC_T=$?
assert_eq "$RC_T" "0" "--ticket override exec succeeds"

EV_T="/tmp/polaris-verified-RVC-OVERRIDE-${HEAD_S}.json"
assert_file_exists "$EV_T" "--ticket override evidence file"

# ────────────────────────────────────────────────────────────────────────────
echo "=== build level (mock run-test-prep.sh on PATH) ==="
# Strategy: instead of injecting on PATH (the script resolves run-test-prep.sh
# via SCRIPT_DIR/env/run-test-prep.sh, not PATH), we create a temporary scripts
# tree with a fake env/run-test-prep.sh and call run-verify-command.sh from
# that tree.
FAKE_BUILD_DIR="$WORK_DIR/fake-scripts-build"
mkdir -p "$FAKE_BUILD_DIR/env"
cp "$RVC" "$FAKE_BUILD_DIR/run-verify-command.sh"
cp "$SCRIPT_DIR/parse-task-md.sh" "$FAKE_BUILD_DIR/parse-task-md.sh"
cp "$SCRIPT_DIR/resolve-task-base.sh" "$FAKE_BUILD_DIR/resolve-task-base.sh" 2>/dev/null || true
chmod +x "$FAKE_BUILD_DIR"/*.sh 2>/dev/null
cat > "$FAKE_BUILD_DIR/env/run-test-prep.sh" <<'PREPSH'
#!/usr/bin/env bash
# fake run-test-prep.sh — selftest stub
echo "FAKE_RUN_TEST_PREP_INVOKED" >&2
touch "$WORK_DIR/_run_test_prep_called" 2>/dev/null || true
exit 0
PREPSH
chmod +x "$FAKE_BUILD_DIR/env/run-test-prep.sh"

PARENT_B="$WORK_DIR/build"
mkdir -p "$PARENT_B/specs/SELFTEST-001/tasks"
REPO_B="$(setup_fake_repo "$PARENT_B" "myrepo")"
TASK_B="$PARENT_B/specs/SELFTEST-001/tasks/T1.md"
make_fake_task_md "$REPO_B" "myrepo" "$TASK_B" "build" 'echo BUILD_OK' "RVC-B1"

env WORK_DIR="$WORK_DIR" "$FAKE_BUILD_DIR/run-verify-command.sh" --task-md "$TASK_B" >"$WORK_DIR/build.out" 2>"$WORK_DIR/build.err"
RC_B=$?
assert_eq "$RC_B" "0" "build level exits 0 with mock prep"
assert_contains "$(cat "$WORK_DIR/build.err")" "FAKE_RUN_TEST_PREP_INVOKED" "build level invokes run-test-prep.sh"
HEAD_B="$(git -C "$REPO_B" rev-parse HEAD)"
EV_B="/tmp/polaris-verified-RVC-B1-${HEAD_B}.json"
assert_file_exists "$EV_B" "build level evidence file"

# Build-level missing primitive → warn and run verify against current repo state.
FAKE_BUILD_BAD_DIR="$WORK_DIR/fake-scripts-build-bad"
mkdir -p "$FAKE_BUILD_BAD_DIR"
cp "$RVC" "$FAKE_BUILD_BAD_DIR/run-verify-command.sh"
cp "$SCRIPT_DIR/parse-task-md.sh" "$FAKE_BUILD_BAD_DIR/parse-task-md.sh"
cp "$SCRIPT_DIR/resolve-task-base.sh" "$FAKE_BUILD_BAD_DIR/resolve-task-base.sh" 2>/dev/null || true
chmod +x "$FAKE_BUILD_BAD_DIR"/*.sh 2>/dev/null
# No env/run-test-prep.sh in this tree
"$FAKE_BUILD_BAD_DIR/run-verify-command.sh" --task-md "$TASK_B" >/dev/null 2>"$WORK_DIR/build_missing.err"
RC_BB=$?
assert_eq "$RC_BB" "0" "build level missing prep → warning + exit 0"
assert_contains "$(cat "$WORK_DIR/build_missing.err")" "WARN build-level prep primitive missing" "build missing prep warning message"

# ────────────────────────────────────────────────────────────────────────────
echo "=== runtime level (mock start-test-env.sh + python http server) ==="
# Pick a random port
PORT=$(python3 -c 'import socket;s=socket.socket();s.bind(("",0));print(s.getsockname()[1]);s.close()')
python3 -u -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 &
HTTP_PID=$!
echo "$HTTP_PID" > "$WORK_DIR/http.pid"
# Wait for server
for _ in 1 2 3 4 5 6 7 8 9 10; do
  curl -fsS -o /dev/null "http://127.0.0.1:$PORT/" 2>/dev/null && break
  sleep 0.3
done

FAKE_RT_DIR="$WORK_DIR/fake-scripts-runtime"
mkdir -p "$FAKE_RT_DIR/env"
cp "$RVC" "$FAKE_RT_DIR/run-verify-command.sh"
cp "$SCRIPT_DIR/parse-task-md.sh" "$FAKE_RT_DIR/parse-task-md.sh"
cp "$SCRIPT_DIR/resolve-task-base.sh" "$FAKE_RT_DIR/resolve-task-base.sh" 2>/dev/null || true
chmod +x "$FAKE_RT_DIR"/*.sh 2>/dev/null
cat > "$FAKE_RT_DIR/start-test-env.sh" <<'STESH'
#!/usr/bin/env bash
echo "FAKE_START_TEST_ENV_INVOKED" >&2
exit 0
STESH
chmod +x "$FAKE_RT_DIR/start-test-env.sh"

PARENT_R="$WORK_DIR/runtime"
mkdir -p "$PARENT_R/specs/SELFTEST-001/tasks"
REPO_R="$(setup_fake_repo "$PARENT_R" "myrepo")"
TASK_R="$PARENT_R/specs/SELFTEST-001/tasks/T1.md"
RT_TARGET="http://127.0.0.1:${PORT}"
make_fake_task_md "$REPO_R" "myrepo" "$TASK_R" "runtime" \
  "curl -sS -o /dev/null -w \"%{http_code}\\n\" http://127.0.0.1:${PORT}/" \
  "RVC-R1" \
  "$RT_TARGET"

"$FAKE_RT_DIR/run-verify-command.sh" --task-md "$TASK_R" >"$WORK_DIR/rt.out" 2>"$WORK_DIR/rt.err"
RC_R=$?
assert_eq "$RC_R" "0" "runtime level exits 0 with mock orchestrator + live http"
assert_contains "$(cat "$WORK_DIR/rt.err")" "FAKE_START_TEST_ENV_INVOKED" "runtime level invokes start-test-env.sh"
assert_contains "$(cat "$WORK_DIR/rt.out")" "200" "verify command stdout shows http 200"

HEAD_R="$(git -C "$REPO_R" rev-parse HEAD)"
EV_R="/tmp/polaris-verified-RVC-R1-${HEAD_R}.json"
assert_file_exists "$EV_R" "runtime evidence file"

# Runtime contract checks
RC_LEVEL="$(python3 -c "import json;d=json.load(open('$EV_R'));print(d['runtime_contract']['level'])" 2>/dev/null)"
assert_eq "$RC_LEVEL" "runtime" "runtime_contract.level"

RC_TARGET="$(python3 -c "import json;d=json.load(open('$EV_R'));print(d['runtime_contract']['runtime_verify_target'])" 2>/dev/null)"
assert_eq "$RC_TARGET" "$RT_TARGET" "runtime_contract.runtime_verify_target"

RC_THOST="$(python3 -c "import json;d=json.load(open('$EV_R'));print(d['runtime_contract']['runtime_verify_target_host'])" 2>/dev/null)"
RC_VHOST="$(python3 -c "import json;d=json.load(open('$EV_R'));print(d['runtime_contract']['verify_command_url_host'])" 2>/dev/null)"
assert_eq "$RC_THOST" "$RC_VHOST" "runtime_contract host parity"

# results[] should contain a curl entry with url + http_status
RES_URL="$(python3 -c "
import json
d = json.load(open('$EV_R'))
r = d.get('results') or []
print(r[0]['url'] if r else '')
" 2>/dev/null)"
assert_contains "$RES_URL" "127.0.0.1:${PORT}" "results[0].url contains test server"

RES_STATUS="$(python3 -c "
import json
d = json.load(open('$EV_R'))
r = d.get('results') or []
print(r[0].get('http_status', '') if r else '')
" 2>/dev/null)"
assert_eq "$RES_STATUS" "200" "results[0].http_status == 200"

# Cleanup http server
kill "$HTTP_PID" 2>/dev/null || true
sleep 0.3

# ────────────────────────────────────────────────────────────────────────────
echo "=== validate-task-md DP-065 command-shape regressions ==="
VALIDATE_TASK_MD="$SCRIPT_DIR/validate-task-md.sh"
VT_DIR="$WORK_DIR/validator"
mkdir -p "$VT_DIR/tasks"

make_validator_task_md() {
  local task_path="$1"
  local level="$2"
  local runtime_target="$3"
  local bootstrap="$4"
  local verify_command="$5"

  cat > "$task_path" <<EOF
---
title: "Work Order - T1: docs-manager runtime 測試 (1 pt)"
description: "此工單描述 docs-manager runtime 測試。"
---

# T1: docs-manager runtime 測試 (1 pt)

> Source: DP-999 | Task: DP-999-T1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-999 |
| Task ID | DP-999-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Branch chain | main -> task/DP-999-T1-test |
| Task branch | task/DP-999-T1-test |
| Depends on | N/A |
| References to load | - \`scripts/validate-task-md.sh\` |

## Verification Handoff

此為 framework work order。

## 目標

測試 validator regression。

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| \`scripts/validate-task-md.sh\` | modify | 測試 |

## Allowed Files

- \`scripts/validate-task-md.sh\`

## 估點理由

1 pt - 測試。

## 測試計畫（code-level）

- 測試 validator regression。

## Test Command

\`\`\`bash
echo ok
\`\`\`

## Test Environment

- **Level**: ${level}
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: ${runtime_target}
- **Env bootstrap command**: ${bootstrap}

## Verify Command

\`\`\`bash
${verify_command}
\`\`\`
EOF
}

TASK_VT_BARE="$VT_DIR/tasks/T_bare.md"
make_validator_task_md "$TASK_VT_BARE" "runtime" "http://127.0.0.1:8080" \
  "bash scripts/polaris-viewer.sh --detach --port 8080 --no-open" \
  "curl -fsS http://127.0.0.1:8080/docs-manager/ >/dev/null"
"$VALIDATE_TASK_MD" "$TASK_VT_BARE" >"$WORK_DIR/vt_bare.out" 2>"$WORK_DIR/vt_bare.err"
RC_VT_BARE=$?
assert_eq "$RC_VT_BARE" "1" "docs-manager bare runtime target fails validation"
assert_contains "$(cat "$WORK_DIR/vt_bare.err")" "must include /docs-manager/ path" "docs-manager bare target error mentions base path"

TASK_VT_OK="$VT_DIR/tasks/T_ok.md"
make_validator_task_md "$TASK_VT_OK" "runtime" "http://127.0.0.1:8080/docs-manager/" \
  "bash scripts/polaris-viewer.sh --detach --port 8080 --no-open" \
  "curl -fsS http://127.0.0.1:8080/docs-manager/ >/dev/null"
"$VALIDATE_TASK_MD" "$TASK_VT_OK" >/dev/null 2>"$WORK_DIR/vt_ok.err"
RC_VT_OK=$?
assert_eq "$RC_VT_OK" "0" "docs-manager /docs-manager/ runtime target passes validation"

TASK_VT_FLAG="$VT_DIR/tasks/T_flag.md"
make_validator_task_md "$TASK_VT_FLAG" "static" "N/A" "N/A" \
  "bash scripts/verify-docs-manager-runtime.sh --style-check --ports 8080"
"$VALIDATE_TASK_MD" "$TASK_VT_FLAG" >"$WORK_DIR/vt_flag.out" 2>"$WORK_DIR/vt_flag.err"
RC_VT_FLAG=$?
assert_eq "$RC_VT_FLAG" "1" "unsupported repo-local script flag fails validation"
assert_contains "$(cat "$WORK_DIR/vt_flag.err")" "unsupported flag --style-check" "unsupported flag error mentions flag"

TASK_VT_RG="$VT_DIR/tasks/T_rg.md"
make_validator_task_md "$TASK_VT_RG" "static" "N/A" "N/A" \
  "rg -n '\\\\{workspace_root\\\\}' README.md"
"$VALIDATE_TASK_MD" "$TASK_VT_RG" >"$WORK_DIR/vt_rg.out" 2>"$WORK_DIR/vt_rg.err"
RC_VT_RG=$?
assert_eq "$RC_VT_RG" "1" "rg regex parse failure fails validation"
assert_contains "$(cat "$WORK_DIR/vt_rg.err")" "rg pattern parse failed" "rg parse error is reported"

# ────────────────────────────────────────────────────────────────────────────
echo "=== idempotent re-run on same head_sha (overwrite) ==="
# Re-run static and confirm evidence file still present and timestamp updated
SLEEP_THRESHOLD="$(date -u +%s)"
sleep 1
"$RVC" --task-md "$TASK_S" >/dev/null 2>&1
RC_RR=$?
assert_eq "$RC_RR" "0" "re-run static level exits 0"
EV_AT="$(python3 -c "
import json, datetime
d = json.load(open('$EV_S'))
ts = datetime.datetime.fromisoformat(d['at'].replace('Z','+00:00'))
print(int(ts.timestamp()))
" 2>/dev/null)"
if [[ "${EV_AT:-0}" -ge "$SLEEP_THRESHOLD" ]]; then
  PASS=$((PASS + 1))
  [[ "$DEBUG" == "1" ]] && printf "  [ok] evidence 'at' updated on re-run\n"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] evidence 'at' not updated on re-run (at=%s, threshold=%s)\n" "$EV_AT" "$SLEEP_THRESHOLD"
fi

# Different head_sha (new commit) → different evidence filename
echo "extra" > "$REPO_S/extra.txt"
git -C "$REPO_S" -c user.email=t@t.t -c user.name=t add . >/dev/null
git -C "$REPO_S" -c user.email=t@t.t -c user.name=t commit -q -m "extra"
HEAD_S2="$(git -C "$REPO_S" rev-parse HEAD)"
"$RVC" --task-md "$TASK_S" >/dev/null 2>&1
RC_RR2=$?
assert_eq "$RC_RR2" "0" "re-run after new commit succeeds"
EV_S2="/tmp/polaris-verified-RVC-1-${HEAD_S2}.json"
assert_file_exists "$EV_S2" "new head_sha → new evidence file"
if [[ "$HEAD_S" != "$HEAD_S2" && -f "$EV_S" && -f "$EV_S2" ]]; then
  PASS=$((PASS + 1))
  [[ "$DEBUG" == "1" ]] && printf "  [ok] both old and new head_sha evidence files coexist\n"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] head_sha-bound coexistence broke\n"
fi

# Cleanup the static evidence we created
rm -f "$EV_S" "$EV_S2" "$EV_F" "$EV_T" "$EV_B" "$EV_R" "$EV_CWD" 2>/dev/null

# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Summary ==="
TOTAL=$((PASS + FAIL))
echo "PASS=$PASS  FAIL=$FAIL  TOTAL=$TOTAL"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
echo "All assertions passed."
exit 0
