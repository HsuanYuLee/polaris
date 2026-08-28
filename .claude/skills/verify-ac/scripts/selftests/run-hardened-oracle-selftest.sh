#!/usr/bin/env bash
# Purpose: Verify the hardened oracle judges both directions in one run.
# Inputs: Hermetic fixtures under mktemp, including three injected lies.
# Outputs: PASS when a genuinely passing command is PASS and each of the three
#          injection shapes is judged non-PASS. Both directions are required —
#          a runner that always answers FAIL would satisfy the negatives alone.

set -euo pipefail

for tool in python3 bash; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "POLARIS_TOOL_MISSING:$tool" >&2
    echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
    exit 2
  fi
done

# 往上兩層是這支 skill 自己的目錄，所以下面的 $ROOT_DIR/scripts/X 指的是
# 這支 skill 帶著的那一份，不是 repo 根目錄的共用檔——共用檔已經沒有了。
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ORACLE="$ROOT_DIR/scripts/run-hardened-oracle.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS_COUNT=0

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

run_oracle() {
  # Description: run the oracle, capturing combined output and exit status.
  # Args: $@ = oracle arguments
  # Side effects: sets ORACLE_OUT and ORACLE_STATUS.
  ORACLE_STATUS=0
  ORACLE_OUT="$("$@" 2>&1)" || ORACLE_STATUS=$?
}

expect_pass() {
  # Description: assert the oracle returned a PASS verdict.
  # Args: $1 = case name, $2.. = oracle arguments
  local name="$1"
  shift
  run_oracle "$@"
  [[ "$ORACLE_STATUS" -eq 0 ]] \
    || fail "$name expected verdict PASS, got exit $ORACLE_STATUS: $ORACLE_OUT"
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "  ok  $name -> PASS"
}

expect_not_pass() {
  # Description: assert the oracle refused, with a specific marker.
  # Args: $1 = case name, $2 = expected marker, $3.. = oracle arguments
  local name="$1" marker="$2"
  shift 2
  run_oracle "$@"
  [[ "$ORACLE_STATUS" -ne 0 ]] || fail "$name was judged PASS but must not be: $ORACLE_OUT"
  grep -Fq "$marker" <<<"$ORACLE_OUT" \
    || fail "$name did not emit $marker; got: $ORACLE_OUT"
  echo "  ok  $name -> non-PASS ($marker)"
}

SHIM_BIN="$WORK/shim-bin"
mkdir -p "$SHIM_BIN"

# --- Positive case: a command that genuinely measures something -------------
# Without this case the whole file could be satisfied by a runner that always
# answers FAIL, which is the exact failure mode the fence calls out.
cat > "$WORK/real-suite.sh" <<'EOF'
#!/usr/bin/env bash
echo "ran 12 tests, 12 passed"
echo "coverage: 87%"
exit 0
EOF
chmod +x "$WORK/real-suite.sh"

expect_pass "positive: real suite with positive evidence" \
  bash "$ORACLE" --command "bash '$WORK/real-suite.sh'" \
    --expect-evidence '[0-9]+ passed' \
    --forbid-evidence 'coverage: 0%' \
    --evidence-out "$WORK/positive-evidence.json"

python3 - "$WORK/positive-evidence.json" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["verdict"] == "PASS", data["verdict"]
assert data["command_exit_code"] == 0
assert "12 passed" in data["stdout"], "stdout was not preserved in the evidence record"
PY

# --- Injection (a): rg replaced by a shim that ignores --pcre2 ---------------
# A negative assertion (`! rg --pcre2 …`) inverts into exit 0 when the shim
# cannot honour the flag, so the unhardened form silently passes.
cat > "$SHIM_BIN/rg" <<'EOF'
#!/usr/bin/env bash
# BSD-grep-shaped shim: does not understand --pcre2, never matches, exits 1.
for arg in "$@"; do
  if [[ "$arg" == "--pcre2" ]]; then
    echo "rg: unrecognized option '--pcre2'" >&2
    exit 2
  fi
done
exit 1
EOF
chmod +x "$SHIM_BIN/rg"

# Prove the injection really does flip an unhardened verdict; otherwise the
# hardened result below would prove nothing.
unhardened_status=0
PATH="$SHIM_BIN:$PATH" bash -c '! rg --pcre2 "forbidden" /dev/null' >/dev/null 2>&1 \
  || unhardened_status=$?
[[ "$unhardened_status" -eq 0 ]] \
  || fail "fixture (a) did not reproduce the inversion: unhardened negation exited $unhardened_status"

expect_not_pass "injection (a): rg shim without --pcre2" \
  POLARIS_ORACLE_TOOL_CAPABILITY_FAILED:rg \
  env "PATH=$SHIM_BIN:$PATH" bash "$ORACLE" \
    --command '! rg --pcre2 "forbidden" /dev/null' \
    --require-tool 'rg:--pcre2 --version'

# --- Injection (b): tests silently skipped, coverage 0, exit 0 --------------
cat > "$WORK/skipping-suite.sh" <<'EOF'
#!/usr/bin/env bash
echo "no test files matched; skipping"
echo "coverage: 0%"
exit 0
EOF
chmod +x "$WORK/skipping-suite.sh"

expect_not_pass "injection (b): silent skip with coverage 0" \
  POLARIS_ORACLE_NO_POSITIVE_EVIDENCE \
  bash "$ORACLE" --command "bash '$WORK/skipping-suite.sh'" \
    --expect-evidence '[0-9]+ passed'

# The forbidden-pattern lane catches the same lie from the other side.
expect_not_pass "injection (b'): coverage 0 named as a non-measurement" \
  POLARIS_ORACLE_FORBIDDEN_EVIDENCE \
  bash "$ORACLE" --command "bash '$WORK/skipping-suite.sh'" \
    --forbid-evidence 'coverage: 0%'

# --- Injection (c): curl error swallowed into a generic timeout -------------
cat > "$SHIM_BIN/curl" <<'EOF'
#!/usr/bin/env bash
# Swallows the real failure (DNS/TLS) and reports a generic timeout, exit 0.
echo "Operation timed out"
exit 0
EOF
chmod +x "$SHIM_BIN/curl"

# `curl` is declared so the lying binary is the one actually exercised; without
# the declaration the runner would resolve the system curl and this fixture
# would test nothing.
expect_not_pass "injection (c): curl error swallowed into a timeout" \
  POLARIS_ORACLE_NO_POSITIVE_EVIDENCE \
  env "PATH=$SHIM_BIN:$PATH" bash "$ORACLE" \
    --command 'curl -sS -D - -o /dev/null https://example.invalid/' \
    --require-tool 'curl' \
    --expect-evidence 'HTTP/[0-9.]+ 200'

# --- Fail-closed: an unresolvable required tool names itself ----------------
expect_not_pass "unresolvable tool fails closed by name" \
  POLARIS_ORACLE_TOOL_UNRESOLVED:polaris-tool-that-does-not-exist \
  bash "$ORACLE" --command 'true' \
    --require-tool 'polaris-tool-that-does-not-exist:--version'

# --- No silent PATH fallback -------------------------------------------------
# The inherited PATH must not survive into the command: a tool reachable only
# through the caller's PATH, and not declared, is not available.
cat > "$SHIM_BIN/polaris-undeclared-tool" <<'EOF'
#!/usr/bin/env bash
echo "undeclared tool ran"
exit 0
EOF
chmod +x "$SHIM_BIN/polaris-undeclared-tool"

run_oracle env "PATH=$SHIM_BIN:$PATH" bash "$ORACLE" \
  --command 'polaris-undeclared-tool' \
  --expect-evidence 'undeclared tool ran'
[[ "$ORACLE_STATUS" -ne 0 ]] \
  || fail "the inherited PATH leaked into the command: an undeclared tool was reachable"
echo "  ok  inherited PATH does not leak into the command"

# --- stderr and exit code are preserved, not remapped -----------------------
cat > "$WORK/loud-failure.sh" <<'EOF'
#!/usr/bin/env bash
echo "diagnostic detail on stderr" >&2
exit 37
EOF
chmod +x "$WORK/loud-failure.sh"

run_oracle bash "$ORACLE" --command "bash '$WORK/loud-failure.sh'" \
  --evidence-out "$WORK/failure-evidence.json"
[[ "$ORACLE_STATUS" -eq 1 ]] \
  || fail "a failing command should report runner exit 1, got $ORACLE_STATUS"
grep -Fq "diagnostic detail on stderr" <<<"$ORACLE_OUT" \
  || fail "stderr was swallowed instead of replayed"
python3 - "$WORK/failure-evidence.json" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["command_exit_code"] == 37, f"exit code was remapped to {data['command_exit_code']}"
assert data["verdict"] == "FAIL", data["verdict"]
assert "diagnostic detail on stderr" in data["stderr"], "stderr missing from the evidence record"
PY
echo "  ok  stderr and exit code survive the runner"

# DP-482: the record has to name the tree the command actually ran in. Reading HEAD from
# this process's cwd instead of --cwd names a commit the command never saw, and the record
# still looks well-formed — so the delivery gate compares evidence against the wrong tree.
measured_repo="$WORK/measured-tree"
git init -q "$measured_repo"
git -C "$measured_repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "the measured tree"
measured_head="$(git -C "$measured_repo" rev-parse HEAD)"
here_head="$(git rev-parse HEAD 2>/dev/null || true)"
[[ "$measured_head" != "$here_head" ]] \
  || fail "fixture repo shares HEAD with the caller; this case would pass either way"
bash "$ORACLE" --command 'echo MEASURED' --expect-evidence MEASURED \
  --cwd "$measured_repo" --evidence-out "$WORK/cwd-evidence.json" >/dev/null 2>&1 \
  || fail "measuring inside --cwd should still pass"
python3 - "$WORK/cwd-evidence.json" "$measured_head" <<'PY_CWD'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["head_sha"] == sys.argv[2], (
    f"evidence named {data['head_sha']}, but the command ran in the tree at {sys.argv[2]}")
PY_CWD
echo "  ok  the record names the tree the command ran in, not the caller's cwd"

[[ "$PASS_COUNT" -ge 1 ]] \
  || fail "no positive case ran; a suite of negatives alone cannot prove the verdict is two-way"

echo "PASS: run-hardened-oracle-selftest.sh"
