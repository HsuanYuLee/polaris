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
  (cd "$WORKSPACE_ROOT" && bash -lc "$command")
}

capability_command() {
  python3 "$PARSER" "$MANIFEST" --command "$1"
}

check_minimum_environment() {
  local json="${1:-false}"
  local failures=0
  local node_major
  node_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"

  local pnpm_path=""
  pnpm_path="$(command -v pnpm 2>/dev/null || true)"
  local python_version=""
  python_version="$(python3 - <<'PY' 2>/dev/null || true
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")
PY
)"

  [[ "${BASH_VERSINFO[0]}" -ge 3 ]] || failures=$((failures + 1))
  [[ "$node_major" =~ ^[0-9]+$ && "$node_major" -ge 20 ]] || failures=$((failures + 1))
  [[ -n "$pnpm_path" ]] || failures=$((failures + 1))
  [[ -n "$python_version" ]] || failures=$((failures + 1))

  if [[ "$json" == "true" ]]; then
    python3 - <<PY
import json
print(json.dumps({
  "minimum_environment": {
    "bash": {"ok": ${BASH_VERSINFO[0]} >= 3, "version": "${BASH_VERSION}"},
    "node": {"ok": str("${node_major}").isdigit() and int("${node_major}") >= 20, "version": "$(node --version 2>/dev/null || true)"},
    "pnpm": {"ok": bool("${pnpm_path}"), "path": "${pnpm_path}"},
    "python": {"ok": bool("${python_version}"), "version": "${python_version}"}
  }
}, ensure_ascii=False, indent=2))
PY
  else
    echo "Minimum environment:"
    echo "  bash: ${BASH_VERSION}"
    echo "  node: $(node --version 2>/dev/null || echo missing)"
    echo "  pnpm: ${pnpm_path:-missing}"
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
