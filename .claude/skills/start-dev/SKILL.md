---
name: start-dev
description: >
  Transitions a JIRA ticket status to "In Development" when the developer is ready
  to start working on it. Use when: (1) user says "開始開發", "開工", "start developing",
  "start working on", (2) user specifies a JIRA ticket key and wants to begin development,
  (3) user says "開始 PROJ-123", "開工 PROJ-456". This skill handles only the status
  transition — for Epic breakdown and sub-task creation, use epic-breakdown instead.
metadata:
  author: Polaris
  version: 1.0.0
---

# Start Development — 轉狀態開工

當 RD 確認要開始開發某張 ticket 時，將該 ticket 狀態轉為 `In Development`。

## 前置：讀取 workspace config

讀取 workspace config（參考 `references/workspace-config-reader.md`）。
本步驟需要的值：`jira.instance`。
若 config 不存在，使用 `references/shared-defaults.md` 的 fallback 值。

## Workflow

### 1. 解析 Ticket Key

從使用者輸入中提取 JIRA ticket key（如 `PROJ-459`、`PROJ-1234`）。

### 2. 確認 Ticket 資訊

讀取 ticket 內容確認是正確的單：

```
mcp__claude_ai_Atlassian__getJiraIssue
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  issueIdOrKey: <ticket key>
```

簡要顯示 ticket summary，讓 RD 確認。

### 3. 轉換狀態

將 ticket 狀態轉為 `In Development`：

```
mcp__claude_ai_Atlassian__transitionJiraIssue
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  issueIdOrKey: <ticket key>
  transitionName: In Development
```

### 4. 確認結果

回報狀態轉換成功，並提示 RD 可以開始開發。

## 定位

這是一個輕量 skill，只做「JIRA 狀態轉換」這一件事。刻意與 `jira-branch-checkout`（建分支）分開，因為 RD 可能想先轉狀態但還不建分支（例如先確認開工再決定從哪個 branch 開）。

## 注意事項

- 如果 ticket 當前狀態無法轉換為 `In Development`（例如已在其他狀態），顯示可用的 transitions 讓 RD 選擇
- 此 skill 只負責狀態轉換，不涉及建立分支或其他開發流程


## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
