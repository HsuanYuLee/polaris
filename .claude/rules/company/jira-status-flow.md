---
description: JIRA 狀態流轉規則，操作 JIRA ticket 狀態轉換時載入
---

# JIRA 狀態流轉

## 主要流程

```
開放 → IN DEVELOPMENT → CODE REVIEW → WAITING FOR QA → QA TESTING → WAITING FOR STAGE → REGRESSION → WAITING FOR RELEASE → 已釋出
```

## AI 自動轉換的狀態

| 時機 | 自動轉換 | 觸發 Skill |
|------|----------|-----------|
| RD 說「開始開發」後 | 開放 → **IN DEVELOPMENT** | your-company-start-dev |
| PR 建立後 | IN DEVELOPMENT → **CODE REVIEW** | git-pr-workflow |

其餘狀態轉換（包含轉 WAITING FOR QA）由 RD 或 QA 手動操作。

## 所有狀態說明

| 狀態 | 說明 |
|------|------|
| **開放** | 新建立的 ticket，尚未開始處理 |
| **SA/SD** | 進行 Review 以及設計開發階段（從「開放」轉入） |
| **DISCUSS** | 需要討論的議題（任何狀態皆可轉入） |
| **IN DEVELOPMENT** | 開發中（從「開放」開始開發，或從「SA/SD」開始開發） |
| **CODE REVIEW** | 程式碼審核中（從「IN DEVELOPMENT」轉入） |
| **WAITING FOR QA** | 已通知送測，等待 QA 開始測試 |
| **QA TESTING** | QA 正在 SIT 環境進行測試 |
| **WAITING FOR STAGE** | 通過 SIT 測試，等待封版部署到 Stage |
| **REGRESSION** | 在 Stage 環境進行回歸測試 |
| **WAITING FOR RELEASE** | 回歸測試通過，等待上線 |
| **已釋出** | 已上線完成 |
| **完成** | 任務完成（子任務開發完畢、討論結束等情境） |
| **PENDING** | 暫緩處理（從「開放」轉入，可重啟回「開放」） |
| **已關閉** | 不處理（從「PENDING」轉入） |

## 必填欄位

> **Config 優先**：欄位 ID 和值定義在公司 config 的 `jira.custom_fields.requirement_source`（參考 `references/workspace-config-reader.md`）。

轉換狀態為 IN DEVELOPMENT 時，JIRA 要求填入「需求來源」欄位：

| 單據類型 | 需求來源值 |
|---------|-----------|
| 優化重構單（tech debt、refactor、AI 設定等） | `Tech - maintain`（id: `13478`） |
| Bug 修復 | `Tech - bug`（id: `13479`） |
| 其他類型 | 依單據描述或詢問使用者 |

> 欄位 ID：`customfield_10534`。需先用 `editJiraIssue` 設定此欄位，再用 `transitionJiraIssue` 轉狀態（transition screen 不含此欄位）。

## 狀態轉換細節

**正常開發流程：**

- 開放 →（開始開發）→ IN DEVELOPMENT 🤖 _自動轉換_
- 開放 →（進行 Review 以及設計開發）→ SA/SD →（開始開發）→ IN DEVELOPMENT
- IN DEVELOPMENT →（程式碼審核）→ CODE REVIEW 🤖 _自動轉換_
- CODE REVIEW →（通知送測）→ WAITING FOR QA 👤 _RD 手動操作_
- WAITING FOR QA →（開始測試）→ QA TESTING
- QA TESTING →（通過 SIT 測試待封版）→ WAITING FOR STAGE
- WAITING FOR STAGE →（進行回歸測試）→ REGRESSION
- REGRESSION →（待上線）→ WAITING FOR RELEASE
- WAITING FOR RELEASE →（已上線）→ 已釋出

**特殊路徑：**

- IN DEVELOPMENT →（回朔）→ 開放（需求有變或需要重新評估）
- IN DEVELOPMENT →（子任務開發完畢）→ 完成（子票完成時）
- CODE REVIEW →（開發單的子票 code review 通過後就算開發完畢）→ 完成
- WAITING FOR QA →（設定檔 or 不影響需求的東西上線）→ WAITING FOR RELEASE（跳過 QA 測試）
- SA/SD →（討論結束）→ 完成
- DISCUSS →（討論結束票也結束）→ 完成
- 開放 →（重啟議題）→ PENDING →（不處理）→ 已關閉
