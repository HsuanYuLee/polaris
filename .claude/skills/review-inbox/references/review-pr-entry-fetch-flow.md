---
title: "Review PR Entry Fetch Flow"
description: "review-pr 的 workspace config、Slack PR input、PR resolver、remote mode、fetch-pr-info script 與 large PR strategy 判定。"
---

# Review Entry Contract

這份 reference 負責 review 前的 PR input resolution 與 metadata fetch。

## Workspace Config

先讀 `workspace-config-reader.md`，取得：

- GitHub org。
- Slack notification channel when invoked from Slack。
- Company base directory。
- Workspace language fallback。

Config 不存在時，讀 `shared-defaults.md` fallback。

## Input Source

使用者直接提供 PR URL 或 PR number 時，解析成單一 PR。若輸入來自 Slack message，
依 `slack-pr-input.md` 擷取 PR URL，並保留 `slack_channel_id`、`slack_thread_ts`、
`slack_source` 供 submit 後通知。

若找到多個 PR，不在本 skill 批次處理，轉 `review-inbox`。

## PR Resolution

依 `pr-input-resolver.md` 解析 owner、repo、PR number、本地 project path。Review 是 read-only；
本地找不到 repo 時啟用 `remote_mode: true`，用 GitHub API 讀 PR branch 上的 files、rules、
與 diff。

後續所有 repo-relative paths 都以 resolver 結果為準，不用 hardcoded paths。

## Fetch PR Info

使用 bundled `fetch-pr-info.sh` 一次取得：

| Field | Use |
|---|---|
| repo, number, title, author | identity |
| base, head | diff and rules ref |
| file_count, additions, deletions | strategy decision |
| files | review target list |
| all_reviews | approval and re-review state |
| pushed_at | stale approval detection |
| review_strategy | single or batch |
| is_re_review | route to re-review flow |

Fetch output 是後續流程的 authoritative PR snapshot。若 review 前間隔太久，或使用者明確說
作者剛 push，重新 fetch。

## Strategy Decision

`is_re_review: true` 時進入 `review-pr-rereview-learning-flow.md`。

`review_strategy: single` 時直接 review full diff。

`review_strategy: batch` 時分組派 sub-agents。分組前排除 lock files、generated files、
純刪除檔。剩餘 files 依目錄與語意相關性分組，單組控制在可讀範圍。單一巨大檔案獨立一組。
