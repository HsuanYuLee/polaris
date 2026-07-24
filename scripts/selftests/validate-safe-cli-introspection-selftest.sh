#!/usr/bin/env bash
# Purpose: 驗證 safe CLI introspection exact-prefix、隔離執行與各種 escape 負向案例。
# Inputs: temporary good/bad CLI fixtures。
# Outputs: literal help 放行，prefix side effects 與 redirection 皆 fail-closed 時輸出 PASS。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-safe-cli-introspection.sh"
SAFE_MODULE="$ROOT_DIR/scripts/lib/validate_safe_cli_introspection_1.py"
TMP_ROOT="$(mktemp -d)"
trap 'chmod -R u+rwX "$TMP_ROOT" 2>/dev/null || true; rm -rf "$TMP_ROOT"' EXIT
FIXTURE_REPO="$TMP_ROOT/repo"
mkdir -p "$FIXTURE_REPO/scripts"

cat > "$FIXTURE_REPO/scripts/good-cli.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
# POLARIS_SAFE_CLI_INTROSPECTION_BEGIN
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  command printf '%s\n' 'Usage: good-cli.sh command > file'
  exit 0
fi
# POLARIS_SAFE_CLI_INTROSPECTION_END
bash "$(dirname "$0")/side-effect.sh"
SH

write_bad_prefix_fixture() {
  local name="$1"
  local unsafe_line="$2"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' 'set -euo pipefail'
    printf '%s\n' "$unsafe_line"
    cat <<'SH'
# POLARIS_SAFE_CLI_INTROSPECTION_BEGIN
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  command printf '%s\n' 'Usage: unsafe fixture'
  exit 0
fi
# POLARIS_SAFE_CLI_INTROSPECTION_END
SH
  } > "$FIXTURE_REPO/scripts/$name"
}

write_bad_prefix_fixture bad-repo-cli.sh 'bash "$(dirname "$0")/side-effect.sh"'
write_bad_prefix_fixture bad-absolute-cli.sh 'FLAG=1 /usr/bin/git ls-remote https://example.invalid/polaris.git'
write_bad_prefix_fixture bad-trap-cli.sh 'builtin trap - DEBUG'
write_bad_prefix_fixture bad-shell-cli.sh "/bin/sh -c '/usr/bin/git ls-remote https://example.invalid/polaris.git'"
write_bad_prefix_fixture bad-cwd-cli.sh "printf 'leak\\n' > cwd-relative-leak.txt"

cat > "$FIXTURE_REPO/scripts/bad-heredoc-cli.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
# POLARIS_SAFE_CLI_INTROSPECTION_BEGIN
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF' > leaked.txt
Usage: heredoc escape
EOF
  exit 0
fi
# POLARIS_SAFE_CLI_INTROSPECTION_END
SH

# Source snapshots must cover the git-owned source surface without reading
# ignored runtime state.  An unreadable ignored file proves the validator does
# not regress to recursively hashing node_modules/.polaris/worktree-style data.
printf '%s\n' 'runtime-cache/' > "$FIXTURE_REPO/.gitignore"
mkdir -p "$FIXTURE_REPO/runtime-cache"
printf '%s\n' 'local ignored state' > "$FIXTURE_REPO/runtime-cache/unreadable"
chmod 000 "$FIXTURE_REPO/runtime-cache/unreadable"
git -C "$FIXTURE_REPO" init -q
git -C "$FIXTURE_REPO" add .gitignore scripts

bash "$VALIDATOR" \
  --repo "$FIXTURE_REPO" \
  --script scripts/good-cli.sh \
  --guard-repo-command scripts/side-effect.sh \
  --expect 'Usage: good-cli.sh command > file' >/dev/null
chmod 600 "$FIXTURE_REPO/runtime-cache/unreadable"

expect_unsafe_prefix() {
  local script="$1"
  local output="$TMP_ROOT/${script##*/}.out"
  if bash "$VALIDATOR" \
    --repo "$FIXTURE_REPO" \
    --script "scripts/$script" \
    --guard-repo-command scripts/side-effect.sh >"$output" 2>&1; then
    echo "FAIL: validator must reject unsafe prefix: $script" >&2
    exit 1
  fi
  grep -q 'POLARIS_SAFE_CLI_INTROSPECTION_UNSAFE_PREFIX' "$output" || {
    echo "FAIL: unsafe prefix must emit canonical marker: $script" >&2
    cat "$output" >&2
    exit 1
  }
}

for script in \
  bad-repo-cli.sh \
  bad-absolute-cli.sh \
  bad-trap-cli.sh \
  bad-shell-cli.sh \
  bad-cwd-cli.sh \
  bad-heredoc-cli.sh; do
  expect_unsafe_prefix "$script"
done

[[ ! -e "$FIXTURE_REPO/cwd-relative-leak.txt" ]] || {
  echo "FAIL: rejected prefix must never execute a cwd-relative source write" >&2
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

python3 - "$SAFE_MODULE" "$FIXTURE_REPO" \
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

echo "validate-safe-cli-introspection-selftest: PASS"
