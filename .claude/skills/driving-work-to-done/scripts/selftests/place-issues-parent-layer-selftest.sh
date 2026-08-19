#!/usr/bin/env bash
# Purpose: 母單層的九條斷言（DP-551 A-P1~A-P5、A-N1~A-N4）各自被單獨量一次。
# Inputs:  無。自己在暫存目錄裡搭一棵假的單樹，注入一個假的解析器，不碰任何真的單、
#          不連任何外部系統。
# Outputs: 逐條印 `A-xx PASS`／`A-xx FAIL`。
# Exit:    0 九條全過 / 1 有任一條沒過
#
# 這支存在的理由是那個會靜靜發生的後果：多一層之後子單整批從判定裡消失，而看 diff 的人
# 看不出來——`place_issues_by_state.py` 自己記著同型的事故（「實測一次弄丟 100 張」），
# 而它的下游動作是真的去搬幾百個目錄。
set -euo pipefail
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/place_issues_parent_layer_selftest.py"
