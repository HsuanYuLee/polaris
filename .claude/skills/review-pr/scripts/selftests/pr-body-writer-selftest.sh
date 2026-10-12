#!/usr/bin/env bash
# Purpose: pr-body writer（`swe-knowledge:pr-body`）改 PR 描述之前先過語言檢查：語言不符的
#          body 被擋，符合的通過。不呼叫 gh——擋的是送出去之前那一步。
# Inputs:  mktemp 底下的兩份 body；語言用 --language zh-TW 指定，不讀這台機器的設定。
# Outputs: 每一格一行 `✅` 或 `❌`。
# Exit:    0 全綠 / 1 有紅的 / 2 量不到

set -uo pipefail

GATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/polaris-external-write-gate.sh"
[[ -f "$GATE" ]] || { echo "UNMEASURABLE gate 不在：$GATE" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
printf '## 摘要\n\n這顆 PR 把描述裡的 commit 表換成聚合後的新 SHA，行為不變。\n' > "$WORK/zh.md"
printf '## Summary\n\nThis PR changes the commit table so it points at the new SHA after squashing the branch.\n' > "$WORK/en.md"

RED=0
check() {  # $1 = 名字, $2 = 期望離場碼, $3 = body 檔
  local rc=0
  POLARIS_EXTERNAL_WRITE_WRITER=swe-knowledge:pr-body \
    bash "$GATE" --surface pr-body --body-file "$3" --language zh-TW >"$WORK/out" 2>&1 || rc=$?
  if [[ "$rc" == "$2" ]]; then
    printf '  ✅ %s（exit %s）\n' "$1" "$rc"
  else
    printf '  ❌ %s：期望 exit %s，得到 %s\n' "$1" "$2" "$rc"; sed 's/^/     /' "$WORK/out"; RED=1
  fi
}

check "語言不符的描述被擋" 1 "$WORK/en.md"
check "語言符合的描述通過" 0 "$WORK/zh.md"
exit "$RED"
