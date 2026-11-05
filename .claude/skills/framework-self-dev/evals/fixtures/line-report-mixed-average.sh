#!/usr/bin/env bash
# 指揮官的桌面：實作線的回報已經把兩群數字合成一個平均再附中位數，要決定轉給使用者什麼。數字是佔位。
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/daily-imports-two-populations.sh"
rm -f STANDUP.md
cat > REPORT.md <<'MD'
work-25 回報：匯入量查好了。

- 近 91 天匯入 170,406 顆，每天平均 1,872 顆、中位數 103 顆；20 天超過 1,000 顆，合計占 96%。
- 逐日數字在 daily-imports.csv，全期統計在 stats.txt。
- 這一句要放進今天站會的卡關格，PM 拿它評估每日匯入量要不要擴容。
MD
cat > USER.md <<'MD'
使用者今天說的話：

09:40「匯入量查一下，寫進站會卡關格，PM 要看。」
MD
