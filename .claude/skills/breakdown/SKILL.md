---
name: breakdown
description: "Universal planning skill: Bug reads ROOT_CAUSE then estimates; Story/Task/Epic explores codebase then splits into sub-tasks with estimates, and packs each sub-task into a self-contained task.md work order for engineering to consume. Also handles scope challenge (advisory mode). Trigger: 拆單, 'split tasks', 拆解, 'breakdown', 'break down', 子單, 'sub-tasks', 評估這張單, 'evaluate this ticket', 估點, 'estimate', 'scope challenge', '挑戰需求', 'challenge scope', '需求質疑'."
metadata:
  author: Polaris
  version: 3.0.0
---

# Breakdown — Packer

> **你是估價師 + 工地主任，不是建築師。** 你接過藍圖（refinement artifact 或 bug-triage 根因），拆成工項、估價、排班、打包工單（task.md）。你不做需求探索、不討論技術方案 — 那是 Architect（refinement）的工作。你的產出是 JIRA 子單 + task.md，讓 Engineer（engineering）能直接施工。

三層架構的 Layer 2，適用所有 ticket 類型：Bug / Story / Task / Epic。

## 前置：讀取 workspace config

讀取 workspace config（參考 `references/workspace-config-reader.md`）。
本步驟需要的值：`jira.instance`、`jira.projects`（取得 project keys）。
若 config 不存在，使用 `references/shared-defaults.md` 的 fallback 值。

> **Task.md schema reference（DP-033 Phase A + Phase B）**：兩種 task.md 的完整 schema 統一在 `skills/references/task-md-schema.md`：
> - **實作 task.md（T{n}.md）** — § 3 Implementation Schema（DP-033 Phase A）
> - **驗收 task.md（V{n}.md）** — § 4 Verification Schema（DP-033 Phase B；對稱 T{n}.md，所有共用基礎設施 reuse — 不平行造）
>
> 本 SKILL.md 內的 task.md 格式說明皆以該文件為準；若有衝突以 `task-md-schema.md` 為主。

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

**Worktree dispatch — 主 checkout 絕對路徑**
Sub-agent 在 worktree 執行；`specs/` 與 `.claude/skills/` 是 gitignored（worktree 無此檔）。dispatch prompt 須以主 checkout 絕對路徑讀寫：
- task.md: `{company_base_dir}/specs/{EPIC}/tasks/T{n}.md`
- artifacts / verification: `{company_base_dir}/specs/{EPIC}/artifacts/`、`.../verification/`
詳見 `skills/references/worktree-dispatch-paths.md`。

使用 `references/explore-pattern.md` 的自適應探索模式。啟動 1 個 Explore subagent，帶入需求摘要和專案路徑。Subagent 會自行判斷範圍大小。

Sub-agent dispatch 必須注入 Completion Envelope spec（見 `skills/references/sub-agent-roles.md`），Detail 寫入 `specs/{EPIC}/artifacts/explore-{timestamp}.md`。

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

**分段驗收偵測（DP-033 D4 § 5.3，advisory）：**

如果偵測到「兩組互不依賴 AC + 兩組互不依賴的實作 task 群」（例：T1+T2 → V1（前段驗收） → T3+T4 → V2（後段驗收）），主動提示：

> 「偵測到分段驗收結構（V1 ← T1+T2，V2 ← T3+T4，前後不交集）。**建議拆 Epic**：兩個交付 = 兩個 Epic 是 PM 視角的自然分法（JIRA 上看兩個 Epic 比帶 phase label 的單一 Epic 直覺）。是否拆 Epic？」

由 PM / 使用者判斷是否拆。**Validator 不 enforce** — `validate-task-md-deps.sh` 只 hard fail T→V 方向（避免 phase 化的根本問題），分段驗收偵測屬規劃層 advisory（DP-033 § 5.3 表格末段）。

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
  - **驗收 task.md schema（DP-033 Phase B 已定義）**：完整 schema（required sections / Operational Context cells / `ac_verification` lifecycle / 驗收步驟 entry / Test Environment / V→T 合法 / T→V 禁止）見 `skills/references/task-md-schema.md` § 4。本 step 產出驗收 task.md 必須通過 `scripts/validate-task-md.sh`（V mode）+ `scripts/validate-task-md-deps.sh`（跨類型方向性 V→T pass / T→V fail）。
  - **檔名命名（producer cutover 規範 — DP-039 一起 atomic 切）**：
    - **目標命名**：`V{n}[suffix].md`（V1.md / V2a.md，sequential 從 V1 起、sub-split 用 V1a/V1b — 對稱 T{n}.md）
    - **過渡期命名（DP-039 重構 verify-AC consumer 落地前）**：保留 `{V-KEY}.md`（如 TASK-123.md，以 JIRA key 命名）— 因為 verify-AC 仍在讀 `{V-KEY}.md` 路徑；breakdown 同步切到 V{n}.md 會造成 producer / consumer 不同步
    - **DP-039 atomic 切換之後**：breakdown 改產 V{n}.md + verify-AC 改讀 V{n}.md + 既有 `{V-KEY}.md` migration script rename → 全部一起切到位
  - **驗收 task.md 必填內容**（依 § 4 schema，過渡期相容 `{V-KEY}.md` 命名）：
    - 標題、Header、`## Operational Context`（含 V-specific cells：`Implementation tasks` 取代 T 的 `Test sub-tasks`，移除 `AC 驗收單` / `Task branch`）
    - `## 驗收項目`（對應 T 的 `## 改動範圍`）— AC 清單與對應實作 task
    - `## 估點理由`、`## Test Environment`、`## 驗收步驟`（對應 T 的 `## Verify Command`）
    - frontmatter `depends_on`（V→T 合法，V→V 線性合法）
    - lifecycle 欄位（`ac_verification` / `ac_verification_log[]` / `jira_transition_log[]`）由 verify-AC 寫入（breakdown 階段省略）

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

### 14. 建立 Branch（依 depends_on DAG topological 順序）

> **DP-028 D4 / D5 / D6**：task branch 依 `depends_on` DAG topological 順序建立；非線性 DAG 先拒絕；`Base branch` 寫入 snapshot 當下的正確值，無 `PR base` 欄位。engineering 開工時若 snapshot 過時（依賴已 merge），Resolve 層在 `engineer-delivery-flow.md § 4.5 / § R0 / § Step 7` 動態改值——snapshot **不是永遠不變**。
>
> 本步驟沿用 `breakdown-step14-no-checkout` canary：**只用 `git branch <name> <start>` + `git push`，不使用 `git checkout` / `git checkout -b` / `git pull origin develop`**。主 checkout 的 HEAD / working tree 在 Step 14 執行後必須完全不動，使用者 WIP 不受干擾。

**14a. 按專案分組子單**（從子單 description 或 Step 2 的專案辨識結果）

**14a'. 非線性 DAG 拒絕（D5 pre-check）**

在建立任何 branch 之前，先確認同 Epic 的 task.md depends_on graph 是線性的：

```bash
bash "${CLAUDE_PROJECT_DIR}/scripts/validate-task-md-deps.sh" \
  {company_base_dir}/specs/{EPIC_KEY}/tasks/
```

- exit 0 → 線性 DAG，繼續 14b
- exit 1 → validator 列出違反項目（含 `non-linear depends_on DAG` 或 cycle）。**停下來，不建任何 branch**，把非線性依賴 + 建議呈現給使用者：

  ```
  ⛔ 非線性 depends_on DAG 偵測：
  - T{n}.md: {TASK_KEY} 同時 depends on [{depA}, {depB}] — 兩者無前後順序

  breakdown **不支援** multi-base 或 merge-commit 方案（deterministic 優先）。請擇一處理：
  1. **線性化**：調整 depends_on 順序使成鏈狀（例 T3d depends on T3c、T3c depends on T3b）
  2. **拆 Epic**：把互不依賴的分支拆成兩個獨立 Epic / feature branch

  確認選擇後再跑 Step 14。
  ```

- exit 2 → 使用錯誤或路徑不存在，修正後重跑

> 為什麼硬性要線性：`Base branch` 只能指向一個上游；非線性 DAG 需 merge-commit 或同時切多個 base，與 deterministic snapshot 模型衝突（DP-028 Blind #4）。

**14b. 建立母單 feature branch**（每個涉及的 repo 一個）

先取得 develop 最新 commit 當 start point，再**只用 `git branch`** 建立本地 branch（不切走）：

```bash
git -C {base_dir}/<repo> fetch origin develop
DEVELOP_SHA=$(git -C {base_dir}/<repo> rev-parse origin/develop)
git -C {base_dir}/<repo> branch feat/<TICKET_KEY>-<description> "$DEVELOP_SHA"
git -C {base_dir}/<repo> push -u origin feat/<TICKET_KEY>-<description>
```

> 小型 ticket（≤ 5pt，單一子單）可跳過 feature branch，後續 14c 直接用 `$DEVELOP_SHA` 當 start point 開 task branch。

**14c. 依 depends_on DAG 依序建立子單 branch（D4 topological ordering）**

同一個 Epic 的 task branch **必須依 topological 順序建**：一張 task 的 depends_on 指向的 task branch 必須先於它建立，確保 `git branch <name> <start>` 的 start point 永遠存在。

**排序演算法**：

讀取 `{company_base_dir}/specs/{EPIC_KEY}/tasks/T*.md` 的 frontmatter `depends_on`，跑 Kahn's algorithm（bash 或 python 皆可；以下用 python 示意）：

```bash
python3 <<'PY'
import os, re, sys
from pathlib import Path

tasks_dir = Path(os.environ["TASKS_DIR"])  # e.g. specs/{EPIC}/tasks/
graph = {}   # task_id → list of deps (task_id)
for f in sorted(tasks_dir.glob("T*.md")):
    text = f.read_text()
    m = re.search(r"^---\n(.*?)\n---", text, re.DOTALL)
    fm = m.group(1) if m else ""
    task_id = f.stem
    dm = re.search(r"^depends_on:\s*\[(.*?)\]", fm, re.MULTILINE)
    deps = []
    if dm and dm.group(1).strip():
        deps = [d.strip().strip('"\'') for d in dm.group(1).split(",") if d.strip()]
    graph[task_id] = deps

# Kahn topological sort — 線性 DAG 已由 14a' 保證
indeg = {t: len(d) for t, d in graph.items()}
ready = [t for t, n in indeg.items() if n == 0]
order = []
while ready:
    t = ready.pop(0)
    order.append(t)
    for u, deps in graph.items():
        if t in deps:
            indeg[u] -= 1
            if indeg[u] == 0:
                ready.append(u)
# 結果：order = ['T1', 'T2', 'T3', 'T3a', 'T3b', ...]
print("\n".join(order))
PY
```

**依序建立 branch（snapshot Base branch → D2 + D6）**：

對 `order` 中每張 task，依其 `depends_on` 決定 start point（= snapshot 當下 Base branch 值）：

| 情境 | start point（= task.md `Base branch` snapshot 值）|
|------|----|
| `depends_on: []`（無依賴）| `feat/<TICKET_KEY>-<description>`（母單 feature branch；小型 ticket 單一子單時 = develop 的 SHA）|
| `depends_on: [<UPSTREAM_KEY>]`（有依賴）| 最下游依賴的 task branch，即 `task/<UPSTREAM_KEY>-<description>`（該 branch 已於本迴圈前一輪建好）|

```bash
# 無 depends_on 的 task（從 feat 切）
git -C {base_dir}/<repo> branch task/<SUB_KEY>-<description> feat/<TICKET_KEY>-<description>
git -C {base_dir}/<repo> push -u origin task/<SUB_KEY>-<description>

# 有 depends_on 的 task（從上游 task branch 切，stacked）
git -C {base_dir}/<repo> branch task/<SUB_KEY>-<description> task/<UPSTREAM_KEY>-<description>
git -C {base_dir}/<repo> push -u origin task/<SUB_KEY>-<description>
```

**Snapshot 寫入 task.md（14.5 產出時）**：

建完 branch 後，Step 14.5 產 task.md 時 `Base branch` 欄位填**該 task 的 start point 值**（即上表第二欄）。**不新增 `PR base` 欄位**（D6）——`gh pr create --base` 直接使用 `Base branch`（經 engineering Resolve 層調整後）的值。

> Snapshot ≠ 永遠不變：engineering 開工 / revision 時 `engineer-delivery-flow.md § 4.5 / § R0 / § Step 7` 會重跑 `scripts/resolve-task-base.sh`——若 snapshot 指向的 upstream branch 已 merge 到 feat，resolve 層自動改為從 feat 切 / 對 feat 開 PR（D2 三層消費模型的 Resolve 層）。

**14c'. Chain depth advisory**（非阻擋）

對 `order` 中每張 task 計算其 depends_on chain 長度（從根 task 算起的邊數）。若任一 chain 長度 > 3，印出 warning（不擋流程）：

```
⚠ Stacked PR chain 超過 3 層：
  T3a → T3b → T3c → T3d（長度 4）

Chain 越長，CI / rebase 成本上升、reviewer 追蹤負擔加重。考慮：
- 把末端 task 併回上游（減少 chain 層數）
- 拆 Epic（兩條獨立 chain 各自開 feature branch）
```

> 此為 advisory（DP-028 Blind #2 explicit non-goal），使用者可忽略後繼續。

**14d. 回報 branch 結構**

列出 feature branch 與所有 task branch，附 snapshot Base branch 關係：

```
feat/PROJ-123-...
  ├── task/TASK-123-... (T3a, Base: feat/PROJ-123-...)
  │     └── task/TASK-123-... (T3b, Base: task/TASK-123-..., stacked)
  │     └── task/TASK-123-... (T3c, Base: task/TASK-123-..., stacked)
  │           └── task/TASK-123-... (T3d, Base: task/TASK-123-..., stacked, chain depth 3)
  └── task/TASK-123xxx-... (無 depends_on, Base: feat/PROJ-123-...)
```

### 14.5. 產出 task.md work orders

為每張實作子單產出 self-contained 工單檔案，讓 engineering 只消費 codebase + task.md + repo handbook（sub-agent 須自行讀取 `{repo}/.claude/rules/handbook/`，不會自動載入）。

**Worktree 提醒**：task.md Write 路徑須用主 checkout 絕對路徑 `{company_base_dir}/specs/{EPIC_KEY}/tasks/T{n}.md`（gitignored，跨 worktree 共享）。詳見 `skills/references/worktree-dispatch-paths.md`。

**路徑規則：**

| 情境 | 輸出路徑 |
|------|---------|
| Epic 拆多張子單 | `{company_base_dir}/specs/{EPIC_KEY}/tasks/T{n}.md` |
| Story/Task 拆多張子單 | `{company_base_dir}/specs/{TICKET_KEY}/tasks/T{n}.md` |
| 單一子單 ticket（≤ 5pt） | `{company_base_dir}/specs/{TICKET_KEY}/tasks/T1.md` |

> `{n}` 從 1 起算，對應 Step 8 呈現順序（API-first 排序後的實際排序）。

**檔案 schema** — 嚴格遵循 `references/task-md-schema.md`（DP-033 Phase A 升格為單一權威 spec；`pipeline-handoff.md § task.md Schema` 為舊入口，以本 reference 為準）。每張 task.md 包含：

1. **Header**：`# T{n}: {Task summary} ({SP} pt)` + quote 行 `> Epic: {EPIC_KEY} | JIRA: {TASK_KEY} | Repo: {repo_name}`（無 Epic 時省略 Epic 欄位）
2. **Operational Context 表格** — 必填欄位：
   - Task JIRA key、Parent Epic（或母單 key）
   - Test sub-tasks（Step C 產出的測試計劃 key list）
   - AC 驗收單（Step D 產出的 verification ticket key）
   - Base branch — **DP-028 snapshot 值（D2 / D6）**：
     - `depends_on: []`（無依賴）→ Step 14b 建立的 `feat/{TICKET_KEY}-{slug}`（小型 ticket 跳過 feature branch 時寫 `develop`）
     - `depends_on: [<UPSTREAM_KEY>]`（有依賴）→ 最下游依賴的 task branch `task/{UPSTREAM_KEY}-{slug}`（stacked）
     - 不新增 `PR base` 欄位：`gh pr create --base` 直接用本欄位（engineering Resolve 層可能動態改值，見 `engineer-delivery-flow.md § 4.5 / § R0 / § Step 7`）
   - Task branch（Step 14c 建立的 `task/{TASK_KEY}-{slug}`）
   - Depends on（frontmatter `depends_on` 的 human-readable 摘要，例 `TASK-123 (T3a — 需 dayjs plugin 就緒)`；無依賴時省略）
   - References to load（見下方「挑選規則」）
3. **Verification Handoff 段落**：一句話 `AC 驗證不在本 task 範圍，委派至 {AC_TICKET_KEY}（由 verify-AC skill 執行）。`
4. **目標**：一段話（從 Step 6 的子任務 description 摘要）
5. **改動範圍**表格：檔案 / 動作 / 說明（從 Step 6 的 Dev Scope 轉寫）
6. **估點理由**：一段話（從 Step 7 的估點邏輯）
7. **測試計畫（code-level）**：對應 test sub-tasks 的 unit/integration 測試項目
8. **Test Command**：專案特定的測試指令（見下方「Test Command 填寫規則」）
9. **Test Environment**：本 task Verify Command 需要的環境層級 + workspace-config pointer + fixtures（見下方「Test Environment 填寫規則」）
10. **Verify Command**：一個可執行的 shell 指令，驗證本 task 的核心改動在 runtime 是否生效（見下方「Verify Command 撰寫指南」）

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

**Batch cross-file gate（DP-033 A3）：所有 T*.md 寫完後，再跑一次跨檔案驗證：**

```bash
scripts/validate-task-md-deps.sh {company_base_dir}/specs/{EPIC_KEY}/tasks/
```

此 script 驗證：
- `depends_on[]` 所有引用存在（含 `complete/` fallback）
- DAG 無 cycle（DFS coloring）
- linear chain（每個 task `depends_on` ≤ 1 其他 task）
- `Fixtures:` 路徑存在性（非 `N/A` 時）
- 同一 key 不同時出現在 `tasks/` 與 `tasks/complete/`

結果判斷：
- exit 0 → 所有 T*.md 依賴關係合規，繼續 Step 15
- exit 1 → 列出違反項目；**停下來，修補對應 task.md 並重跑**，直到 pass。不可在跨檔案驗證 FAIL 的狀態下繼續建 branch 或 JIRA 子單
- exit 2 → 路徑不存在或用法錯誤，確認 tasks/ 目錄存在後重跑

> **注意**：Step 14a'（非線性 DAG pre-check）已在 branch 建立前跑一次 `validate-task-md-deps.sh`；本步驟是「所有 T*.md 內容完整填寫後」的最終確認，時間點不同（14a' 在 branch 建立前，本 gate 在 task.md 內容寫完後）。

# DP-033 Phase B 已實裝：V*.md 共用同一支 validate-task-md-deps.sh — filename 自動掃 T*.md + V*.md，
# 包含 V→T pass / T→V fail 跨類型方向性檢查（§ 5.3）。
# 過渡期 producer 仍產 {V-KEY}.md（TASK-XXXX.md），DP-039 切到 V{n}.md 後同此 script 自動覆蓋。

**Test Command 填寫規則：**

每張 task.md 必須包含專案特定的測試指令，讓 engineering sub-agent 直接使用，不自行推導。

來源優先順序：
1. `workspace-config.yaml` → `projects[].dev_environment.test_command`（首選，已含 monorepo 工作目錄）
2. 專案 CLAUDE.md 的測試指令
3. Fallback: `npx vitest run`（最後手段）

讀取方式：在 Step 14.5 產出 task.md 前，讀 workspace-config 的 `test_command` 欄位。若為 monorepo（`is_monorepo: true`），指令已包含正確子目錄路徑。

**Test Environment 填寫規則：**

每張 task.md 必須包含 `## Test Environment` 區塊，標示 Verify Command 需要的環境層級（Level），讓 engineering sub-agent 知道是否需要起 dev server / docker / fixture。

**Level 決策流程**（依 Verify Command 的形式判斷）：

| Verify Command 特徵 | Level | 範例 |
|-------------------|-------|------|
| 只 `grep` / `ls` source 或 config，不需要 build 產物 | `static` | `grep -q 'pattern' src/file.ts` |
| 需讀 `.output/` / `dist/` / build artifact | `build` | `ls .output/public/_nuxt/*.js`（如 PROJ-123 T3 `grep moment .output`） |
| 需 `curl` live endpoint / 瀏覽器互動 / runtime API | `runtime` | `curl -sk https://dev.yourapp.com/zh-tw`（如 PROJ-123 T2 `curl dev.yourapp.com`） |

**產出格式**：

```markdown
## Test Environment

> engineering 執行 Verify Command 前，依本區塊決定如何準備環境。

- **Level**: {static | build | runtime}
- **Dev env config**: `workspace-config.yaml` → `projects[{repo_name}].dev_environment`
- **Fixtures**: {`specs/{EPIC_KEY}/tests/mockoon/` 或 `N/A`}
- **Runtime verify target**: {`https://dev.yourapp.com/...` | `http://localhost:3001/...` | `N/A`}
- **Env bootstrap command**: {`./scripts/polaris-env.sh start <company> --project <repo>` | `<company>/scripts/*.sh` | `N/A`}
```

**填寫細節**：
- `{repo_name}` 填實際 repo name（如 `your-app`），對應 workspace-config `projects[].name`
- **Fixtures 判斷**：若 Epic 有 mockoon fixtures（`specs/{EPIC}/tests/mockoon/` 存在且本 task 的 runtime Verify 會經過這些 route），填 fixture path；否則填 `N/A`
- `static` level 的 Fixtures 一律 `N/A`（不需 runtime env）
- **Runtime verify target 判斷**：
  - `Level=runtime`：必填且不可 `N/A`，需與 `Verify Command` 實際打的 URL 同主機（host）
  - `Level=static/build`：固定填 `N/A`
  - 來源優先順序：`Verify Command` 的 URL > repo handbook local-dev 文件 > workspace-config `health_check`
- **Env bootstrap command 判斷**：
  - `Level=runtime`：建議填寫；優先找 workspace/company 提供的啟環境腳本（例如 `scripts/polaris-env.sh` 或公司目錄下 `scripts/*.sh`）
  - `Level=static/build`：填 `N/A`
  - 目的是讓 engineering 有單一入口啟環境，不依賴人腦記憶公司細節
- **健康檢查 URL vs 驗證 URL 不同是允許的**：`health_check` 用來判斷服務 ready；`Runtime verify target` 用來表達 smoke 實際驗證入口

**為何 pointer 模式**：dev_environment 細節（start_command, requires, health_check, is_monorepo）已在 workspace-config，單一來源。複製到 task.md 會 stale — workspace-config 改了沒人同步 task.md。engineering sub-agent 自己讀 workspace-config。

**Runtime Consistency Gate（強制）**：

當 `Level=runtime` 時，task.md 必須同時滿足以下條件，否則視為不合格工單：

1. `Runtime verify target` 不可為 `N/A`
2. `Env bootstrap command` 不可為 `N/A`
3. `Verify Command` 必須包含對 live endpoint 的 runtime 驗證（例如 `curl` / 瀏覽器測試），且目標 host 必須與 `Runtime verify target` 一致（同 host，可不同 path）
4. `Verify Command` 不可只做 static 檢查（例如只有 `grep` / 檔案存在性）後就宣告 PASS

若 `Verify Command` 只能做到 static 檢查，`Level` 必須改為 `static` 或 `build`；不可標成 `runtime`。

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
- runtime URL 可使用 local domain 或 localhost，依 repo handbook / workspace-config 實際可用入口為準；若是 HTTPS 自簽憑證可加 `-k`
- **不能驗的情境**（純視覺、複雜互動）→ 寫 `N/A — 需 VR 或手動驗證` 並說明原因
- `Level=runtime` 時，指令必須打 `Runtime verify target`（同 host），不可只跑 `grep`
- 若 workspace-config 顯示該 repo `requires` docker 專案，`Env bootstrap command` 應優先使用公司標準腳本（如 `polaris-env.sh start {company} --project {repo}`）

**與 legacy plan.md 並行（過渡期）：**

P5 pipeline cutover 前，`specs/{TICKET_KEY}/plan.md` 若已存在不動它；新流程以 `tasks/T{n}.md` 為 engineering 的主要輸入。P5 完成後移除 legacy plan.md 生成。

### 15. 銜接 SA/SD（選擇性）

詢問使用者是否要產出 SA/SD 文件。確認則觸發 `sasd-review`。

### 16. 開工準備完成

所有子單已有 branch、測試計畫、驗證子單、**task.md work order**。

**觸發方式：** `做 <子單 key>` → `engineering`（讀對應 `specs/{EPIC_KEY}/tasks/T{n}.md`）

### 17. L2 Deterministic Check: post-task-feedback-reflection

子單建立完畢、breakdown 收尾前，跑 advisory check：session 內若出現自糾正信號但無新 feedback memory 檔案 → 提示反思。

```bash
bash "$CLAUDE_PROJECT_DIR/scripts/check-feedback-signals.sh" \
  --skill breakdown
```

根據 exit code（advisory — script 恆 exit 0）：
- **exit 0 + 無 stdout** — 無反思訊號，breakdown 正式收尾
- **exit 0 + 有 stdout** — 依 `rules/feedback-and-memory.md` 判斷是否寫 feedback memory 或更新 handbook

此 canary 原列 `rules/mechanism-registry.md § Feedback & Memory`（behavioral），DP-030 Phase 2C 下放為 deterministic。L1 fallback 由 Stop hook 補位。遵循 `skills/references/l2-script-conventions.md` advisory 約定。

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
