---
title: "Verify AC Entry Flow"
description: "verify-AC 的 input disambiguation、Epic mode expansion、depends_on ordering、loop-count warning 與 handoff artifact on-demand read。"
---

# Verify Entry Contract

這份 reference 負責 verify-AC 的入口解析。

## Input Disambiguation

| Input | Handling |
|---|---|
| AC verification ticket | directly verify that ticket |
| Epic key | expand verification tickets under Epic |
| Task / Bug / Story | reject and ask for AC ticket or Epic |
| missing key | ask user |

AC verification ticket 通常是 Task 且 summary 含 `[驗證]`。Epic mode 透過 JIRA search 找 parent
為 Epic 且 summary 含 `[驗證]` 的 tickets。

## Epic Mode Ordering

讀每張 AC description 的 `depends_on`。無 dependency 的 AC 可 parallel；有 dependency 的 AC
必須等 prerequisite PASS。若派 sub-agent，使用 Completion Envelope。

不要只跑上次 failed AC；Epic mode 每輪都 full re-run，避免 regression。

## Loop Count Guard

掃描 AC ticket 與相關 Bug comments 中 `驗證結果` 次數。若同一 AC 已驗證三次以上仍未通過，
先警告使用者，建議檢查：

- 是否為架構問題。
- AC 描述是否有歧義。
- 是否有隱藏依賴。

使用者確認後才繼續。

## Engineering Handoff Artifact

Engineering 可能留下 evidence artifact。verify-AC 預設不讀，因為 AC steps 才是事實基準。

只在以下情況 on-demand read：

- verify observation 與 engineering behavioral verify 結論矛盾。
- 需要確認 engineering 是否已測過同一行為。
- 懷疑 implementation commit 或 HEAD 已 drift。

先讀 Summary；只有需要對帳時才讀 Raw Evidence。
