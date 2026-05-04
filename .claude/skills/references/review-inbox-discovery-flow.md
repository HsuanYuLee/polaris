---
title: "Review Inbox Discovery Flow"
description: "review-inbox 的 Label、Slack、Thread discovery、bundled scripts、review_status 判定與 scan freshness 規則。"
---

# Discovery Contract

這份 reference 負責找出需要自己 review 的 PR candidates。

## Defaults

從 workspace config 與 `shared-defaults.md` 取得：

| Value | Use |
|---|---|
| GitHub org | restrict PR URLs and repo scans |
| Slack PR channel | Slack mode scan source and notification target |
| need review label | Label mode |
| approval threshold | approve status summary |
| batch size | maximum PRs reviewed this run |
| concurrency | parallel review sub-agent count |
| confirm | list-only confirmation behavior |

Current GitHub username 必須動態取得，並排除自己的 PR。

## Bundled Scripts

使用 skill bundled scripts 做 deterministic discovery，不手動組 API query：

| Script | Purpose |
|---|---|
| `scan-need-review-prs.sh` | org-wide need review label scan |
| `fetch-prs-by-url.sh` | PR URLs -> PR metadata |
| `check-my-review-status.sh` | attach `review_status` and filter irrelevant PRs |
| `extract-pr-urls.py` | Slack JSON -> PR URLs and PR-thread mapping |
| `slack-webapi.sh` | Slack MCP fallback for read and send |

Script path 以 skill directory 為準。

## Source Selection

Thread mode 優先：使用者訊息含 Slack URL 且有 review intent。從 URL 解析 channel ID 與
thread timestamp；若 URL 不是 thread link，將 message timestamp 當作 thread root。

Label mode：只有使用者明確提到 `need review` label、`review inbox`、或 label scan 才使用。

Slack mode：其他 batch review intent 的預設來源，從 PR channel 最近訊息提取 PR URLs。
時間範圍依使用者語意推導；未指定時用 7 天。

## Slack Channel Scan

Slack mode 的 channel scan 應委派給 sub-agent，避免 100+ raw Slack messages 進主 context。
Sub-agent 先試 Slack MCP；timeout、auth error、unavailable 時改用 `slack-webapi.sh` fallback。

Sub-agent pipeline：

1. 讀 channel messages。
2. 用 `extract-pr-urls.py` 產出 PR URLs 與 mapping。
3. 用 `fetch-prs-by-url.sh` 取得 metadata 並排除自己的 PR。
4. 用 `check-my-review-status.sh` 判定 review status。
5. Completion Envelope 回傳 candidates JSON、mapping JSON、PR count、raw URL count。

主 session 不讀 raw Slack JSON，只讀 filtered artifacts。

## Thread Scan

Thread mode 只讀單一討論串，訊息量通常小，可在主 session 直接執行同一條 pipeline。
所有 URL 都映射到指定 `thread_ts`。

## Review Status

Candidates 只保留：

| Status | Meaning |
|---|---|
| `needs_first_review` | reviewer 尚未 review |
| `needs_re_approve` | approve 後作者有新 commit，approval stale |
| `needs_re_review` | REQUEST_CHANGES 後作者已回覆 comments |

`valid_approve` 與 `waiting_for_author` 必須被過濾。Stale approval 判定見
`stale-approval-detection.md`。

## Scan Freshness

Scan 是 point-in-time snapshot。每次 show list 或開始 review 前，檢查 scan result mtime。
若距離現在超過 60 秒，必須重跑 discovery；不可沿用舊 candidates JSON。
