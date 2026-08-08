#!/usr/bin/env bash
# Polaris runtime toolchain runner.

set -euo pipefail

find_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/polaris-toolchain.yaml" && -d "$dir/scripts" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done

  local script_root
  script_root="$(cd "$(dirname "$0")/.." && pwd)"
  if [[ -f "$script_root/polaris-toolchain.yaml" ]]; then
    echo "$script_root"
    return 0
  fi

  echo "ERROR: cannot locate Polaris workspace root" >&2
  return 1
}

usage() {
  cat >&2 <<'EOF'
usage:
  scripts/polaris-toolchain.sh install --required
  scripts/polaris-toolchain.sh doctor --required [--json]
  scripts/polaris-toolchain.sh run <capability.command>
  scripts/polaris-toolchain.sh manifest [--required] [--json]
EOF
}

WORKSPACE_ROOT="$(find_root)"
MANIFEST="$WORKSPACE_ROOT/polaris-toolchain.yaml"
PARSER="$WORKSPACE_ROOT/scripts/lib/polaris_toolchain_manifest.py"
# shellcheck source=lib/tool-resolution.sh
source "$WORKSPACE_ROOT/scripts/lib/tool-resolution.sh"

validate_manifest() {
  python3 "$PARSER" "$MANIFEST" >/dev/null
}

manifest_json() {
  if [[ "${1:-}" == "--required" ]]; then
    python3 "$PARSER" "$MANIFEST" --required --json
  else
    python3 "$PARSER" "$MANIFEST" --json
  fi
}

run_command_string() {
  local command="$1"
  shift || true
  local arg
  for arg in "$@"; do
    command+=" $(printf '%q' "$arg")"
  done
  POLARIS_WORKSPACE_ROOT="$WORKSPACE_ROOT" polaris_with_runtime_tools bash -lc "$command"
}

capability_command() {
  python3 "$PARSER" "$MANIFEST" --command "$1"
}

check_minimum_environment() {
  local json="${1:-false}"
  local failures=0
  local node_path pnpm_path python_path
  local node_version node_ok pnpm_version python_version
  node_path="$(POLARIS_WORKSPACE_ROOT="$WORKSPACE_ROOT" polaris_require_mise_tool node 2>/dev/null || true)"
  pnpm_path="$(POLARIS_WORKSPACE_ROOT="$WORKSPACE_ROOT" polaris_require_mise_tool pnpm 2>/dev/null || true)"
  python_path="$(polaris_require_python 2>/dev/null || true)"
  node_version="$(POLARIS_WORKSPACE_ROOT="$WORKSPACE_ROOT" polaris_with_runtime_tools node -p 'process.versions.node' 2>/dev/null || echo 0.0.0)"
  node_ok="$(POLARIS_WORKSPACE_ROOT="$WORKSPACE_ROOT" polaris_with_runtime_tools node - <<'NODE' 2>/dev/null || echo false
const [major, minor, patch] = process.versions.node.split('.').map(Number);
const ok = major > 22 || (major === 22 && (minor > 12 || (minor === 12 && patch >= 0)));
console.log(ok ? 'true' : 'false');
NODE
)"

  if [[ -n "$pnpm_path" ]]; then
    pnpm_version="$(POLARIS_WORKSPACE_ROOT="$WORKSPACE_ROOT" polaris_with_runtime_tools pnpm --version 2>/dev/null || true)"
  fi
  if [[ -n "$python_path" ]]; then
    python_version="$("$python_path" - <<'PY' 2>/dev/null || true
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")
PY
)"
  else
    python_version=""
  fi

  [[ "${BASH_VERSINFO[0]}" -ge 3 ]] || failures=$((failures + 1))
  [[ "$node_ok" == "true" ]] || failures=$((failures + 1))
  [[ -n "$pnpm_path" ]] || failures=$((failures + 1))
  [[ -n "$python_path" && -n "$python_version" ]] || failures=$((failures + 1))

  if [[ "$json" == "true" ]]; then
    python3 - <<PY
import json
print(json.dumps({
  "minimum_environment": {
    "bash": {"ok": ${BASH_VERSINFO[0]} >= 3, "version": "${BASH_VERSION}"},
    "node": {"ok": "${node_ok}" == "true", "path": "${node_path}", "version": "${node_version}", "required": ">=22.12.0"},
    "pnpm": {"ok": bool("${pnpm_path}"), "path": "${pnpm_path}", "version": "${pnpm_version}", "required": "10.10.0"},
    "python": {"ok": bool("${python_path}") and bool("${python_version}"), "path": "${python_path}", "version": "${python_version}"}
  }
}, ensure_ascii=False, indent=2))
PY
  else
    echo "Minimum environment:"
    echo "  bash: ${BASH_VERSION}"
    echo "  node: ${node_path:-missing} (${node_version:-missing}; required >=22.12.0)"
    echo "  pnpm: ${pnpm_path:-missing}${pnpm_version:+ (${pnpm_version})}"
    echo "  python3: ${python_version:-missing}"
  fi

  return "$failures"
}

install_required() {
  validate_manifest
  run_command_string "$(capability_command docs.viewer.install)"
  run_command_string "$(capability_command fixtures.mockoon.install)"
  run_command_string "$(capability_command browser.playwright.install)"
  run_command_string "$(capability_command browser.playwright.install-browser)"
}

doctor_required() {
  local json=false
  if [[ "${1:-}" == "--json" ]]; then
    json=true
  fi

  validate_manifest
  check_minimum_environment "$json"

  if [[ "$json" == "true" ]]; then
    return 0
  fi

  echo ""
  echo "Required capabilities:"
  run_command_string "$(capability_command docs.viewer.doctor)"
  run_command_string "$(capability_command fixtures.mockoon.doctor)"
  run_command_string "$(capability_command browser.playwright.doctor)"
  echo "PASS: required Polaris toolchain capabilities"
}

case "${1:-}" in
  install)
    [[ "${2:-}" == "--required" ]] || { usage; exit 2; }
    install_required
    ;;
  doctor)
    [[ "${2:-}" == "--required" ]] || { usage; exit 2; }
    doctor_required "${3:-}"
    ;;
  run)
    [[ -n "${2:-}" ]] || { usage; exit 2; }
    validate_manifest
    command_id="$2"
    shift 2
    if [[ "${1:-}" == "--" ]]; then
      shift
    fi
    command_string="$(capability_command "$command_id")"
    run_command_string "$command_string" "$@"
    ;;
  manifest)
    validate_manifest
    if [[ "${2:-}" == "--required" ]]; then
      manifest_json --required
    else
      manifest_json
    fi
    ;;
  --help|-h|"")
    usage
    exit 0
    ;;
  *)
    usage
    exit 2
    ;;
esac
