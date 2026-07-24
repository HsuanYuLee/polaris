#!/usr/bin/env bash
# Purpose: 驗證 Verify Command script 分類、safe CLI flag discovery 與 timeout process-group 收斂。
# Inputs: temporary selftest/non-CLI/safe-CLI/forked-descendant fixtures。
# Outputs: 所有分類與 process containment 斷言成立時輸出 PASS，否則 fail-closed。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATE_MODULE="$ROOT_DIR/scripts/lib/validate_task_md.py"
SAFE_MODULE="$ROOT_DIR/scripts/lib/validate_safe_cli_introspection_1.py"
PYTHON_BIN="$(command -v python3 || true)"
[[ -n "$PYTHON_BIN" ]] || {
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
}

TMP_ROOT="$(mktemp -d -t verify-command-safe-introspection.XXXXXX)"
trap 'rm -rf "$TMP_ROOT"' EXIT
FIXTURE_REPO="$TMP_ROOT/repo"
mkdir -p "$FIXTURE_REPO/scripts/selftests" "$FIXTURE_REPO/scripts"

write_task_fixture() {
  local target="$1"
  local script_path="$2"
  cat >"$target" <<EOF
## 改動範圍

| 檔案 | 動作 | 變更摘要 |
|------|------|----------|
| \`$script_path\` | modify | fixture |

## Allowed Files

- \`$script_path\`
EOF
}

cat >"$FIXTURE_REPO/scripts/selftests/no-help-selftest.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'spawned\n' > .selftest-was-spawned
SH
write_task_fixture "$TMP_ROOT/selftest-task.md" "scripts/selftests/no-help-selftest.sh"

(
  cd "$FIXTURE_REPO"
  "$PYTHON_BIN" "$VALIDATE_MODULE" smoke "$TMP_ROOT/selftest-task.md" \
    "bash scripts/selftests/no-help-selftest.sh" verify_command
)
[[ ! -e "$FIXTURE_REPO/.selftest-was-spawned" ]] || {
  echo "FAIL: test-classified Verify Command script was dynamically spawned" >&2
  exit 1
}

cat >"$FIXTURE_REPO/scripts/non-cli.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'spawned\n' > .non-cli-was-spawned
printf '%s\n' '--danger'
SH
write_task_fixture "$TMP_ROOT/non-cli-task.md" "scripts/non-cli.sh"

if (
  cd "$FIXTURE_REPO"
  "$PYTHON_BIN" "$VALIDATE_MODULE" smoke "$TMP_ROOT/non-cli-task.md" \
    "bash scripts/non-cli.sh --danger" verify_command
) >"$TMP_ROOT/non-cli.out" 2>&1; then
  echo "FAIL: unsafe non-CLI script with a flag must fail closed" >&2
  exit 1
fi
grep -q 'POLARIS_VERIFY_COMMAND_UNSAFE_INTROSPECTION' "$TMP_ROOT/non-cli.out" || {
  echo "FAIL: unsafe non-CLI diagnostic missing" >&2
  cat "$TMP_ROOT/non-cli.out" >&2
  exit 1
}
[[ ! -e "$FIXTURE_REPO/.non-cli-was-spawned" ]] || {
  echo "FAIL: unsafe non-CLI script was dynamically spawned" >&2
  exit 1
}

(
  cd "$FIXTURE_REPO"
  "$PYTHON_BIN" "$VALIDATE_MODULE" smoke "$TMP_ROOT/non-cli-task.md" \
    "bash scripts/non-cli.sh --danger" env_bootstrap
)
[[ ! -e "$FIXTURE_REPO/.non-cli-was-spawned" ]] || {
  echo "FAIL: env bootstrap command-shape validation spawned a script" >&2
  exit 1
}

cat >"$FIXTURE_REPO/scripts/safe-cli.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
# POLARIS_SAFE_CLI_INTROSPECTION_BEGIN
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  command printf '%s\n' 'Usage: safe-cli.sh [--known]'
  exit 0
fi
# POLARIS_SAFE_CLI_INTROSPECTION_END
exit 0
SH
write_task_fixture "$TMP_ROOT/safe-cli-task.md" "scripts/safe-cli.sh"

(
  cd "$FIXTURE_REPO"
  "$PYTHON_BIN" "$VALIDATE_MODULE" smoke "$TMP_ROOT/safe-cli-task.md" \
    "bash scripts/safe-cli.sh --known" verify_command
)
if (
  cd "$FIXTURE_REPO"
  "$PYTHON_BIN" "$VALIDATE_MODULE" smoke "$TMP_ROOT/safe-cli-task.md" \
    "bash scripts/safe-cli.sh --unknown" verify_command
) >"$TMP_ROOT/unsupported.out" 2>&1; then
  echo "FAIL: safe CLI unsupported flag must remain rejected" >&2
  exit 1
fi
grep -q 'Verify Command uses unsupported flag --unknown' "$TMP_ROOT/unsupported.out" || {
  echo "FAIL: DP-065 unsupported flag diagnostic regressed" >&2
  cat "$TMP_ROOT/unsupported.out" >&2
  exit 1
}

if (
  cd "$FIXTURE_REPO"
  "$PYTHON_BIN" "$VALIDATE_MODULE" smoke "$TMP_ROOT/safe-cli-task.md" \
    "bash scripts/selftests/../safe-cli.sh --unknown" verify_command
) >"$TMP_ROOT/traversal-unsupported.out" 2>&1; then
  echo "FAIL: lexical selftest traversal must not bypass safe CLI flag validation" >&2
  exit 1
fi
grep -q 'Verify Command uses unsupported flag --unknown' "$TMP_ROOT/traversal-unsupported.out" || {
  echo "FAIL: canonicalized traversal lost DP-065 unsupported diagnostic" >&2
  cat "$TMP_ROOT/traversal-unsupported.out" >&2
  exit 1
}

cp "$FIXTURE_REPO/scripts/safe-cli.sh" "$TMP_ROOT/outside-safe-cli.sh"
ln -s "$TMP_ROOT/outside-safe-cli.sh" "$FIXTURE_REPO/scripts/outside-safe-cli.sh"
write_task_fixture "$TMP_ROOT/outside-safe-cli-task.md" "scripts/outside-safe-cli.sh"
if (
  cd "$FIXTURE_REPO"
  "$PYTHON_BIN" "$VALIDATE_MODULE" smoke "$TMP_ROOT/outside-safe-cli-task.md" \
    "bash scripts/outside-safe-cli.sh --unknown" verify_command
) >"$TMP_ROOT/outside-script.out" 2>&1; then
  echo "FAIL: repo-local token resolving outside the repo must fail closed" >&2
  exit 1
fi
grep -q 'POLARIS_VERIFY_COMMAND_INVALID_SCRIPT_PATH' "$TMP_ROOT/outside-script.out" || {
  echo "FAIL: outside-repo script diagnostic missing" >&2
  cat "$TMP_ROOT/outside-script.out" >&2
  exit 1
}

cat >"$FIXTURE_REPO/scripts/safe-empty-cli.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
# POLARIS_SAFE_CLI_INTROSPECTION_BEGIN
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  command printf '%s\n' 'Usage: safe-empty-cli.sh'
  exit 0
fi
# POLARIS_SAFE_CLI_INTROSPECTION_END
exit 0
SH
write_task_fixture "$TMP_ROOT/safe-empty-cli-task.md" "scripts/safe-empty-cli.sh"

if (
  cd "$FIXTURE_REPO"
  "$PYTHON_BIN" "$VALIDATE_MODULE" smoke "$TMP_ROOT/safe-empty-cli-task.md" \
    "bash scripts/safe-empty-cli.sh --unknown" verify_command
) >"$TMP_ROOT/empty-unsupported.out" 2>&1; then
  echo "FAIL: safe CLI with an empty declared flag set must reject --unknown" >&2
  exit 1
fi
grep -q 'Verify Command uses unsupported flag --unknown' "$TMP_ROOT/empty-unsupported.out" || {
  echo "FAIL: empty safe CLI flag-set lost DP-065 unsupported diagnostic" >&2
  cat "$TMP_ROOT/empty-unsupported.out" >&2
  exit 1
}

cat >"$FIXTURE_REPO/scripts/fork-descendant.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
sentinel="${1:?sentinel path required}"
pids="${2:?pid path required}"
(
  trap '' TERM
  sleep 1
  printf 'leaked\n' >"$sentinel"
) &
child_pid=$!
printf '%s\n' "$child_pid" >"$pids"
wait "$child_pid"
SH

"$PYTHON_BIN" - "$SAFE_MODULE" "$FIXTURE_REPO" \
  "$FIXTURE_REPO/.descendant-leaked" "$FIXTURE_REPO/.descendant-pid" <<'PY'
import sys
from pathlib import Path

module_path, repo, sentinel, pids = sys.argv[1:5]
sys.path.insert(0, str(Path(module_path).parent))
import validate_safe_cli_introspection_1 as module

result = module.run_bounded_command(
    ["bash", "scripts/fork-descendant.sh", sentinel, pids],
    cwd=Path(repo),
    timeout_seconds=0.2,
)
if not result.timed_out:
    raise SystemExit("bounded runner did not report timeout")
PY

descendant_pid="$(cat "$FIXTURE_REPO/.descendant-pid")"
if kill -0 "$descendant_pid" 2>/dev/null; then
  kill -KILL "$descendant_pid" 2>/dev/null || true
  echo "FAIL: timed-out descendant process remains alive: $descendant_pid" >&2
  exit 1
fi
sleep 1.1
[[ ! -e "$FIXTURE_REPO/.descendant-leaked" ]] || {
  echo "FAIL: timed-out descendant survived long enough to write sentinel" >&2
  exit 1
}

bash "$ROOT_DIR/scripts/selftests/bug-source-task-identity-selftest.sh"

echo "PASS: Verify Command safe introspection selftest"
