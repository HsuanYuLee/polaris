#!/usr/bin/env bash
# Shared deterministic tool resolution helpers for Polaris scripts.

set -u

POLARIS_TOOL_RESOLUTION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tool-attribution.sh
source "$POLARIS_TOOL_RESOLUTION_DIR/tool-attribution.sh"

polaris_workspace_root() {
  if [[ -n "${POLARIS_WORKSPACE_ROOT:-}" && -d "$POLARIS_WORKSPACE_ROOT" ]]; then
    (cd "$POLARIS_WORKSPACE_ROOT" && pwd)
    return 0
  fi
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

polaris_find_mise() {
  if [[ -n "${POLARIS_MISE_BIN:-}" && -x "$POLARIS_MISE_BIN" ]]; then
    printf '%s\n' "$POLARIS_MISE_BIN"
    return 0
  fi
  command -v mise 2>/dev/null && return 0
  return 1
}

polaris_tool_attr_field() {
  local json="$1"
  local field="$2"
  "${PYTHON_BIN:-python3}" - "$json" "$field" <<'PY'
import json
import sys
print(json.loads(sys.argv[1]).get(sys.argv[2], ""))
PY
}

polaris_tool_missing() {
  local tool="$1"
  local attr_json="$2"
  local owner authority hint
  owner="$(polaris_tool_attr_field "$attr_json" owner)"
  authority="$(polaris_tool_attr_field "$attr_json" install_authority)"
  hint="$(polaris_tool_attr_field "$attr_json" handoff_hint)"
  echo "POLARIS_TOOL_MISSING tool=$tool owner=$owner install_authority=$authority hint=$hint" >&2
}

polaris_tool_auth_failed() {
  local tool="$1"
  local attr_json="$2"
  local owner authority hint
  owner="$(polaris_tool_attr_field "$attr_json" owner)"
  authority="$(polaris_tool_attr_field "$attr_json" install_authority)"
  hint="$(polaris_tool_attr_field "$attr_json" handoff_hint)"
  echo "POLARIS_TOOL_AUTH_FAILED tool=$tool owner=$owner install_authority=$authority hint=$hint" >&2
}

polaris_require_mise_tool() {
  local tool="${1:-}"
  local attr_json mise_bin root tool_path
  attr_json="$(polaris_classify_tool "${tool:-mise}")"
  if [[ -z "$tool" ]]; then
    polaris_tool_missing "<empty>" "$attr_json"
    return 2
  fi
  if ! mise_bin="$(polaris_find_mise)"; then
    polaris_tool_missing mise "$(polaris_classify_tool mise)"
    return 1
  fi
  root="$(polaris_workspace_root)"
  tool_path="$(cd "$root" && "$mise_bin" exec -- bash -lc "command -v $(printf '%q' "$tool")" 2>/dev/null || true)"
  if [[ -z "$tool_path" ]]; then
    polaris_tool_missing "$tool" "$attr_json"
    return 1
  fi
  printf '%s\n' "$tool_path"
}

polaris_require_delivery_tool() {
  local tool="${1:-}"
  local attr_json tool_path
  attr_json="$(polaris_classify_tool "${tool:-gh}")"
  if [[ -z "$tool" ]]; then
    polaris_tool_missing "<empty>" "$attr_json"
    return 2
  fi
  if ! tool_path="$(command -v "$tool" 2>/dev/null)"; then
    polaris_tool_missing "$tool" "$attr_json"
    return 1
  fi
  if [[ "$tool" == "gh" ]] && ! "$tool_path" auth status >/dev/null 2>&1; then
    polaris_tool_auth_failed "$tool" "$attr_json"
    return 1
  fi
  printf '%s\n' "$tool_path"
}

polaris_require_python() {
  local python_bin
  if python_bin="$(command -v python3 2>/dev/null)"; then
    export PYTHON_BIN="$python_bin"
    printf '%s\n' "$PYTHON_BIN"
    return 0
  fi
  polaris_tool_missing python3 "$(polaris_classify_tool python3)"
  return 1
}

polaris_with_runtime_tools() {
  local mise_bin root
  if ! mise_bin="$(polaris_find_mise)"; then
    polaris_tool_missing mise "$(polaris_classify_tool mise)"
    return 1
  fi
  root="$(polaris_workspace_root)"
  (cd "$root" && "$mise_bin" exec -- "$@")
}
