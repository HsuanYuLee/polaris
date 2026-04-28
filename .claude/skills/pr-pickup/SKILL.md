---
name: pr-pickup
description: >
  Slack collaboration layer: extracts PR URLs from Slack messages and dispatches
  to engineering revision mode. Does NOT modify code — all code changes, GitHub
  review replies, and lesson extraction are engineering's responsibility.
  Trigger: "pr-pickup", "pickup", Slack URL + PR intent ("pickup <slack_url>",
  "處理 <slack_url>", "同仁貼的 <slack_url>", "接這個 PR <slack_url>").
  NOT for: reviewing others' PRs (use review-pr), first-cut implementation
  (use engineering directly), fixing your own PR without Slack context
  (use engineering with ticket key or PR URL directly).
metadata:
  author: Polaris
  version: 1.0.0
---

# pr-pickup

從 Slack 訊息擷取 PR review 請求，dispatch 給 engineering revision mode 處理，完工後回 Slack thread 告知結果。

**職責邊界**：pr-pickup 只做協作傳遞（intake → dispatch → broadcast）。不讀 review comments、不改 code、不回覆 GitHub review、不做 lesson 萃取——這些全部由 engineering revision mode 負責。

## 前置：讀取 workspace config

讀取 workspace config（參考 `references/workspace-config-reader.md`）。
本步驟需要的值：`github.org`、`slack.channels.ai_notifications`。
若 config 不存在，使用 `references/shared-defaults.md` 的 fallback 值。

## 流程總覽

```
Step 0: 前置 config
Step 1: 解析 Slack 輸入 → PR URL + thread context
Step 2: Skill tool 呼叫 engineering（傳 PR URL）→ 同步等待完成
Step 3: 根據 engineering 結果組 Slack 回覆訊息
Step 4: 回 Slack thread
```

---

## Step 1: 解析 Slack 輸入

依 `references/slack-pr-input.md` 的流程從使用者輸入中擷取 PR URL。

### 1a. 輸入型態

| 輸入 | 處理 |
|------|------|
| Slack URL（`*.slack.com/archives/*`） | 讀取 Slack thread，提取 PR URL |
| 直接的 PR URL + Slack context 提示 | 使用 PR URL，從提示中取得 Slack thread 資訊 |
| 純文字無 PR URL | → Step 1c 錯誤處理 |

### 1b. 保留 Slack Context

記住以下資訊供 Step 4 使用：
- `slack_channel_id`：頻道 ID
- `slack_thread_ts`：訊息 timestamp（依 `references/slack-pr-input.md` 的 `p` 參數轉換規則）
- `slack_source`: `true`

### 1c. 錯誤處理：無法解析 PR URL

若 Slack 訊息中找不到 GitHub PR URL（`github.com/{org}/{repo}/pull/{n}` 格式）：

1. 回覆 Slack thread：「無法從訊息中解析出 PR URL，請確認訊息中包含 GitHub PR 連結。」
2. 告知使用者並結束流程。

### 1d. 多 PR 處理

若偵測到多個 PR URL，為每個 PR 依序執行 Step 2-4（不平行——engineering revision mode 是重量級操作，同步一個一個跑較穩定）。收集所有結果後在 Step 4 統一回覆。

---

## Step 2: Dispatch engineering revision mode

使用 Skill tool 同步呼叫 engineering，傳入 PR URL：

```
Skill("engineering", "<PR_URL>")
```

engineering 進入 revision mode（依 engineering SKILL.md Step 0 mode detection），同步執行完成後回傳結果。

### 2a. engineering 可能的回傳結果

| 結果 | 含義 |
|------|------|
| **成功完成** | code drift 已修正、已通過驗證、已回覆 reviewer、已 push |
| **退回 breakdown** | plan gap — 施工圖有漏洞，需退回上游重新規劃（D3） |
| **退回 refinement** | spec issue — AC 本身有問題，需退回需求釐清（D3） |
| **硬擋（無 task.md）** | PR 沒有新版 task.md，需先跑 bug-triage 或 breakdown 補 work order |
| **失敗** | 其他原因（build 失敗、環境問題等） |

---

## Step 3: 組 Slack 回覆訊息

根據 Step 2 結果，組裝對應的 Slack 回覆訊息。

### 成功完成

```
:white_check_mark: *PR Review 已處理*

<{pr_url}|#{number} {title}>

{engineering 回傳的修正摘要}

已修正並 push，請 reviewer re-review。
```

### 退回 breakdown / refinement（plan gap / spec issue）

```
:no_entry: *PR 需退回上游規劃*

<{pr_url}|#{number} {title}>

*原因*: {engineering 回傳的 classification 理由}
*退回層級*: {breakdown / refinement}

:point_right: *下一步*: 執行 `/breakdown {TICKET}` 或 `/refinement {TICKET}` 補強施工圖後重新進入 engineering。
```

### 硬擋（無 task.md）

```
:no_entry: *PR 無 task.md，無法進入 revision mode*

<{pr_url}|#{number} {title}>

此 PR 沒有對應的新版 task.md。

:point_right: *下一步*: Bug 執行 `/bug-triage {TICKET}`，Story/Task/Epic 執行 `/breakdown {TICKET}`，建立 `specs/{EPIC}/tasks/T*.md` 後再重新觸發 engineering。
```

### 失敗

```
:warning: *PR 處理失敗*

<{pr_url}|#{number} {title}>

*原因*: {失敗描述}

需要人工介入處理。
```

---

## Step 4: 回 Slack thread

使用 `slack_send_message` MCP tool 回覆原始 thread：

```
slack_send_message({
  channel_id: "<slack_channel_id>",
  thread_ts: "<slack_thread_ts>",
  text: "<Step 3 組裝好的訊息>"
})
```

**重要**：必須帶 `thread_ts` 回覆在原始訊息的 thread 中，不要發成獨立訊息。

若 Step 1d 偵測到多個 PR，將所有結果合併成一則訊息回覆。

---

## Do / Don't

- Do: 嚴守協作層職責——只做 intake / dispatch / broadcast
- Do: 完整保留 Slack context（channel_id, thread_ts）供回覆使用
- Do: 回覆時明確標示狀態（成功/退回/硬擋/失敗）和下一步指引
- Don't: 讀 PR review comments（那是 engineering 的事）
- Don't: 修改任何 code（那是 engineering 的事）
- Don't: 回覆 GitHub review comments（那是 engineering 的事）
- Don't: 做 lesson 萃取（那是 engineering 的事）
- Don't: 跑 quality check（那是 engineering 的事）

---

## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
