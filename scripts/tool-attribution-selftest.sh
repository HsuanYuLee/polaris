#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PYTHON_BIN="${PYTHON_BIN:-$(command -v python3)}"
# shellcheck source=lib/tool-attribution.sh
source "$ROOT_DIR/scripts/lib/tool-attribution.sh"

assert_field() {
  local tool="$1"
  local field="$2"
  local expected="$3"
  local json actual
  json="$(polaris_classify_tool "$tool")"
  actual="$("$PYTHON_BIN" - "$json" "$field" <<'PY'
import json
import sys
value = json.loads(sys.argv[1]).get(sys.argv[2])
if isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
)"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL $tool $field expected=$expected actual=$actual json=$json" >&2
    exit 1
  fi
}

assert_field node owner framework
assert_field node install_authority root_mise
assert_field node goes_to_mise true

assert_field gh owner delivery
assert_field gh runtime_profile delivery
assert_field gh goes_to_mise false

assert_field mockoon-cli owner project
assert_field mockoon-cli install_authority project_package_manager
assert_field mockoon-cli runtime_profile runtime

assert_field gt-567-cli owner ticket
assert_field gt-567-cli install_authority manual_user_action
assert_field gt-567-cli runtime_profile ticket
assert_field gt-567-cli goes_to_mise false

assert_field custom-local-tool owner user
assert_field custom-local-tool install_authority manual_user_action
assert_field custom-local-tool goes_to_mise false

echo "tool-attribution-selftest PASS"
