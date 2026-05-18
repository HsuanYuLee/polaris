#!/usr/bin/env bash
# Polaris root runtime doctor.

set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$WORKSPACE_ROOT/scripts"
MISE_CHECK="$SCRIPT_DIR/doctor-mise-check.sh"
PROFILE="core"
DRY_RUN=false
SIMULATE_NO_VSCODE_PATH=false
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

usage() {
  cat <<'EOF'
Usage:
  scripts/polaris-doctor.sh [--profile core|runtime|delivery|full] [--dry-run] [--simulate-no-vscode-path]
  scripts/polaris-doctor.sh --help

Profiles:
  core      bash, git, Python stdlib, mise-managed rg and jq
  runtime   core + Node, pnpm, package-local deps, Playwright cache, Mockoon
  delivery  core + gh binary and auth
  full      runtime + delivery
EOF
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS: %s\n' "$*"
}

warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  printf 'WARN: %s\n' "$*" >&2
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL: %s\n' "$*" >&2
}

blocked_env() {
  local blocker_class="$1"
  local message="$2"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL: BLOCKED_ENV blocker_class=%s %s\n' "$blocker_class" "$message" >&2
}

info() {
  printf 'INFO: %s\n' "$*"
}

validate_profile() {
  case "$PROFILE" in
    core|runtime|delivery|full) ;;
    *) fail "invalid --profile: $PROFILE"; exit 2 ;;
  esac
}

sanitize_vscode_path() {
  local original="${1:-}"
  local result=""
  local old_ifs="$IFS"
  local part=""

  IFS=:
  for part in $original; do
    case "$part" in
      *Code*|*code*|*vscode*|*VSCODE*|*Cursor*|*cursor*|*ChatGPT*|*chatgpt*|*openai*|*OpenAI*)
        ;;
      *)
        if [[ -z "$result" ]]; then
          result="$part"
        else
          result="$result:$part"
        fi
        ;;
    esac
  done
  IFS="$old_ifs"
  printf '%s\n' "$result"
}

resolve_toolchain_root() {
  if [[ -n "${POLARIS_TOOLCHAIN_ROOT:-}" ]]; then
    (cd "$POLARIS_TOOLCHAIN_ROOT" && pwd) || return 1
    return 0
  fi

  if [[ -f "$SCRIPT_DIR/lib/main-checkout.sh" ]] && command -v git >/dev/null 2>&1; then
    # shellcheck source=lib/main-checkout.sh
    . "$SCRIPT_DIR/lib/main-checkout.sh"
    resolve_main_checkout "$WORKSPACE_ROOT" 2>/dev/null && return 0
  fi

  printf '%s\n' "$WORKSPACE_ROOT"
}

check_command() {
  local cmd="$1"
  local label="${2:-$1}"
  local blocker_class="${3:-${cmd}-missing}"
  if [[ "$DRY_RUN" == "true" ]]; then
    info "would check command: $cmd ($label)"
    return 0
  fi
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "$label command found: $(command -v "$cmd")"
  else
    blocked_env "$blocker_class" "$label command missing: $cmd"
  fi
}

check_mise_tool() {
  local command_name="$1"
  local label="$2"
  local output=""
  local status=""
  local blocker_class=""
  local tool_path=""
  if [[ "$DRY_RUN" == "true" ]]; then
    info "would check mise-managed $label: $command_name"
    return 0
  fi
  if [[ ! -x "$MISE_CHECK" ]]; then
    fail "mise check helper missing: $MISE_CHECK"
    return 0
  fi
  if output="$(bash "$MISE_CHECK" --tool "$command_name" 2>/dev/null)"; then
    tool_path="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("path") or "")' "$output")"
    pass "mise-managed $label available: $command_name${tool_path:+ at $tool_path}"
  else
    status="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("status") or "")' "$output" 2>/dev/null || true)"
    blocker_class="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("blocker_class") or "")' "$output" 2>/dev/null || true)"
    case "$blocker_class" in
      mise-missing)
        blocked_env "mise-missing" "mise missing; cannot verify managed $label ($command_name)"
        ;;
      mise-managed:*)
        blocked_env "$blocker_class" "mise-managed $label missing: $command_name"
        ;;
      *)
        fail "mise-managed $label check failed: ${status:-unknown}"
        ;;
    esac
  fi
}

check_path() {
  local path="$1"
  local label="$2"
  if [[ "$DRY_RUN" == "true" ]]; then
    info "would check path: $path ($label)"
    return 0
  fi
  if [[ -e "$path" ]]; then
    pass "$label exists: $path"
  else
    fail "$label missing: $path"
  fi
}

run_toolchain_doctor() {
  local capability="$1"
  if [[ "$DRY_RUN" == "true" ]]; then
    info "would run toolchain doctor: $capability"
    return 0
  fi
  if bash "$WORKSPACE_ROOT/scripts/polaris-toolchain.sh" run "$capability"; then
    pass "$capability passed"
  else
    fail "$capability failed"
  fi
}

check_core() {
  echo "[core]"
  check_command bash "bash"
  check_command git "git"
  check_command python3 "Python stdlib"
  check_command mise "mise runtime manager" "mise-missing"
  check_mise_tool rg "ripgrep"
  check_mise_tool jq "jq"
}

check_runtime() {
  echo "[runtime]"
  check_mise_tool node "Node"
  check_mise_tool pnpm "pnpm"
  check_path "$PLAYWRIGHT_BROWSERS_PATH" "Playwright browser cache"
  run_toolchain_doctor fixtures.mockoon.doctor
  run_toolchain_doctor browser.playwright.doctor
}

check_delivery() {
  echo "[delivery]"
  check_command gh "GitHub CLI" "gh-missing"
  if [[ "$DRY_RUN" == "true" ]]; then
    info "would check gh auth status"
  elif command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    pass "gh auth status passed"
  else
    blocked_env "gh-unauth" "gh auth status failed or gh is not logged in"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --simulate-no-vscode-path)
      SIMULATE_NO_VSCODE_PATH=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "unknown argument: $1"
      exit 2
      ;;
  esac
done

validate_profile

if [[ "$SIMULATE_NO_VSCODE_PATH" == "true" ]]; then
  PATH="$(sanitize_vscode_path "$PATH")"
  export PATH
fi

TOOLCHAIN_ROOT="$(resolve_toolchain_root)" || {
  fail "cannot resolve POLARIS_TOOLCHAIN_ROOT"
  exit 1
}
PLAYWRIGHT_BROWSERS_PATH="$TOOLCHAIN_ROOT/.polaris/toolchain/ms-playwright"
export POLARIS_TOOLCHAIN_ROOT="$TOOLCHAIN_ROOT"
export PLAYWRIGHT_BROWSERS_PATH

echo "Polaris Doctor"
echo "workspace: $WORKSPACE_ROOT"
echo "toolchain root: $POLARIS_TOOLCHAIN_ROOT"
echo "profile: $PROFILE"
echo "PLAYWRIGHT_BROWSERS_PATH=$PLAYWRIGHT_BROWSERS_PATH"
if [[ "$SIMULATE_NO_VSCODE_PATH" == "true" ]]; then
  echo "PATH simulation: no VS Code / ChatGPT extension segments"
fi
echo

case "$PROFILE" in
  core)
    check_core
    ;;
  runtime)
    check_core
    check_runtime
    ;;
  delivery)
    check_core
    check_delivery
    ;;
  full)
    check_core
    check_runtime
    check_delivery
    ;;
esac

echo
echo "Result: ${PASS_COUNT} pass, ${WARN_COUNT} warn, ${FAIL_COUNT} fail"
if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
