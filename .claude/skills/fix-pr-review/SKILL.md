---
name: fix-pr-review
description: >
  Fix PR review comments AND CI/lint/test/coverage failures on YOUR OWN PR. Reads review
  comments, fixes issues per .claude/rules, runs self-review via sub-agent, replies to
  each comment. Trigger: "fix review", "修正 review", "修 PR", "PR 有 review", "處理
  review", "address review", "回覆 review", "fix PR", "CI 沒過", "CI failed",
  "lint/test/coverage failed", "pre-commit failed", or user shares a PR URL asking to
  fix. NOT for JIRA bugs (use fix-bug) or reviewing others' PRs (use review-pr).
metadata:
  author: Polaris
  version: 2.8.0
---

# fix-pr-review

讀取 GitHub PR review comments，依據專案規範逐一修正或回覆。
修正完成後透過 Sub-Agent 自我審查，確保修正沒有引入新問題。

## 前置：讀取 workspace config

讀取 workspace config（參考 `references/workspace-config-reader.md`）。
本步驟需要的值：`github.org`。
若 config 不存在，使用 `references/shared-defaults.md` 的 fallback 值。

## 流程總覽

```
偵測輸入來源(0) → 選擇模式(0.5) → [自動] 原有流程(1~13) / [互動] 逐一確認 → worktree 執行 → diff 確認 → push
```

**自動模式（預設）**：
```
Parse PR(1) → Worktree 隔離(2) → Rebase(3) → Fetch Comments(4) → Read Rules(5) → Fix CI(6) → Fix Review Comments(7) → Simplify Loop(8) → Post-fix Self Review(9) → Reply Comments(10) → Quality Gate(11) → Test Plan Re-validation(11) → Commit & Push(11) → Summary(12) → Review Lesson 萃取(12.5) → Slack 通知(13)
```

**互動模式**：
```
Parse PR(1) → Fetch Comments(4) → Read Rules(5) → 逐一展示 & 確認 → Worktree sub-agent 執行修正 → 展示 diff → 使用者確認 → Commit & Push → Reply → Review Lesson 萃取(12.5) → Slack
```

## 0. 偵測輸入來源

### 從 Slack 訊息擷取 PR 連結

依 `references/slack-pr-input.md` 的流程從 Slack 訊息中擷取 PR URL。

保留的 Slack context（`slack_channel_id`、`slack_thread_ts`、`slack_source`）供 Step 13 使用。

### 多 PR 輸入

若偵測到多個 PR，為每個 PR 啟動獨立的 sub-agent 平行處理（每個 sub-agent 都使用 `isolation: "worktree"`），收集結果後統一回報 + Slack 通知。

## 0.5 選擇執行模式

使用 AskUserQuestion 詢問使用者要使用哪種模式：

| 模式 | 說明 |
|------|------|
| **自動模式（預設）** | Worktree sub-agent 全自動執行所有步驟，完成後回報結果 |
| **互動模式** | 主 agent 逐一展示每個 comment 的修正方案，等使用者確認後再執行 |

### 自動模式

繼續現有流程（Step 1 → Step 13），無改動。

### 互動模式

互動模式分兩階段執行：

#### 階段 1：討論修正方向（主 agent，不建 worktree）

1. 執行 Step 1（Parse PR）取得 PR 資訊
2. 執行 Step 4（Fetch Comments）取得所有 review comments
3. 執行 Step 5（Read Rules）讀取專案規範
4. **逐一展示每個 comment**：
   - 顯示 comment 原文（reviewer 說了什麼）、檔案路徑、行號、嚴重度
   - 讀取相關程式碼上下文
   - 提出修正方案（含 code diff preview）或回覆方向（不修正 / 需討論）
   - 使用 AskUserQuestion 等使用者確認（同意 / 調整方向）
5. 收集所有已確認的修正指令清單

#### 階段 2：執行修正（worktree sub-agent）

6. 啟動 worktree sub-agent，帶入已確認的完整修正清單
7. Sub-agent 依序執行：
   - Rebase base branch（Step 3）
   - Check & Fix CI failures（Step 6）
   - 依照修正清單逐一修改程式碼（Step 7）
   - Post-fix Self Review（Step 9）
8. Sub-agent 完成後，主 agent **展示完整 diff 給使用者最終確認**
9. 使用者確認後：
   - Commit & Push（Step 11）
   - Reply to each comment（Step 10）
   - Slack 通知（Step 13）

**互動模式注意事項**：
- 若多個 comment 指向同一問題（如重複指出），合併說明並標註「一併修正」
- 使用者可在任一 comment 調整修正方向，不受原本 reviewer 建議約束
- CI failures 在階段 2 由 sub-agent 自動處理，不需逐一確認

## Scripts

本 skill 包含 shell script 處理確定性邏輯，避免 LLM 重複組裝 API 查詢：

| Script | 用途 | Input | Output |
|--------|------|-------|--------|
| `scripts/fetch-pr-review-comments.sh` | 取得 PR inline review comments、issue comments 並過濾出需要處理的（含 CI 狀態） | `<owner/repo> <pr_number> [--my-user <username>]` | JSON object（含 `comments`、`issue_comments`、`review_summaries`、`ci_checks`） |

Script 路徑相對於本 SKILL.md 所在目錄。執行前確認有 `+x` 權限。

## 1. Parse PR Number & 辨識對應專案

依 `references/pr-input-resolver.md` 的流程解析 PR 資訊並定位本地專案路徑。

本 skill 需要修改程式碼，若本地找不到 repo 目錄，詢問使用者。

後續讀取程式碼、修正檔案時，以解析出的專案路徑為根目錄。

## 2. Worktree 隔離執行

**一律使用 worktree 隔離**，避免打斷 RD 當前的開發工作。

使用 Agent tool 啟動 sub-agent，設定 `isolation: "worktree"`：

- sub-agent 在 temporary git worktree 中工作，RD 的原始工作目錄完全不受影響
- sub-agent 的 prompt 需包含完整的 fix-pr-review 流程（Step 4 ~ Step 11 的所有指示）
- sub-agent 需先 `git checkout {headRefName}` 切到 PR branch 再開始修正
- sub-agent 完成後，修正會直接 commit & push 到 PR branch，worktree 自動清理

Sub-agent prompt 範本：

```
你是 PR fix agent，在 worktree 隔離環境中修正 PR review comments 和 CI failures。

## 基本資訊
- PR: {pr_url}
- PR Number: {pr_number}
- Repo: {owner}/{repo}
- Head Branch: {headRefName}
- Base Branch: {baseRefName}
- 專案路徑: {worktree 會自動設定}

## 前置動作
1. git checkout {headRefName}
2. 確認在正確的 branch 上
3. Rebase base branch（Step 3）

## 執行流程
依序執行以下步驟（完整的 Step 3 ~ Step 12）：
- Rebase Base Branch
- Fetch Review Comments
- Read Project Rules（.claude/rules/）
- Check CI Status & Fix Failures
- Analyze & Fix Each Review Comment
- Simplify Loop
- Post-fix Self Review
- Reply to Each Comment
- Commit & Push
- Output Summary
- Review Lesson 萃取

{將 Step 3 ~ Step 12.5 的完整指示嵌入}
```

主 agent 等待 sub-agent 完成後，將結果摘要回報給使用者。

## 3. Rebase Base Branch

**在開始任何修正之前，先 rebase PR 的 base branch**，確保 PR 基於最新的程式碼。

### 為什麼要先 rebase

1. 確保 PR diff 是最新狀態，避免 reviewer 看到 outdated diff
2. rebase/merge 後 GitHub 可能 dismiss 已有的 approve，先 rebase 再修正可以避免「修完再 rebase 又被 dismiss」的循環
3. 提早發現 merge conflict，避免修正完才 rebase 導致 conflict 破壞修正

### 執行步驟

```bash
# 1. Fetch 最新的 base branch
git fetch origin {baseRefName}

# 2. Rebase
git rebase origin/{baseRefName}

# 3. Force push（rebase 改變了 history）
git push --force-with-lease
```

### Conflict 處理

- **無 conflict** → 繼續後續步驟
- **有 conflict** → 嘗試解決。若 conflict 範圍超過 PR 變動的檔案（即 conflict 來自 base branch 其他人的改動），回報使用者手動處理

## 4. Fetch Review Comments

用 bundled script 一次取得 review comments、review summaries 和 CI 狀態：

```bash
SKILL_DIR="$(dirname "$(readlink -f "$0")")"  # 或直接用 skill 的絕對路徑
"$SKILL_DIR/scripts/fetch-pr-review-comments.sh" {owner}/{repo} {pr_number} --my-user {my_username}
```

**輸出 JSON 格式**：

```json
{
  "repo": "your-org/repo-a",
  "number": 1920,
  "title": "feat: xxx",
  "author": "alice",
  "base": "develop",
  "head": "feat/xxx",
  "comments": [...],
  "all_comments": [...],
  "review_summaries": [...],
  "all_reviews": [...],
  "issue_comments": [...],
  "ci_checks": [...],
  "stats": {
    "total_comments": 10,
    "actionable_comments": 5,
    "actionable_review_summaries": 2,
    "issue_comments": 2,
    "ci_failed": 2,
    "ci_passed": 3,
    "ci_pending": 0
  }
}
```

Script 自動處理的過濾邏輯：

**Inline review comments**（`comments`）：
- **Thread-based 判斷**：對每個 top-level comment，找出整個 thread（含所有 replies），取最後一則 comment 判斷：
  - 最後一則是 author → 已回覆，跳過
  - 最後一則是 reviewer 的確認回覆（含「確認」+「✅」或「LGTM」）→ 已解決，跳過
  - 最後一則是 reviewer 的新問題/建議 → 未回覆，保留
- **跳過**：自己留的 comment、非 code review bot（changeset-bot、codecov-commenter、your-bot-account）
- **保留**：`comments` 只含需要處理的 top-level comments（thread 未被回覆的）
- **保留**：`all_comments` 含完整原始資料（reply thread 追溯用）

**Review body comments**（`review_summaries`）：
- 來自 `pulls/{number}/reviews` API 的 review body（reviewer 提交 review 時寫的整體回饋）
- **跳過**：自己的 review
- **跳過**：APPROVED 狀態的 review（approval 是結論，不需要 author 回覆）
- **跳過**：空 body 的 review
- **跳過**：author 在該 review 之後有任何活動（inline comment 或 review submission）→ 視為已回覆
- **保留**：`review_summaries` 只含需要處理的 review body
- **保留**：`all_reviews` 含完整原始 reviews（含已處理的，供 context 追溯用）

**Issue comments**（`issue_comments`）：
- 來自 `issues/{number}/comments` API — PR 底部的一般留言（非 inline review）
- **跳過**：非 actionable Bot 帳號（GitHub `user.type == "Bot"`，如 codecov-bot）— 但 **保留 changeset-bot**，其「No Changeset found」警告視為 CI 層面問題，歸入 Step 6h 處理
- **跳過**：自己的留言
- **保留**：其他人類留下的 review 回饋（如 Claude Code Review 結果、手動 review 意見）
- 常見場景：reviewer 用 AI review 工具產出的結構化回饋會以 issue comment 形式留在 PR 上

根據 `stats.ci_failed` 判斷是否需要先修 CI（Step 6），再處理 review comments（`comments` + `review_summaries`）和 issue comments（Step 7）。

## 5. Read Project Rules

讀取 `.claude/rules/` 目錄下的規範檔案，作為修正依據：

```bash
ls .claude/rules/
```

讀取與 comment 內容相關的規範檔案（依各專案的 rules 目錄結構而定）。常見規範類型包含：型別安全、專案架構、狀態管理、API 開發、格式化、命名、元件開發等。

## 6. Check CI Status & Fix Failures

在處理 review comments 之前，先檢查 PR 的 CI checks 狀態，修正所有失敗項目。

### 6a. 取得 CI checks 狀態

```bash
# 取得所有 CI check 結果
gh pr checks {pr_number} --repo {owner}/{repo} --json name,state,description
```

如果所有 checks 都通過（或尚無 checks），跳至 Step 7 處理 review comments。

### 6b. 分類失敗原因

根據失敗的 check name 和 description 分類：

| 失敗類型 | 常見 check 名稱關鍵字 | 修正方式 |
| --- | --- | --- |
| **Lint 失敗** | `lint`, `eslint`, `stylelint`, `prettier` | 在本地執行 lint 指令並自動修復 |
| **測試失敗** | `test`, `jest`, `vitest`, `spec` | 在本地執行測試，讀取錯誤訊息修正 |
| **覆蓋率不足** | `coverage`, `codecov`, `sonar` | 執行覆蓋率報告，針對未覆蓋程式碼補寫測試 |
| **Build 失敗** | `build`, `compile`, `typecheck` | 在本地執行 build，修正編譯錯誤 |

### 6c. 修正 Lint 失敗

```bash
# 1. 先嘗試自動修復
pnpm fix:full  # 或專案對應的 fix 指令

# 2. 若仍有錯誤，手動讀取並逐一修正
pnpm lint:full 2>&1
```

讀取 lint 錯誤輸出，使用 Edit tool 逐一修正。不要使用 `eslint-disable` 繞過。

### 6d. 修正測試失敗

```bash
# 1. 執行測試，取得失敗清單
pnpm test 2>&1
```

分析失敗原因：
- **程式碼 bug** → 修正原始碼
- **測試預期過時** → 更新測試預期（確認新行為是正確的）
- **缺少 mock / setup** → 補齊測試環境

修正後重新執行確認通過。

### 6e. 修正覆蓋率不足

```bash
# 1. 執行覆蓋率報告
pnpm test-cover 2>&1
```

分析覆蓋率報告：
1. 讀取 terminal 輸出或 `coverage/` 目錄下的報告
2. 找出未覆蓋的檔案與行號（重點關注本次 PR 變動的檔案）
3. 針對未覆蓋的邏輯補寫測試

補寫測試時：
- 參考同目錄下既有測試的寫法風格（import 方式、describe/it 結構、mock 慣例）
- 測試檔放在對應的 `__tests__/` 目錄
- 優先覆蓋本次 PR 新增/修改的程式碼
- 覆蓋主要邏輯路徑（happy path + 邊界條件）

### 6f. 修正 Build / TypeCheck 失敗

```bash
# 1. 執行 build 或 typecheck
pnpm build 2>&1
# 或
npx tsc --noEmit 2>&1
```

讀取編譯錯誤，修正型別問題或語法錯誤。

### 6g. 補 Changeset（若缺少）

若 issue comments 中有 **changeset-bot** 的「No Changeset found」警告，視為 CI 層面問題，需產生 changeset 檔案。

這不是所有專案都有的機制——只在專案根目錄存在 `.changeset/` 目錄時才處理。

**偵測方式**：檢查 Step 4 回傳的 `issue_comments` 中是否有 `changeset-bot` 且 body 包含 `No Changeset found`。

**產生 changeset**：

1. 讀取 `.changeset/` 目錄下既有的 changeset 範例，了解格式（通常是 `---` frontmatter + 描述）
2. 從 PR title 和變更內容判斷 bump type（`patch` 用於 bug fix，`minor` 用於 feature）
3. 找出本次 PR 變更涉及的 package name（從 `package.json` 或 monorepo workspace 結構）
4. 產生 changeset 檔案：

```bash
# 使用 pnpm changeset 互動式指令的替代方案 — 直接寫檔
# 檔名格式：隨機形容詞組合.md（模仿 @changesets/cli 的命名）
```

```markdown
---
"<package-name>": patch
---

<PR title 或簡述變更>
```

5. `git add .changeset/<filename>.md`

**不要回覆 changeset-bot 的留言**——它是 bot 產生的狀態提示，修正後下次 push 會自動更新。

### 6h. 驗證所有 CI 項目

所有修正完成後，在本地重新執行相關指令確認全部通過：

```bash
pnpm lint:full && pnpm test
```

若專案有覆蓋率門檻，也執行 `pnpm test-cover` 確認達標。

## 7. Analyze & Fix Each Review Comment

對每個 review comment **和 issue comment** 進行分析與處理。

Issue comments 中的 review 回饋（如 Claude Code Review 產出的結構化分析）通常包含多個 review items（🔴/🟡/🟢/💡），需逐一分析每個 item 並決定是否修正。

### 7a. 讀取相關程式碼

```bash
# 讀取 comment 指向的檔案
Read tool: path + line context (±20 lines)
```

### 7b. 判斷是否需要修正

根據 comment 內容與 `.claude/rules/` 規範，判斷：

| 判斷結果                           | 行動                                    |
| ---------------------------------- | --------------------------------------- |
| **需要修正**                       | 修改程式碼 → commit → 回覆 comment      |
| **不需要修正**（合理的設計決策）   | 回覆 comment 說明原因                   |
| **不需要修正**（comment 理解有誤） | 回覆 comment 補充說明                   |
| **需要討論**                       | 回覆 comment 提出疑問，請 reviewer 確認 |

### 7c. 修正程式碼

使用 Edit tool 修正程式碼，修正時遵循：

1. **依據 `.claude/rules/` 規範**修正，不要引入新的違規
2. **最小化變更**：只修正 comment 指出的問題，不做額外重構
3. **確保型別安全**：修正後不應產生新的 TypeScript 錯誤
4. **跑測試**：修正後執行相關測試確認不破壞既有功能

```bash
# 修正後執行相關測試（依專案測試框架而定）
npm test -- <related-test-files>
```

## 8. Simplify Loop（程式碼簡化）

在修正 CI 和 review comments 後、進入 self review 前，用 `/simplify` 迭代簡化修正過的程式碼。

### 8a. 觸發條件

**只在有程式碼修改時觸發**。如果所有 review comments 都是「不需修正」或「需要討論」，且沒有 CI 修正，跳過此步驟直接進入 Step 9。

### 8b. 執行流程

```
┌────────────────────────────────┐
│ 1. 執行 /simplify              │
│ 2. 有修改檔案?                 │
│    ├─ Yes → 回到 1            │
│    └─ No  → 進入 Step 9      │
└────────────────────────────────┘
```

使用 Skill tool 呼叫 `simplify`，它會：
1. 檢視目前變更的程式碼（本次修正的 diff）
2. 審查重用性（是否有重複邏輯可抽共用）、品質（是否有不必要的複雜度）、效率（是否有低效寫法）
3. 若發現問題，直接修正檔案

### 8c. 迭代邏輯

- 每輪 `/simplify` 執行後，檢查 `git diff` 是否有新的變更
- **有變更** → 再跑一輪 `/simplify`
- **無變更** → 進入下一步
- **最多 2 rounds**（與 self review 一致，修正範圍較小）
- 每輪回報：`Simplify round N/2: <修改摘要 or 無變更，進入 self review>`

## 9. Post-fix Self Review（Sub-Agent 迭代審查）

在 commit 之前，啟動 Reviewer Sub-Agent 對本次修正的 diff 進行自我審查，確保修正沒有引入新問題。

### 8a. 為什麼需要這一步

修正 CI failures 和 review comments 時，可能引入：
- 新的格式規範違反（例如修 test 時沒加大括號）
- 型別不一致（例如改了 interface 但沒更新使用處）
- 遺漏的 import 或未使用的 import
- 測試覆蓋不足（新補的程式碼沒有對應測試）

### 8b. 觸發條件

**只在有程式碼修改時觸發**。如果所有 review comments 都是「不需修正」或「需要討論」，跳過此步驟直接進入 Step 10。

### 8c. 執行流程

```
┌─────────────────────────────────────────┐
│  Dev Agent                              │
│  ┌───────────────────────────────────┐  │
│  │ 1. git diff (本次所有修正)        │  │
│  │ 2. 啟動 Reviewer Sub-Agent (前景) │  │
│  │ 3. 等待 review 結果               │  │
│  │ 4. 有 blocking issues?            │  │
│  │    ├─ Yes → 修正 → 回到 1        │  │
│  │    └─ No  → 進入 Step 10 (Reply) │  │
│  └───────────────────────────────────┘  │
│                                          │
│  ┌───────────────────────────────────┐  │
│  │ Reviewer Sub-Agent (獨立 context) │  │
│  │ - 讀取 git diff + .claude/rules/ │  │
│  │ - 只審查本次修正引入的新問題      │  │
│  │ - 不重新審查整個 PR               │  │
│  │ - 回傳 JSON 結果                  │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

### 8d. Reviewer Sub-Agent 檢查範圍

**只檢查本次修正的 diff**，不重新審查整個 PR 原有的程式碼。

| 面向 | 說明 |
| --- | --- |
| 型別安全 | 修正是否引入新的型別錯誤 |
| 邊界處理 | 修正是否遺漏 null check 或 error handling |
| 測試覆蓋 | 新增的程式碼是否有對應測試 |
| 程式碼風格 | 修正是否符合 `.claude/rules/` 規範 |
| 一致性 | 修正是否與周圍程式碼風格一致 |

### 8e. Sub-Agent 回傳格式

```json
{
  "passed": true,
  "blocking": [
    { "file": "path/to/file.ts", "line": 42, "issue": "描述問題", "suggestion": "建議修正方式" }
  ],
  "non_blocking": [
    { "file": "path/to/file.ts", "line": 10, "issue": "描述建議", "suggestion": "可選改進" }
  ],
  "summary": "一句話總結"
}
```

* `passed: true` → 沒有 blocking issues，進入 Step 10
* `passed: false` → Dev Agent 逐一修正 blocking issues，修正後回到 9c 重新 review

### 8f. Blocking vs Non-blocking

* **Blocking**（必須修正）：型別錯誤、邏輯 bug、安全問題、格式規範違反、測試失敗
* **Non-blocking**（記錄但不阻擋）：命名風格建議、micro-optimization

### 8g. 迭代限制

* **最多 2 rounds**（比 git-pr-workflow 的 3 rounds 少，因為修正範圍較小）
* 每輪修正後回報進度：`Self-review round N/2: X blocking issues 已修正，重新送審中...`
* 如果 2 輪後仍有 blocking issues，列出未解決項目並詢問使用者

## 10. Reply to Each Comment

修正完畢或決定不修正後，**必須回覆每個 comment**。

### 回覆 API

**Inline review comments**（來自 `comments`）：
```bash
# 回覆 inline review comment（使用 reply-to）
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  -f body="<reply_content>" \
  -F in_reply_to=<comment_id>
```

**Issue comments**（來自 `issue_comments`）：
```bash
# 回覆 issue comment — 在 PR 上新增一則留言，@mention 原留言者
gh api repos/{owner}/{repo}/issues/{pr_number}/comments \
  -f body="回覆 @{reviewer_username} 的 review：<reply_content>"
```

Issue comments 沒有 `in_reply_to` 機制，回覆方式是新增一則 issue comment 並 @mention 原留言者。若原留言包含多個 review items（如 🟡/🟢/💡），在同一則回覆中逐一回應每個 item。

### 回覆格式

#### 已修正

```markdown
已修正 ✅

<簡述修正內容，例如：已將 `packagesData` 初始化移至 `initState()` 中，避免切換商品時殘留舊資料。>

commit: <short_sha>
```

#### 不需修正

```markdown
不需修正，說明如下：

<具體原因，引用 `.claude/rules/` 中的規範或技術理由。>

例如：

- 此處的設計決策符合 `.claude/rules/` 中 XX 規範的 Y 條，理由如下⋯⋯
- 此函式有其獨立用途，非重複實作。詳見函式上方 JSDoc。
```

#### 需要討論

```markdown
想確認一下：

<提出疑問，說明目前的設計考量，請 reviewer 確認方向。>
```

## 11. Quality Gate → Commit & Push

所有修正完成後（CI fixes + review comment fixes + self-review fixes），**push 前必須在本地跑完整品質驗證**，等同開發完發 PR 的標準：

### 10.1 本地品質驗證（執行 `dev-quality-check`）

讀取 `dev-quality-check` skill 的 SKILL.md 並依序執行其完整流程（detect → lint → test → coverage）。

若任一步驟失敗，回頭修正直到全過。**不可跳過驗證直接 push**——push 後 CI 失敗等於浪費一輪 CI 時間和 reviewer 的注意力。

### 10.2 Test Plan Re-validation

修正 review comments 後，原本的驗證項目可能被改壞（例如修正 A 元件導致 B 流程不通）。品質檢查只驗證 lint/test/coverage，不驗證行為面。這一步重跑 JIRA 上的 `[驗證]` 子單，確保功能仍然正常。

#### 執行流程

1. **從 PR 提取 JIRA ticket key**：從 branch name 或 PR title 提取（如 `PROJ-3462`）。無法提取時跳過，進入 10.3。

2. **Invoke `verify-completion`**：直接委託 verify-completion 執行完整驗證流程。它會：
   - 查詢該 ticket 下所有 `[驗證]` 子單（`parent = <TICKET> AND summary ~ "驗證"`）
   - 將已「完成」的子單**重設為「開放」**（因為修正 review 後需要重新驗證）
   - 平行啟動 sub-agent 逐一驗證
   - 每個 sub-agent 獨立執行驗證 → 留 JIRA comment → 轉子單狀態
   - 回傳驗證報告（PASS / BLOCKED / MANUAL_REQUIRED）

3. **根據驗證結果決定是否放行**：

| 結果 | 行動 |
|------|------|
| 全部 PASS | 進入 10.3 Commit & Push |
| 有 FAIL 項目 | 分析原因，修正程式碼，回到 10.1 重跑品質檢查 + 驗證（最多 2 輪） |
| 有 BLOCKED / MANUAL_REQUIRED | 列出未通過項目回報使用者，等確認後再繼續 |

### 10.3 Commit & Push

```bash
# Stage 修正的檔案
git add <modified-files>

# Commit（訊息包含 PR 編號與修正類型）
git commit -m "fix: address PR #<number> review comments and CI failures

- <列出主要修正項目>
- <CI 修正項目：lint fix / test fix / coverage 補寫等>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"

# Push（本地驗證全過後才執行）
git push
```

若 CI fixes 和 review comment fixes 性質差異大，可拆為兩個 commit：
1. `fix: resolve CI failures for PR #<number>` — lint、test、coverage 修正
2. `fix: address PR #<number> review comments` — reviewer 回饋修正

## 12. Output Summary

完成後輸出摘要報告：

```
PR 修正報告：
- PR: #<number>

CI Checks 修正：
- Lint 錯誤: A 個（已修正）
- 測試失敗: B 個（已修正）
- 覆蓋率: 補寫 C 個測試檔
- Build/TypeCheck: D 個錯誤（已修正）

Review Comments 處理：
- 處理 comments: N 個
- 已修正: X 個
- 不需修正: Y 個（已回覆原因）
- 需要討論: Z 個（已回覆提問）

Post-fix Self Review：
- 審查輪數: R/2
- 修正 blocking issues: B 個
- Non-blocking 建議: S 個（已記錄）

Commit: <sha>
```

## 12.5 Review Lesson 萃取

修正完成後，靜默分析本次 review comments，將可通用化的 coding pattern 萃取為 `.claude/rules/review-lessons/` 規則檔。目的：避免同類問題在未來的 PR 反覆出現——寫 code 的 skill（work-on、fix-bug、tdd）啟動時會讀取 `.claude/rules/`，等同於把 reviewer 的回饋內建到開發流程中。

### 萃取條件

**萃取**（可通用化的 pattern）：
- 框架慣用法（Vue reactivity 選擇、composable 拆分、lifecycle 使用）
- Error handling / 邊界處理慣例
- 型別安全 pattern（泛型用法、type guard、discriminated union）
- 效能相關決策（computed vs watch、lazy loading、memoization）
- 測試撰寫慣例（mock 方式、assertion 風格）
- 元件設計原則（props 設計、emit 規範、slot 使用）

**排除**（一次性問題）：
- Typo、變數名打錯
- 漏 import、多餘 import
- Copy-paste 錯誤
- 純格式問題（已由 lint 規則覆蓋）
- 只適用於特定業務邏輯的修正

### 執行流程

1. **掃描本次所有 review comments**（Step 4 取得的 `comments` + `issue_comments`），篩選出「已修正」的 comment
2. **逐一判斷**是否為可通用化 pattern
3. **雙層去重**：比對 (1) 既有 review-lessons 檔案 **和** (2) 主 rules 檔案（`.claude/rules/*.md`），語意相同則跳過
   - 既有 lesson 有同主題 → 讀取後追加新的 Source 記錄，必要時更新規則描述
   - 無 → 建立新檔案
   - **框架級分流**：若 pattern 屬於框架層級（skill 設計、delegation 策略、rules 機制、memory 管理），在 entry 前方標記 `[framework]`
4. **如果沒有可通用化的 pattern → 直接跳過**，不輸出任何訊息

### 檔案格式

檔名：`review-lessons/<主題>.md`（kebab-case，如 `vue-reactivity.md`、`error-handling.md`）

```markdown
# [主題標題]

- [規則描述]
- Why: [為什麼這樣做——從 reviewer 的 comment 提煉原因]
- Source: [PR URL] ([日期])
```

若同一主題累積多條規則：

```markdown
# Vue Reactivity 選擇

- 從現有 reactive data 衍生的值用 `computed`，不用 `watch` + `ref`
- Why: watch 多一層副作用，且容易漏掉初始值
- Source: https://github.com/your-org/repo-a/pull/1920 (2026-03-15)

- `watchEffect` 僅用於需要自動追蹤依賴的副作用，明確依賴時用 `watch`
- Why: watchEffect 的隱式依賴追蹤在複雜場景下難以除錯
- Source: https://github.com/your-org/repo-a/pull/1950 (2026-03-27)
```

### 重要注意事項

- **靜默執行**：只在確實萃取到 lesson 時通知使用者（「已萃取 N 條 review lesson 到 `.claude/rules/review-lessons/`」）
- **檔案歸屬**：review-lessons 屬於 Polaris 框架管理的檔案，由 `ai-config/` 統一管理。在專案 repo 中這些檔案被 `.gitignore` 排除，不會進入 feature PR
- **不 commit**：萃取的 lesson 檔案不加入本次 fix commit——它們透過 reverse-sync 寫回 `ai-config/`
- **合併而非重複**：同一主題的 lesson 追加到既有檔案，不建新檔

### Review Lessons 畢業檢查（靜默）

萃取完成後，計算 `{base_dir}/<repo>/.claude/rules/review-lessons/` 的總條目數（每個 `^- ` 開頭的行 = 1 條）。若 >= 15 → invoke `review-lessons-graduation`。若 < 15 → 不輸出任何訊息。

### Reverse Sync（靜默）

萃取完成後，執行 reverse-sync 將 review-lessons 寫回 ai-config（source of truth）：

```bash
{base_dir}/polaris-sync.sh --reverse {project-name}
```

其中 `{project-name}` 從 repo 目錄名推導（例如 `kkday-b2c-web`）。

## 13. Slack 通知（僅當輸入來源為 Slack 時）

若 Step 0 標記了 `slack_source: true`，在修正完成並 push 後，回覆原始 Slack thread 通知 reviewer。

### 12a. 查找 Reviewer 的 Slack 帳號

從 Step 4 取得的 review comments 中，提取所有 reviewer 的 GitHub username（`user.login`），用 `slack_search_users` 搜尋對應的 Slack 帳號：

```
slack_search_users({ query: "<reviewer_github_username>" })
```

若找到匹配的 Slack user，取得其 user ID 用於 @mention。若找不到，使用 GitHub username 作為純文字顯示。

### 12b. 組裝 Slack 訊息

```
✅ *PR Review 修正完成*

<{pr_url}|#{number} {title}>

• 已修正: X 個 comments
• 不需修正: Y 個（已回覆原因）
• 需要討論: Z 個（已回覆提問）
• CI 修正: lint A 個 / test B 個

<@{reviewer_slack_id_1}> <@{reviewer_slack_id_2}> 請 re-review 🙏
{如有「需要討論」的項目，加一行：⚠️ 有 Z 個 comment 需要討論，請查看 PR}
```

### 12c. 發送 Slack 訊息

使用 `slack_send_message` MCP tool，回覆到原始 thread：

```
slack_send_message({
  channel_id: "<slack_channel_id>",
  thread_ts: "<slack_thread_ts>",
  text: "<組裝好的訊息>"
})
```

**重要**：必須帶 `thread_ts` 回覆在原始訊息的 thread 中，不要發成獨立訊息。

## Do / Don't

- Do: 先修 CI failures，再處理 review comments（避免 review 修正又引入新的 CI 問題）
- Do: 逐一回覆每個 review comment，不要遺漏
- Do: 修正時依據 `.claude/rules/` 規範，確保一致性
- Do: 不需修正時提供具體、有說服力的原因
- Do: 修正後跑相關測試確認不破壞功能
- Do: 在回覆中引用具體規範條目（如 `.claude/rules/typescript-guideline.md` Section X）
- Do: 補寫測試時參考同目錄既有測試的風格
- Do: commit 前執行 Post-fix Self Review，確保修正品質
- Do: 品質檢查通過後重跑 JIRA `[驗證]` 子單（invoke `verify-completion`），確認修正沒有破壞原本功能
- Don't: 使用 `eslint-disable` 或 `_` 前綴繞過 ESLint 錯誤
- Don't: 一次性 commit 所有修正而不回覆 comment
- Don't: 對 bot 自動產生的 comment（如 CI check、changeset-bot）進行回覆——修正後 bot 會自動更新
- Don't: 修正時做超出 comment 範圍的額外重構
- Don't: 跳過 CI check 修正直接處理 review comments
- Don't: Self Review 時重新審查整個 PR，只審查本次修正的 diff

## 流程串接

所有 CI failures 與 review comments 修正並 push 後：
1. 若為 Slack 來源 → 自動執行 Step 13 回覆 Slack thread，tag reviewer 請求 re-review
2. 若非 Slack 來源 → 主動提醒 RD「修正已 push，可以請 reviewer 重新檢視」
3. 如果有「需要討論」的項目，提醒 RD 追蹤 reviewer 的回覆
4. 如果只有 CI failures 沒有 review comments，直接報告 CI 修正結果即可

## Prerequisites

- `gh` CLI installed and authenticated
- Current branch has an open PR, or user provides PR number/URL
