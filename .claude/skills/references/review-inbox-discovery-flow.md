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
| `extract-pr-urls.py` | Slack JSON -> PR URLs, PR-thread mapping, root ticket key mapping |
| `annotate-review-candidates.py` | attach sister PR cluster metadata and model tier hints |
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
Sub-agent 先試 Slack MCP 並指定 `concise` output format；timeout、auth error、unavailable
時改用 `slack-webapi.sh` fallback。Fallback `read-channel --oldest` 接受 Slack timestamp 或
ISO date/datetime，由 script 轉成 Slack timestamp。

Sub-agent pipeline：

1. 讀 channel messages。
2. 用 `extract-pr-urls.py` 產出 PR URLs 與 mapping。
3. 用 `fetch-prs-by-url.sh` 取得 metadata 並排除自己的 PR。
4. 用 `check-my-review-status.sh` 判定 review status。
5. 用 `annotate-review-candidates.py --mapping <mapping.json>` 補 `cluster_role`,
   `cluster_key`, `cluster_lead_url`, `model_tier`。
6. Completion Envelope 回傳 annotated candidates JSON、mapping JSON、PR count、raw URL count。

主 session 不讀 raw Slack JSON，只讀 filtered artifacts。

## Thread Scan

Thread mode 只讀單一討論串，訊息量通常小，可在主 session 直接執行同一條 pipeline。
所有 URL 都映射到指定 `thread_ts`。

## Sister PR Cluster And Model Tier Annotation

Discovery 結束後，所有來源都必須執行 `annotate-review-candidates.py`。Annotation rules：

- Cluster key = `(thread_ts, root_ticket_key || ticket_key)`。`extract-pr-urls.py` 從 Slack
  root message 的第一個 PR URL 前方擷取 umbrella ticket，例如 `GT-493`；沒有 root key
  時才 fallback 到 PR title / URL / repo 的 `KB2CW-NNN` 或通用 `PROJECT-NNN`。
- 同一 cluster 內按 `(repo, PR number)` 排序，第一筆是 `cluster_lead`，其餘是
  `cluster_sibling`。
- `cluster_lead` 使用 `standard_coding`，完整 review 並留下 lead summary。
- `cluster_sibling` 使用 `small_fast` model class hint 跑 sibling-diff mode；若行為差異或
  confidence 不足，輸出 `needs_standard_review` 讓主流程升級。
- 非 cluster PR 依 PR size/path 判斷 model tier：單檔且 additions+deletions <= 50，或全為
  asset/config/changeset-only 檔案時用 `small_fast`；其他用 `standard_coding`。

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
