---
title: "Bug Triage AC Fail Flow"
description: "bug-triage 處理 verify-AC [VERIFICATION_FAIL] Bug 的 feature-branch scoped investigation、artifact handoff 與 next-step routing。"
---

# AC-Fail Diagnosis Contract

這份 reference 處理 verify-AC 建立的 `[VERIFICATION_FAIL]` Bug。

## Parse Verification Block

從 ticket description 解析：

| Field | Use |
|---|---|
| source AC ticket | link context |
| Epic | locate related work orders |
| analysis branch | primary investigation surface |
| involved repos | scope |
| related task keys | work order context |
| related PR numbers | exact change set |
| feature branch commit range | bounded git log / diff scope |
| failed AC items | observed vs expected |
| reproduction conditions | URL, locale, viewport, fixtures |
| verification metadata | reference only |

分析對象是 feature branch，不是 develop/main。

## Scoped Explorer

派 Explorer sub-agent，prompt 只給 verify-AC 已確認的 facts。不要重跑 verify-AC 的驗證步驟。

Hard scope：

- branch from verification block
- listed repos
- listed PR diffs and commit range
- failed AC observed / expected
- reproduction conditions

Forbidden：

- `git blame` or author attribution。
- 擴大到 feature branch 以外。
- 將 spec issue 當 implementation bug 重判。

Explorer 目標：

1. 讀 handbook 了解架構。
2. 從 PR diff 與 feature branch code 找 observed behavior 產生點。
3. 對比 expected，分類為缺實作、實作錯、邊界條件漏、或依賴整合錯。
4. 提出最小修正範圍，限定在 feature branch fix path。

## Artifact

Explorer Detail 寫入 handoff artifact，格式依 `handoff-artifact.md`：

- frontmatter with skill, ticket, scope, timestamp, scrub flags
- Summary with Root Cause / Impact / Proposed Fix
- Raw Evidence with grep results, PR diff snippets, verification block, suspect code lines

寫入後必跑 scrub and cap；artifact path 回傳給 strategist。

## Handoff

AC-FAIL diagnosis 完成後，仍進 RD confirmation hard stop。確認後寫 JIRA RCA。

Handoff 要明確說明 engineering 後續 checkout feature branch，在上面開 fix branch；修完 merge
回 feature branch 後，使用 `verify-AC` full re-run。
