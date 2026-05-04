---
title: "Verify AC Reporting Flow"
description: "verify-AC 的 overall verdict、JIRA wiki report、language gate、PASS transition、Epic implemented marking 與 PENDING handling。"
---

# Verify Reporting Contract

這份 reference 負責整體結論、JIRA report、transition。

## Overall Verdict

| Step Results | Overall |
|---|---|
| all PASS | PASS |
| any FAIL | FAIL |
| MANUAL_REQUIRED or UNCERTAIN and no FAIL | PENDING |

## JIRA Report

Verification report 使用 JIRA REST API v2 wiki markup，不使用 MCP markdown comment。Report
包含：

- date
- overall conclusion
- step table
- observed
- expected
- environment
- tools
- timestamp
- attachments when any

送出前把 final report 寫成 temp artifact，依 `workspace-language-policy.md` 或 external write
gate 驗證。引用 AC 原文、HTTP response、error message、多語系畫面文字可以保留原文，但主敘述
使用 workspace language。

## PASS

PASS 後透過 shared JIRA transition script 將 AC ticket 轉 Done。Transition 找不到、已 Done、
credential error、API error 時，不阻塞 verification report；surface 給使用者手動處理。

Epic mode 下，所有 AC tickets Done 時：

1. 回報 Epic 全部 AC 通過。
2. 執行 spec implemented marker，idempotent。

## PENDING

有 MANUAL_REQUIRED / UNCERTAIN 且無 FAIL 時，列出待人工判斷項目與 observation。

使用者確認全部 OK 後，可重新跑 verify-AC 讓該 AC 轉 PASS；若人工判斷有問題，走 FAIL
disposition。
