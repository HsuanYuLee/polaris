#!/usr/bin/env bash
# Purpose: 搬動順序與「沒搬成」的五條斷言（DP-561 A-P1~A-P3、A-N1~A-N2）各量一次。
# Inputs:  無。自己在暫存目錄裡搭一棵假的單的目錄樹，注入一個假的解析器，不碰任何真的單、
#          不連任何外部系統。
# Outputs: 逐條印 `A-xx PASS`／`A-xx FAIL`。
# Exit:    0 五條全過 / 1 有任一條沒過
#
# 這支存在的理由是一個已經發生過的、看 diff 看不出來的後果：2026-08-21 對真實單的目錄樹跑一次
# 遷移，遷移前 0 組同號重複、遷移後 12 組，而那一次的報告寫著「搬了 0 張，原本就在對的
# 位置的 710 張」。搬動的順序錯了，一張單的目的地被它自己的子單先造出來，於是它被安靜
# 地跳過——內容留在舊路徑，新路徑只剩一個空殼。
set -euo pipefail
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/place_issues_move_order_selftest.py"
