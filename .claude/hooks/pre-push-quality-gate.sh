#!/bin/bash
# Pre-push Quality Gate — 門下省機制
# 攔截 git push，確認品質檢查已通過才放行
#
# 機制：your-company-dev-quality-check 通過後寫 marker file，本 hook 檢查 marker 是否存在
# Marker: /tmp/.quality-gate-passed-{branch}
#
# 環境變數（Claude Code hook 提供）：
#   CLAUDE_TOOL_INPUT — Bash tool 的 JSON input

# 只攔截 git push 指令
if ! echo "$CLAUDE_TOOL_INPUT" | grep -qE '"command"[^"]*git[^"]*push'; then
  exit 0
fi

# 取得專案目錄（從 CLAUDE_PROJECT_DIR 或 fallback）
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# 從 tool input 提取實際操作的 repo（支援 git -C /path push）
REPO_PATH=$(echo "$CLAUDE_TOOL_INPUT" | grep -oE 'git -C [^ ]+' | head -1 | sed 's/git -C //')
if [ -n "$REPO_PATH" ]; then
  PROJECT_DIR="$REPO_PATH"
fi

# 取得 branch 名稱
BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)

# 主要 branch 不攔截（通常不會直接 push）
case "$BRANCH" in
  main|master|develop) exit 0 ;;
esac

# 檢查 marker file
MARKER="/tmp/.quality-gate-passed-${BRANCH}"

if [ -f "$MARKER" ]; then
  # Marker 存在，檢查是否過期（超過 24 小時視為過期）
  if [ "$(uname)" = "Darwin" ]; then
    MARKER_AGE=$(( $(date +%s) - $(stat -f %m "$MARKER") ))
  else
    MARKER_AGE=$(( $(date +%s) - $(stat -c %Y "$MARKER") ))
  fi

  if [ "$MARKER_AGE" -lt 86400 ]; then
    exit 0  # 有效 marker，放行
  else
    rm -f "$MARKER"  # 過期，刪除
  fi
fi

# 沒有有效 marker，阻擋 push
cat >&2 <<'EOF'
⚠️ 品質閘門未通過 — 請先執行 your-company-dev-quality-check

推送前必須通過品質檢查（lint + test + coverage）。
執行品質檢查後，marker 會自動建立，即可正常 push。

提示：說「品質檢查」或「quality check」即可觸發。
EOF
exit 2
