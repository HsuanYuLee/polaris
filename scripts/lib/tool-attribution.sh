#!/usr/bin/env bash
# Shared tool ownership / install-authority classifier for Polaris scripts.

set -u

polaris_tool_attr_json() {
  "${PYTHON_BIN:-python3}" - "$@" <<'PY'
import json
import sys

keys = [
    "name",
    "owner",
    "install_authority",
    "check_command",
    "install_command",
    "runtime_profile",
    "goes_to_mise",
    "handoff_hint",
]
values = dict(zip(keys, sys.argv[1:]))
values["goes_to_mise"] = values.get("goes_to_mise") == "true"
print(json.dumps(values, ensure_ascii=False, sort_keys=True))
PY
}

# 這支 lib 住在 <repo>/scripts/lib/，skill 根在 <repo>/.claude/skills/。
polaris_skills_root() {
  (cd "${BASH_SOURCE[0]%/*}/../../.claude/skills" && pwd)
}

polaris_classify_tool() {
  local tool="${1:-}"
  if [[ -z "$tool" ]]; then
    echo "POLARIS_TOOL_MISSING tool=<empty> owner=unknown install_authority=manual_user_action hint=tool name is required" >&2
    return 2
  fi

  # 先問宣告：一支 skill 需要什麼寫在它自己的 frontmatter 裡（見 lib/skill_tools.py）。
  # 底下那個 case 是這份資料的舊家，現在只剩兩個角色：bootstrap 地板那幾樣（它們在讀得到
  # 宣告之前就要在，所以不能由宣告提供），以及問不到宣告時的落點。
  local declared_line declared_provision declared_fix
  if [[ -f "${POLARIS_SKILL_TOOLS_READER:-}" || -f "${BASH_SOURCE[0]%/*}/skill_tools.py" ]]; then
    declared_line="$("${PYTHON_BIN:-python3}" "${POLARIS_SKILL_TOOLS_READER:-${BASH_SOURCE[0]%/*}/skill_tools.py}" \
      list "$(polaris_skills_root)" 2>/dev/null | awk -F'\t' -v t="$tool" '$1 == t {print; exit}')" || true
    if [[ -n "$declared_line" ]]; then
      declared_provision="$(printf '%s' "$declared_line" | cut -f2)"
      declared_fix="$(printf '%s' "$declared_line" | cut -f3)"
      [[ "$declared_fix" == "-" ]] && declared_fix=""
      if [[ "$declared_provision" == "framework" ]]; then
        polaris_tool_attr_json "$tool" framework root_mise "mise exec -- $tool --version" "N/A" \
          core true "${declared_fix:-mise run init}"
      else
        polaris_tool_attr_json "$tool" user manual_user_action "$tool --version" "N/A" \
          delivery false "$declared_fix"
      fi
      return 0
    fi
  fi

  case "$tool" in
    mise)
      polaris_tool_attr_json "$tool" framework root_mise "mise --version" "N/A" core true "Install mise through the Polaris bootstrap/runtime setup before running framework scripts."
      ;;
    node|pnpm|jq|rg)
      polaris_tool_attr_json "$tool" framework root_mise "mise exec -- $tool --version" "N/A" core true "Run Polaris bootstrap so root mise provides $tool."
      ;;
    python3)
      polaris_tool_attr_json "$tool" framework system "python3 --version" "N/A" core false "Install Python 3 or expose python3 on PATH."
      ;;
    gh)
      polaris_tool_attr_json "$tool" delivery system "gh --version && gh auth status" "N/A" delivery false "Install GitHub CLI and authenticate for PR/review delivery operations."
      ;;
    mockoon-cli|playwright|vitest|jest)
      polaris_tool_attr_json "$tool" project project_package_manager "$tool --version" "N/A" runtime false "Install through the product repo package manager or project runtime setup."
      ;;
    gt-567|gt-567-cli|ticket-cli|paid-cli)
      polaris_tool_attr_json "$tool" ticket manual_user_action "$tool --version" "N/A" ticket false "This is ticket-scoped; install or authorize it for the specific work order only."
      ;;
    *)
      polaris_tool_attr_json "$tool" user manual_user_action "$tool --version" "N/A" ticket false "Unknown tool; confirm owner/install authority before adding it to a deterministic script."
      ;;
  esac
}
