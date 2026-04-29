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

Scope-escalation returns follow the same rule. `engineering` raw sidecars are
consumed by `breakdown` only. If `breakdown` decides the issue must return to
`refinement`, it writes a `refinement-inbox/*.md` decision record first; `refinement`
reads that inbox record and never opens the raw sidecar. See
`refinement-return-inbox.md`.

## Role Boundaries

| Role | Skill | Responsibility | Must Not |
|------|-------|----------------|----------|
| **Architect** (Planning) | refinement | AC 定案、技術方案、codebase 探索 | 不建 JIRA 子單、不估點 |
| **Packer** (Packing) | breakdown | 拆 task + 建 JIRA 子單 + 產 task.md work order | 不做技術探索（有 `refinement.json` 時直接消費 artifact） |
| **Engineer** (Execution) | engineering | 實作 + TDD unit test + 開 PR | 不做 AC 驗證、不診斷 bug |
| **QA** | verify-AC | 跑 AC 驗證步驟、呈現 observed vs expected | 不判斷 FAIL 原因（交給人工 disposition） |
| **Diagnosis** | bug-triage | Root cause 分析、規劃修復 | 不直接寫 code（交給 engineering） |

## Artifact Schemas

**此章節為 Atom 層 single source of truth**。所有 pipeline validator script（`scripts/validate-*.sh`）都從此文件派生；skill 產出 artifact 時的必填欄位以此為準。若本章節與個別 skill 的 SKILL.md 描述衝突，**以本章節為準**。

作用範圍（DP-025 locked 2026-04-22）：檔案型 artifact（refinement.json / task.md）。**不含** JIRA comment 結構（bug-triage `[ROOT_CAUSE]`、verify-AC `## 驗證結果`），見 DP-025 scope boundary。

所有欄位驗證以 **hard-fail**（validator exit 2）為預設；若實務上發現必填欄位阻礙 refinement / breakdown 推進，再個別討論降級。

### refinement.json Schema（producer: refinement Tier 2+）

完整欄位與型別定義見 `refinement-artifact.md`。本節只列 validator 必驗的**必填欄位**與**結構硬條件**。

| 欄位 | 型別 | 必填？ | 驗證規則 |
|------|------|-------|----------|
| `epic` | string | **必填** | 非空；JIRA key 格式 `[A-Z][A-Z0-9]+-[0-9]+` |
| `version` | string | **必填** | 非空 |
| `created_at` | string | **必填** | 非空；ISO8601 建議 |
| `modules` | array | **必填** | 長度 ≥ 1；每個 module 必含 `path`（string, 非空）+ `action`（string, `create`/`modify`/`delete`/`investigate`） |
| `acceptance_criteria` | array | **必填** | 長度 ≥ 1；每個 AC 必含 `id`（string, 非空）+ `text`（string, 非空）+ `verification`（object） |
| `acceptance_criteria[].verification` | object | **必填** | 必含 `method`（string, `playwright`/`lighthouse`/`curl`/`unit_test`/`manual`）+ `detail`（string, 非空） |
| `dependencies` | array | **必填**（可為空陣列） | 若非空，每個 dep 必含 `type`（string）+ `target`（string）+ `blocking`（bool） |
| `edge_cases` | array | **必填**（可為空陣列） | 若非空，每個 edge case 必含 `scenario`（string, 非空）+ `handling`（string, 非空） |

**可選欄位**（不驗但 refinement-artifact.md 定義）：`tier`、`tier_signals`、`refinement_round`、`completeness`、`rd_decisions`、`gaps`、`downstream`、`research`、`references`、`type`、`direction_assessment`。

Validator：`scripts/validate-refinement-json.sh <path>` 或 `--scan <workspace_root>`。

### task.md Schema（producer: breakdown / engineering update）

詳細章節模板見下方 `## task.md Schema`。Validator 必驗項目：

| 項目 | 驗證規則 |
|------|----------|
| Header `# T{n}[suffix]: {summary} ({SP} pt)` | 必須存在且格式正確（`[suffix]` 為 `a-z*` 支援 split subtasks） |
| Metadata line | Legacy `> Epic: ... \| JIRA: {KEY} \| Repo: ...` 或 canonical `> Source: {SOURCE_ID} \| Task: {WORK_ITEM_ID} \| JIRA: {JIRA_KEY_OR_N/A} \| Repo: ...`；`Repo:` 必含非空值 |
| Identity | Parser 輸出 canonical `identity.source_type` / `identity.source_id` / `identity.work_item_id` / nullable `identity.jira_key`；legacy `task_jira_key` 只是 migration alias |
| `## Operational Context` | 必須存在；identity cells 可為 legacy `Task JIRA key` + `Parent Epic`，或 canonical `Source type` + `Source ID` + `Task ID` + `JIRA key`；另必含 `Test sub-tasks`、`AC 驗收單`、`Base branch`、`Task branch`、`References to load` |
| `## Verification Handoff` | 必須存在 |
| `## 目標` | 必須存在且非空 |
| `## 改動範圍` | 必須存在且非空（至少 1 行表格 data 或 bullet） |
| `## 估點理由` | 必須存在且非空（至少 1 行非空文字） |
| `## 測試計畫` | 必須存在 |
| `## Test Command` | 必須存在；內含 fenced code block |
| `## Test Environment` | 必須存在；詳細規則見下方 "Test Environment Level" 段 + DP-023 runtime contract |
| `## Verify Command` | 必須存在；內含 fenced code block |
| Frontmatter `status` | 可選；若存在應為 `IN_PROGRESS` / `IMPLEMENTED` / `BLOCKED` 其中之一（目前不 enforce；留給 `scripts/mark-spec-implemented.sh`） |
| Frontmatter `depends_on` | 可選；若存在須為 array of task id strings（如 `["T1", "T2"]`）；驗證拓撲見下方 |

Validator：`scripts/validate-task-md.sh <path>` 或 `--scan <workspace_root>`。

**Runtime contract fields**（DP-023）：`Level` / `Runtime verify target` / `Env bootstrap command` 三欄位 + `Level=runtime` 時 Verify Command host alignment — 繼續由 `validate-task-md.sh` 的 runtime block enforce，不在此重述。

### task.md Cross-File Schema（depends_on + fixture 存在性）

依賴同 Epic 其他 task.md 或檔案系統：

| 規則 | 驗證邏輯 |
|------|----------|
| `depends_on` 必須指向同目錄既有 task | 每個 `depends_on` item（如 `"T1"`）對應 `{tasks_dir}/T1.md` 必須存在 |
| `depends_on` 不可循環 | DFS 偵測 cycle；發現 cycle 直接 fail 並印出 cycle chain |
| `## Test Environment` 若宣告 `Fixtures: {path}`（非 `N/A`），該 path 必須存在 | `{path}` 相對於 workspace_root 或 Epic folder 解析；找不到檔案/目錄 → fail |

Validator：`scripts/validate-task-md-deps.sh <tasks_dir>` 或 `--scan <workspace_root>`。

### Dependency Binding (DP-028)

**Writer**: `breakdown` skill Step 14（寫 task.md + 依 DAG 順序建 task branch）
**Consumer**: `engineering` skill（first-cut + revision mode）

當 task 有跨 task 依賴（`depends_on` 非空）時，`Depends on`（`## Operational Context` 表格 row）與 `Base branch` 是 engineering 消費依賴的**主要接口** — engineering 不再需要自行 reconcile depends_on 語義與切分支策略，兩欄位即為 deterministic source of truth。本節為 DP-025 task.md schema 的 **additive 擴充**，不變動既有 required fields。

#### 三層消費模型（DP-028 Decision D2）

engineering 分三層 deterministic 消費 `depends_on`，每層各自可驗證，不依賴 LLM 推理：

| 層 | Owner | 行為 |
|----|-------|------|
| **1. Snapshot** | breakdown Step 14 | 寫 task.md 時，`Base branch` 已是正確值：有 `depends_on` → 最下游依賴的 task branch（topological 最末）；無 `depends_on` → feat 分支。engineering 讀 task.md 即用，不推理 |
| **2. Resolve** | `scripts/resolve-task-base.sh` | engineering pre-work rebase（`engineer-delivery-flow.md § 4.5` first-cut / `§ R0` revision）呼叫 helper：輸入 task.md → 輸出 resolve 後的 base。若 `Base branch` 指向的 task branch 已 merged 到 feat → 動態改為 feat；未 merged → 維持 snapshot 值 |
| **3. Gate** | `.claude/hooks/pr-base-gate.sh`（PreToolUse） | 擋 `gh pr create --base X`，當 X 不符 resolve 後的 Base branch → exit 2。Bypass：`POLARIS_SKIP_PR_BASE_GATE=1` |

#### Cross-field Rule（DP-028 D5 / D6 / Blind #3）

以下規則由 validator 強制（hard-fail），補在 DP-025 既有欄位驗證之上：

| 規則 | 驗證邏輯 | Validator |
|------|----------|-----------|
| `depends_on` 非空 ⇒ `Base branch` 必須 `task/...` | `## Operational Context` 表格 `Base branch` cell 值不得為 `feat/...` / `develop` / `main` 等；須為 `task/{DEP_KEY}-{slug}` | `scripts/validate-task-md.sh`（cross-field rule） |
| `depends_on` 陣列長度 ≤ 1（強制線性 chain） | frontmatter `depends_on: [...]` 若長度 > 1 → fail。非線性依賴是「scope 太大 / 規劃不清」的信號，breakdown 須重排依賴或拆 Epic | `scripts/validate-task-md-deps.sh`（is-linear-dag） |

#### 與其他 schema 段落的關係（additive）

- **DP-023 runtime contract**（`Level` / `Runtime verify target` / `Env bootstrap command`）— 不變。Dependency Binding 不觸碰 runtime 欄位
- **DP-025 task.md required fields**（`## Operational Context` / `## 改動範圍` / `## 估點理由` / `## Test Command` / `## Verify Command`）— 不變。Dependency Binding 僅擴張 `Base branch` 的 cross-field rule 與 `depends_on` 的 DAG 規則
- **PR base 欄位刻意不新增**（DP-028 D6）：`gh pr create --base` 的值 = resolve 後的 `Base branch`，單一 source of truth，避免雙欄位同步風險

#### Revision mode cascade（DP-028 Blind #6）

engineering revision mode（`§ R0` pre-work rebase）每次進入都重跑 Resolve 層 — 若期間依賴 task branch 被 force-push 重寫或 merged 到 feat，Resolve 回傳的 base 會自動跟上，hook 也會依新 base 放行 `gh pr create`。cascade rebase 不需要人工介入。

### Schema 演進

- 新增欄位採 optional（下游 skill 用 `?.` 存取），`version` 遞增
- 必填欄位升級為 required 前，先發 validator 公告（使用 `--scan` 盤點現況）
- 刪除欄位需走 deprecation path（先 optional 標記 + warning，一個 minor 後移除）

## task.md Schema

Breakdown 產出的 task.md 是 engineering 的唯一施工輸入（除了 codebase、company handbook、repo handbook）。Engineering / sub-agent 須自行讀取 `{base_dir}/.claude/rules/{company}/handbook/index.md` + index 引用子文件，以及 `{repo}/.claude/rules/handbook/index.md` + index 引用子文件；handbook 不會自動載入。必須 self-contained。

```markdown
# T{n}: {Task summary} ({SP} pt)

> Source: {SOURCE_ID} | Task: {WORK_ITEM_ID} | JIRA: {JIRA_KEY_OR_N/A} | Repo: {repo_name}

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | {jira|dp} |
| Source ID | {EPIC_KEY_OR_DP_ID} |
| Task ID | {WORK_ITEM_ID} |
| JIRA key | {JIRA_KEY_OR_N/A} |
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
> Monorepo 須包含正確的工作目錄（如 `pnpm --dir apps/main exec vitest run`）。

\`\`\`bash
{專案特定的測試指令，含正確工作目錄}
\`\`\`

## Test Environment

> engineering 執行 Verify Command 前，依本區塊決定如何準備環境。**pointer 模式** — 不把 dev env 細節複製進 task.md，由 engineering sub-agent 自行讀 workspace-config 和 fixture runner。

- **Level**: {static | build | runtime}
- **Dev env config**: `workspace-config.yaml` → `projects[{repo_name}].dev_environment`
- **Fixtures**: {`specs/{EPIC}/tests/mockoon/` 或 `N/A`}
- **Runtime verify target**: {`https://dev.kkday.com/...` | `http://localhost:3001/...` | `N/A`}
- **Env bootstrap command**: {`./scripts/polaris-env.sh start <company> --project <repo>` | `<company>/scripts/*.sh` | `N/A`}

**Level 定義**：

| Level | 需要什麼 | Engineering 須執行 |
|-------|---------|------------------|
| `static` | 只讀 source code（grep、檔案存在性、config 註冊） | 無 — 直接跑 Verify Command |
| `build` | 需要 `pnpm build` 產 `.output/` 才能跑 Verify Command | 在 worktree 跑 build，不需啟動 dev server |
| `runtime` | 需要 live endpoint（curl / dev server / nginx）才能跑 Verify Command | 依 `dev_environment.requires` 啟動 dependencies（如 `kkday-web-docker`）+ `start_command` 起 dev server + `health_check` 驗證 ready，**若 Fixtures 非 N/A**，同時起 `mockoon-runner.sh start {fixture_path}` |

**`runtime` 補充說明（避免 URL 誤解）**：
- `dev_environment.health_check` 只用於「服務是否 ready」檢查，未必等於 smoke 驗證入口。
- `Runtime verify target` 才是 Verify Command 要打的實際 URL。
- 目標 URL 可能是 localhost 或 local domain（透過 hosts / docker proxy 指到本機），不應預設視為遠端環境。
- 若 workspace / company 有標準啟環境腳本，`Env bootstrap command` 應優先引用該腳本，避免把公司知識硬編在 skill 內。
- `Level=runtime` 時，`Runtime verify target` 視為**必填硬契約**；`health_check` 不可替代此欄位。
- `Level=runtime` 時，Verify Command 必須對 live endpoint 驗證，且目標 host 必須與 `Runtime verify target` 一致（同 host，可不同 path）。
- Deterministic validator 規則：`Level=runtime` 但 Verify Command 無 live endpoint 或 host 不一致，`scripts/validate-task-md.sh` 直接 fail。

**不放進 task.md 的細節**（engineering sub-agent 自己從 workspace-config 讀）：
- `start_command`、`ready_signal`、`base_url`、`health_check`
- `requires`（依賴的其他 service，如 `kkday-web-docker`）
- `is_monorepo` / `monorepo_apps`

## Verify Command

> breakdown 產出，engineering 必須執行並附上 output。不可修改指令內容。
> `Level=runtime` 時，此指令必須命中 `Runtime verify target`（同 host）做 runtime 驗證；僅 grep / 檔案存在性檢查不合格。

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
| Test Environment Level + pointer + Runtime verify target + Env bootstrap command | dev env 細節（start_command / requires / health_check） |
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

## Evidence Artifact（Handoff 層的證據載體）

本文件定義 handoff contract 的**結論文件**（task.md、JIRA comment）。支撐這些結論的**原始 tool return**（grep 結果、error trace、endpoint response）由 evidence artifact 承載：

- 規格：[handoff-artifact.md](handoff-artifact.md) — Summary/Raw Evidence 格式、20KB cap、secret scrub
- 位置：`specs/{EPIC}/artifacts/{skill}-{scope}-{ticket}-{ts}.md`（與 Completion Envelope Detail 合流）
- 讀取：下游 sub-agent **on-demand**，預設信任結論文件
- P4 pilot：bug-triage → engineering（DP-024 P4 2026-04-22）

## 和其他 references 的關係

- [handoff-artifact.md](handoff-artifact.md) — Evidence artifact 格式規範（本文件結論層的補充）
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

設計決策：2026-04-13，GT-521 breakdown v2 試跑後討論 pipeline 權責拆分。
