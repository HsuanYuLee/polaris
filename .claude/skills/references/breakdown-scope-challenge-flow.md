---
title: "Breakdown Scope Challenge Flow"
description: "breakdown advisory scope challenge：檢查 ticket 完整性、挑戰 scope、提出替代方案，不直接寫入。"
---

# Scope Challenge Flow

## Entry

使用者直接要求 `scope challenge`、`挑戰需求`、`challenge scope` 或 `需求質疑` 時啟用。
這是 advisory mode，預設不寫 JIRA、不建 task、不改 specs。

## Read Ticket

讀 ticket Summary / Description / AC / attachments / linked docs。若缺 key context，
先列出缺口並詢問，不用假設。

## Completeness Check

檢查：

- 需求目標是否明確。
- AC 是否可驗收。
- 使用者流程是否完整。
- API / data dependency 是否清楚。
- 是否需要跨 repo / infra / permission。
- 是否已有 refinement artifact 或 design decision。
- 是否有 hidden dependency 會讓估點失真。

## Challenge

從下列角度提出 challenge：

- Scope 是否過大，應拆 Epic / phase / prerequisite。
- 是否把探索、實作、驗收混在同一張。
- 是否有更小的 80/20 delivery。
- 是否有缺失決策應回 refinement。
- 是否有不該由 engineering 承擔的 baseline/env/product decision。

## Output

輸出：

- Missing information。
- Risk / ambiguity。
- Recommended scope adjustment。
- Alternative plan。
- Suggested next route：`refinement`、normal `breakdown`、或先補 PM/spec decision。

使用者明確要求落地後，才切回 Planning Flow 或 DP Intake Flow。
