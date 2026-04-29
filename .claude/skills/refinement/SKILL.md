---
name: refinement
description: >
  Iteratively enriches incomplete JIRA Epics into estimation-ready, technically-validated specs.
  Five modes: batch readiness scan, RD discovery (Phase 0), PM elaboration (Phase 1),
  technical approach (Phase 2), and multi-round iteration. Phase 1 goes beyond checklist
  filling — it explores the codebase, hardens AC, and produces a structured artifact for
  downstream skills. Trigger: "refinement", "grooming", "討論需求", "需求釐清", "補完 Epic",
  "這張單缺什麼", "brainstorm", "方案討論", "想重構", "tech debt", "batch refinement",
  "sprint prep", or Epic with sparse content needing enrichment.
metadata:
  author: Polaris
  version: 4.0.0
---

# Backlog Refinement — Architect

> **你是建築師，不是施工隊。** 你的工作是把模糊需求變成可執行藍圖 — 探索 codebase、驗證技術可行性、定案 AC。你不拆子單、不估點、不寫 code。你的產出是 `refinement.json`，讓下游的 Packer（breakdown）和 Engineer（engineering）能直接消費，不用重工。

四種模式 + 複雜度分層，一個目標：產出**經過技術驗證的方案 + 可量化的 AC**。

## Source Resolution（JIRA optional）

`refinement` 的入口不再只限 JIRA Epic。所有 source 解析先讀
`references/spec-source-resolver.md`，再依 source type 分流：

| Source type | 入口例 | Container | 行為 |
|-------------|--------|-----------|------|
| `jira` | `refinement PROJ-123` | `{company_base_dir}/specs/{TICKET}/` + JIRA issue | 既有 JIRA-backed refinement；定版後寫 JIRA comment / label / description |
| `dp` | `refinement DP-045` | `{workspace_root}/specs/design-plans/DP-NNN-*/` | 讀既有 DP plan，進入 ticketless refinement；不寫 JIRA |
| `topic` | `refinement "討論 XXX"`、`想討論 XXX`、`ADR XXX`、`design plan XXX` | 新建 DP folder | 建立 DP container 後進入 ticketless refinement；同步 docs-viewer sidebar；不寫 JIRA |
| `artifact_path` | direct `refinement.md` / `refinement.json` path | nearest specs container | 接續 artifact 所屬 source |

**DP locator hard rules**：
- `DP-NNN` 必須唯一對應 `specs/design-plans/DP-NNN-*/`
- 找不到或多筆 match 都 fail loud，不 fallback 成新 topic
- `LOCKED` / `IMPLEMENTED` DP 不可被新 topic overwrite；要改方向就新開 DP，並在 Background 加 see-also

**Trigger migration**：原本屬於 `design-plan` 的「想討論 / 怎麼設計 / 重構 / ADR / design plan」入口，改 route 到本 skill 的 ticketless mode。`design-plan` skill 已 sunset；legacy `/design-plan DP-NNN` prompt 也應轉入 `refinement DP-NNN`。

## Framework Contract Change Guard

當使用者用 `refinement` 討論 skill / rule / reference / validator / handoff contract /
workflow boundary 的變更時，預設是**設計流程**，不是直接 implementation。

適用範圍：

- 修改任一 skill 的 workflow、role boundary、handoff input/output
- 修改 `rules/` 或 `skills/references/` 中的 pipeline policy
- 新增或改動 validator / hook，會改變其他 skill 的放行條件
- 使用者用「refinement X」描述一個 framework contract 問題

執行規則：

1. 先把變更整理成 DP / ticketless refinement proposal（Goal、Decisions、AC / acceptance checks、Implementation scope）
2. 在主對話呈現 proposal 與風險；未得到使用者明確確認前，不改 `SKILL.md`、`rules/`、`scripts/`、validator
3. 使用者說「定版 / 套用 / 直接改 / 可以上」後，才進 implementation；若要改 skill 本身，必須同時套用 `skill-creator` 的修改規範
4. 例外只限 typo、格式、broken link，或使用者明確要求 hotfix / 直接修改；final 必須標明這次是 explicit bypass

不可接受的 shortcut：只讀 refinement 規則當背景，然後直接改跨 skill contract。這會讓 Architect 的決策流程消失，也讓下游無法知道哪些 decision 已被使用者確認。

## Return Inbox Intake（breakdown → refinement）

當 `breakdown` 判定 scope-escalation intake 已超出 task-md 修補能力，必須先把
engineering raw sidecar 轉譯成 refinement-facing inbox record。`refinement` 發動時只讀
inbox record，不直接讀 `engineering` escalation sidecar。

Contract source：`references/refinement-return-inbox.md`

### R0. Scan inbox before normal refinement

Source resolution 得到 `{source_container}` 後，先掃：

```text
{source_container}/refinement-inbox/*.md
```

若有 `consumed: false` 的 record：

1. 取最新一筆（檔名 timestamp 最大；若使用者指定 record path，讀指定那筆）
2. 先跑 validator：
   ```bash
   scripts/validate-refinement-inbox-record.sh \
     "{source_container}/refinement-inbox/{record}.md"
   ```
3. 只讀 inbox record 的 `## Decision` / `## Refinement Context` /
   `## Decisions Needed` / `## Source Audit`
4. 把 `## Decisions Needed` 轉成本輪 refinement 的 agenda，更新
   `refinement.md` 的 Decisions / Blind Spots / Acceptance Criteria /
   Technical Approach（依實際問題歸位）
5. 定版並產出新的 `refinement.json` 後，把該 inbox record frontmatter 改為
   `consumed: true`

### R1. Raw sidecar ban

- 不讀 `{source_container}/escalations/T{n}-{count}.md`
- 不讀 engineering `## Raw Evidence` 來補 refinement context
- 使用者若直接給 sidecar path 並要求 refinement，回覆 routing error：
  「請先跑 `breakdown {EPIC}` scope-escalation intake，讓 breakdown 產
  `refinement-inbox/*.md`；refinement 只消化 inbox decision。」
- 若 inbox context 不足，不自行開 sidecar；要求 `breakdown` 重寫或補一筆 inbox record

此規則的目的不是丟失證據，而是維持權威邊界：engineering raw sidecar 是 execution evidence，
breakdown 才能把它轉成 planner decision；refinement 只重新決策 AC / 技術方案。

## Sub-agent Completion Envelope

本 skill 的所有 sub-agent dispatch（Batch Scan 平行讀取、Explore subagent、多角色分析）都必須注入 Completion Envelope spec（見 `skills/references/sub-agent-roles.md`）。Detail 統一寫入 `specs/{EPIC}/artifacts/{agent-type}-{timestamp}.md`。

## Local-First Workflow

多輪 refinement 不逐輪寫回 JIRA。改為本地 markdown 迭代 + browser 預覽，定版後一次寫入。

```
Round 1-N（本地迭代）
  {source_container}/refinement.md                   ← Strategist 每輪更新
  localhost:3333                              ← browser 即時預覽（大螢幕討論用）
  ↕ 使用者 + 其他 RD 討論、修正

定版後（一次寫入）
  refinement.md → JIRA comment（人讀，JIRA-backed only）
  refinement.md → refinement.json（機器讀 artifact）
```

**Preview server 啟動方式：**

```bash
python3 scripts/refinement-preview.py {company_base_dir}/specs/{EPIC_KEY}/refinement.md
# → http://localhost:3333 自動開啟，3 秒刷新
# → 可指定 --port 3334 換 port
```

**Flow：**
1. Phase 1 Step 1-4 的產出寫入 `{source_container}/refinement.md`（不寫 JIRA）
2. 啟動 preview server，使用者在 browser 查看、和團隊討論
3. 使用者回饋 → Strategist 更新 `refinement.md` → browser 自動刷新
4. 重複直到使用者說「定版」
5. Step 7 一次性產出 artifact JSON；JIRA-backed source 才同步寫 JIRA comment / label / description

## 模式總覽

| 模式 | 核心問題 | 入口 | 輸入 | 輸出 |
|------|---------|------|------|------|
| **Batch Scan** | 這些 Epic 準備好了嗎？ | 多張 Epic keys | Epic keys 清單 | 完整度總覽表 + JIRA label + comment |
| **Phase 0：發現 & 開單** | 為什麼要做？值不值得？ | RD 主動發起 | code smell / 效能問題 / tech debt | JIRA ticket + 問題分析 + 影響評估 |
| **Phase 1：需求充實** | 這張單到底要做什麼？ | PM 開的粗略 Epic | Epic 標題 + PM 的零散描述 | 完整 Epic + structured artifact |
| **Phase 2：方案討論** | 怎麼做比較好？ | 需求已明確 | 完整的 Epic / ticket | Decision Record（選定方案 + trade-offs） |
| **Ticketless / DP Source** | 非 ticket 討論如何進 pipeline？ | `DP-NNN` 或一句話 topic | DP plan / topic | DP-backed `refinement.md` + `refinement.json` |

各模式可以獨立使用，也可以串接（Batch Scan → 挑出 needs-refinement 的 → Phase 1 深度補充）。

## Complexity Tier（複雜度分層）

Phase 1 的執行深度由 complexity tier 控制。**Tier 2 是地板** — 除非明確偵測到 Tier 1 條件，否則走 Tier 2。

| Tier | 條件 | 執行深度 |
|------|------|---------|
| **Tier 1** | ≤ 2 個預期子單 且 Epic 描述已幾乎完整（≥ 6/8） | 完整性檢查 + 補充建議（不探索 codebase） |
| **Tier 2** | 預設（大多數 Epic） | + Codebase exploration + Historical context + AC hardening + Artifact 輸出 |
| **Tier 3** | PM 附競品/範例 URL、Epic 涉及新技術/新框架、使用者說「深度 refinement」 | + Solution Research + 多角色分析（RD/QA/Arch） |

### Tier 偵測

Epic 通常還沒有 story points（估點是 refinement 下游），所以 tier 偵測基於 **Epic 內容信號**：

| 信號 | 偵測方式 | 指向 |
|------|---------|------|
| Description 長度 < 200 字且結構完整 | 字數 + checklist 比對 | Tier 1 |
| Description 含外部 URL（競品、範例網站） | URL pattern 掃描 | Tier 3 |
| Description 含「新技術」「migration」「架構」「第三方」 | 關鍵詞比對 | Tier 3 |
| 涉及 3+ 模組（從 codebase 探索推斷） | 探索結果 | Tier 2+ |
| 使用者明確說「深度」「深入」 | 觸發詞 | 強制 Tier 3 |
| 使用者明確說「簡單掃一下」 | 觸發詞 | 強制 Tier 1 |

偵測結果在開頭報告：

```
🔍 Tier：Tier 2（3+ 模組涉及，無新技術信號）
   → Codebase depth + AC hardening，跳過 Solution Research
   （說「深度」可升 Tier 3）
```

---

## Batch Scan：批次完整度掃描

適用於 sprint planning 前，一次掃描多張 Epic 的 readiness。

### 觸發場景

- 「幫我看這幾張 Epic 準備好了嗎：PROJ-481 PROJ-500 PROJ-510」
- 「sprint 準備，掃一下這些單」
- 「批次 refinement」
- 提供多個 Epic key + 任何與 refinement/readiness/完整度相關的意圖

### 1. 平行讀取所有 Epic

用 **sub-agent 平行**（`model: "haiku"` — 純 JIRA 讀取 + checklist 比對）對每張 Epic 執行：
1. `getJiraIssue` 讀取 Summary、Description、Comments、Labels
2. 根據 `references/project-mapping.md` 確認對應專案
3. 對照 Readiness Checklist（`references/epic-template.md`）逐項檢查

### 2. 彙整總覽表

所有 sub-agent 回報後，彙整為總覽表呈現給使用者：

```
## Refinement Readiness — Sprint 準備掃描

| # | Epic | Summary | 完整度 | 狀態 | 缺項 | 建議 |
|---|------|---------|--------|------|------|------|
| 1 | PROJ-481 | [feature] i18n key 減量... | 8/8 | ✅ Ready | — | → breakdown |
| 2 | PROJ-500 | [web] 商品頁重構... | 3/8 | ❌ Needs work | AC, Scope, Figma | → Phase 1 |
| 3 | PROJ-510 | [DS] Button 元件優化 | 6/8 | ⚠️ Almost | 依賴, Edge cases | → 快速補充 |

✅ Ready: 1 張（可直接排入 sprint）
❌ Needs work: 1 張（需深度 refinement）
⚠️ Almost: 1 張（快速補充後可排）
```

### 3. 更新 JIRA Label + Comment

使用者確認總覽表後，對每張 Epic 更新：

**Label**（用於 JQL 篩選）：
- 完整度達標（必要項 1-3 全有）→ 加 `refinement-ready`，移除 `needs-refinement`（如有）
- 完整度不足 → 加 `needs-refinement`，移除 `refinement-ready`（如有）

**Comment**（詳細 checklist）：寫入完整性檢查結果 + 建議，格式見 Phase 1 Step 2。

### 4. 引導下一步

- 「哪幾張要深入 refine？」→ 逐張進入 Phase 1
- 「Ready 的要直接拆單嗎？」→ 觸發 `breakdown`
- 「全部看完了，準備 planning」→ 觸發 `sprint-planning`

---

## Ticketless / DP Source Mode

適用於非 JIRA source：framework skill/rule/reference 設計、repo convention、CI/deployment 流程、ADR 類討論，以及原本會進 `design-plan` 的「想討論 XXX」入口。

### T0. Resolve source

依 `references/spec-source-resolver.md` 判斷 source type：

| Input | 行動 |
|-------|------|
| `DP-NNN` | 定位唯一 `specs/design-plans/DP-NNN-*/plan.md` |
| direct DP plan path | 使用該 DP folder 作為 source container |
| 一句話 topic | 分配下一個 `DP-NNN-{slug}`，建立 `plan.md`，status = `DISCUSSION` |
| `SEEDED` DP | 讀 `artifacts/research-report.md`（若存在）並轉成候選 Decisions |
| `LOCKED` / `IMPLEMENTED` DP | fail loud：不得把新討論塞進已定版 / 已完成 DP |

新建 DP folder 或首次建立 `plan.md` 後，必須同步 docs-viewer sidebar，讓 `http://localhost:4000/docs-viewer` 立即出現新 DP：

```bash
bash scripts/docs-viewer-sync-hook.sh {workspace_root} {workspace_root}/specs/design-plans/DP-NNN-{slug}/plan.md
```

若 hook entrypoint 無法判斷路徑，直接 fallback：

```bash
bash scripts/generate-specs-sidebar.sh {workspace_root}
```

### T1. Build or update DP plan

`refinement` 擁有下列 DP sections：

- `## Goal`
- `## Background`
- `## Decisions`
- `## Blind Spots`
- `## Acceptance Criteria`
- `## Technical Approach` / `## 技術方案`

每輪使用者確認的設計決策都要寫入 DP plan；不能只留在對話記憶。若出現 pivot，依 `spec-source-resolver.md` 的 source container 規則新開 DP 並互相 see-also。

每次新增或更新 DP `plan.md` / `refinement.md` 後，若不是由 Claude Code Write/Edit hook 自動觸發 sidebar sync，需手動呼叫：

```bash
bash scripts/docs-viewer-sync-hook.sh {workspace_root} {changed_dp_markdown_path}
```

### T2. Local-first refinement

Ticketless source 仍使用 local-first workflow：

```bash
python3 scripts/refinement-preview.py {workspace_root}/specs/design-plans/DP-NNN-{slug}/refinement.md
```

`refinement.md` 只放下游需要的實作資訊：scope、technical approach、AC、edge cases、risks、references。不放完整討論歷史；完整決策歷史留在 `plan.md`。

### T3. Artifact output

定版後產出：

```text
specs/design-plans/DP-NNN-{slug}/refinement.md
specs/design-plans/DP-NNN-{slug}/refinement.json
```

`refinement.json` 必須包含：

```jsonc
{
  "epic": null,
  "source": {
    "type": "dp",
    "id": "DP-NNN",
    "container": "{workspace_root}/specs/design-plans/DP-NNN-{slug}",
    "plan_path": "{workspace_root}/specs/design-plans/DP-NNN-{slug}/plan.md",
    "jira_key": null
  }
}
```

### T4. Lock and handoff

使用者說「定版 / 開始做 / 可以執行 / lock」後：

1. 檢查 Goal / Decisions / Blind Spots / AC / Technical Approach 是否足夠讓 breakdown 拆工
2. 將 DP frontmatter `status` 改為 `LOCKED`，填 `locked_at`
3. 產出 / 更新 `refinement.json`
4. 下一步提示 `breakdown DP-NNN`

Ticketless source 不寫 JIRA comment、不改 JIRA label、不建 JIRA ticket。若使用者需要跨團隊正式文件，另走 `sasd-review` 或手動建立 JIRA。

---

## Phase 0：發現 & 開單（RD 主動發起）

RD 在開發過程中發現問題（code smell、效能瓶頸、tech debt、架構不合理），想研究是否值得投入時間改善。

### 觸發場景

- 「這段 code 寫得很亂，想研究一下怎麼重構」
- 「這個頁面載入很慢，想查一下原因」
- 「想重構」、「tech debt」、「效能不好」

### 1. 問題分析（自適應 Explore）

使用 `references/explore-pattern.md` 的自適應探索模式掃描 codebase。

啟動 1 個 Explore subagent，帶入使用者指定的程式碼/模組路徑和問題描述。Subagent 會自行判斷範圍大小 — 單一模組直接探索，跨多模組自動分裂。

**收到探索摘要後**，主 agent 彙整產出結構化的問題分析：

```
── 問題分析 ─────────────────────────────
📍 位置：src/composables/useFeature.ts
📊 被引用：12 個檔案（5 頁面 + 7 元件）

問題：
1. 沒有 error handling — API 失敗時整個頁面 crash
2. 沒有 cache — 每次切換 tab 都重新 fetch
3. 沒有測試 — 0% coverage，改了怕壞

影響：
- 使用者體驗：切 tab 閃一下（重新 fetch）
- 穩定性：API 不穩時商品頁白屏
- 維護性：任何改動都可能影響 12 個使用者
```

### 2. 影響評估

產出一份讓非技術人員能理解的影響評估：

```
── 影響評估 ─────────────────────────────
問題嚴重度：🟡 Medium

不修的風險：
- API 不穩時商品頁會白屏（影響營收）
- 每次改 price 相關邏輯都要祈禱不壞其他頁面

修了的好處：
- 商品頁 API 錯誤有 graceful fallback
- 有測試保護，未來改動更安全

建議投入：3-5 pts（≈ 1-2 天）
ROI 評估：高 — 影響範圍大（12 個檔案）、投入小
```

### 3. 產出 JIRA ticket 草稿

結構化 ticket 草稿，含 Summary、Description（背景/目標/AC/Scope/QA 影響範圍）。

### 4. 確認 & 開單

RD 確認草稿後：
1. 用 `createJiraIssue` 建立 JIRA ticket
2. 設定 `需求來源` = `Tech - maintain`（重構）或 `Tech - bug`（效能問題）
3. 建議下一步：
   - 簡單的 → Phase 2 討論做法 → 估點 → 開工
   - 複雜的 → Phase 2 討論做法 → SA/SD → 拆子單

---

## Phase 1：需求充實（做什麼）— 5 步驟

Phase 1 是 refinement 的核心，從 checklist 填空升級為 **codebase-backed 技術驗證**。執行深度由 Complexity Tier 控制。

### Step 1 — Context Gathering

從多個來源建立 Epic 的完整 context：

**1a. JIRA 讀取**（所有 Tier）
- `getJiraIssue` 讀取 Summary、Description、AC、Comments、Linked Issues、Figma link
- 讀取所有 comments（接續上一輪 refinement 進度）

**1b. Handbook + Learnings**（Tier 2+）
- 根據 `references/project-mapping.md` 確認對應專案
- 讀取該 repo 的 handbook（`{repo}/.claude/rules/handbook/`）
- `POLARIS_WORKSPACE_ROOT={workspace_root} polaris-learnings.sh query --top 5 --min-confidence 3` 查歷史教訓（slug 自動由 workspace_root 推導）

**1c. External Content**（Tier 3 — 當 Epic 含外部 URL）
- WebFetch PM 提供的範例網站、Figma、Google Docs 連結
- 消化內容，附信心標示（見 `references/confidence-labeling.md`）

**1d. Tier 偵測**
- 基於以上收集的資訊，偵測 complexity tier（見 § Complexity Tier）
- 報告偵測結果，使用者可覆寫

### Step 2 — Codebase Exploration + Completeness Check

**2a. 自適應 Codebase 探索**（Tier 2+）

**Worktree dispatch — 主 checkout 絕對路徑**
Sub-agent 在 worktree 執行；`specs/` 與 `.claude/skills/` 是 gitignored（worktree 無此檔）。dispatch prompt 須以主 checkout 絕對路徑讀寫：
- task.md: `{company_base_dir}/specs/{EPIC}/tasks/T{n}.md`
- artifacts / verification: `{company_base_dir}/specs/{EPIC}/artifacts/`、`.../verification/`
詳見 `skills/references/worktree-dispatch-paths.md`。

使用 `references/explore-pattern.md` 掃描 codebase，探索目標：

- 找出與 Epic 需求相關的現有實作（哪些檔案要改、哪些要新增）
- 辨識影響範圍（module 引用關係、跨專案依賴）
- 發現隱藏複雜度（沒有測試的模組、過度耦合的元件）

啟動 1 個 Explore subagent，帶入 Epic 需求摘要和專案路徑。收到探索摘要後，主 agent 彙整進入下一步。

**2b. Production Runtime 驗證**（Tier 2+ — 當 Epic 涉及 SSR 輸出、結構化資料、API 回應等 runtime 行為時）

Codebase 探索的結論若涉及 runtime 行為（「這個 composable 輸出在 head」「API 回傳格式是 X」），**必須用 curl / dev server 驗證**，不可只看源碼就下結論。框架有 plugin、config、rendering pipeline 會改變最終輸出。

```bash
# 範例：驗證 JSON-LD 實際輸出位置
curl -s https://www.your-company.com/zh-tw/product/12156 | python3 check_jsonld_position.py
```

若 runtime 結果與源碼分析矛盾 → 以 runtime 為準，並在 refinement 文件中記錄驗證結果。

**2c. 完整性檢查**（所有 Tier）

對照 checklist 逐項檢查（格式同 `references/epic-template.md`）：

| 項目 | 說明 |
|------|------|
| 背景 & 目標 | 為什麼做這個？解決什麼問題？ |
| AC（Acceptance Criteria） | 可驗收的條件，一條一條列 |
| Scope（影響範圍） | 涉及哪些頁面、元件、API |
| Edge cases | 異常情境怎麼處理 |
| Figma / 設計稿 | 視覺目標 |
| API 文件 | 資料來源與格式 |
| 依賴 | 需要其他團隊或其他單先完成的 |
| 不做什麼（Out of scope） | 明確排除的項目 |

```
── Epic 完整性檢查 ──────────────────────
✅ 標題      明確描述功能目標
⚠️ 背景      有提到原因，但缺使用者痛點或商業目標
❌ AC        沒有 Acceptance Criteria
✅ Scope     [Tier 2+] 根據 codebase 分析：3 個模組、2 個新增
❌ Edge cases 沒有提到錯誤處理、空狀態、多語系
── 完整度：3/8（不足以估點）────────────
```

Tier 2+ 的 Scope 和 Edge cases 項目會帶入 codebase 探索的具體發現，而非僅看 Epic 描述。

### Step 3 — Solution Research（Tier 3 only）

當偵測到 Tier 3 或使用者說「深度」時才執行。

**3a. 範例網站分析**
- WebFetch PM 提供的範例網站
- 分析其前端實作方式（SSR/CSR、用了哪些 pattern）
- 附信心標示（見 `references/confidence-labeling.md`）

**3b. 業界標準搜尋**
- WebSearch 搜尋主題相關的業界標準做法
- 比對搜尋結果與 codebase 現狀 → gap analysis
- 所有研究發現附信心標示

**3c. 方案建議**（2-3 個）
- 每個方案附：approach、pros/cons、effort estimate、risk
- 如果 PM 的隱含方向偏離業界 → 明確指出（附來源和信心）
- **AI 不做結論** — 列出選項，由 RD/PM 決定

```
── Solution Research ────────────────────
| # | 做法 | 信心 | 來源 |
|---|------|------|------|
| 1 | Intersection Observer lazy loading | [HIGH] | MDN official docs |
| 2 | Virtual scroll for long lists | [MEDIUM] | CSS-Tricks 2024 |
| 3 | Server-side pagination | [NOT_RESEARCHED] | 需確認 API 支援 |

推薦方向：Option 1（信心最高 + 與現有 codebase 最相容）
⚠️ PM 範例網站用 Option 2，但該網站列表 < 50 項，我們的場景可達 500+
```

### Step 4 — AC Hardening（Tier 2+）

現有 AC 通常只覆蓋 happy path。這一步強化 AC 的可驗證性和覆蓋範圍。

**4a. 量化 AC**
- 將模糊 AC 轉為可量化：「頁面要快」→「LCP < 2.5s」
- 加入非功能 AC（效能、SEO、a11y）——只在相關時

**4b. 負面 AC**
- 什麼不應該壞：「既有頁面的 LCP 不因此功能退化 > 10%」
- 什麼不應該改：「其他使用 useFeature 的頁面行為不變」

**4c. 驗證方式建議**
- 每條 AC 附建議的驗證方法：`playwright` / `lighthouse` / `curl` / `unit_test` / `manual`
- 這讓下游的 engineer-delivery-flow Step 3 行為驗證知道怎麼驗

```
── AC Hardening ─────────────────────────
📝 AC（建議草稿，RD 確認後跟 PM 對齊）：

功能 AC：
1. 使用者進入商品頁 → 價格區塊顯示預設日期的價格 [playwright]
2. 使用者切換日期 → 價格即時更新 [playwright]
3. 該日無價格 → 顯示「價格洽詢」[playwright]

非功能 AC：
4. LCP < 2.5s（與 baseline 相比不退化 > 10%）[lighthouse]
5. Breadcrumb JSON-LD 結構正確 [curl + JSON parse]

負面 AC：
6. 其他使用 useFeature 的頁面行為不變 [unit_test]
7. 既有 i18n key 不被影響 [unit_test]
```

### Step 5 — Gap Report + Local Preview

**5a. Gap Report**（所有 Tier）

```
── 需要 PM 回答的問題（最多 3-5 個）────
❓ 多幣別切換是否在本次 scope 內？
❓ 「價格洽詢」的 CTA 導向哪裡？

── RD 發現的風險 ────────────────────────
⚠️ FeatureComp 元件已過度複雜，加 loading state 可能需要先重構
   → 緩解：可先用 wrapper component 隔離
⚠️ /api/product/price endpoint 在 codebase 中不存在
   → 需確認後端是否已開發
```

**5b. 寫入本地 markdown**

將 Step 1-5 的產出整合寫入 `{company_base_dir}/specs/{EPIC_KEY}/refinement.md`（ticket workspace 模式，見 memory: `project_designs_at_company_level`）。

**產出格式規則：只放實作需要的資訊，不放討論過程或歷史沿革。**

完整性 checklist、歷史比較分析、「上次為什麼走錯」等推導過程是討論階段的工具，不進入產出文件。下游（breakdown, engineering）只需要知道「該怎麼做」，不需要知道「為什麼上次搞砸」。

```markdown
# Refinement — {EPIC_KEY}: {Summary}

> Tier: {N} | Date: {YYYY-MM-DD}

## 涉及 Repo
| Repo | 角色 | 說明 |
|------|------|------|
| {repo-name} | 實作 / Dev infra | ... |

## Production 現況（runtime 驗證數據，若有）
（curl / dev server 驗證結果，表格呈現）

## 涉及模組
| Repo | 檔案 | 動作 | 說明 |
|------|------|------|------|
| ... |

## 技術方案
（正確做法 + 研究順序，不含「為什麼上次錯了」）

## AC
### 功能 AC
### 非功能 AC
### 負面 AC

## Edge Cases

## RD 風險

## 待確認

## 子單結構
| # | Key | Summary | Points | 備註 |
|---|-----|---------|--------|------|
| ... |

## 參考資料
```

**5c. 啟動 preview server**

```bash
python3 scripts/refinement-preview.py {company_base_dir}/specs/{EPIC_KEY}/refinement.md
```

告知使用者：「Preview 已開在 http://localhost:3333 ，可以在大螢幕上跟團隊討論。有修改告訴我，我更新 markdown 後 browser 會自動刷新。定版後說「寫回 JIRA」。」

**不寫 JIRA** — 所有中間輪次的產出留在本地 markdown，省去每輪寫入成本。

### Step 6 — 多輪迭代（本地）

使用者或團隊提出修改 → Strategist 更新 `refinement.md` → browser 自動刷新。

每輪更新：
1. 更新 markdown 中的相關段落（Round 編號遞增）
2. 針對仍不足的部分產出新建議
3. 標記已解決的 PM 問題和已確認的 AC

**不寫 JIRA，不寫 artifact** — 所有中間產出留在本地 markdown。

**判斷「夠了」的標準：**
- AC ≥ 3 條且可驗收（含驗證方法）
- Scope 明確到可以列出受影響的檔案/元件
- Edge cases 至少覆蓋：空狀態、錯誤狀態、loading 狀態
- 依賴已釐清（有對應 ticket 或確認不需要）

使用者說「定版」/「寫回 JIRA」/「OK 了」/「可以進 breakdown」/「足夠推到 breakdown」→ 進入 Step 7。

### Step 7 — 定版寫入（一次性）

使用者確認定版後，一次性產出三份：

**7a. JIRA comment**
以 `refinement.md` 的最終版內容為基礎，寫入 JIRA comment（格式同上述 markdown 結構）。

**7b. Artifact JSON**（Tier 2+）
根據 `references/refinement-artifact.md` schema 產出 `{company_base_dir}/specs/{EPIC_KEY}/refinement.json`。

**7b'. Handoff artifact gate（hard）**
在說「可進 breakdown」或提示下一步 `breakdown` 前，必須跑：

```bash
bash scripts/refinement-handoff-gate.sh {company_base_dir}/specs/{EPIC_KEY}/refinement.md
```

- exit 0 → `refinement.json` 存在且通過 schema validation，才可繼續 7c/7d 並提示 breakdown
- exit 1/2 → 停下來補 `refinement.json` 或修 artifact；不可只用 `refinement.md` 交給 breakdown

**7b''. Workspace language policy gate（hard）**
在任何 refinement artifact 對下游公開前，必須依 root `workspace-config.yaml language`
檢查自然語言內容。`refinement.md` 一律 blocking；DP / ticketless source 若同一
container 有 `plan.md`，也一併檢查。`refinement.json` 的結構由 handoff gate 管，
自然語言摘要若已同步進 markdown，不另以 JSON 原文作語言判定來源。

```bash
files=("{company_base_dir}/specs/{EPIC_KEY}/refinement.md")
[[ -f "{company_base_dir}/specs/{EPIC_KEY}/plan.md" ]] && files+=("{company_base_dir}/specs/{EPIC_KEY}/plan.md")
bash scripts/validate-language-policy.sh --blocking --mode artifact "${files[@]}"
```

exit ≠ 0 → 修 artifact 語言後重跑；不可用英文 refinement artifact 交給 breakdown。

**7c. 整合母單 description**
用 `editJiraIssue` 更新母單 description — 結構化格式（`references/epic-template.md`）。

**7d. Label + 下一步**
- 更新 JIRA Label：加 `refinement-ready`，移除 `needs-refinement`
- 建議下一步：`breakdown`（拆子單 + 估點）
- 關閉 preview server（如還在跑）

### Step 8 — L2 Deterministic Check: post-task-feedback-reflection

定版寫入 / artifact 產出完成後，跑 advisory check：session 內若出現自糾正信號但無新 feedback memory 檔案 → 提示反思。

```bash
bash "$CLAUDE_PROJECT_DIR/scripts/check-feedback-signals.sh" \
  --skill refinement
```

根據 exit code（advisory — script 恆 exit 0）：
- **exit 0 + 無 stdout** — 無反思訊號，refinement 輪次正式收尾
- **exit 0 + 有 stdout** — 依 `rules/feedback-and-memory.md` 判斷是否寫 feedback memory 或更新 handbook

此 canary 原列 `rules/mechanism-registry.md § Feedback & Memory`（behavioral），DP-030 Phase 2C 下放為 deterministic。L1 fallback 由 Stop hook（`.claude/hooks/feedback-reflection-stop.sh`）補位。遵循 `skills/references/l2-script-conventions.md` advisory 約定。Phase 2（方案討論）收尾時亦建議重跑一次。

---

## Phase 2：方案討論（怎麼做）

Epic 內容完整後，如果做法不明確（多種實作路徑、架構選擇），進入方案討論。

### 適用場景

- 預估 > 8 點的 Epic
- 涉及跨專案改動
- 技術選型有多個選項
- RD 主動問「這張怎麼做比較好」

### 流程

1. **產出 2-3 種方案**，每個附：

```
── Option A: 擴展現有元件 ──────────────
Approach:  修改 FeatureComp 元件，加入 loading/error state
Pros:      複用現有元件，改動範圍小
Cons:      FeatureComp 已經很複雜，再加 state 可能過載
Effort:    M（3-5 pts）
Affects:   <design-system> + <your-repo>
Risk:      DS 改動需要先 merge 才能在 main-repo 用
```

2. **比較矩陣** + 推薦，但由 RD 決定

3. **多角色分析**（Tier 3 或使用者要求時）

   類似 challenger audit 的模式，啟動 3 個 sonnet sub-agent 平行分析：

   - **RD lens**: 技術可行性、影響範圍、歷史教訓、隱藏複雜度
   - **QA lens**: AC 可驗證嗎？邊界案例？需要什麼測試基礎設施？
   - **Arch lens**: 跨系統影響、API 契約、共用元件、tech debt 風險

   三個角色產出彙整為一份 **Technical Assessment**，附在比較矩陣後面。

4. **產出 Decision Record** → 寫回 JIRA comment：

```
## Decision Record — [日期]

**Decision**: Option A — 擴展 FeatureComp 元件
**Reason**: 複用性高，長期維護成本低
**Key decisions**:
- 用 Intl.NumberFormat（不自己寫 formatting）
- SSR render 價格（SEO）
**Open questions**:
- [ ] DS 的 PR 能否在本 sprint 內 merge？
```

5. **更新 artifact** — 將選定方案寫入 `refinement.json` 的 `downstream` 區塊

---

## Skill Chain

```
refinement
  ├─ Batch Scan 完成
  │   ├─ refinement-ready → breakdown / sprint-planning
  │   └─ needs-refinement → Phase 1 逐張深度補充
  │
  ├─ Phase 0 完成（開單）
  │   → Phase 2（討論做法）→ breakdown → engineering
  │
  ├─ Phase 1 完成（Epic 充實 + artifact + label: refinement-ready）
  │   → breakdown（拆子單 + 估點 — 讀 artifact）
  │
  └─ Phase 2 完成（方案確定）
      → sasd-review（複雜需求產出 SA/SD）
      → engineering（直接開工）
```

## Do / Don't

- Do: 用 codebase 分析產出具體建議，不要列空白問題讓 RD 自己填
- Do: 討論過程中寫回 JIRA comment（保留討論歷史），完整度達標後整合到 description
- Do: 每次 refinement 開始時先讀 JIRA comments + 既有 artifact，接續上一輪進度
- Do: 標出「需要 PM 回答」和「RD 可以自己決定」的問題
- Do: 完整度達標時主動建議進入估點/拆單
- Do: Phase 0 的影響評估用非技術語言寫
- Do: Tier 2+ 產出 structured artifact（JIRA comment + local JSON 同步）
- Do: AC hardening 區分功能 AC、非功能 AC、負面 AC
- Do: 所有研究發現附信心標示（`references/confidence-labeling.md`）
- Don't: 替 PM 決定需求 — 建議草稿可以，但最終由 PM 確認
- Don't: 一次要求 PM 回答太多問題 — 分優先級，最多 3-5 個關鍵問題
- Don't: 完整度不足就直接進估點 — 先把需求釐清
- Don't: 跳過 codebase 分析（Tier 2+）— 不讀 code 就無法產出有意義的 scope 和 edge cases
- Don't: Phase 0 誇大問題嚴重度 — 如實評估，讓數據說話
- Don't: Solution Research 時做結論 — 標信心、列來源，人決定
- Don't: Tier 1 case 跑完整 Tier 2 流程 — 簡單的 Epic 不需要重砲

## Prerequisites

- **Phase 0**：RD 指定的程式碼或模組路徑 + 對應專案已 clone
- **Phase 1**：JIRA ticket 存在（至少有標題）
- **Phase 2**：需求已明確（Phase 0 或 Phase 1 完成）
- Atlassian MCP 已連線
- 對應專案已 clone 到 `{base_dir}/`（用於 codebase 分析）

## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
