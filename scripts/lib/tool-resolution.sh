#!/usr/bin/env bash
# Shared deterministic tool resolution helpers for Polaris scripts.
#
# ## Python invocation pattern
#
# Python helpers must not call ``subprocess.run(["rg", ...])`` directly. Import
# the Python mirror of this resolver and resolve once per process:
#
#     from tool_resolution import ToolResolutionError, resolve_tool
#     try:
#         rg = resolve_tool("rg")
#     except ToolResolutionError as exc:
#         print(f"POLARIS_TOOL_MISSING {exc}", file=sys.stderr)
#         sys.exit(2)
#     subprocess.run([rg, "-n", "pattern", "path"], check=False)
#
# Resolution layers mirror the bash helpers: POSIX baseline PATH lookup (for
# bash / python3 / cp / mv / ... — AC-NEG15), ``mise where``, mise shims, then
# a last-resort PATH lookup that emits a ``POLARIS_TOOL_RESOLUTION_ADVISORY``
# stderr line. ``scripts/validate-script-dependencies.sh`` enforces the rule by
# scanning Python sources for direct subprocess calls on managed tools (D38).

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
  local candidate
  for candidate in \
    "$HOME/.local/bin/mise" \
    "$HOME/.local/share/mise/bin/mise" \
    /opt/homebrew/bin/mise \
    /usr/local/bin/mise
  do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
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
  local profile hint
  profile="$(polaris_tool_attr_field "$attr_json" runtime_profile)"
  hint="$(polaris_tool_attr_field "$attr_json" handoff_hint)"
  [[ -n "$profile" ]] || profile="runtime"
  [[ -n "$hint" ]] || hint="bash scripts/polaris-doctor.sh --profile $profile"
  echo "[POLARIS_TOOL_MISSING] tool=$tool profile=$profile remediation=\"$hint\"" >&2
}

polaris_tool_auth_failed() {
  local tool="$1"
  local attr_json="$2"
  local hint
  hint="$(polaris_tool_attr_field "$attr_json" handoff_hint)"
  [[ -n "$hint" ]] || hint="gh auth login"
  echo "[POLARIS_TOOL_AUTH_FAILED] tool=$tool profile=delivery hint=\"$hint\"" >&2
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
