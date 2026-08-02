---
title: "Review Inbox Slack Reporting"
description: "review-inbox 的 Label summary、Slack/thread replies、GitHub-to-Slack user mapping、language gate 與 conversation summary。"
---

# Slack Reporting Contract

這份 reference 負責 review 完成後的 Slack 通知與對話摘要。

## Result Symbols

| Result | Symbol |
|---|---|
| `APPROVE` | check mark |
| `REQUEST_CHANGES` | cross mark |
| `COMMENT` | speech bubble |

每個 PR result line 必須附 approve threshold status，例如已達標或還需要幾位 reviewer。

## Label Source

Label source 發一則 channel summary 到 PR channel。內容按 repo 分組，包含：

- review date
- reviewer username
- PR link、title、author
- result
- one key must-fix summary when present
- approve status
- total reviewed count and result counts

## Slack Source

Slack source 不發 channel-wide summary。使用 discovery mapping 找回每個 PR 原始 thread，
並回覆到該 thread。

先依 `github-slack-user-mapping.md` 查 GitHub username -> Slack user ID。此 skill 可以使用
context match，因為 discovery 已讀過 PR channel messages。

依 `(thread_ts, author)` 分組；同一 thread 同一作者的多個 PR 合成一則 message。不同作者
分開發，避免 mention 錯人。

Thread reply 不得設定 `reply_broadcast: true`。

## Thread Source

Thread source 回覆使用者指定 thread。若同 thread 有多位作者，依作者分組多則回覆。

## Sending Method

優先使用 Slack MCP `slack_send_message`。MCP 失敗時，使用 `slack-webapi.sh send-message`
fallback；需要 token 與對應 Slack scopes。

每則 Slack message 送出前：

1. 將 final message 寫成 temp markdown artifact。
2. 執行 `validate-language-policy.sh --blocking --mode artifact <artifact>`.
3. 未通過就修正 message 並重跑；不可送出未通過 gate 的文字。

Message formatting 遵守 `slack-message-format.md`，尤其是 mrkdwn link、mention、長度限制。

## Conversation Summary

Slack 發送後，在對話中輸出完整摘要：

- 每個 PR 的 number、title、result。
- approve status。
- must-fix count when any。
- Label source：已發送 channel summary。
- Slack / Thread source：已回覆 N 則 thread，通知 M 位作者。

若 Slack notification 失敗，仍回報 review results，並列出未送出的 target threads 與 fallback
錯誤。
