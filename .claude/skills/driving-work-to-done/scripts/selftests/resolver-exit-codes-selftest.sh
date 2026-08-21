#!/usr/bin/env bash
# Purpose: 「問不到」與「答不出來」是兩件事（DP-563 A-P1~A-P3、A-N1~A-N3）各量一次。
# Inputs:  無。解析器換成一支照要求收場的 stub，五種離場方式各一個，不連任何外部系統。
# Outputs: 逐條印 `A-xx PASS`／`A-xx FAIL`。
# Exit:    0 六條全過 / 1 有任一條沒過
#
# 這支存在的理由是一段自己取消掉自己的程式：`slot_from_resolver()` 的
# `if returncode != 0 or not answer:` 底下第二條 return 永遠到不了——解析器答不出來時用
# die() 收場，只寫 stderr，所以任何一種失敗的 stdout 都是空的。那一段自己的註解寫著
# 「exit 2 與 exit 1 是兩件事，報告上也必須是兩件事」，而它現在又是同一句了。
# 真實的樹上量過：「上游說沒有這張單」印出來是 `這次沒問到——上游說沒有這張單（回 404）`，
# 自相矛盾。
set -euo pipefail
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolver_exit_codes_selftest.py"
