#!/usr/bin/env bash
# Purpose: 單的目錄樹依歸屬分組的十條 assertion（DP-555 A-P1~A-P5、A-N1~A-N5）各自被單獨量一次。
# Inputs:  無。自己在暫存目錄裡搭一棵假的單的目錄樹，注入一個假的解析器，不碰任何真的單、
#          不連任何外部系統。
# Outputs: 逐條印 `A-xx PASS`／`A-xx FAIL`。
# Exit:    0 十條全過 / 1 有任一條沒過
#
# 這支存在的理由是那個會靜靜發生的後果：換一個路徑主軸之後子單整批從判定裡消失，而看
# diff 的人看不出來——`place_issues_by_state.py` 自己記著同型的事故（「實測一次弄丟 100
# 張」），而它的下游動作是真的去搬幾百個目錄。
set -euo pipefail
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/place_issues_ownership_selftest.py"
