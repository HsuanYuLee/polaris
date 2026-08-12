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

polaris_classify_tool() {
  local tool="${1:-}"
  if [[ -z "$tool" ]]; then
    echo "POLARIS_TOOL_MISSING tool=<empty> owner=unknown install_authority=manual_user_action hint=tool name is required" >&2
    return 2
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
