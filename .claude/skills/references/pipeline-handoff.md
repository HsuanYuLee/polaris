# Pipeline Handoff Contract

Defines the role boundaries and handoff inputs/outputs between **breakdown → engineering → verify-AC → bug-triage**. This is the contract document — each skill's SKILL.md implements its own side of the contract.

## Pipeline Overview

```
refinement → breakdown（打包 task.md）
                ↓
          engineering（施工 + TDD unit test）
                ↓
          verify-AC（QA agent）
            ├─ PASS → 驗收單轉 Done、Epic 可 merge
            └─ FAIL（人工 disposition）
                ├─ 實作偏差 → bug-triage → engineering → re-verify
                └─ 規格問題 → refinement → breakdown → engineering → verify
```

Core principle: **each skill consumes a self-contained input and produces a well-defined output.** No skill needs to reach back into upstream artifacts to fill gaps.

## Role Boundaries

| Role | Skill | Responsibility | Must Not |
|------|-------|----------------|----------|
| **Architect** (Planning) | refinement | AC 定案、技術方案、codebase 探索 | 不建 JIRA 子單、不估點 |
| **Packer** (Packing) | breakdown | 拆 task + 建 JIRA 子單 + 產 task.md work order | 不做技術探索（有 `refinement.json` 時直接消費 artifact） |
| **Engineer** (Execution) | engineering | 實作 + TDD unit test + 開 PR | 不做 AC 驗證、不診斷 bug |
| **QA** | verify-AC | 跑 AC 驗證步驟、呈現 observed vs expected | 不判斷 FAIL 原因（交給人工 disposition） |
| **Diagnosis** | bug-triage | Root cause 分析、規劃修復 | 不直接寫 code（交給 engineering） |

## task.md Schema

Breakdown 產出的 task.md 是 engineering 的唯一輸入（除了 codebase 和 repo handbook — sub-agent 須自行讀取 `{repo}/.claude/rules/handbook/`，不會自動載入）。必須 self-contained。

```markdown
# T{n}: {Task summary} ({SP} pt)

> Epic: {EPIC_KEY} | JIRA: {TASK_KEY} | Repo: {repo_name}

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | {TASK_KEY} |
| Parent Epic | {EPIC_KEY} |
| Test sub-tasks | {KEYS}, ... |
| AC 驗收單 | {AC_TICKET_KEY} |
| Base branch | {feature_branch_name} |
| Task branch | task/{TASK_KEY}-{slug} |
| References to load | - `skills/references/{name}.md`<br>- ... |

## Verification Handoff

AC 驗證**不在本 task 範圍**，委派至 {AC_TICKET_KEY}（由 verify-AC skill 執行）。

## 目標

{What this task accomplishes in one paragraph}

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| ... | ... | ... |

## Allowed Files

> breakdown 時依改動範圍列出，engineering 超出此清單的修改觸發 risk scoring +15%。

- `{file_path_1}`
- `{file_path_2}`
- ...

## 估點理由

{Why this is {SP} pt}

## 測試計畫（code-level）

供 TDD 使用，對應到 test sub-tasks：

- unit test: {描述} → {Test sub-task key}
- ...

## Test Command

> breakdown 產出。engineering 跑測試時**必須使用此指令**，不可自行推導。
> 來源優先順序：workspace-config `projects[].dev_environment.test_command` → 專案 CLAUDE.md → fallback `npx vitest run`。
> Monorepo 須包含正確的工作目錄（如 `pnpm -C apps/main vitest run`）。

\`\`\`bash
{專案特定的測試指令，含正確工作目錄}
\`\`\`

## Verify Command

> breakdown 產出，engineering 必須執行並附上 output。不可修改指令內容。

\`\`\`bash
{一個可執行的 shell 指令，驗證本 task 的核心改動在 runtime 是否生效}
\`\`\`

預期輸出：{PASS 時應看到的內容}
```

### Schema 邊界

| 放 task.md | 不放 task.md |
|-----------|-------------|
| Operational context（JIRA keys、branch） | Epic description / refinement artifact |
| 目標、涉及檔案、測試計畫（code-level） | AC 驗證場景（business-level）→ 在 AC 驗收單 |
| Verify Command（per-task smoke test） | 完整 AC 驗證流程（verify-AC 的工作） |
| Test Command（專案特定的測試指令） | 通用 test 指令（sub-agent 不可自行推導） |
| 估點理由 | 技術方案選項分析（refinement 已定） |
| References 清單 | handbook 內容（sub-agent 須自行讀取，不複製進 task.md） |

## Handoff Contracts

### breakdown → engineering

**Input to engineering**: `specs/{EPIC}/tasks/T{n}.md`（符合上述 schema）

**Pre-conditions（breakdown 產出前須滿足）**：
- JIRA task 已建立、Test sub-tasks 已建立、AC 驗收單已建立
- Feature branch 已存在
- 所有 JIRA keys 已回填進 task.md

**Contract**：engineering 讀 task.md 即可開工，不需回頭看 breakdown.md 或 refinement.md。

### engineering → verify-AC

**Input to verify-AC**: `{AC_TICKET_KEY}`（Epic 驗收單 key）

**Pre-conditions（engineering 產出前須滿足）**：
- 所有 test sub-tasks → Done
- PR 已開、unit test pass、CI 綠
- task.md 在 PR description 中 link 到 AC 驗收單

**Contract**：verify-AC 從驗收單 task.md（`specs/{EPIC}/tasks/{V-KEY}.md`）讀取 fixture 設定與環境指令，從 AC 驗收單 JIRA description 讀取驗證步驟。若無 task.md → fallback 到 `specs/{EPIC}/tests/mockoon/` 自動偵測。

### verify-AC PASS

**Output**：
1. AC 驗收單轉 Done
2. 驗收單 comment（PASS 格式，見 `epic-verification-structure.md` § 驗證結果 Comment）
3. Notify Strategist：Epic 可以 merge

### verify-AC 四態 Disposition

AI 不擅自壓通過。每條 AC 驗證結果分四態：

| 狀態 | 條件 | 後續 |
|------|------|------|
| **PASS** | 步驟能機器檢查 + 通過 | 自動進入整體 PASS 判定 |
| **FAIL** | 步驟能機器檢查 + 未通過 | 進入下方 FAIL Disposition Gate |
| **MANUAL_REQUIRED** | 步驟需主觀判斷（UX、視覺、文案） | 輸出 checklist 給使用者手動勾 |
| **UNCERTAIN** | 能跑但 AI 不確定斷言正確性 | 附原始 observation，使用者判斷 |

**整體結論判定**：
- 全部 PASS → 驗收單 Done
- 任一 FAIL → 走 FAIL Disposition Gate（見下）
- 有 MANUAL_REQUIRED 或 UNCERTAIN 但無 FAIL → 等使用者處理後再判定

### MANUAL_REQUIRED / UNCERTAIN 累積為能力擴充素材

每次遇到 UNCERTAIN 或 MANUAL_REQUIRED，記錄到 `polaris-learnings.sh`（type: verify-ac-gap）。同類案例累積 3 次 → 抽成自動驗證 pattern，擴充 verify-AC skill 能力。

### FAIL → Human Disposition Gate

**Output to JIRA（AC 驗收單 comment）**：

```markdown
## 驗證結果 — {date}

**結論：FAIL ❌**

| 步驟 | 結果 | Observed | Expected |
|------|------|----------|----------|
| 1. {操作} | ✅ | {actual} | {expected} |
| 2. {操作} | ❌ | {actual} | {expected} |

環境：{SIT / local / staging}

## Disposition（請人工勾選）

- [ ] **實作偏差** — code 沒達到 AC 行為 → 走 bug-triage
- [ ] **規格問題** — AC 描述錯誤/不完整 → 回 refinement
```

**AI 只呈現事實，不判斷原因。** Disposition 由人工勾選後，skill 再依勾選路由。

### FAIL → bug-triage（實作偏差）

當人工勾「實作偏差」時，verify-AC 自動：

1. **建 Bug ticket**（issueType: Bug, parent: Epic）
2. **貼 comment on Bug ticket**（載體 = JIRA comment，格式見下）
3. **在 AC 驗收單留 comment**：「FAIL — 追蹤於 {BUG_KEY}」
4. **Routing** → bug-triage skill，以 Bug ticket key 為入口

#### Bug ticket 必要資訊

```markdown
## [VERIFICATION_FAIL]

### 基本資訊
- 來源：verify-AC on {AC_TICKET_KEY}
- Epic：{EPIC_KEY}
- **分析對象：{feature_branch_name} 上的 code**（不是 develop / main）
- Repos 涉入：{repo_a}, {repo_b}
- PR merge 狀態：未 merge（僅在 feature branch 測到，develop 不受影響）

### 實作追溯
- 相關 Task keys：{TASK_KEY_1}, {TASK_KEY_2}
- 相關 PR numbers：#{PR_1}, #{PR_2}
- Feature branch commit range：{base_sha}..{head_sha}

### 失敗項目
| AC# | Step | Observed | Expected |
|-----|------|----------|----------|
| AC#{N} | {描述} | {actual} | {AC spec} |

### 復現條件
- URL / page：{url}
- Locale：{zh-tw / en / ja ...}
- Device / viewport：{desktop 1920 / mobile 375 ...}
- Mockoon fixtures：{fixture_set_name 或 N/A}

### 驗證 metadata
- 驗證工具：{curl / Playwright / Lighthouse}
- 執行時間：{timestamp}
```

#### Assignee 規則

| 情境 | Assignee |
|------|----------|
| 1 個 task 涉入 | 該 task 實作者 |
| 多個 task 涉入 | Epic owner |
| 實作者不在（PTO / 離職） | Epic owner |
| Bug-triage 後發現 root cause 在**非本 Epic 的共用 code** | Re-assign 給共用 code 原作者 |

**重要**：Assignee 是**運維層**（誰去修），**bug-triage skill 對此 blind**：
- Bug-triage dispatch prompt **不包含 assignee 欄位**
- Bug-triage 不跑 `git log --author` 或 `git blame`
- 避免「X 通常怎麼寫錯」的錨定偏差，確保純粹的 root-cause 分析

### FAIL → refinement（規格問題）

當人工勾「規格問題」時，verify-AC 自動：

1. **在 Epic 上留 comment**（載體 = JIRA comment，prefix `[VERIFICATION_SPEC_ISSUE]`）
2. **在 Epic 加 label**：`verification-spec-issue`
3. **在 AC 驗收單留 comment**：「規格待 refinement 釐清 → 見 Epic {EPIC_KEY} comment」
4. **不建新 ticket**（規格問題不值得佔一張單）

Refinement skill 的 batch readiness scan 會自動抓到帶此 label 的 Epic，進入規格討論流程。AC 更新後，breakdown 重新打包受影響的 task.md（增量更新）。

#### Epic comment 格式

```markdown
## [VERIFICATION_SPEC_ISSUE] AC#{N}

- 來源：verify-AC on {AC_TICKET_KEY}
- Observed：{actual behavior}
- Expected (per AC)：{AC spec}
- 規格問題：{AC 描述哪裡不清楚 / 矛盾 / 不完整}
- 建議方向：{可能的修改建議，給 refinement 參考}
```

## Re-verify 觸發（Hybrid: Explicit + Opportunistic）

Strategist 沒有 passive event 能力（不做 webhook / polling），因此 re-verify 透過兩條路徑觸發：

| 類型 | 機制 | 實例 |
|------|------|------|
| **Explicit**（主要） | 使用者明確說 | 「驗 {EPIC}」、「verify {AC_TICKET}」 |
| **Opportunistic**（次要） | 既有 state-check skill 跑時順便偵測並 surface | `converge`、`epic-status`、`next`、`my-triage`、`standup` |

### 偵測條件

當 state-check skill 掃到 Epic 同時滿足以下所有條件 → surface 建議執行 verify-AC：

- Feature branch 所有 task PR 已 merge
- AC 驗收單狀態仍是 Open（或 FAIL）
- 沒有正在進行中的 bug-triage Bug ticket

### 實作影響

P4 實作 verify-AC skill 時，同步更新這幾個 skill 的 SKILL.md 加入偵測步驟：`converge`、`epic-status`、`next`、`my-triage`、`standup`。**不做 webhook、不做 polling。**

## 過渡策略

一刀切：新 pipeline 在 **P5 全部完成後**生效，之前的 Epic 跑完現況格式。切換標誌為 commit message `feat(pipeline): enable new verify-AC flow`。

## 整併 verify-completion（P4 前置）

現有 `verify-completion` skill 與 verify-AC 在「跑驗證 + 呈現事實 + 不擅自通過」的核心動作重疊。P4 啟動前必須：

1. 讀 `verify-completion/SKILL.md`
2. 判斷兩者是 task-level vs Epic-level 還是完全重疊
3. 選一：**整併**（rename + 擴充支援 AC ticket input）或 **保留分工**
4. 傾向整併，減少概念冗餘

## Loop 終止條件

Pipeline 收斂在以下任一條件：
- verify-AC 全部 PASS → Epic merge
- 人工介入中止（scope 撤回、Epic 取消）

如果 verify-AC ↔ bug-triage 來回 **≥ 3 輪**，Strategist 必須介入檢查：是否為架構問題，而非單點 bug。

## 和其他 references 的關係

- [epic-verification-structure.md](epic-verification-structure.md) — 驗收單本身的結構（本文件描述的是 pipeline handoff，不是 ticket 結構）
- [jira-subtask-creation.md](jira-subtask-creation.md) — breakdown 建 JIRA 子單的機械步驟
- [branch-creation.md](branch-creation.md) — task branch 建立流程（engineering 消費）
- [sub-agent-roles.md](sub-agent-roles.md) — 各 skill 內部 sub-agent dispatch 規格

## Implementation Phases

本 reference 為 pipeline 拆分的 contract 文件。實作依序為：

1. **P1**（本文件）— 定義 task.md schema + 角色邊界
2. **P2** — 更新 breakdown skill 產出符合 schema 的 task.md
3. **P3** — 精簡 engineering dispatch prompt 只帶 task.md
4. **P4** — 新建 verify-AC skill（含 disposition gate）
5. **P5** — 更新 bug-triage 接受 AC-FAIL input + routing table

## 來源

設計決策：2026-04-13，PROJ-123 breakdown v2 試跑後討論 pipeline 權責拆分。
