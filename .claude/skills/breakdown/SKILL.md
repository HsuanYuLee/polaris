---
name: breakdown
description: "Universal planning skill: Bug reads ROOT_CAUSE then estimates; Story/Task/Epic explores codebase then splits into sub-tasks with estimates, and packs each sub-task into a self-contained task.md work order for engineering to consume. Also handles scope challenge (advisory mode). Trigger: 拆單, 'split tasks', 拆解, 'breakdown', 'break down', 子單, 'sub-tasks', 評估這張單, 'evaluate this ticket', 估點, 'estimate', 'scope challenge', '挑戰需求', 'challenge scope', '需求質疑'."
metadata:
  author: Polaris
  version: 2.2.0
---

# Breakdown — Packer

> **你是估價師 + 工地主任，不是建築師。** 你接過藍圖（refinement artifact 或 bug-triage 根因），拆成工項、估價、排班、打包工單（task.md）。你不做需求探索、不討論技術方案 — 那是 Architect（refinement）的工作。你的產出是 JIRA 子單 + task.md，讓 Engineer（engineering）能直接施工。

三層架構的 Layer 2，適用所有 ticket 類型：Bug / Story / Task / Epic。

## 前置：讀取 workspace config

讀取 workspace config（參考 `references/workspace-config-reader.md`）。
本步驟需要的值：`jira.instance`、`jira.projects`（取得 project keys）。
若 config 不存在，使用 `references/shared-defaults.md` 的 fallback 值。

## Workflow

### 1. 取得 Ticket + 偵測類型

從以下來源取得 ticket key（優先順序）：
1. 使用者直接提供的 issue key（如 `PROJ-432`）
2. 當前 branch 名稱：`feat/PROJ-432` → `PROJ-432`
3. 詢問使用者

使用 MCP 工具讀取 ticket：

```
mcp__claude_ai_Atlassian__getJiraIssue
  cloudId: {config: jira.instance}
  issueIdOrKey: <TICKET>
```

讀取後判斷 **Issue Type** 並路由：

| Type | Path | 前置條件 |
|------|------|---------|
| Bug | Bug Path (B1-B4) | 必須有 `[ROOT_CAUSE]` comment（由 bug-triage 產出）|
| Story / Task / Spike | Planning Path (4-16) | — |
| Epic | Planning Path (4-16) | — |

**Bug 前置檢查**：用 JQL 或 getJiraIssue 的 comment 檢查是否有 `[ROOT_CAUSE]` 標記。若無：
> 「這張 Bug 還沒有根因分析。請先跑 `bug-triage {TICKET}` 完成診斷。」

同時檢查 ticket 是否**已有估點**或**已有子單**。若是，提示使用者確認是否覆蓋。

### 2. 辨識對應專案

從 ticket 的 **Summary** 中擷取 `[...]` tag，依 `references/project-mapping.md` 對應到本地專案路徑（`{base_dir}/<專案目錄>`）。不分大小寫比對。

若 Summary 中沒有 tag，進一步檢查 **Labels** 和 **Components** 欄位。仍無法匹配時，詢問使用者指定專案。

### 3. 偵測開發進度

在分析需求之前，先確認這張 ticket 是否已有開發進度：

1. **檢查既有子單** — 用 JQL `parent = <TICKET_KEY>` 查詢
2. **檢查 feature branch** — `git branch -a | grep <TICKET_KEY>`
3. **檢查 commit 紀錄** — 如果有 branch，用 `git log` 檢視已完成的工作

根據偵測結果調整行為：
- **已有子單** → 列出既有子單，詢問是否要補充
- **已有 branch + commits 但無子單** → 提示根據已完成工作建立子單追蹤
- **全新** → 進入正常流程

---

## Bug Path（Bug only）

### B1. 讀取根因分析

從 JIRA comment 中擷取 bug-triage 產出的結構化資訊：
- `[ROOT_CAUSE]` — 根因、檔案位置、問題描述
- `[IMPACT]` — 影響範圍、變更風險
- `[PROPOSED_FIX]` — 修正方向、預估改動範圍

### B2. 估點 + 規劃

依 `references/estimation-scale.md` 評估修正工作量。

**依複雜度分流：**

| 複雜度 | 條件 | 處理方式 |
|--------|------|---------|
| 簡單 | 1-2pt，改動 ≤ 3 檔案 | 不建子單，直接估點 → 銜接 engineering |
| 複雜 | 3+pt 或跨模組 | 拆子單（進入 Planning Path Step 6 起） |

**簡單 Bug 規劃輸出：**

```
## Bug 修復規劃

**Root Cause**: （摘要自 bug-triage）
**Proposed Fix**: （修正方案 + 涉及檔案）
**估點**: X pt（對應標準：...）

### 驗證計畫
**Local 驗證（PR 前）：**
- 重現原 bug 步驟 → 預期修正後不再發生
- 邊界場景 → 預期行為正常

**Post-deploy 驗證（如適用）：**
- 需真實環境確認的項目
```

### B3. 確認

呈現規劃給使用者確認。使用者可調整估點或修正方案。

### B4. 寫入 JIRA + 銜接

1. 查詢 Story Points 欄位 ID（依 `references/jira-story-points.md`）
2. 更新 ticket 估點 + 回查驗證
3. 將規劃以 comment 寫入 JIRA（格式同 B2 輸出）

**銜接：**
- 簡單 Bug → 「規劃完成。輸入 `做 {TICKET}` 開始修復。」
- 複雜 Bug → 進入 Planning Path Step 6（拆子單），帶入 ROOT_CAUSE 作為分析基礎，跳過 Step 4-5 的探索（根因已知）

---

## Planning Path（Story / Task / Epic）

### 4. 分析需求 + Codebase 探索（自適應 Explore）

從 ticket 中提取關鍵資訊：
- **Summary** — 概述
- **Description** — 詳細需求、AC
- **附件連結** — PRD、Figma、API doc

如果 description 資訊不足以拆單，主動列出缺少的資訊並詢問使用者補充。

**Refinement Artifact Early-Exit：**

在啟動 Explore 前，先檢查 `{company_base_dir}/specs/{EPIC_KEY}/refinement.json` 是否存在：

| 條件 | 行動 |
|------|------|
| `refinement.json` 存在且 `modules` 非空 | **跳過 Explore**。直接讀取 artifact 的 `modules`、`ac`、`technical_approach` 作為拆單依據，進入 Step 5 |
| `refinement.json` 存在但 `modules` 為空或缺少關鍵欄位 | 補跑 Explore（scope 限定在 artifact 缺少的部分） |
| `refinement.json` 不存在 | 正常跑 Explore（下方流程） |

> **為什麼**：Architect（refinement）已做過深度技術探索並產出結構化 artifact。Packer 不需要重複探索同一個 codebase — 直接消費 artifact 即可。重複探索浪費 sub-agent 成本且可能產出與 refinement 矛盾的結論。

**Codebase 掃描（僅在無 artifact 時）：**

使用 `references/explore-pattern.md` 的自適應探索模式。啟動 1 個 Explore subagent，帶入需求摘要和專案路徑。Subagent 會自行判斷範圍大小。

收到探索摘要後，彙整 codebase 現況，結合需求進入 Step 5。

### 5. 評估拆單粒度

根據 ticket 規模決定拆單策略：

| 規模 | 預估總點數 | 策略 |
|------|-----------|------|
| 小型 | ≤ 5 pt | 一張 Task 涵蓋所有改動 |
| 中型 | 6-13 pt | 拆為 2-4 張子單 |
| 大型 | 13+ pt | 拆為 4+ 張子單，每張 2-5 pt |

### 6. 拆解子任務

將 ticket 拆解為具體的開發任務。

**拆解原則：**
- 依功能模組或頁面拆分，非依技術層（不要拆成「寫 API」「寫 UI」「寫測試」）
- 單一功能無法切分獨立測試時，不要硬拆 — 開一張集中處理
- 每張子單 story point 建議 **2-5 pt**，超過 5 pt 考慮再拆
- 如有 BFF 層改動，可獨立成子單
- 埋點量大時獨立成子單
- Spike / POC 類探索獨立出來
- 已有 feature branch 時，以實際 commit 改動範圍為準

**API-first 排序規則：**

涉及 cross-repo API 變更時，API 變更 task 排第一（前端消費 API，自然依賴順序）。

**穩定測資單（Fixture Recording Task）：**

若 project 有 `visual_regression` config，自動加入穩定測資 task（1pt），排在 API task 之後、前端 task 之前。

排序：`API/cross-repo → 穩定測資 → 前端開發`

**子任務結構（每張需包含）：**

- **Summary** — 格式：`[TICKET_KEY] 簡短描述`
- **Description** — 包含：需求、異動範圍（Dev Scope）、前端設計（如適用）、測試計畫
- **Story Points** — 依估點標準評估

> 實作細節寫在子單 description 中，不更新母單。

### 7. 估點

依 `references/estimation-scale.md` 對每個子任務評估 Story Point。

### 7.5. Quality Challenge 自動迴圈（最多 3 輪）

拆單 + 估點完成後，**自動**執行品質審查。

**審查項目（逐張子單檢查，標記 PASS / FAIL）：**

| 項目 | PASS 條件 | FAIL 時的建議 |
|------|----------|-------------|
| 點數合理 | ≤ 5 pt | 拆成更小的子單 |
| AC 明確 | 有具體的驗收條件 | 補上 AC |
| Happy Flow | 有使用者視角的操作步驟 | 補上 Happy Flow |
| 獨立可測 | 可獨立開發、獨立驗收 | 合併到相關子單或重新劃分邊界 |
| 無循環依賴 | 子單之間無環形相依 | 調整依賴方向或合併 |
| 無隱藏假設 | 不依賴未驗證的 API / 元件 | 標明假設或加 Spike 子單 |
| 更簡單的替代方案 | 沒有被忽略的 80/20 簡化 | 提出替代方案 |

**輸出格式：**

```
🔍 Quality Challenge — 拆單審查

| # | 子單 | Points | AC | Happy Flow | 獨立可測 | 結果 |
|---|------|--------|----|------------|---------|------|
| 1 | ... | ✅ 3pt | ✅ | ✅ | ✅ | PASS |
| 2 | ... | ❌ 8pt | ✅ | ❌ | ✅ | FAIL |

FAIL 項目：
- #2：8 點過大，建議拆為「API handler」(3pt) + 「前端串接」(5pt)
- #2：缺少 Happy Flow

結論：FAIL（2 項需調整）
```

**迴圈邏輯：**
```
拆單結果 → 品質審查
  → 全部 PASS → Step 8
  → 有 FAIL → 自動調整 → 再審查 → ...
  → 最多 3 輪。超過仍有 FAIL → 連同未解決問題呈現給使用者
```

### 8. 呈現拆單結果並確認

以表格呈現通過 Quality Challenge 的拆單結果：

```
## [TICKET_KEY] Summary

| # | Summary | Points | 說明 |
|---|---------|--------|------|
| 1 | [TICKET_KEY] 子任務描述 | 3 | 改動範圍摘要 |
| 2 | [TICKET_KEY] 子任務描述 | 5 | 改動範圍摘要 |
| **Total** | | **N** | 預估 X 天（每日 2-3 pt） |
```

**必須等使用者明確確認後才進行下一步。**

### 9. 查詢 Story Points 欄位 ID

依 `references/jira-story-points.md` 動態查詢。後續 Step 10、11 使用此 fieldId。

### 10. 批次建立 JIRA Sub-task

依 `references/jira-subtask-creation.md` 完整流程（Step A → B → C → D）：

- Step A: 建立實作子單
- Step B: 填入估點 + 回查驗證
- Step C: 建立測試計劃 sub-task
- Step D: 建立驗收單（依 `references/epic-verification-structure.md`）
  - **AC 依賴**：若某 AC 須先通過另一個 AC 才有意義，在 description 加 `## depends_on` 段列出被依賴 AC 編號（見 `references/epic-verification-structure.md § depends_on 欄位`）。無強依賴時不要硬加
  - **驗收單 task.md**：每張驗收單同步產出 `specs/{EPIC_KEY}/tasks/{V-KEY}.md`，讓 verify-AC 能自主起環境。Schema：
    - `fixture_required: true/false`（判斷依據：該 AC 是否需要 runtime 頁面資料，純 unit test/config 檢查 → false）
    - `fixture_path: specs/{EPIC_KEY}/tests/mockoon/`（fixture_required=true 時填寫，使用 deterministic convention path）
    - `fixture_start_command: mockoon-runner.sh start {fixture_path}`（啟動指令）
    - `test_urls: [...]`（verify-AC 要打的具體 URL）
    - `env_start_command: bash {base_dir}/scripts/polaris-env.sh <project>`
    - 驗證步驟與預期結果（從 JIRA description 同步）

本 skill 設定：
- `parent` 指向母單（TICKET_KEY）
- `projectKey` 從 ticket key 動態提取
- assignee：從母單 assignee 取得（見 `references/jira-subtask-creation.md` § Assignee 規則）
- Step B 驗證失敗時立即報錯

> 迴圈：每張實作子單 A → B（含驗證）→ C，完成後下一張。全部完成後 Step D。

### 11. 更新母單估點（必須）

子單點數總和寫入母單 SP + 回查驗證。不可省略。

### 12. 建立完成回報

```
## 建立完成

| # | Key | Summary | Points | Repo | Branch |
|---|-----|---------|--------|------|--------|
| 1 | PROJ-1001 | 子任務描述 | 5 | <repo> | task/PROJ-1001-desc |

Total: N pt，預估 X 天
```

### 12.5. AC ↔ 子單追溯矩陣

> Epic 必須執行。Story/Task 有明確 AC 時也建議執行。

比對 ticket description 中的 AC 與子單覆蓋關係：

```
| AC | 對應子單 | 驗證場景 |
|----|---------|---------|
| AC1: ... | PROJ-501 | ✅ 已定義 |
| AC2: ... | ❌ 無對應 | — |
```

若有 AC 無對應子單 → 強制 block，詢問使用者新增子單或移到 Out of Scope。

通過後將追溯矩陣寫入 JIRA comment。

### 13. 整合母單描述

> Epic 必須執行。Story/Task 視 description 品質決定。

檢查母單 description 是否已結構化。若資訊散落在 comment 中或缺少拆單總覽，主動整合更新。

結構化 description 參考 `references/epic-template.md`，必須包含**拆單總覽**（子單 Key + Summary + Points）。

### 14. 建立 Branch

**14a. 按專案分組子單**（從子單 description 或 Step 2 的專案辨識結果）

**14b. 建立母單 feature branch**（每個涉及的 repo 一個）

```bash
git -C {base_dir}/<repo> checkout develop
git -C {base_dir}/<repo> pull origin develop
git -C {base_dir}/<repo> checkout -b feat/<TICKET_KEY>-<description>
git -C {base_dir}/<repo> push -u origin feat/<TICKET_KEY>-<description>
```

> 小型 ticket（≤ 5pt，單一子單）可跳過 feature branch，直接從 develop 開 task branch。

**14c. 為每張子單建立 branch**（從對應 repo 的母單 branch 開出）

```bash
git -C {base_dir}/<repo> checkout feat/<TICKET_KEY>-<description>
git -C {base_dir}/<repo> checkout -b task/<SUB_KEY>-<description>
git -C {base_dir}/<repo> push -u origin task/<SUB_KEY>-<description>
```

**14d. 回報 branch 結構**

### 14.5. 產出 task.md work orders

為每張實作子單產出 self-contained 工單檔案，讓 engineering 只消費 codebase + task.md + repo handbook（sub-agent 須自行讀取 `{repo}/.claude/rules/handbook/`，不會自動載入）。

**路徑規則：**

| 情境 | 輸出路徑 |
|------|---------|
| Epic 拆多張子單 | `{company_base_dir}/specs/{EPIC_KEY}/tasks/T{n}.md` |
| Story/Task 拆多張子單 | `{company_base_dir}/specs/{TICKET_KEY}/tasks/T{n}.md` |
| 單一子單 ticket（≤ 5pt） | `{company_base_dir}/specs/{TICKET_KEY}/tasks/T1.md` |

> `{n}` 從 1 起算，對應 Step 8 呈現順序（API-first 排序後的實際排序）。

**檔案 schema** — 嚴格遵循 `references/pipeline-handoff.md` § task.md Schema。每張 task.md 包含：

1. **Header**：`# T{n}: {Task summary} ({SP} pt)` + quote 行 `> Epic: {EPIC_KEY} | JIRA: {TASK_KEY} | Repo: {repo_name}`（無 Epic 時省略 Epic 欄位）
2. **Operational Context 表格** — 必填欄位：
   - Task JIRA key、Parent Epic（或母單 key）
   - Test sub-tasks（Step C 產出的測試計劃 key list）
   - AC 驗收單（Step D 產出的 verification ticket key）
   - Base branch（Step 14b 建立的 feature branch；小型 ticket 跳過時寫 `develop`）
   - Task branch（Step 14c 建立的 `task/{TASK_KEY}-{slug}`）
   - References to load（見下方「挑選規則」）
3. **Verification Handoff 段落**：一句話 `AC 驗證不在本 task 範圍，委派至 {AC_TICKET_KEY}（由 verify-AC skill 執行）。`
4. **目標**：一段話（從 Step 6 的子任務 description 摘要）
5. **改動範圍**表格：檔案 / 動作 / 說明（從 Step 6 的 Dev Scope 轉寫）
6. **估點理由**：一段話（從 Step 7 的估點邏輯）
7. **測試計畫（code-level）**：對應 test sub-tasks 的 unit/integration 測試項目
8. **Test Command**：專案特定的測試指令（見下方「Test Command 填寫規則」）
9. **Verify Command**：一個可執行的 shell 指令，驗證本 task 的核心改動在 runtime 是否生效（見下方「Verify Command 撰寫指南」）

**不放 task.md 的東西**（屬於 refinement 或 AC 層級）：
- Epic description 全文 / refinement artifact
- 業務層 AC 驗證場景（由 AC 驗收單持有）
- 技術方案選項分析（refinement 已定案）
- handbook 內容（engineering sub-agent 須自行讀取 `{repo}/.claude/rules/handbook/`，不複製進 task.md）

**References to load 挑選規則：**

讀 `skills/references/INDEX.md`，依 task 性質挑選相關項目。常見對應：

| Task 性質 | 建議 references |
|----------|----------------|
| 涉及 cross-repo API | `cross-repo-verification.md` |
| 涉及 i18n / locale | 對應 company handbook 下 i18n 檔 |
| 涉及 VR / 截圖 | `vr-jira-report-template.md` |
| 涉及 JIRA 子單寫入 | `jira-subtask-creation.md` |
| 涉及 mockoon / fixture / lighthouse / VR baseline | `epic-folder-structure.md` |
| 所有 task | `branch-creation.md`（engineering 起手） |

若無法判斷，至少列 `branch-creation.md` + 對應 repo handbook 入口。

**產出方式：**

以 Write tool 建立檔案。批次產出時可 parallel 呼叫多個 Write。每張檔案獨立，單一失敗不影響其他子單或 JIRA/branch state。

**Schema 強制驗證（deterministic gate）：**

每張 task.md 寫入後，立即呼叫 validator：

```bash
scripts/validate-task-md.sh <task.md path>
```

- exit 0 → 該檔案合格，繼續
- exit 1 → validator 列出缺漏欄位；**就地修補 task.md（補上欄位）並重跑**，直到 pass。不可讓不合格檔案 land
- exit 2 → 檔案不存在或用法錯誤，檢查路徑

**為何強制**：pipeline 契約「engineering 只消費 task.md + codebase」的前提是 task.md 完整。靠 AI 自律難保每次產齊，所以用 script exit code 強拘束。見 `CLAUDE.md § Deterministic Enforcement Principle`。

**Test Command 填寫規則：**

每張 task.md 必須包含專案特定的測試指令，讓 engineering sub-agent 直接使用，不自行推導。

來源優先順序：
1. `workspace-config.yaml` → `projects[].dev_environment.test_command`（首選，已含 monorepo 工作目錄）
2. 專案 CLAUDE.md 的測試指令
3. Fallback: `npx vitest run`（最後手段）

讀取方式：在 Step 14.5 產出 task.md 前，讀 workspace-config 的 `test_command` 欄位。若為 monorepo（`is_monorepo: true`），指令已包含正確子目錄路徑。

**Verify Command 撰寫指南：**

breakdown 在 codebase exploration 後已掌握改動影響的 URL/endpoint 和預期 runtime 行為，此時為每張 task 寫一個 smoke-level 驗證指令。engineering sub-agent 完成實作後**必須原封不動執行**此指令（不可修改）。

| 改動類型 | Verify Command 範例 |
|----------|-------------------|
| SSR HTML 結構（JSON-LD、meta tag） | `curl -sS <url> \| python3 -c "import sys; html=sys.stdin.read(); head=html.split('</head>')[0]; assert '<pattern>' in head, 'NOT FOUND'; print('PASS')"` |
| API response format | `curl -sS <endpoint> \| python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('key'), 'missing key'; print('PASS')"` |
| 檔案 wiring（import/export） | `grep -q '<pattern>' <file_path> && echo 'PASS' \|\| echo 'FAIL: pattern not found'` |
| Config 註冊 | `grep -q '<module_name>' <config_path> && echo 'PASS' \|\| echo 'FAIL: not registered'` |

**撰寫原則：**
- 一個 task 一個指令（可用 `&&` 串多個 assert，但保持一個 exit code）
- 指令必須 **self-contained**（不依賴額外安裝的工具，只用 curl/grep/python3/jq）
- 寫明 **預期輸出**（PASS 時印什麼），讓 evidence file 可對比
- URL 使用 handbook 的 dev domain（如 `https://dev.yourapp.com`），不寫 localhost。自簽憑證加 `-k`
- **不能驗的情境**（純視覺、複雜互動）→ 寫 `N/A — 需 VR 或手動驗證` 並說明原因

**與 legacy plan.md 並行（過渡期）：**

P5 pipeline cutover 前，`specs/{TICKET_KEY}/plan.md` 若已存在不動它；新流程以 `tasks/T{n}.md` 為 engineering 的主要輸入。P5 完成後移除 legacy plan.md 生成。

### 15. 銜接 SA/SD（選擇性）

詢問使用者是否要產出 SA/SD 文件。確認則觸發 `sasd-review`。

### 16. 開工準備完成

所有子單已有 branch、測試計畫、驗證子單、**task.md work order**。

**觸發方式：** `做 <子單 key>` → `engineering`（讀對應 `specs/{EPIC_KEY}/tasks/T{n}.md`）

---

## Scope Challenge Mode（直接觸發：'scope challenge'、'挑戰需求'、'challenge scope'）

當使用者直接要求 scope challenge（而非透過拆單流程自動觸發），執行以下獨立流程：

### SC1. 讀取 Ticket

用 `getJiraIssue` 取得 ticket 內容（Summary、Description、AC、Issue type、子單、linked issues）。

### SC2. 完整性檢查

逐項檢查，缺少的標記 ❌：

| 項目 | 檢查方式 |
|------|----------|
| Acceptance Criteria | description 中有明確的 AC 或驗收條件 |
| 開發路徑（path） | description 中指明哪個專案 / 目錄 |
| Figma 連結 | description 或 attachment 中有 figma.com URL |
| API 文件 | description 中有 API endpoint 說明或 Swagger/Postman 連結 |
| 影響範圍 | 明確說明改動涉及哪些頁面 / 流程 |

缺少 ≥2 項 → 建議補齊後再估點。

### SC3. Scope 挑戰

對 ticket 提出適用的質疑：

- **過大？** — 單張 Story/Task 涵蓋 >3 個獨立功能 → 建議拆分
- **過度設計？** — 能用既有元件解決但描述中要求從零建造；要求通用化但只有一個使用場景
- **隱藏假設？** — 假設 API 已存在、Design System 有元件、不需 migration（有明確專案路徑時可啟動 Explore subagent 驗證）
- **80/20 簡化？** — 是否有更小的改動能達成 80% 效果

### SC4. 替代方案

提出 2-3 個方案（原始 scope / 簡化版 / 拆分），每個方案含預估複雜度、優缺點。小改動（≤2 files, 明確 AC）直接說「scope 合理，建議直接估點」。

### SC5. 輸出與銜接

```
📋 Scope Challenge Report — {TICKET-KEY}

完整性：✅ AC ✅ Path ❌ Figma ✅ API
建議：{proceed / simplify / split / needs-more-info}

{替代方案}

→ 建議採用方案 {X}，原因：{一句話}
```

使用者選定方案後，用 `addCommentToJiraIssue` 將結論寫入 JIRA comment（格式參考 `references/decision-audit-trail.md`）。之後銜接正常拆單流程。

---

## 注意事項

- Ticket 資訊太少時（只有 summary）不要硬拆，列出需要補充的資訊
- 拆單粒度以「一個 PR 能完成」為原則
- 小型 ticket（≤ 5 pt）直接一張子單，不要過度拆分
- 不要自動建單，一定要使用者確認後才建立
- **Do**：拆單後產出 AC 追溯矩陣（Epic 必須，其他建議）
- **Don't**：跳過追溯矩陣 — 有 AC 沒被覆蓋時必須處理

## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
