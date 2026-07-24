#!/usr/bin/env bash
# Purpose: 驗證 CLI introspection 在任何 repo command、host tool 或檔案副作用前 fast-exit。
# Inputs: repo、target script、introspection argument、fixture dependency 與 guarded repo commands。
# Outputs: side-effect-free 時輸出 PASS；command failure、unexpected output 或 tree drift 時 exit 2。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/tool-resolution.sh
source "$ROOT_DIR/scripts/lib/tool-resolution.sh"

REPO="$ROOT_DIR"
TARGET=""
INTROSPECTION_ARG="--help"
EXPECT="Usage:"
COPY_DEPENDENCIES=()
GUARD_REPO_COMMANDS=()

usage() {
  cat >&2 <<'USAGE'
Usage:
  validate-safe-cli-introspection.sh --script <repo-relative-path>
    [--repo <path>] [--arg <introspection-arg>] [--expect <text>]
    [--copy-dependency <repo-relative-path>]...
    [--guard-repo-command <repo-relative-path>]...

Requires an exact safe prefix before executing the target, then runs it in an
isolated fixture with a dirty sentinel. Guarded repo commands and host tools
record an invocation marker as defense-in-depth.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --script) TARGET="${2:-}"; shift 2 ;;
    --arg) INTROSPECTION_ARG="${2:-}"; shift 2 ;;
    --expect) EXPECT="${2:-}"; shift 2 ;;
    --copy-dependency) COPY_DEPENDENCIES+=("${2:-}"); shift 2 ;;
    --guard-repo-command) GUARD_REPO_COMMANDS+=("${2:-}"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "POLARIS_SAFE_CLI_INTROSPECTION_INVALID_ARGUMENT:$1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$TARGET" ]] || { echo "POLARIS_SAFE_CLI_INTROSPECTION_MISSING_SCRIPT" >&2; exit 2; }
[[ "$INTROSPECTION_ARG" == "--help" || "$INTROSPECTION_ARG" == "-h" ]] || {
  echo "POLARIS_SAFE_CLI_INTROSPECTION_UNSUPPORTED_ARGUMENT:$INTROSPECTION_ARG" >&2
  exit 2
}
[[ -d "$REPO" ]] || { echo "POLARIS_SAFE_CLI_INTROSPECTION_REPO_NOT_FOUND:$REPO" >&2; exit 2; }
REPO="$(cd "$REPO" && pwd)"

validate_relative_file() {
  local path="$1"
  [[ -n "$path" && "$path" != /* && "$path" != *".."* ]] || {
    echo "POLARIS_SAFE_CLI_INTROSPECTION_INVALID_PATH:$path" >&2
    exit 2
  }
  [[ -f "$REPO/$path" ]] || {
    echo "POLARIS_SAFE_CLI_INTROSPECTION_PATH_NOT_FOUND:$path" >&2
    exit 2
  }
}

validate_relative_file "$TARGET"
for path in "${COPY_DEPENDENCIES[@]+"${COPY_DEPENDENCIES[@]}"}"; do
  validate_relative_file "$path"
done
for path in "${GUARD_REPO_COMMANDS[@]+"${GUARD_REPO_COMMANDS[@]}"}"; do
  [[ -n "$path" && "$path" != /* && "$path" != *".."* ]] || {
    echo "POLARIS_SAFE_CLI_INTROSPECTION_INVALID_GUARD_PATH:$path" >&2
    exit 2
  }
done

PYTHON_BIN="$(polaris_require_python)"
BASH_BIN="$(command -v bash)"

"$PYTHON_BIN" "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_safe_cli_introspection_1.py" "$REPO/$TARGET"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
FIXTURE="$TMP_ROOT/fixture"
OUTPUT="$TMP_ROOT/output.txt"
RUNNER_ERROR="$TMP_ROOT/runner-error.txt"
GUARD_BIN="$TMP_ROOT/guard-bin"
mkdir -p "$FIXTURE/home" "$FIXTURE/tmp" "$GUARD_BIN"
: >"$OUTPUT"

copy_fixture_file() {
  local path="$1"
  mkdir -p "$FIXTURE/$(dirname "$path")"
  cp "$REPO/$path" "$FIXTURE/$path"
}

copy_fixture_file "$TARGET"
for path in "${COPY_DEPENDENCIES[@]+"${COPY_DEPENDENCIES[@]}"}"; do
  copy_fixture_file "$path"
done

printf 'dirty sentinel must remain byte-identical\n' > "$FIXTURE/.dirty-sentinel"
SENTINEL="$FIXTURE/.introspection-side-effect"

write_guard() {
  local destination="$1"
  mkdir -p "$(dirname "$destination")"
  cat > "$destination" <<'GUARD'
#!/usr/bin/env bash
set -euo pipefail
printf 'invoked:%s\n' "${0##*/}" >> "${POLARIS_INTROSPECTION_SENTINEL:?}"
exit 97
GUARD
  chmod +x "$destination"
}

for path in "${GUARD_REPO_COMMANDS[@]+"${GUARD_REPO_COMMANDS[@]}"}"; do
  write_guard "$FIXTURE/$path"
done
for tool in git gh mise curl wget ssh scp nc node pnpm python python3 ruby perl; do
  write_guard "$GUARD_BIN/$tool"
done

snapshot_tree() {
  local root="$1"
  "$PYTHON_BIN" "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_safe_cli_introspection_2.py" "$root"
}

fixture_before="$(snapshot_tree "$FIXTURE")"
source_before="$(snapshot_tree "$REPO")"
set +e
"$PYTHON_BIN" "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_safe_cli_introspection_1.py" \
  --run-bounded \
  --cwd "$FIXTURE" \
  --timeout 5 \
  --output "$OUTPUT" \
  --clear-env \
  --env "POLARIS_INTROSPECTION_SENTINEL=$SENTINEL" \
  --env "PATH=$GUARD_BIN:/usr/bin:/bin" \
  --env "HOME=$FIXTURE/home" \
  --env "TMPDIR=$FIXTURE/tmp" \
  -- "$BASH_BIN" "$FIXTURE/$TARGET" "$INTROSPECTION_ARG" \
  2>"$RUNNER_ERROR"
rc=$?
set -e
fixture_after="$(snapshot_tree "$FIXTURE")"
source_after="$(snapshot_tree "$REPO")"

if [[ "$source_before" != "$source_after" ]]; then
  echo "POLARIS_SAFE_CLI_INTROSPECTION_SOURCE_REPO_MUTATION:$TARGET:$INTROSPECTION_ARG" >&2
  exit 2
fi
if [[ "$fixture_before" != "$fixture_after" ]]; then
  echo "POLARIS_SAFE_CLI_INTROSPECTION_SIDE_EFFECT:$TARGET:$INTROSPECTION_ARG" >&2
  [[ -f "$SENTINEL" ]] && cat "$SENTINEL" >&2
  exit 2
fi
if [[ "$rc" -ne 0 ]]; then
  if [[ "$rc" -eq 124 ]]; then
    echo "POLARIS_SAFE_CLI_INTROSPECTION_TIMEOUT:$TARGET:$INTROSPECTION_ARG" >&2
  fi
  echo "POLARIS_SAFE_CLI_INTROSPECTION_COMMAND_FAILED:$TARGET:$INTROSPECTION_ARG:exit=$rc" >&2
  cat "$RUNNER_ERROR" >&2
  cat "$OUTPUT" >&2
  exit 2
fi
if ! grep -Fq -- "$EXPECT" "$OUTPUT"; then
  echo "POLARIS_SAFE_CLI_INTROSPECTION_OUTPUT_MISMATCH:$TARGET:$INTROSPECTION_ARG" >&2
  cat "$OUTPUT" >&2
  exit 2
fi

echo "PASS: safe CLI introspection ($TARGET $INTROSPECTION_ARG)"
