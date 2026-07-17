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

"$PYTHON_BIN" - "$REPO/$TARGET" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines()
begin_marker = "# POLARIS_SAFE_CLI_INTROSPECTION_BEGIN"
end_marker = "# POLARIS_SAFE_CLI_INTROSPECTION_END"

def fail(detail: str) -> None:
    print(f"POLARIS_SAFE_CLI_INTROSPECTION_UNSAFE_PREFIX:{path.name}:{detail}", file=sys.stderr)
    raise SystemExit(2)

if lines.count(begin_marker) != 1 or lines.count(end_marker) != 1:
    fail("canonical markers must each appear exactly once")
begin = lines.index(begin_marker)
end = lines.index(end_marker)
if end <= begin:
    fail("end marker must follow begin marker")
if not lines or lines[0] != "#!/usr/bin/env bash":
    fail("first line must be the canonical bash shebang")

executable_prefix = [
    line.strip()
    for line in lines[1:begin]
    if line.strip() and not line.lstrip().startswith("#")
]
if executable_prefix != ["set -euo pipefail"]:
    fail("only set -euo pipefail may execute before the canonical help block")

block = lines[begin + 1 : end]
expected_if = 'if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then'
if len(block) < 4 or block[0] != expected_if or block[-2:] != ["  exit 0", "fi"]:
    fail("help block must use the canonical condition and terminal exit 0")
printf_lines = block[1:-2]
if not printf_lines:
    fail("help block must emit at least one literal line")
literal_printf = re.compile(r"  command printf '%s\\n' '[^']*'")
for line in printf_lines:
    if not literal_printf.fullmatch(line):
        fail(f"non-literal or side-effecting help statement: {line}")
PY

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
FIXTURE="$TMP_ROOT/fixture"
OUTPUT="$TMP_ROOT/output.txt"
GUARD_BIN="$TMP_ROOT/guard-bin"
mkdir -p "$FIXTURE/home" "$FIXTURE/tmp" "$GUARD_BIN"

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
  "$PYTHON_BIN" - "$root" <<'PY'
import hashlib
import os
import subprocess
import stat
import sys
from pathlib import Path

root = Path(sys.argv[1])
digest = hashlib.sha256()

# A framework source snapshot is the git-owned source surface: tracked files
# plus non-ignored untracked files.  Local runtime state (for example
# node_modules, .polaris evidence, and linked worktrees) is deliberately outside
# that surface.  Reading every byte below the checkout made a single --help
# fixture scan unrelated ignored state twice and turned release re-verification
# into an unbounded workspace-size operation.
try:
    listed = subprocess.run(
        [
            "git",
            "-C",
            str(root),
            "ls-files",
            "-z",
            "--cached",
            "--others",
            "--exclude-standard",
        ],
        check=True,
        capture_output=True,
    ).stdout
    paths = [root / raw.decode("utf-8", "surrogateescape") for raw in listed.split(b"\0") if raw]
except (FileNotFoundError, subprocess.CalledProcessError):
    # Hermetic non-git fixtures retain the original complete-tree behavior.
    paths = [path for path in root.rglob("*") if ".git" not in path.relative_to(root).parts]

for path in sorted(paths, key=lambda item: item.as_posix()):
    if not path.exists() and not path.is_symlink():
        # A path may disappear between enumeration and hashing.  Encode the
        # disappearance so the before/after digest still differs deterministically.
        digest.update(f"{path.relative_to(root).as_posix()}\0missing\0".encode())
        continue
    relative = path.relative_to(root).as_posix()
    mode = stat.S_IMODE(path.lstat().st_mode)
    digest.update(f"{relative}\0{mode:o}\0".encode())
    if path.is_symlink():
        digest.update(os.readlink(path).encode())
    elif path.is_file():
        digest.update(path.read_bytes())
    digest.update(b"\0")
print(digest.hexdigest())
PY
}

fixture_before="$(snapshot_tree "$FIXTURE")"
source_before="$(snapshot_tree "$REPO")"
set +e
(
  cd "$FIXTURE"
    env -i \
    POLARIS_INTROSPECTION_SENTINEL="$SENTINEL" \
    PATH="$GUARD_BIN:/usr/bin:/bin" \
    HOME="$FIXTURE/home" \
    TMPDIR="$FIXTURE/tmp" \
    "$BASH_BIN" "$FIXTURE/$TARGET" "$INTROSPECTION_ARG"
) >"$OUTPUT" 2>&1
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
  echo "POLARIS_SAFE_CLI_INTROSPECTION_COMMAND_FAILED:$TARGET:$INTROSPECTION_ARG:exit=$rc" >&2
  cat "$OUTPUT" >&2
  exit 2
fi
if ! grep -Fq -- "$EXPECT" "$OUTPUT"; then
  echo "POLARIS_SAFE_CLI_INTROSPECTION_OUTPUT_MISMATCH:$TARGET:$INTROSPECTION_ARG" >&2
  cat "$OUTPUT" >&2
  exit 2
fi

echo "PASS: safe CLI introspection ($TARGET $INTROSPECTION_ARG)"
