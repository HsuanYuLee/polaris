#!/usr/bin/env bash
# Purpose: `next --across-issues` 涵蓋整棵樹的六條斷言（DP-558 A-P1~A-P3、A-N1~A-N3）各量一次。
# Inputs:  無。自己在暫存目錄裡搭一棵九張單的假樹，蓋掉「這張單的狀態在哪」的每一種答案，
#          不碰任何真的單、不連任何外部系統。
# Outputs: 逐條印 `A-xx PASS`／`A-xx FAIL`。
# Exit:    0 六條全過 / 1 有任一條沒過
#
# 這支存在的理由是一個已經發生過的、看 diff 看不出來的後果：2026-08-21 量到 `next
# --across-issues` 只涵蓋 700 張單裡的 555 張，差的 145 張（非終局格佔 121 張，含正在
# 進行的產品工作）不在任何一格、也不在任何一個數字裡；而同一次重算產出的 OPEN.md 逐張
# 列得出其中大部分。同一個問題有兩個答案，而少算的那一份看起來完全正常。
set -euo pipefail
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/next_across_issues_coverage_selftest.py"
