#!/usr/bin/env bash
# Purpose: 一支探針怎麼解出「要量哪一棵樹」。**這一份是要被抄進探針裡的**——探針要先有根
#          才找得到這個檔案，所以它不能靠 source。這裡是那幾行的權威版本。
# Inputs:  $PWD（執行者給的工作目錄，由 run-hardened-oracle.sh --cwd 決定）；
#          $1 = 探針自己的位置（通常給 "${BASH_SOURCE[0]}"），只在前者走不到時才用。
# Output:  一行 repo 根路徑（帶著 .claude/skills 的那個目錄）。
# Exit:    0 解到了／2 兩條路都走不到——說出來，不猜一個。
#
# 起點為什麼是執行者給的工作目錄，不是探針自己的位置：探針住在 issues/，而 issues/ 巢在
# 主 checkout 底下。從探針自己往上走一定先撞到主 checkout，所以那一輪的程式碼在別的
# worktree 的時候它就量錯了樹——而訊息是「檔案不存在」，讀起來像交付壞了，不像量錯了
# 地方（DP-598 第二輪，五條判紅）。誰有資格說量哪一棵樹，答案是執行者。
#
# 為什麼不數固定層數：終局那幾格底下多一層日期資料夾，所以單一搬進 released/{日期}/，
# `../../../..` 就少一層、解到 issues/ 本身（DP-586 釋出後六條全紅）。往上走找
# .claude/skills 才停，深度就不參與。

probe_repo_root() {
  # Args: $1 = 探針自己的位置（可略）
  local fallback="${1:-}" dir start
  # 兩個起點都走 `pwd -P`：/var 與 /private/var 是同一個地方，而沒有正規化的話它們
  # 比起來不相等——「解到同一棵樹」會因為兩種寫法而判成兩棵。
  local starts=("$(pwd -P)")
  if [[ -n "$fallback" ]]; then
    start="$(cd "$(dirname "$fallback")" 2>/dev/null && pwd -P)" || start=""
    [[ -n "$start" ]] && starts+=("$start")
  fi
  for start in "${starts[@]}"; do
    dir="$start"
    while [[ -n "$dir" && "$dir" != "/" ]]; do
      if [[ -d "$dir/.claude/skills" ]]; then
        printf '%s\n' "$dir"
        return 0
      fi
      dir="$(dirname "$dir")"
    done
  done
  echo "POLARIS_PROBE_ROOT_UNRESOLVED" >&2
  echo "從執行者給的工作目錄（${PWD}）與探針自己的位置（${fallback:-沒給}）往上走，都沒有" >&2
  echo "找到帶著 .claude/skills 的目錄。這一趟不挑一個往下走——量錯樹的紅跟交付壞掉的紅" >&2
  echo "長得一模一樣。用 run-hardened-oracle.sh --cwd 指名要量哪一棵樹。" >&2
  return 2
}

# 直接跑這個檔案時把解出來的根印出來。A-P4／A-P5 量的就是它。
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  probe_repo_root "${1:-}"
fi
