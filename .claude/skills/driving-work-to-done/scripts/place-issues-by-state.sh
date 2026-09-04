#!/usr/bin/env bash
# Purpose: 把每一張單放到它的狀態說的那一格（backlog / in-progress / in-review / done /
#          released/{日期} / triage），並把推導結果寫回 {單}/.spine/placement.json。
# Inputs:  --issues <path>（issues 根目錄）、--check（只報落差，有落差 exit 1）、
#          --execute（寫回紀錄並把搬得動的搬過去；預設只看不動）
# Outputs: 六格各自的數量、位置與狀態對不上的清單、落 triage/ 的逐張理由。
# Exit:    0 一致 / 1 --check 有落差 / 2 根不對、樹是空的
#
# 位置是狀態的投影，不是第二個權威。這支是**唯一**知道版面長什麼樣的地方——其餘消費端一律
# 讀 placement.json，不從路徑推導意思。以前有四個地方各自用 glob 樣式猜「一張單可以住在
# 哪裡」，多開一格資料夾就要改四處，而漏掉的那一處不會爆炸，只會安靜地少算。
set -euo pipefail
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/place_issues_by_state.py" "$@"
