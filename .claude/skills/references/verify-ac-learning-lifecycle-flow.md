---
title: "Verify AC Learning Lifecycle Flow"
description: "verify-AC 的 verify-ac-gap learning、post-task feedback reflection、re-verify trigger 與 opportunistic state-check surfacing。"
---

# Verify Learning Lifecycle Contract

這份 reference 負責驗收後的 learning 與 lifecycle signals。

## Verify-ac-gap Learning

每個 `MANUAL_REQUIRED` 或 `UNCERTAIN` step 都可累積一筆 learning，內容包含：

- AC ticket
- step id
- step description
- why automation could not assert it
- observed evidence
- source command or tool

同類案例累積三次後，提煉成可自動驗證 pattern，再更新 verify-AC references 或 scripts。

## Post-task Reflection

整輪 PASS / FAIL / PENDING 都要執行 post-task reflection。若 session 中有 command failure
self-correction、rerun、manual workaround，但沒有 feedback memory，提示反思。

此檢查是 advisory；behavioral write 仍依 `post-task-reflection-checkpoint.md`。

## Re-verify

verify-AC 是 stateless full re-run。觸發方式：

- 使用者明確說 `驗 {EPIC}` 或 `verify {AC_KEY}`。
- State-check skills 發現 feature branch task PRs 已 merge、AC tickets 仍 Open/FAIL、且沒有進行中
  bug-triage Bug，surface 建議驗收。

不做 webhook，不做 polling。

## Loop Escalation

verify-AC 和 bug-triage 來回三輪以上時，Strategist 介入檢查是否是架構問題、spec ambiguity、
fixture drift、或 hidden dependency，而不是繼續單點修 bug。
