---
title: "Learning Setup Flow"
description: "learning Setup mode 的 daily learning scanner 設定、RemoteTrigger 建立與 Slack connector 授權流程。"
---

# Setup Mode Flow

這份 reference 是 `learning/SKILL.md` Setup mode 的延後載入流程。當使用者要求
設定、更新、測試或停用 daily learning scanner 時讀取。

## Step S1: Check Existing Scanner

使用 `RemoteTrigger list` 檢查既有 daily-learning-scan trigger（名稱包含
`daily-learning-scan`）。

If found and enabled:

```text
目前已有 daily learning scanner：
- Trigger: {name} ({trigger_id})
- 排程: {cron_expression}
- 狀態: enabled

要更新設定還是停用？(更新 / 停用 / 取消)
```

- 更新 -> 繼續 Step S2。
- 停用 -> `RemoteTrigger update` -> `{"enabled": false}`，完成後停止。
- 取消 -> 停止。

若沒有找到，或 trigger 已停用，繼續 Step S2。

## Step S2: Collect Preferences

盡量先自動偵測，再讓使用者確認或調整。

### 2a. Slack Channel

依 `workspace-config-reader.md` 讀取 company `workspace-config.yaml`，取得
`slack.channels.ai_notifications`。

若找到 channel，顯示並確認。若找不到，詢問 channel ID 或名稱；使用者提供名稱時，
用 Slack channel search 解析成 channel ID。

### 2b. Tech Stack

讀取 company `workspace-config.yaml` 的 `projects` block。每個 project 從
`tags`、`keywords`、`tech_stack` 欄位萃取 tech stack，並顯示偵測結果：

```text
從 workspace config 偵測到的技術棧：
  Nuxt 3, Vue 3, TypeScript, Vitest, Turborepo, Docker

要調整嗎？（直接 Enter 確認，或輸入修改版）
```

若沒有 workspace config 或找不到 tags，請使用者手動輸入。

### 2c. Active Repos

從同一個 `projects` block 萃取 repo 名稱與 tech stack：

```text
偵測到的 repos：
  my-app (Nuxt 3, SSR, TypeScript)
  my-api (Node, Express)
  web-design-system (Vue 3)

要調整嗎？（直接 Enter 確認，或輸入修改版）
```

### 2d. Custom Topics

```text
有特別想關注的主題嗎？（選填）
例如：SSR performance, testing patterns, AI code review

直接輸入，或 Enter 跳過：
```

### 2e. Schedule

```text
掃描排程？（預設：每天 21:57，cron: 57 13 * * *）
直接 Enter 用預設，或輸入自訂 cron expression：
```

## Step S3: Assemble Trigger Prompt

先讀 `daily-learning-scan-spec.md` 取得 template 結構。

依使用者偏好組裝 RemoteTrigger prompt：

1. AI/Agent searches，永遠包含：
   - `Claude Code tips tricks {year}`
   - `Claude Code MCP server tutorial`
   - `AI coding agent workflow patterns {year}`
   - `multi-agent orchestration LLM {year}`
   - `AI-assisted development best practices`
2. Step S2b 的 tech stack searches：
   - 每個 tech 產生 1-2 個 search queries。
   - 例如 tech 是 `Nuxt` 時，產生 `Nuxt 4 performance optimization` 與 `Nuxt SSR best practices {year}`。
3. 若 Step S2d 有 custom topics，加入 custom topic searches。
4. Step S2c 的 repo tagging rules：
   - 建立 topic -> repos mapping table。
5. Step S2a 的 Channel ID，直接寫入 prompt。
6. Dedup:
   - Prompt 從 repo 讀 `learning-archive.md`；找不到則略過。

Prompt 必須：

- 使用 `slack_send_message` 發送到 channel。
- 遵守 `daily-learning-scan-spec.md` 的 Slack message format。
- 不 commit、不 push。
- 包含完整 search queries，不能只寫「read the spec」。
- Slack 發送前先跑 workspace language policy gate。見
  `workspace-language-policy.md`；將 final digest 寫入 temp markdown 後執行
  `bash scripts/validate-language-policy.sh --blocking --mode artifact <learning-digest.md>`.

## Step S4: Create RemoteTrigger

1. 若是更新，先用 `RemoteTrigger update` -> `{"enabled": false}` 停用舊 trigger。
2. 從 git remote 判斷 workspace repo URL。
3. 建立新 trigger：

```text
RemoteTrigger create:
  name: daily-learning-scan-v{N}
  cron_expression: {from Step S2e}
  model_class: standard_coding
  allowed_tools: Read, Glob, Grep, WebSearch, WebFetch, mcp__claude_ai_Slack__slack_send_message
  sources: [{workspace_repo_url}]
  mcp_connections: [{connector_uuid: "Slack connector UUID", name: "Slack", url: "https://mcp.slack.com/mcp"}]
  prompt: {assembled prompt from Step S3}
```

Slack connector 注意事項：

- `mcp_connections` 必須包含 Slack connector，否則 remote agent 無法發送訊息。
- Slack connector 需要使用者至少在 Anthropic 授權過一次 Slack。
- 永遠顯示首次授權提示，因為 setup flow 無法偵測是否已授權：

```text
首次設定需要手動授權 Slack connector（只需一次）：

1. 到 claude.ai/code/scheduled
2. 找到剛建立的 daily-learning-scan trigger
3. 點 Schedule 區塊 -> Connectors -> Add connector -> 選 Slack
4. 完成 OAuth 授權 -> Save

授權一次後，之後的 setup 都會自動帶上，不需要再手動設定。
```

4. 確認 trigger 建立結果、trigger ID 與下次執行時間。

## Step S5: Test Run

詢問：

```text
Scanner 已建立。要現在試跑一次嗎？(y/n)
```

若使用者同意，執行 `RemoteTrigger run`，再請使用者檢查 Slack queue message。

## Step S6: Summary

```text
Daily Learning Scanner 設定完成

- Trigger: {name} ({trigger_id})
- 排程: {cron_expression} ({human readable time})
- Slack Channel: {channel_name or ID}
- 技術棧: {tech stack}
- 自訂主題: {custom topics or "無"}

每天會自動掃描文章推薦到 Slack。
用 `每日學習` 消化推薦文章，用 `learning setup` 更新設定。
```
