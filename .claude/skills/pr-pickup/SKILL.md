---
name: pr-pickup
description: |
  Slack collaboration layer: extracts PR URLs from Slack messages, hands the PR
  over to be fixed, then reports back to the thread. Owns the Slack half only —
  it does not read review comments and does not modify code.
  Trigger: "pr-pickup", "pickup", Slack URL + PR intent ("pickup <slack_url>",
  "處理 <slack_url>", "同仁貼的 <slack_url>", "接這個 PR <slack_url>").
  NOT for: reviewing others' PRs (use review-pr), or fixing your own PR when
  nobody is waiting on a Slack thread — then just fix it, no relay needed.

  同仁在 Slack 貼了一個 PR 連結要人接手。例如「pickup <slack_url>」
  「處理 <slack_url>」「接這個 PR」。

  這支只管 Slack 那一半：抽出 PR、交出去修、修完回報那一串。它不讀 review comment、
  不改程式碼。

  不用於：review 別人的 PR（走 review-pr）、修自己的 PR 而且沒有人在 Slack 等
  （那就直接修）。
metadata:
  author: Polaris
  version: 1.0.0
scope: universal
---

# pr-pickup

從 Slack 訊息擷取 PR review 請求，把 PR 交出去修，完工後回 Slack thread 告知結果。

**職責邊界**：pr-pickup 只做協作傳遞（intake → 交付出去 → broadcast）。不讀 review comments、不改 code、不回覆 GitHub review。修 PR 這件事本身不歸它——那多半不用立案（改的是既有 assertion 底下的做法），直接修；若連成功的定義都要改，那是 `refinement` 的事。
它的 shared authority 應收斂在 intake artifact，而不是 prose 解析。Slack/PR 輸入的 canonical
解析結果由 `$SKILL_DIR/scripts/resolve-pr-pickup-input.sh` 定義；skill 只消費該 artifact，不能再手工
各寫一套 PR URL / thread context 判斷。

## 前置：讀取 workspace config

讀取 workspace config（參考 `workspace-config.yaml`）。
本步驟需要的值：`github.org`、`slack.channels.ai_notifications`。
若 config 不存在，使用 `workspace-config.yaml`（讀不到就用預設） 的 fallback 值。

## Bundled Authority

| Script | Role |
|---|---|
| `$SKILL_DIR/scripts/resolve-pr-pickup-input.sh` | canonical intake resolver：統一解析 direct PR URL、Slack URL、Slack thread context、以及 thread-derived PR URLs |

## 流程總覽

```
Step 0: 前置 config
Step 1: 解析 Slack 輸入 → PR URL + thread context
Step 2: 把 PR 交出去修 → 同步等待完成
Step 3: 根據結果組 Slack 回覆訊息
Step 4: 回 Slack thread
```

---

## Step 1: 解析 Slack 輸入

先跑 shared intake resolver，而不是手工解析：

```bash
"$SKILL_DIR/scripts/resolve-pr-pickup-input.sh" \
  --input "$USER_INPUT" \
  --allow-empty-prs \
  --format json
```

若 resolver 回傳 `needs_slack_thread_read=true`，再依 `references/slack-pr-input.md` 讀取
Slack thread，然後用同一支 script 完成第二階段解析：

```bash
"$SKILL_DIR/scripts/resolve-pr-pickup-input.sh" \
  --input "$USER_INPUT" \
  --org "$GITHUB_ORG" \
  --slack-thread-file "$SLACK_THREAD_EXPORT" \
  --format json
```

後續 Step 2-4 一律只吃這個 intake artifact，不再自行從原始訊息重解析 PR URL / thread context。

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

這三個欄位應來自 `resolve-pr-pickup-input.sh` 的 JSON output，不是由 skill prose 再重建。

### 1c. 錯誤處理：無法解析 PR URL

若 Slack 訊息中找不到 GitHub PR URL（`github.com/{org}/{repo}/pull/{n}` 格式）：

1. 回覆 Slack thread：「無法從訊息中解析出 PR URL，請確認訊息中包含 GitHub PR 連結。」
2. 告知使用者並結束流程。

若 resolver 的第一階段只得到 Slack context、尚未得到 PR URL，這不算最終失敗；必須先完成
Slack thread read，再用第二階段 resolver 嘗試取得 PR URLs。只有第二階段仍 `pr_count=0`
時，才算真正的 `no_pr_url` fail-stop。

### 1d. 多 PR 處理

若偵測到多個 PR URL，為每個 PR 依序執行 Step 2-4（不平行——修 PR 是重量級操作，同步一個一個跑較穩定）。收集所有結果後在 Step 4 統一回覆。
多 PR 清單以 intake artifact 的 `pr_urls[]` 為唯一權威；不得再從 Slack raw text 自行增減。

---

## Step 2: 把 PR 交出去修

同步處理這個 PR：讀 review comments、改 code、回覆 GitHub review、push。這一段不是
pr-pickup 的職責，但它要**等**——回 Slack 之前必須知道結果。

修 PR 通常**不用立案**：review comments 改的是既有 assertion 底下的做法，成功的定義沒變。
只有在 review 指出「成功的定義本身錯了」時才停下來走 `refinement` 重簽。

### 2a. 可能的結果

| 結果 | 含義 |
|------|------|
| **成功完成** | 已修正並 push；pr-pickup 只轉述 PR 的實際狀態，不自行判定「可 merge / 可 release」 |
| **成功的定義要改** | review 指出的問題在 assertion 層，不在做法層——停下來，回 `refinement` |
| **失敗** | 其他原因（build 失敗、環境問題等） |

---

## Step 3: 組 Slack 回覆訊息

根據 Step 2 結果，組裝對應的 Slack 回覆訊息。

### 成功完成

```
:white_check_mark: *PR Review 已處理*

<{pr_url}|#{number} {title}>

{修正摘要}

已修正並 push，請 reviewer re-review。是否實際 merge 由 reviewer / owner 決定。
```

### 成功的定義要改

```
:no_entry: *這個 PR 卡在 assertion 層，不是做法層*

<{pr_url}|#{number} {title}>

*原因*: {為什麼 review 指出的問題不能靠改做法解決}

:point_right: *下一步*: 回 `refinement` 重簽成功的定義，簽完再修。
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
- Do: 只轉述 PR 的實際狀態，不自行發明 `ready` / `done` / `release complete`
- Don't: 讀 PR review comments（那不是協作傳遞層的事）
- Don't: 修改任何 code（那不是協作傳遞層的事）
- Don't: 回覆 GitHub review comments（那不是協作傳遞層的事）
- Don't: 做 lesson 萃取（那不是協作傳遞層的事）
- Don't: 跑 quality check（那不是協作傳遞層的事）

---

## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

