#!/usr/bin/env bash
# 拿到這份東西之後的第一個命令：把每一支 skill 宣告的工具都裝齊。入口是 `mise run init`。

set -euo pipefail

# POLARIS_SAFE_CLI_INTROSPECTION_BEGIN
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  command printf '%s\n' 'Usage:'
  command printf '%s\n' '  scripts/polaris-init.sh [--profile core|runtime|delivery|full] [--dry-run]'
  command printf '%s\n' '  scripts/polaris-init.sh --help'
  command printf '%s\n' ''
  command printf '%s\n' 'Bootstraps Polaris framework runtime dependencies from repo-owned contracts.'
  exit 0
fi
# POLARIS_SAFE_CLI_INTROSPECTION_END

usage() {
  cat <<'EOF'
Usage:
  scripts/polaris-init.sh [--profile core|runtime|delivery|full] [--dry-run]
  scripts/polaris-init.sh --help

Bootstraps Polaris framework runtime dependencies from repo-owned contracts:
  - mise.toml for managed runtimes and native tools
  - package-local pnpm installs for Polaris-owned Node packages
  - workspace-shared Playwright browser cache at .polaris/toolchain/ms-playwright
  - four generated runtime instruction targets via compile-runtime-instructions.sh

Missing mise is reported with repair hints. This script does not silently install
global CLIs or require Homebrew.
EOF
}

WORKSPACE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$WORKSPACE_ROOT/scripts"
DRY_RUN=false
PROFILE="runtime"
# shellcheck source=lib/tool-resolution.sh
source "$SCRIPT_DIR/lib/tool-resolution.sh"
MAIN_CHECKOUT_RESOLVER="resolve_main_checkout"

log() {
  printf '[polaris-init] %s\n' "$*"
}

blocked_env() {
  local blocker_class="$1"
  local message="$2"
  printf '[polaris-init] BLOCKED_ENV blocker_class=%s %s\n' "$blocker_class" "$message" >&2
}

die() {
  printf '[polaris-init] ERROR: %s\n' "$*" >&2
  exit 1
}

run_cmd() {
  log "+ $*"
  if [[ "$DRY_RUN" == "true" ]]; then
    return 0
  fi
  (cd "$TOOLCHAIN_ROOT" && "$@")
}

resolve_toolchain_root() {
  if [[ -n "${POLARIS_TOOLCHAIN_ROOT:-}" ]]; then
    (cd "$POLARIS_TOOLCHAIN_ROOT" && pwd) || return 1
    return 0
  fi

  if [[ -f "$SCRIPT_DIR/lib/main-checkout.sh" ]] && command -v git >/dev/null 2>&1; then
    # shellcheck source=lib/main-checkout.sh
    . "$SCRIPT_DIR/lib/main-checkout.sh"
    "$MAIN_CHECKOUT_RESOLVER" "$WORKSPACE_ROOT" 2>/dev/null && return 0
  fi

  printf '%s\n' "$WORKSPACE_ROOT"
}

print_mise_repair_hints() {
  cat >&2 <<'EOF'
[polaris-init] mise is required before init can install managed tools.

Repair:
  1. Install mise using the official installation path for your platform:
     https://mise.jdx.dev/getting-started.html
  2. Re-open your shell so `mise` is on PATH.
  3. Re-run:
     mise run init

Notes:
  - Homebrew is optional, not a Polaris prerequisite.
  - Do not rely on a VS Code extension bundle PATH for rg, jq, node, pnpm, or python.
  - Automatic mise installation must be an explicit opt-in flow; this bootstrap
    does not perform silent global installs.
EOF
}

require_mise() {
  if polaris_find_mise >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    log "mise missing; dry-run continues after repair hint."
    print_mise_repair_hints
    return 0
  fi
  blocked_env "mise-missing" "mise is required before bootstrap."
  print_mise_repair_hints
  return 1
}

require_managed_tool() {
  local command_name="$1"
  local label="$2"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "would verify mise-managed $label: $command_name"
    return 0
  fi
  if POLARIS_WORKSPACE_ROOT="$WORKSPACE_ROOT" polaris_require_mise_tool "$command_name" >/dev/null; then
    return 0
  fi
  blocked_env "mise-managed:${command_name}" "mise-managed $label missing after mise install."
  return 1
}

require_gh_delivery() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log "would verify gh binary and auth"
    return 0
  fi
  if ! polaris_require_delivery_tool gh >/dev/null; then
    if ! command -v gh >/dev/null 2>&1; then
    blocked_env "gh-missing" "GitHub CLI is required for delivery/full bootstrap profiles."
    return 1
    fi
    blocked_env "gh-unauth" "GitHub CLI is installed but not authenticated."
    return 1
  fi
}

validate_profile() {
  case "$PROFILE" in
    core|runtime|delivery|full) ;;
    *) die "invalid --profile: $PROFILE" ;;
  esac
}

run_mise() {
  local mise_bin
  if [[ "$DRY_RUN" == "true" ]]; then
    log "+ mise $*"
    return 0
  fi
  mise_bin="$(polaris_find_mise)" || return 1
  (cd "$TOOLCHAIN_ROOT" && "$mise_bin" "$@")
}

run_managed() {
  local command="$1"
  shift || true
  if [[ "$DRY_RUN" == "true" ]]; then
    log "+ mise exec -- $command $*"
    return 0
  fi
  POLARIS_WORKSPACE_ROOT="$TOOLCHAIN_ROOT" polaris_with_runtime_tools "$command" "$@"
}

bootstrap_core() {
  run_mise trust "$TOOLCHAIN_ROOT/mise.toml"
  run_mise install
}

mise_declares_key() {
  # Description: whether mise.toml's [tools] table declares this exact key.
  # Args: $1 = key as written in the declaration (quotes in the toml are stripped)
  # Returns: 0 when declared.
  local key="$1"
  awk -v key="$key" '
    /^\[/ { in_tools = ($0 == "[tools]"); next }
    in_tools {
      line = $0
      sub(/[ \t]*=.*/, "", line)
      gsub(/^[ \t]+|[ \t]+$/, "", line)
      gsub(/^"|"$/, "", line)
      if (line == key) found = 1
    }
    END { exit(found ? 0 : 1) }
  ' "$TOOLCHAIN_ROOT/mise.toml"
}

resolve_installer() {
  # Description: which step installs this declared tool.
  # Args: $1 = tool name, $2 = declared `install` value ("" when not declared)
  # Outputs: "<kind>|<arg>" on stdout, or the reason on stdout with a non-zero return.
  #   理由走 stdout 而不是一個變數：呼叫端用命令替換接它，而命令替換是子行程——在那裡設的
  #   變數回不到呼叫端，於是失敗的原因會靜靜地變成空字串。
  local name="$1" install="$2" key dir other
  case "$install" in
    "")
      # 不填的意思是「跟工具同名的那個安裝項」——推得出來的不必寫死。但它要被驗過：
      # 一個推出來、然後沒有人裝的名字，跟沒有宣告一樣。
      if mise_declares_key "$name"; then printf 'mise|%s\n' "$name"; return 0; fi
      printf '%s\n' "mise.toml 的 [tools] 沒有同名的鍵，而宣告也沒說是誰裝它。要嘛補一行 install: 指出安裝者，要嘛先登記：mise use ${name}@<版本>"
      return 1 ;;
    mise:*)
      key="${install#mise:}"
      if mise_declares_key "$key"; then printf 'mise|%s\n' "$key"; return 0; fi
      # 印出要跑的那一條，不是只說「沒有那個鍵」。這是「加了新工具要先登記」唯一不會被
      # 跳過的表面——它只在該知道的那一刻出現，而且它是紅的。
      printf '%s\n' "還沒有人登記它。先跑：mise use ${key}@<版本>　然後重跑 mise run init"
      return 1 ;;
    pnpm:*)
      dir="${install#pnpm:}"
      if [[ -f "$TOOLCHAIN_ROOT/$dir/package.json" ]]; then printf 'pnpm|%s\n' "$dir"; return 0; fi
      printf '%s\n' "說它由 ${dir} 裝，而那底下沒有 package.json"
      return 1 ;;
    uv)
      if [[ -f "$TOOLCHAIN_ROOT/pyproject.toml" ]]; then printf 'uv|\n'; return 0; fi
      printf '%s\n' "說它由 uv 裝，而這個工作區沒有 pyproject.toml"
      return 1 ;;
    with:*)
      other="${install#with:}"
      # 跟著另一個工具來的（npx 跟著 node），由那一個負責；那一個自己也會被解析一次。
      if printf '%s\n' "$DECLARED_NAMES" | grep -qx -- "$other"; then
        printf 'with|%s\n' "$other"; return 0
      fi
      printf '%s\n' "說它跟著 ${other} 一起來，而沒有人宣告 ${other}"
      return 1 ;;
    *)
      printf '%s\n' "不認得的安裝者：${install}（只認得 mise:<鍵>、pnpm:<目錄>、uv、with:<工具>）"
      return 1 ;;
  esac
}

plan_declared_tools() {
  # Description: turn every `provision: framework` declaration into the step that installs it.
  # Side effects: sets PNPM_DIRS / NEED_UV / VERIFY_SPECS; exits 1 naming any tool nobody installs.
  #
  # 這一步在裝任何東西之前跑。一個說「這裡裝得起來」而沒有人裝的宣告，會讓 doctor 指著
  # `mise run init`，而這條命令什麼都不會做——DP-540 修掉的是同一個形狀的上一層。
  local reader="$SCRIPT_DIR/lib/skill_tools.py"
  local skills_root="$TOOLCHAIN_ROOT/.claude/skills"
  local listing status=0 name provision fix probe install wanted resolved unresolved=0
  PNPM_DIRS=""
  NEED_UV=false
  VERIFY_SPECS=""
  [[ -f "$reader" && -d "$skills_root" ]] || {
    log "讀不到工具宣告（$reader / $skills_root），這一步跳過"
    return 0
  }
  listing="$("${PYTHON_BIN:-python3}" "$reader" list "$skills_root" 2>&1)" || status=$?
  if [[ "$status" == "2" || -z "$listing" ]]; then
    blocked_env "declarations-unreadable" "讀不到任何工具宣告（${listing}）"
    return 1
  fi
  DECLARED_NAMES="$(printf '%s\n' "$listing" | cut -f1)"
  while IFS=$'\t' read -r name provision fix probe install wanted; do
    [[ -n "$name" ]] || continue
    [[ "$provision" == "framework" ]] || continue
    [[ "$install" == "-" ]] && install=""
    [[ "$probe" == "-" ]] && probe=""
    if ! resolved="$(resolve_installer "$name" "$install")"; then
      unresolved=$((unresolved + 1))
      printf '[polaris-init] 沒有人裝 %s：%s（要它的：%s）\n' "$name" "$resolved" "$wanted" >&2
      continue
    fi
    case "${resolved%%|*}" in
      pnpm) PNPM_DIRS="${PNPM_DIRS}${resolved#*|}"$'\n' ;;
      uv) NEED_UV=true ;;
    esac
    VERIFY_SPECS="${VERIFY_SPECS}${name}	${resolved}	${probe}"$'\n'
  done <<< "$listing"
  PNPM_DIRS="$(printf '%s' "$PNPM_DIRS" | sort -u)"
  if [[ "$unresolved" != "0" ]]; then
    blocked_env "declared-uninstallable" "有 ${unresolved} 個宣告說「這裡裝得起來」，而沒有任何一步會裝它。登記完重跑 mise run init。"
    return 1
  fi
  log "宣告解析完成：$(printf '%s\n' "$VERIFY_SPECS" | grep -c .) 個由框架提供的工具都指得出安裝者"
  return 0
}

verify_declared_tools() {
  # Description: after installing, every framework-provided tool must actually be there.
  # Returns: 1 naming each one that is still missing.
  local name resolved probe kind arg missing=0
  if [[ "$DRY_RUN" == "true" ]]; then
    log "would verify $(printf '%s\n' "$VERIFY_SPECS" | grep -c .) declared tool(s)"
    return 0
  fi
  while IFS=$'\t' read -r name resolved probe; do
    [[ -n "$name" ]] || continue
    kind="${resolved%%|*}"
    arg="${resolved#*|}"
    if [[ -n "$probe" ]]; then
      bash -c "$probe" >/dev/null 2>&1 && continue
    elif [[ "$kind" == "pnpm" ]]; then
      [[ -x "$TOOLCHAIN_ROOT/$arg/node_modules/.bin/$name" ]] && continue
    else
      POLARIS_WORKSPACE_ROOT="$TOOLCHAIN_ROOT" polaris_require_mise_tool "$name" >/dev/null 2>&1 && continue
    fi
    missing=$((missing + 1))
    printf '[polaris-init] 裝完之後 %s 還是不在（%s）\n' "$name" "$resolved" >&2
  done <<< "$VERIFY_SPECS"
  if [[ "$missing" != "0" ]]; then
    blocked_env "declared-still-missing" "${missing} 個由框架提供的工具在安裝之後仍然不在。"
    return 1
  fi
  return 0
}

regenerate_runtime_targets() {
  local compiler="$TOOLCHAIN_ROOT/.claude/instructions/compile.sh"
  [[ -f "$compiler" ]] || die "runtime instruction compiler missing: $compiler"
  run_cmd bash .claude/instructions/compile.sh
}

bootstrap_runtime() {
  local dir
  require_managed_tool node "Node" || return 1
  require_managed_tool pnpm "pnpm" || return 1
  # DP-518 之前這幾行走 `scripts/polaris-toolchain.sh run <capability>`，而那支 runner 的
  # parser（scripts/lib/polaris_toolchain_manifest.py）在 51b8208c 那次搬家被刪掉、沒有跟著
  # 搬。所以 `mise run init -- --profile runtime`（當時叫 bootstrap）從那天起就是壞的，而沒有東西會紅。
  #
  # docs-manager 不從宣告推出來，因為它不是任何一支 skill 的工具——它是這個 repo 的站台。
  run_managed pnpm --dir docs-manager install
  while read -r dir; do
    [[ -n "$dir" ]] || continue
    run_managed pnpm --dir "$dir" install
  done <<< "$PNPM_DIRS"
  if [[ "$NEED_UV" == "true" ]]; then
    # uv 把 pyproject.toml 宣告的相依裝進這個工作區自己的 .venv（mise 的 [env] 建它）。
    # 這是「框架提供一個函式庫」唯一不去動宿主直譯器的做法。
    run_managed uv sync
  fi
  if printf '%s\n' "$VERIFY_SPECS" | cut -f1 | grep -qx playwright; then
    # 瀏覽器不是套件，是 playwright 自己的後續步驟；沒有人宣告 playwright 就不需要它。
    #
    # 路徑從宣告那一份拿（`install: pnpm:<目錄>`，經 plan_declared_tools 變成 VERIFY_SPECS
    # 的第二欄），所以這裡沒有第二份路徑。以前這行走 `--filter polaris-toolchain`：那省掉了
    # 路徑，代價是 `pnpm --filter <找不到>` 回 rc=0——這一行會 exit 0 而什麼都沒裝，跟
    # DP-654 在修的那個 bug 是同一個病。`pnpm --dir <錯路徑>` 回 rc=1。
    local pw_dir
    pw_dir="$(printf '%s\n' "$VERIFY_SPECS" | awk -F'\t' '$1=="playwright"{print $2}' | head -1)"
    pw_dir="${pw_dir#pnpm|}"
    if [[ -z "$pw_dir" ]]; then
      blocked_env "playwright-dir-unresolved" "宣告說要 playwright，但它的安裝目錄解不出來（VERIFY_SPECS 裡沒有 playwright 那一列）。"
      return 1
    fi
    run_managed pnpm --dir "$pw_dir" playwright:install
  fi
  verify_declared_tools || return 1
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
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown argument: $1"
      ;;
  esac
done

validate_profile

TOOLCHAIN_ROOT="$(resolve_toolchain_root)" || die "cannot resolve POLARIS_TOOLCHAIN_ROOT"
PLAYWRIGHT_BROWSERS_PATH="$TOOLCHAIN_ROOT/.polaris/toolchain/ms-playwright"
export POLARIS_TOOLCHAIN_ROOT="$TOOLCHAIN_ROOT"
export PLAYWRIGHT_BROWSERS_PATH

log "workspace: $WORKSPACE_ROOT"
log "toolchain root: $POLARIS_TOOLCHAIN_ROOT"
log "profile: $PROFILE"
log "PLAYWRIGHT_BROWSERS_PATH=$PLAYWRIGHT_BROWSERS_PATH"

run_cmd mkdir -p "$POLARIS_TOOLCHAIN_ROOT/.polaris/toolchain"
regenerate_runtime_targets
require_mise || exit 1
plan_declared_tools || exit 1

case "$PROFILE" in
  core)
    bootstrap_core
    ;;
  runtime)
    bootstrap_core
    bootstrap_runtime
    ;;
  delivery)
    bootstrap_core
    require_gh_delivery || exit 1
    log "delivery profile gh checks passed."
    ;;
  full)
    bootstrap_core
    bootstrap_runtime
    require_gh_delivery || exit 1
    log "full profile delivery checks passed."
    ;;
esac

log "都齊了：每一支 skill 宣告的工具都裝好而且驗過"
