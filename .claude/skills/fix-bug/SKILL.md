---
name: fix-bug
description: "Use when the user wants to fix a bug reported in JIRA from start to PR. Trigger: 幫我修正, 'help me fix', 修 bug, 'fix bug', 開始修正, 'start fixing', 修正這張, 'fix this ticket'. NOT for fixing PR review comments (use fix-pr-review)."
metadata:
  author: Polaris
  version: 1.2.0
---

# Fix Bug — 端到端 Bug 修正流程

將 JIRA Bug 單從「讀單」到「發 PR」串接為一個完整流程，不需手動分段觸發各個 skill。

## 前置：讀取 workspace config

讀取 workspace config（參考 `references/workspace-config-reader.md`）。
本步驟需要的值：`jira.instance`。
若 config 不存在，使用 `references/shared-defaults.md` 的 fallback 值。

## 觸發判斷

| 使用者輸入 | 應觸發的 skill |
|-----------|---------------|
| `幫我修正 PROJ-432` / `修 bug PROJ-432` / `fix bug PROJ-432` | **fix-bug**（本 skill） |
| `幫我修正` + GitHub PR URL | fix-pr-review（不是本 skill） |
| `修正 review` / `fix review` + PR URL | fix-pr-review（不是本 skill） |

**關鍵判斷：看使用者提供的是 JIRA ticket key 還是 GitHub PR URL。**

## Workflow

### Step 1：讀取 JIRA 單 → 確認專案

從使用者輸入中提取 JIRA ticket key（如 `PROJ-432`、`PROJ-1234`）。

```
mcp__claude_ai_Atlassian__getJiraIssue
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  issueIdOrKey: <ticket key>
```

讀取後：
1. 顯示 ticket summary + description 摘要，讓 RD 確認是正確的單
2. 依 CLAUDE.md 的「專案 Mapping」表對應到本地專案路徑
3. 如果 ticket 沒有描述開發路徑（path），提示使用者並根據關鍵字推測，詢問確認

確認專案後 cd 到該專案目錄。

### Step 2：分析根因 + 估點

**⚠️ MUST 用 Skill tool invoke `jira-estimation`。** 這個步驟不可跳過、不可自己做 inline 分析替代。

```
Skill: jira-estimation
Args: <ticket key>
```

`jira-estimation` 對 Bug 類型會：
- 分析 [ROOT_CAUSE] + [SOLUTION]
- 以 comment 留在 JIRA ticket 上
- 更新 ticket 的 story points

❌ **NEVER** 自己在對話中分析 root cause 就直接往下走。[ROOT_CAUSE] + [SOLUTION] **必須**透過 `jira-estimation` 寫進 JIRA comment，否則單上不會有任何紀錄。

**🛑 STOP — 等待 RD 確認。** `jira-estimation` 完成後，必須等使用者明確回覆確認 [ROOT_CAUSE] 和 [SOLUTION] 才能進入 Step 3。不可自動繼續。

### Step 3：轉 IN DEVELOPMENT + 建分支

**⚠️ 分支必須在寫任何 code 之前建立。** 不可先改 code 再補建分支 — 這會導致改在錯的 branch 上，需要 stash 搬移，容易出錯。

RD 確認後，**同時執行**：

1. 轉 JIRA 狀態為 `In Development`（等同 `start-dev` skill 的邏輯）：

```
mcp__claude_ai_Atlassian__transitionJiraIssue
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  issueIdOrKey: <ticket key>
  transitionName: In Development
```

> 轉換前須確認「需求來源」欄位已設定。Bug 修復使用 `Tech - bug`（值見 `{config: jira.custom_fields.requirement_source.bug_value}`）：
> ```
> mcp__claude_ai_Atlassian__editJiraIssue
>   cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
>   issueIdOrKey: <ticket key>
>   fields:
>     {config: jira.custom_fields.requirement_source.field_id}:
>       id: "{config: jira.custom_fields.requirement_source.bug_value}"
> ```

2. 建立分支（使用 `jira-branch-checkout` skill 或 `git create-branch --jira --ci`）

### Step 3.5：AC Gate — 確保測試計畫存在

建分支後、開發前，檢查 ticket description 是否有 `## 測試計畫` checklist：

- **有** → 建立 `[驗證]` 子任務（同 work-on Step 4d-4e），進入 Step 4
- **沒有** → 從 Step 2 的 Root Cause + Solution 自動推導測試計畫（重現原 bug 的步驟 + 修正後的預期行為），追加到 ticket description，建立 `[驗證]` 子任務

```
📋 AC Gate — 已補上測試計畫（N 項）
  - [ ] 原 bug 步驟重現 → 預期不再發生
  - [ ] 相關邊界場景 → 預期行為正常
已寫回 JIRA description，建立 N 張 [驗證] 子任務。
```

### Step 4：TDD 開發（預設模式）

在分支上以 **TDD（Red-Green-Refactor）** 實作修正。遵循專案 CLAUDE.md 確保程式碼符合專案規範，遵循 `tdd` skill 的 TDD 循環。

**TDD 智慧判斷**：依 `references/tdd-smart-judgment.md` 判斷每個檔案是否走 TDD 循環。

**實作中發現情況不同時：**
- 在 JIRA ticket 上**新增一則 comment** 標註修正版（保留原始 comment）
- 更新 [ROOT_CAUSE] / [SOLUTION] / 估點
- 與初版的差異說明
- **估點變動 > 30% 時 pause 讓 RD 確認**

### Step 4.5：AC Local Verification（本地驗證）— Hard Gate

> **🛑 Hard Gate — 不可跳過。** Local 驗證項必須逐項執行並產出證據（test output、curl response、截圖），才能進入 Step 5。「unit test 過了所以跳過行為驗證」不是有效理由 — unit test 驗邏輯正確，local 驗證驗行為正確，兩者互補不可替代。

開發完成後、發 PR 前，根據 ticket 的 `[VERIFICATION]` Local 驗證項目逐一檢查：

1. **讀取 ticket 的 Local 驗證 AC**（從 Step 2 的 JIRA comment 或 description 取得）
2. **分類每個 AC 項目：**
   - **Unit test 可驗** → 寫 unit test（永久回歸保護）
   - **行為可驗（需 dev server）** → 起環境（`polaris-env.sh`），用 curl / Playwright 驗證實際行為，附輸出證據
   - **需要手動確認** → 提示 RD 確認
3. **Hard Gate 規則：**
   - 每個 Local 驗證項必須有 **三種 disposition 之一**：`✅ PASS（附證據）`、`⏭️ SKIP（附理由，需 RD 確認）`、`❌ FAIL（停止，回到 Step 4 修正）`
   - **不允許「全部只有 unit test」就跳過行為驗證** — 如果 [VERIFICATION] 列出了需要起 server 才能驗的項目（如「切換語系後 footer 正確」），必須起 server 驗
   - **允許的 SKIP 理由**：dev 環境無法重現（如第三方 API）、純 type/config 改動無運行行為、RD 明確說 skip
4. **更新 JIRA comment** — 以 comment 回報 Local 驗證結果，附截圖/output（如有）
5. **Post-deploy 項目** → 標記「待 SIT/Prod 驗證」，不阻擋 PR

```
📋 AC Local Verification
### Local 驗證
- [x] <AC 項目> → ✅ unit test 通過
- [x] <AC 項目> → ✅ curl 驗證（附 output）
- [x] <AC 項目> → ✅ Playwright 截圖確認

### Post-deploy（待 SIT 驗證）
- [ ] <AC 項目> → 需部署後確認
```

**為什麼是 Hard Gate：** TASK-123 hotfix 中，unit test 驗證 cache key 邏輯正確就跳過了行為驗證（起 server 測切換語系）。如果行為驗證失敗（例如 `$phpRequest` 沒轉發 market header），unit test 不會抓到。行為驗證是最後一道防線，不可省略。

**VR Gate（條件觸發）：** 若改動涉及 `pages/`, `components/`, `layouts/`, `*.vue`, `*.scss`，且 workspace-config 有 `visual_regression` 設定 → 讀取 `visual-regression` SKILL.md 執行 VR 檢查。純 server/config/types 改動則跳過。

### Step 5：品質檢查 → Pre-PR Review → 發 PR（自動銜接）

開發完成後，**自動 invoke `git-pr-workflow` skill** 處理後續（不需等使用者指示）：
- 品質檢查（dev-quality-check）
- Pre-PR Review Loop（Sub-Agent 迭代審查，最多 3 輪）
- Commit + Changeset
- 建立 PR → 自動轉 JIRA 為 CODE REVIEW
- 更新 PR 描述

❌ **NEVER** 用 `pr-convention` 替代 — 它只是簡易版 PR 建立，不含品質檢查、coverage 驗證、pre-PR review loop。手動拆開執行會遺漏步驟（PROJ-12345 就是因此 CI 掛掉）。

直接說「發 PR」即可觸發。

### Step 6（選擇性）：記錄工時

PR 開出後，詢問 RD 是否要記錄工時。若要，委派給 `jira-worklog` skill。

## 流程圖

```
使用者：幫我修正 PROJ-432
  │
  ▼
Step 1: 讀 JIRA 單 → 確認專案 → cd 到專案目錄
  │
  ▼
Step 2: 分析根因 + 估點（jira-estimation）
  │      ↓ 留 JIRA comment
  │
  ▼
👤 RD 確認 [ROOT_CAUSE] & [SOLUTION]
  │
  ▼
Step 3: 轉 IN DEVELOPMENT + 建分支
  │
  ▼
Step 3.5: AC Gate（檢查/補上測試計畫 + 建 [驗證] 子任務）
  │
  ▼
Step 4: TDD 開發（發現不同時更新 JIRA comment，>30% 估點變動 pause）
  │
  ▼
Step 4.5: AC Local Verification（unit test + Playwright/截圖 → 更新 JIRA）
  │        ↓ VR Gate（條件觸發：前端改動 + VR 設定存在）
  │
  ▼
👤 RD 確認改動
  │
  ▼
Step 5: 發 PR（git-pr-workflow：品質檢查 → Pre-PR Review → Commit → PR）
  │      ↓ 自動轉 CODE REVIEW
  │
  ▼
Step 6: 記錄工時？（選擇性）
```

## 與其他 Skill 的關係

| 步驟 | 委派給 | 說明 |
|------|--------|------|
| Step 2 | `jira-estimation` | Bug 根因分析 + 估點 |
| Step 3 | `start-dev` 邏輯 + `jira-branch-checkout` | 狀態轉換 + 建分支 |
| Step 4 | `tdd` + 專案 CLAUDE.md | TDD 開發 + 規範引導 |
| Step 4.5 | `unit-test` + `visual-regression`（條件） | AC Local 驗證 + VR Gate |
| Step 5 | `git-pr-workflow` | 品質檢查 → PR 全流程 |
| Step 6 | `jira-worklog` | 工時記錄 |

## Do / Don't

- Do: Step 2 **用 Skill tool invoke `jira-estimation`**，不可自己做 inline 分析替代
- Do: Step 2 完成後等 RD **明確回覆**確認 [ROOT_CAUSE] 後才進 Step 3
- Do: Step 3 **先建分支再寫 code** — 不可在現有 branch 上先改再搬
- Do: 實作中發現不同時，新增 JIRA comment（不覆蓋原始 comment）
- Do: 估點變動 > 30% 時 pause 讓 RD 確認
- Do: Step 4.5 **逐項執行 Local 驗證**，每項必須有 PASS/SKIP/FAIL disposition + 證據（output、截圖）。行為驗證不可被 unit test 替代
- Do: 每個步驟之間保持銜接，不要停住等使用者手動觸發下一個 skill
- Don't: 自己分析 [ROOT_CAUSE] 然後跳過 `jira-estimation` — 這會導致 JIRA 單上沒有任何紀錄
- Don't: Step 2 完成後自動繼續 — 必須等使用者回覆
- Don't: 在建分支前就開始編輯 code
- Don't: Bug 單不需要拆子單（除非 RD 明確要求）
- Don't: Bug 單不需要 SA/SD（除非 RD 明確要求）
- Don't: 把 JIRA URL 誤判為 PR URL 而觸發 fix-pr-review
- Don't: Step 5 用 `pr-convention` 替代 `git-pr-workflow` — 前者不含品質檢查和 coverage 驗證，會導致 CI 失敗
- Don't: Step 5 手動拆開執行（先跑 quality-check 再跑 pr-convention）— 必須整包委派給 `git-pr-workflow`
- Don't: 使用者說「繼續」或「發 PR」時自行判斷跳過品質檢查 — quality gate 不可省略
- Don't: Step 4.5 只跑 unit test 就判定「行為驗證通過」— unit test 驗邏輯，行為驗證驗實際運行，兩者不可互相替代（TASK-123 教訓）

## Prerequisites

- JIRA MCP 連線正常（Atlassian tools 可用）
- `gh` CLI 已安裝並認證
- 對應專案已 clone 到 `{base_dir}/` 下（base_dir 從 workspace-config.yaml 取得）


## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
