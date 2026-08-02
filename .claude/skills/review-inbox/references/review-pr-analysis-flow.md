---
title: "Review PR Analysis Flow"
description: "review-pr 的 rules/handbook 讀取、既有 comments 去重、large PR sub-agent analysis、review dimensions 與 severity calibration。"
---

# Review Analysis Contract

這份 reference 負責實際 code review analysis。

## Standards Loading

讀取 repo `.claude/rules/`。Local mode 從本地 repo 讀；remote mode 從 PR branch 透過
GitHub API 讀。Rules 不存在時，仍可用通用 review dimensions，但不得假裝有 project rule。

Repo handbook 是 primary standard。若 company handbook 存在，讀 `index.md` 與相關子檔。
符合 handbook 的 pattern 不應被 flag；違反 handbook 的 pattern 應指出。

## Existing Comments Dedup

Review 前讀取 PR existing inline comments 與 review bodies，建立「已指出問題清單」。

去重規則：

| Situation | Action |
|---|---|
| same file, same location, same semantic issue | skip |
| same pattern already raised elsewhere | skip unless impact is materially worse |
| previous reviewer analysis is wrong or incomplete | comment only on missing/corrected angle |
| new issue | comment normally |

AI review 的價值是找到尚未指出的問題，不是重複附和。

## Single Review

對每個 changed file 讀完整檔案與 diff。Remote mode 用 GitHub API 讀 PR branch content。

Review dimensions：

- correctness and edge cases
- type safety
- project rules and handbook compliance
- security
- performance
- maintainability
- accessibility
- cross-file consistency
- PR description vs code consistency
- tests or docs coverage when relevant

新增元件、API、test、composable、store 時，查看 1-2 個同類型既有實作，校準 local pattern。

## Batch Review

Large PR 的每組 files 派 sub-agent analysis。Prompt 必須包含 PR metadata、rules、
handbook、assigned files、diff、dedup list、severity definitions、project root 或 remote read
instruction、Completion Envelope。

Sub-agent 只回傳 JSON findings 與 summary，不提交 GitHub review、不修改檔案、不 review
未分配 files。

主 session fan-in comments，去重後進 submit flow。

## Severity Calibration

| Severity | Use |
|---|---|
| `must-fix` | code 可直接證明會 bug、安全漏洞、型別錯誤、或違反關鍵規範 |
| `should-fix` | 不一定破功能，但違反規範、可維護性、或需要作者確認 |
| `nit` | style or minor clarity，不影響功能或規範 |

API payload key、外部 service behavior、language/library behavior、framework defaults 等，未當場用
source code、official docs、或 executable check 驗證前，最多是 `should-fix`。

不要把個人風格偏好標成 `must-fix` 或 `should-fix`。
