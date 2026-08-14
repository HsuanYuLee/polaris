#!/usr/bin/env bash
# Polaris root runtime doctor.

set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$WORKSPACE_ROOT/scripts"
PROFILE="core"
DRY_RUN=false
SIMULATE_NO_VSCODE_PATH=false
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
# shellcheck source=lib/tool-resolution.sh
source "$SCRIPT_DIR/lib/tool-resolution.sh"

usage() {
  cat <<'EOF'
Usage:
  .claude/skills/framework-release/scripts/polaris-doctor.sh [--profile core|runtime|delivery|full] [--dry-run] [--simulate-no-vscode-path]
  .claude/skills/framework-release/scripts/polaris-doctor.sh --help

Profiles:
  core      這一層的地板：bash、git、Python stdlib、mise 本身。它們要先在，宣告才讀得到
  runtime   core + 宣告的工具 + Playwright cache、Mockoon runner
  delivery  core + 宣告的工具
  full      runtime + delivery

「宣告的工具」不寫在這支腳本裡——它逐支讀 SKILL.md 的 tools:，所以新增一支宣告了新工具
的 skill 不需要編輯這裡。宣告的形狀見 lib/skill_tools.py。
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
  if [[ "$cmd" == "python3" ]]; then
    if command_path="$(polaris_require_python 2>/dev/null)"; then
      pass "$label command found: $command_path"
    else
      blocked_env "$blocker_class" "$label command missing: $cmd"
    fi
  elif [[ "$cmd" == "mise" ]]; then
    if command_path="$(polaris_find_mise 2>/dev/null)"; then
      pass "$label command found: $command_path"
    else
      blocked_env "$blocker_class" "$label command missing: $cmd"
    fi
  elif command -v "$cmd" >/dev/null 2>&1; then
    pass "$label command found: $(command -v "$cmd")"
  else
    blocked_env "$blocker_class" "$label command missing: $cmd"
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

# DP-518 之前這裡走 `scripts/polaris-toolchain.sh run <capability>`，而那支 runner 的 parser
# 在 51b8208c 那次搬家被刪掉、沒有跟著搬。所以這兩格 doctor 從那天起每一次都是 fail，
# 而訊息是「fixtures.mockoon.doctor failed」——讀起來像 mockoon 壞了，不像 runner 不見了。
# 現在直接下那個 package 自己的 doctor script，少一層自己會失效的間接。
run_toolchain_doctor() {
  local label="$1" script="$2"
  if [[ "$DRY_RUN" == "true" ]]; then
    info "would run toolchain doctor: $label"
    return 0
  fi
  if (cd "$TOOLCHAIN_ROOT" && pnpm --dir tools/polaris-toolchain "$script"); then
    pass "$label passed"
  else
    fail "$label failed"
  fi
}

# core 是地板：這幾樣要先在，宣告才讀得到（讀宣告本身就要 python3）。它們刻意不從
# SKILL.md 推——一個「還沒讀到宣告」的階段需要一組先驗的東西，而那組東西不會長。
check_core() {
  echo "[core]"
  check_command bash "bash"
  check_command git "git"
  check_command python3 "Python stdlib"
  check_command mise "mise runtime manager" "mise-missing"
}

# 逐項回答每一個被宣告的工具。清單不寫在這裡——它從每一支 skill 自己的 frontmatter 讀，
# 所以新增一支宣告了新工具的 skill 不需要編輯這支腳本。
check_declared() {
  echo "[declared]"
  local reader="$SCRIPT_DIR/lib/skill_tools.py"
  # TOOLCHAIN_ROOT 是工作區根，已經解過了；再自己往上爬會多算一層而且靜靜地算錯。
  local skills_root="$TOOLCHAIN_ROOT/.claude/skills"
  local listing="" status=0
  if [[ "$DRY_RUN" == "true" ]]; then
    info "would check every tool declared by a skill"
    return 0
  fi
  if [[ ! -f "$reader" ]]; then
    fail "宣告讀取器不在：$reader"
    return 0
  fi
  listing="$("${PYTHON_BIN:-python3}" "$reader" list "$(cd "$skills_root" && pwd)" 2>&1)" || status=$?
  if [[ "$status" == "2" || -z "$listing" ]]; then
    # 讀不到宣告是第三態，不是「沒有工具要查」。說出來，不要靜靜地跳過。
    fail "讀不到任何工具宣告（${listing}）"
    return 0
  fi
  if [[ "$status" != "0" ]]; then
    fail "有宣告不合法：$(printf '%s' "$listing" | grep '^SKILL-TOOLS' || true)"
  fi
  # install 這一欄是給安裝那一面讀的（polaris-bootstrap.sh 用它決定跑哪一步）；
  # 這裡只需要接住它，不接的話它會被讀成 wanted_by。
  local name provision fix probe install wanted
  while IFS=$'\t' read -r name provision fix probe install wanted; do
    [[ -n "$name" ]] || continue
    [[ "$name" == SKILL-TOOLS* ]] && continue
    [[ "$fix" == "-" ]] && fix=""
    [[ "$probe" == "-" ]] && probe=""
    check_declared_tool "$name" "$provision" "$fix" "$probe" "$wanted"
  done <<< "$listing"
}

# 一個被宣告的工具的三種結果：在、不在但這裡裝得起來、不在且只能人補。
check_declared_tool() {
  local name="$1" provision="$2" fix="$3" probe="$4" wanted="$5"
  local where=""
  # 自己帶了問法的，就問它自己的問法——不是每一個相依都是 PATH 上的一個命令。
  if [[ -n "$probe" ]]; then
    if bash -c "$probe" >/dev/null 2>&1; then
      pass "$name 在（自己帶的問法：${probe}；要它的：${wanted}）"
    else
      blocked_env "declared-probe:${name}" "$name 不在——${fix}（要它的：${wanted}）"
    fi
    return 0
  fi
  if [[ "$provision" == "framework" ]]; then
    if where="$(polaris_require_mise_tool "$name" 2>/dev/null)"; then
      pass "$name 由 mise 提供：${where}（要它的：${wanted}）"
    elif where="$(toolchain_provides "$name")"; then
      pass "$name 由 toolchain package 提供：${where}（要它的：${wanted}）"
    else
      blocked_env "declared-missing:${name}" "$name 不在，但這裡裝得起來——${fix}（要它的：${wanted}）"
    fi
    return 0
  fi
  if where="$(command -v "$name" 2>/dev/null)"; then
    pass "$name 在：${where}（人補的，要它的：${wanted}）"
  else
    blocked_env "declared-manual:${name}" "$name 不在，而且框架裝不了——${fix}（要它的：${wanted}）"
  fi
}

# toolchain package 裝的東西不由 mise 管，問它自己的 node_modules/.bin。
toolchain_provides() {
  local name="$1"
  local candidate="$TOOLCHAIN_ROOT/tools/polaris-toolchain/node_modules/.bin/$name"
  [[ -x "$candidate" ]] || return 1
  local dir
  dir="$(cd "$(dirname "$candidate")" && pwd)"
  printf '%s/%s\n' "$dir" "$name"
}

check_runtime() {
  echo "[runtime]"
  check_path "$PLAYWRIGHT_BROWSERS_PATH" "Playwright browser cache"
  run_toolchain_doctor fixtures.mockoon mockoon:doctor
  run_toolchain_doctor browser.playwright playwright:doctor
}

# 「gh 在不在」由宣告那一節問過了，這裡只問它答不出來的那一半：**登入了沒**。
# 那正是 gh 被標成 provision: manual 的理由——二進位檔裝得起來，登入只有人做得到。
check_delivery() {
  echo "[delivery]"
  if [[ "$DRY_RUN" == "true" ]]; then
    info "would check gh auth status"
    return 0
  fi
  if ! command -v gh >/dev/null 2>&1; then
    info "gh 不在，登入無從問起——見上面 [declared] 那一行"
    return 0
  fi
  if polaris_require_delivery_tool gh >/dev/null 2>&1; then
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
    check_declared
    ;;
  runtime)
    check_core
    check_declared
    check_runtime
    ;;
  delivery)
    check_core
    check_declared
    check_delivery
    ;;
  full)
    check_core
    check_declared
    check_runtime
    check_delivery
    ;;
esac

echo
echo "Result: ${PASS_COUNT} pass, ${WARN_COUNT} warn, ${FAIL_COUNT} fail"
if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
