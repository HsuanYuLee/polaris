#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PYTHON_BIN="${PYTHON_BIN:-$(command -v python3)}"
# shellcheck source=lib/tool-resolution.sh
source "$ROOT_DIR/scripts/lib/tool-resolution.sh"

TMP_DIR="$(mktemp -d -t polaris-tool-resolution-selftest-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

assert_contains() {
  local file="$1"
  local pattern="$2"
  if ! grep -q "$pattern" "$file"; then
    echo "FAIL expected '$pattern' in $file" >&2
    sed 's/^/  /' "$file" >&2
    exit 1
  fi
}

NO_TOOL_PATH="$TMP_DIR/no-tools"
FAKE_PATH="$TMP_DIR/fake-bin"
mkdir -p "$NO_TOOL_PATH" "$FAKE_PATH"
BASE_PATH="$NO_TOOL_PATH:/usr/bin:/bin"

if PATH="$BASE_PATH" POLARIS_WORKSPACE_ROOT="$ROOT_DIR" polaris_require_mise_tool node >"$TMP_DIR/missing-mise.out" 2>"$TMP_DIR/missing-mise.err"; then
  echo "FAIL expected missing mise to fail" >&2
  exit 1
fi
assert_contains "$TMP_DIR/missing-mise.err" "POLARIS_TOOL_MISSING"
assert_contains "$TMP_DIR/missing-mise.err" "tool=mise"

cat > "$FAKE_PATH/mise" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "exec" && "\$2" == "--" && "\$3" == "bash" && "\$4" == "-lc" ]]; then
  case "\$5" in
    *"command -v node"*) echo "$FAKE_PATH/node"; exit 0 ;;
    *"command -v pnpm"*) echo "$FAKE_PATH/pnpm"; exit 0 ;;
  esac
fi
if [[ "\$1" == "exec" && "\$2" == "--" ]]; then
  shift 2
  exec "\$@"
fi
exit 1
EOF
cat > "$FAKE_PATH/node" <<'EOF'
#!/usr/bin/env bash
echo v20.0.0
EOF
cat > "$FAKE_PATH/pnpm" <<'EOF'
#!/usr/bin/env bash
echo 9.0.0
EOF
chmod +x "$FAKE_PATH/mise" "$FAKE_PATH/node" "$FAKE_PATH/pnpm"

node_path="$(PATH="$FAKE_PATH:$BASE_PATH" POLARIS_WORKSPACE_ROOT="$ROOT_DIR" polaris_require_mise_tool node)"
if [[ "$node_path" != "$FAKE_PATH/node" ]]; then
  echo "FAIL expected mise-managed node path, got $node_path" >&2
  exit 1
fi

runtime_out="$(PATH="$FAKE_PATH:$BASE_PATH" POLARIS_WORKSPACE_ROOT="$ROOT_DIR" polaris_with_runtime_tools node --version)"
if [[ "$runtime_out" != "v20.0.0" ]]; then
  echo "FAIL expected runtime wrapper to execute fake node, got $runtime_out" >&2
  exit 1
fi

if PATH="$BASE_PATH" polaris_require_delivery_tool gh >"$TMP_DIR/missing-gh.out" 2>"$TMP_DIR/missing-gh.err"; then
  echo "FAIL expected missing gh to fail" >&2
  exit 1
fi
assert_contains "$TMP_DIR/missing-gh.err" "POLARIS_TOOL_MISSING"
assert_contains "$TMP_DIR/missing-gh.err" "tool=gh"

cat > "$FAKE_PATH/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  exit 1
fi
exit 0
EOF
chmod +x "$FAKE_PATH/gh"
if PATH="$FAKE_PATH:$BASE_PATH" polaris_require_delivery_tool gh >"$TMP_DIR/auth-gh.out" 2>"$TMP_DIR/auth-gh.err"; then
  echo "FAIL expected gh auth failure to fail" >&2
  exit 1
fi
assert_contains "$TMP_DIR/auth-gh.err" "POLARIS_TOOL_AUTH_FAILED"
assert_contains "$TMP_DIR/auth-gh.err" "tool=gh"

cat > "$FAKE_PATH/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  exit 0
fi
exit 0
EOF
chmod +x "$FAKE_PATH/gh"
gh_path="$(PATH="$FAKE_PATH:$BASE_PATH" polaris_require_delivery_tool gh)"
if [[ "$gh_path" != "$FAKE_PATH/gh" ]]; then
  echo "FAIL expected fake gh path, got $gh_path" >&2
  exit 1
fi

python_bin="$(polaris_require_python)"
if [[ -z "$PYTHON_BIN" || "$python_bin" != "$PYTHON_BIN" ]]; then
  echo "FAIL expected polaris_require_python to export PYTHON_BIN" >&2
  exit 1
fi

echo "tool-resolution-selftest PASS"
