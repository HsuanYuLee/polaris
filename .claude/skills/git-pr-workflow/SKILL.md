---
name: git-pr-workflow
description: >
  Complete PR lifecycle automation: quality check, pre-PR review loop (sub-agent iterative
  review), commit, changeset, open PR, JIRA transition to CODE REVIEW, and update PR
  description. This skill handles the post-coding path to PR — once code changes are ready,
  it runs quality gates, iterative AI review, and creates the PR. Use when the user says
  "發 PR", "open PR", "create PR", "PR workflow", "commit and PR", "changeset",
  "full pr flow", "pull request", "update PR description", or "準備發 PR".
  Do NOT use this for starting work on a ticket (use work-on instead) or for
  reviewing someone else's PR (use review-pr instead).
  Do NOT trigger for simple "發 PR" or "open PR" without mentioning quality check, review
  loop, or full workflow — use pr-convention for simple PR creation. This skill is
  for the COMPLETE lifecycle including quality gates and iterative AI review.
metadata:
  author: Polaris
  version: 3.3.0
---

# git-pr-workflow (v3.3.0)

**用途：** 完整 PR 生命週期自動化，從建立分支到 AI Code Review。v3.3.0：PR description 自動嵌入 AC Coverage checklist，讀取 JIRA AC 條目並標記覆蓋狀況。

**原始碼：** `.claude/skills/git-pr-workflow/SKILL.md`

---

## 流程總覽（10 步）

```
Branch → Simplify Loop → Quality Check → Pre-PR Review Loop → Commit → Changeset → Open PR → JIRA transition → Update PR desc → Post-PR Review Comment
```

---

### Step 1：Create Branch

如果 `git create-branch` CLI 可用：

```bash
git create-branch --jira --ci
```

否則使用 `jira-branch-checkout` skill，效果相同。

兩者都會從 JIRA ticket 自動產生 commitlint 格式的分支名稱（如 `feat/PROJ-123-add-user-auth`）。

### Step 2：Simplify Loop（程式碼簡化）

在品質檢查前，先用 `/simplify` 迭代審查變更的程式碼，確保重用性、品質與效率。

#### 流程

```
┌────────────────────────────────┐
│ 1. 執行 /simplify              │
│ 2. 有修改檔案?                 │
│    ├─ Yes → 回到 1            │
│    └─ No  → 進入 Step 3      │
└────────────────────────────────┘
```

#### 執行方式

使用 Skill tool 呼叫 `simplify`，它會：
1. 檢視目前變更的程式碼（與 base branch 的 diff）
2. 審查重用性（是否有重複邏輯可抽共用）、品質（是否有不必要的複雜度）、效率（是否有低效寫法）
3. 若發現問題，直接修正檔案

#### 迭代邏輯

- 每輪 `/simplify` 執行後，檢查 `git diff` 是否有新的變更
- **有變更** → 回報修改內容，再跑一輪 `/simplify`（新的修改可能引入新的簡化機會）
- **無變更** → `/simplify` 認為程式碼已經足夠乾淨，進入下一步
- **最多 3 rounds**。超過 3 輪仍有修改，停止迭代並回報，詢問使用者是否繼續

#### 回報格式

每輪結束回報：`Simplify round N/3: <修改摘要 or 無變更，進入品質檢查>`

### Step 3：Quality Check（品質檢查）

在 commit 前執行品質檢查，確保變更有足夠的測試覆蓋。

自動執行：

1. 找出變更的 source files
2. 檢查對應測試檔案是否存在
3. 執行相關測試並確認全部通過
4. 本地跑覆蓋率，預估 Codecov patch coverage（main-core ≥ 60%）
5. 輸出品質報告

如果報告顯示 ⚠️，應先補測試再繼續。

**Re-test-after-fix rule:** If the quality check found issues and code was modified to fix them, ALL tests and lint checks must be re-run from scratch before proceeding. Stale results from before the fix are invalid. This applies to:
- Test failures → fix → must re-run tests
- Lint errors → fix → must re-run lint
- Coverage drops → fix → must re-run coverage

Never proceed to commit/PR with test results that predate the most recent code change. If in doubt, re-run everything.

### Step 3.5：Verify Completion（行為驗證）

品質檢查通過後，invoke `verify-completion` 確認改動在實際運行時符合預期。這一步抓「測試過了但實際行不通」的問題——SSR hydration mismatch、missing runtime dependency、layout shift 等。

- 若 verify-completion 回報 PASS → 繼續 Step 4
- 若 verify-completion 回報 FAIL → 回到開發修正，修正後重新從 Step 3 開始
- 若為純 config 變更、型別定義修改等不需要行為驗證的場景 → 跳過此步驟

### Step 4：Pre-PR Review Loop（Sub-Agent 迭代審查）

在 commit 之前，啟動 Sub-Agent 對本地 diff 進行 code review，根據結果修正後再重新送審，直到沒有 blocking issues。這確保 PR 開出來時品質已經過關，減少人工 review 來回。

> Reviewer Sub-Agent 的角色定義基於 `references/sub-agent-roles.md` 的 Critic 角色。以下為本 skill 的流程特化。

#### 流程圖

```
┌─────────────────────────────────────────┐
│  Dev Agent                              │
│  ┌───────────────────────────────────┐  │
│  │ 1. 產生 local diff               │  │
│  │ 2. 啟動 Reviewer Sub-Agent (前景) │  │
│  │ 3. 等待 review 結果               │  │
│  │ 4. 有 blocking issues?            │  │
│  │    ├─ Yes → 修正 → 回到 1        │  │
│  │    └─ No  → 進入 Step 5 (Commit) │  │
│  └───────────────────────────────────┘  │
│                                          │
│  ┌───────────────────────────────────┐  │
│  │ Reviewer Sub-Agent (獨立 context) │  │
│  │ - 讀取 diff + .claude/rules/     │  │
│  │ - 逐項檢查                        │  │
│  │ - 回傳 JSON 結果                  │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

#### Reviewer Sub-Agent 檢查面向

| 面向 | 說明 |
| --- | --- |
| 型別安全 | interface/type 是否同步更新 |
| 邊界處理 | null check、fallback、error handling |
| 測試覆蓋 | 變更的 source file 是否有對應測試 |
| Changeset | 是否存在且格式正確 |
| 程式碼風格 | 是否符合 `.claude/rules/` 規範 |
| Schema.org 合規性 | 結構化資料相關改動（如適用） |

#### Blocking vs Non-blocking

* **Blocking**（必須修正才能發 PR）：型別錯誤、邏輯 bug、安全問題、缺少測試、格式規範違反
* **Non-blocking**（建議改進但不阻擋）：命名風格、註釋、micro-optimization

#### Sub-Agent 回傳格式

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

* `passed: true` → 沒有 blocking issues，進入 Step 5
* `passed: false` → Dev Agent 逐一修正 blocking issues，修正後回到 Step 4 重新 review

#### 迭代限制

* **最多 3 rounds**。如果 3 輪後仍有 blocking issues，停止迭代並列出未解決項目，詢問使用者是否手動處理或強制繼續。
* 每輪修正後回報進度：`Review round N/3: X blocking issues 已修正，重新送審中...`

#### 實際案例：PROJ-449

| Round | Blocking Issues | 修正內容 |
| --- | --- | --- |
| 1 | 2 | if 語句缺少大括號、Changeset 語言格式 |
| 2 | 2 | Changeset 缺少句尾句號、unstaged changes 提示 |
| 3 | 0 | 全部通過，進入 commit |

全程約 2.5 分鐘，無需人工介入。

### Step 5：AI Commit

```bash
git ai-commit --ci
```

Stage 變更後（`git add`），AI 自動產生並套用 commit message。

### Step 6：Add Changeset

直接用 Write tool 建立 changeset 檔案（不用 `changeset-jira`，它需要互動輸入會在 agent 環境 hang）。

1. 從 branch 名或 commit 取得 JIRA ticket key
2. 用 Write tool 建立 `.changeset/<kebab-case-name>.md`：

```markdown
---
'@your-org/app-main': patch
---

feat: [JIRA-KEY] 簡短描述
```

> 套件名稱從專案的 `package.json` name 欄位取得（e.g. `@your-org/app-main`）。

格式規則（參考專案 `.claude/rules/changeset-guideline.md`）：
* 內文只能一行，必須包含 JIRA 代碼
* 可加 conventional commit type prefix（`feat:`, `fix:`, `chore:` 等）
* 版本一律用 `patch`，除非使用者指定
* 不需版本變更的改動用 `---\n---`（empty changeset）

3. `git add` + commit changeset

#### Changeset 清理（Inherited Changeset 檢查）

新增 changeset 後，掃描 PR diff 是否包含不屬於本 PR 的 changeset：

1. `git diff origin/{baseRefName} --name-only -- .changeset/` 列出所有 changeset 檔案
2. 讀取每個 changeset 內容，比對本 PR 的 ticket key
3. 不匹配的 changeset → `git rm` 刪除（來自 dependency branch 的繼承）
4. 確保最終只有一個 changeset 且匹配本 PR ticket key

**為什麼**：task branch 若從另一個 task branch 分出（dependency），會繼承 parent 的 changeset，導致 PR diff 出現多個不相關的 changeset。每個 PR 只應有自己的一個 changeset。

### Step 7：Open PR

1. 讀取 `.github/pull_request_template.md` 取得模板結構
2. **偵測 base branch**（見下方邏輯）
3. PR title 格式：`[JIRA-KEY] <簡短摘要>`
4. PR body 填入 Description / Changed / **AC Coverage** / Screenshots / Related documents / QA notes

**AC Coverage 產生規則：**
- 從 JIRA ticket description 讀取 AC（Acceptance Criteria）條目
- 對照本次 PR 的 diff 和 verify-completion 結果，逐一標記：
  - `[x]` → 此 PR 已實作並驗證
  - `[ ]` → 未涵蓋（附說明：out of scope / 另一張單 / 待後續）
- 若 JIRA ticket 無 AC → 跳過此 section（不留空、不阻擋流程）

```md
## AC Coverage
- [x] AC1: 點擊日期後價格 300ms 內更新
- [x] AC2: API timeout → skeleton + retry
- [ ] AC3: 多幣別切換（out of scope, 見 PROJ-510）
```

#### Base Branch 偵測邏輯

子單的 PR 應對母單 feature branch 發（不是 develop），這樣 diff 只顯示本子單的改動。

```
1. 從 branch 名或 commit 取得 JIRA ticket key（如 PROJ-3461）
2. 查 JIRA ticket 的 parent:
   getJiraIssue → fields.parent.key（如 PROJ-483）
3. 若有 parent:
   a. 用 git branch -r 搜尋 pattern: origin/feat/<PARENT-KEY>-*
   b. 找到 → base = 該 feature branch（如 feat/PROJ-483-ttfb-optimization）
   c. 沒找到 → fallback develop
4. 若無 parent → base = develop（或 repo default branch）
```

偵測結果回報使用者確認：`Base branch: feat/PROJ-483-ttfb-optimization（母單 PROJ-483 的 feature branch）`

```bash
gh pr create --base <detected-base> --title "[JIRA-KEY] summary" --body "..."
```

### Step 8：Transition JIRA Status → CODE REVIEW

PR 建立後，自動將 JIRA ticket 狀態轉為 `CODE REVIEW`。如果轉換失敗（ticket 不在 IN DEVELOPMENT 狀態），忽略錯誤不中斷流程。

### Step 9：Update PR Description

```bash
git update-pr-desc --ci
```

AI 從 diff 自動產生 PR 描述。

### Step 10：Post-PR Review Comment — 跳過

~~PR 開出後留下 review comment。~~

**此步驟已停用。** 自己開的 PR 不應該自己留 review comment（`gh pr review`），PR review 應由其他人來做。Step 3 的 Pre-PR Review Loop 已確保品質，不需要再對自己的 PR 執行 review。

---

## v3.2.0 → v3.3.0 變更摘要

| 項目 | v3.2.0 | v3.3.0 |
| --- | --- | --- |
| PR body | Description / Changed / Screenshots / Related documents / QA notes | **新增 AC Coverage section**：從 JIRA AC 讀取條目，標記 `[x]`/`[ ]` 覆蓋狀況；無 AC 則跳過 |
| verify-completion 整合 | 行為驗證結果只影響是否繼續 | 驗證結果同時作為 **AC Coverage `[x]`/`[ ]` 依據** |

## v3.1.0 → v3.2.0 變更摘要

| 項目 | v3.1.0 | v3.2.0 |
| --- | --- | --- |
| Changeset | `npx changeset-jira`（需互動輸入，agent 環境會 hang） | **直接 Write tool 建檔**，不依賴 CLI |
| Base Branch | 固定 `develop` | **自動偵測母單 feature branch**：查 JIRA parent → 搜 remote branch → fallback develop |
| changeset-jira 依賴 | 需 `npx changeset-jira init` | **移除** |

## v3.0.0 → v3.1.0 變更摘要

| 項目 | v3.0.0 | v3.1.0 |
| --- | --- | --- |
| 程式碼簡化 | 無 | **Simplify Loop**（Step 2）：用 `/simplify` 迭代簡化，最多 3 輪 |
| 流程順序 | Branch → Quality Check → Review Loop | Branch → **Simplify Loop** → Quality Check → Review Loop |
| 步驟數 | 9 步 | **10 步**（新增 Step 2） |

## v2.0.0 → v3.0.0 變更摘要

| 項目 | v2.0.0 | v3.0.0 |
| --- | --- | --- |
| Review 時機 | PR 開出後（Step 8） | **PR 開出前**迭代審查（Step 3）+ PR 開出後補充（Step 9） |
| Review 執行方式 | Inline（主 Agent 直接執行） | **Sub-Agent**（獨立 context，客觀第三方） |
| 問題修正 | 人工根據 review comment 修正 | **Dev Agent 自動修正** blocking issues |
| 迭代次數 | 無（一次性 review） | 最多 3 輪迭代直到 passed |
| 步驟數 | 8 步 | **9 步**（新增 Step 3、Step 9） |

---

## Do / Don't

- Do: 每個 PR template section 都要填寫，不能留空
- Do: Changed 欄位要列出 side effects / risks
- Do: Test Plan 即使是 config-only 也要寫明
- Do: PR description 自動嵌入 AC Coverage checklist，讓 reviewer 一眼看出覆蓋狀況
- Don't: 用模糊的 title（如「fix bug」、「update code」）
- Don't: 貼上內部機密或長串聊天紀錄
- Don't: 找不到 AC 時硬塞空的 AC Coverage section — 直接跳過不留空佔位

## Post-PR: Feature Branch PR Gate

Task PR 建立完成後，執行 `references/feature-branch-pr-gate.md` 的偵測邏輯。此步驟靜默執行 — 條件成熟就建，條件不成熟就跳過，不打斷使用者。

## Prerequisites

* `gh` CLI 已安裝並認證
* JIRA credentials：`git pr-ai config --jira`
* AI agent：`git pr-ai config --agent`
