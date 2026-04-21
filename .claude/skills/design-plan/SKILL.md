---
name: design-plan
description: "Create and maintain persistent design plan files for non-ticket architecture discussions. Auto-triggers when user starts a design discussion; accumulates decisions as file not memory; locks when user approves; implementation reads plan as spec. Fills the gap between refinement/sasd-review (ticket-scoped) and informal conversation (ephemeral). Trigger: '想討論', '怎麼設計', '重構', '重新設計', '要怎麼改', '要怎麼重做', 'design plan', 'ADR'."
metadata:
  author: Polaris
  version: 1.2.0
---

# Design Plan — 非 Ticket 架構討論的落地機制

解決「討論 → 實作」轉換時早期決策被覆蓋的問題。把對話中的設計決策從記憶轉成檔案，讓實作階段有確定性的 spec 可讀，消除掉棒風險。

## 適用場景

| 場景 | 是否適用 |
|------|---------|
| 框架層級重構（skill、rule、reference） | ✅ |
| Repo 層級架構討論（CI 流程、deployment、convention） | ✅ |
| 非 ticket 的工具／基礎設施設計 | ✅ |
| Ticket-scoped 實作規劃 | ❌ 用 `breakdown` |
| Ticket 需求釐清 | ❌ 用 `refinement` |
| Ticket 技術設計文件（需跨團隊可見） | ❌ 用 `sasd-review` |

## 觸發條件

### 明確觸發詞（高信心，立刻建檔）

- 「想討論」「我想討論」「來討論」
- 「怎麼設計」「要怎麼設計」「要怎麼改」「要怎麼重做」
- 「重構」「重新設計」
- 「design plan」「ADR」「decision record」

### 多輪偵測（中信心，回溯建檔）

同一個 design 話題來回 3+ 輪 → 回溯建立 plan file，把先前的決策補進去。Design 話題的訊號：

- 使用者詢問「你覺得這個設計合理嗎」「會不會有問題」「這樣可行嗎」
- Strategist 做過 blind spot scan 找出 ≥ 1 個問題
- 討論內容包含「架構」「流程」「skill」「rule」「機制」等字眼

### 不觸發

- 單輪 Q&A（即使關於架構）
- 純讀取現有設計（沒有要改）
- 使用者明確說「不用建 plan，先討論」

## 檔案位置與命名

**位置**：`specs/design-plans/DP-NNN-{topic-slug}/plan.md`（workspace root `specs/` 為 framework 層 spec folder，與 `{company}/specs/{TICKET}/` 概念對齊但不綁公司）

**命名**：
- `DP-NNN`：Design Plan 流水號，三位數從 `DP-001` 起，建立時掃 `specs/design-plans/` 取現有最大值 + 1
- `{topic-slug}`：kebab-case，描述討論核心（例：`check-pr-approvals-v2`、`ci-pipeline-refactor`）。避免含版本號除非版本是討論核心

**為什麼是 folder 不是單檔**：非 ticket 討論沒有 JIRA key 可掛，folder 結構讓後續可放 draft、diagram、子檔案（類比 `{company}/specs/{TICKET}/` 的多檔結構）。主檔固定叫 `plan.md`。

**Git**：gitignored（`/specs/` 在 workspace root 被忽略）。Plan 檔案是個人工作空間的思考紀錄，不進 git history；畢業成 rule/reference 後才進 framework。

## Plan 檔案結構

```markdown
---
topic: {Human-readable title}
created: YYYY-MM-DD
status: SEEDED | DISCUSSION | LOCKED | IMPLEMENTED | ABANDONED
locked_at: YYYY-MM-DD  # 只在 LOCKED 後出現
implemented_at: YYYY-MM-DD  # 只在 IMPLEMENTED 後出現
---

# {Title} — Design Plan

## Goal

{要解決的問題 / 要達成的目標，1-3 段}

## Background

{現有機制 / 為什麼需要改 / 相關 context}

## Decisions（按時序累積）

### D1: {決策標題}

- Context: {使用者提的問題或情境}
- Decision: {同意的結論}
- Rationale: {為什麼這樣決定}

### D2: ...

## Blind Spots

每個盲點必須附 Mitigation + Implementation（要實作什麼才算修完）：

- [ ] **#1 {問題描述}**
  > Mitigation: {修法}
  > Implementation: {具體要改哪個檔案 / 加什麼 section}

## Implementation Checklist

從 Decisions + Blind Spots 自動產生，全部打勾才能宣告 done：

- [ ] {D1 要實作的具體動作}
- [ ] {D2 要實作的具體動作}
- [ ] {Blind spot #1 修法要改的具體檔案}

## Locked

Locked at: YYYY-MM-DD by {觸發語句}

## Implementation Notes

{實作過程中的觀察、偏離理由、後續 follow-up}
```

## Status 狀態定義

| Status | 意義 |
|--------|------|
| `SEEDED` | Plan shell 已建、`artifacts/research-report.md` 已放好，等待使用者輸入 `/design-plan DP-NNN` 啟動討論。由 `/learning` 的 handoff 流程建立；不是從對話直接 lock 的狀態 |
| `DISCUSSION` | 討論進行中，決策持續累積 |
| `LOCKED` | 所有 Decisions / Blind Spots / Implementation Checklist 都齊備，進入實作階段 |
| `IMPLEMENTED` | Implementation Checklist 全打勾、實作完成 |
| `ABANDONED` | 討論後決定不做（保留檔案記錄決策過程） |

## Workflow

### Phase 1: 偵測 + 建檔

此 Phase 有兩條 trigger mode，依 skill 呼叫方式分流：

#### Mode A: 人工觸發（無 argument，原有流程）

使用者說出明確觸發詞，或多輪偵測成立 → 從對話脈絡建立 plan file。此 mode **不期待** `artifacts/research-report.md` 存在，研究內容直接寫進 plan 即可：

1. 從討論中提取 topic slug
2. 掃 `specs/design-plans/` 現有 `DP-NNN-*` folder 取最大 N，分配下一個編號（首次使用為 `DP-001`）
3. 建 `specs/design-plans/DP-NNN-{topic-slug}/plan.md`
4. 填入 Goal / Background / 已累積的 Decisions / Blind Spots
5. 告知使用者：「已建立 design plan: `specs/design-plans/DP-NNN-{slug}/plan.md`，後續決策會寫入此檔。」
6. Status: DISCUSSION
7. 更新 Specs Viewer sidebar：`bash scripts/generate-specs-sidebar.sh`

#### Mode B: Handoff 消費（argument = `DP-NNN`，e.g. `/design-plan DP-019`）

此 mode 由 `/learning` 的 seeding handoff 觸發——`/learning` 已建好 DP folder + stub plan + research report，使用者稍後呼叫 `/design-plan DP-NNN` 來啟動討論。

1. **定位 DP folder**：掃 `specs/design-plans/DP-NNN-*/` 找唯一 match 的 folder（slug 任意）
   - 找不到 → **Fail loud**：「錯誤：找不到 `DP-NNN` 對應的 folder。handoff branch 必須有 seeded folder，請確認 `/learning` 是否正確建立。」中止流程，不 fallback 到對話脈絡
2. **檢查既有 plan 狀態**（BS#19）：讀 `plan.md` frontmatter `status`
   - `SEEDED` → 正常 handoff 消費路徑，繼續 Step 3
   - `DISCUSSION` → 允許繼續（可能是先前被中斷、使用者想接續討論）
   - `ABANDONED` → 詢問使用者要不要 revive；要 → 視為 DISCUSSION 繼續；不要 → 中止
   - `LOCKED` / `IMPLEMENTED` → **Fail loud**：「錯誤：DP-NNN 已 {status}，不得將新 report 消費進既有 plan。請建立新 DP（新 DP 的 Background 加 `See also: DP-NNN`）。」中止流程
3. **定位 research report**：讀 `specs/design-plans/DP-NNN-*/artifacts/research-report.md`
   - 找不到 → **Fail loud**：「錯誤：DP-NNN 的 `artifacts/research-report.md` 不存在。handoff branch 明示指定 seeded folder，report 必須存在，不 fallback 到對話脈絡。請確認 `/learning` 是否正確產出 report。」中止流程（BS#16）
4. **讀取 report** 並做分析映射（BS#3' mapping rules）：
   - Report `## Goal` → plan `## Goal`（可直接引用或精簡）
   - Report `## Comparison Matrix` + `## Knowledge Compile Results` → plan `## Background` 的摘要段落 + 「詳見 [artifacts/research-report.md](artifacts/research-report.md)」link
   - Report 每個 `## Recommendations` 項目 → 一個 D{N} 候選：
     - `Context` = Recommendation 的 Why
     - `Decision` = Recommendation 的 What
     - `Rationale` = Recommendation 的 How + Landing
     - **不** copy Effort / Priority（排序不是 plan 的職責）
   - 每個 D{N} 以候選形式寫入（使用者後續 Phase 2 討論時確認或修改）
5. **升級 stub plan**：把 frontmatter `status: SEEDED` 改為 `status: DISCUSSION`
6. 告知使用者：「已讀取 DP-NNN 的 research report，產出初版 Goal / Background / {N} 個 Decision 候選。後續討論會累積進此 plan。」
7. 更新 Specs Viewer sidebar：`bash scripts/generate-specs-sidebar.sh`

**關鍵差別**：
- Mode A 無 argument，不期待 report，從對話建 plan
- Mode B 有 `DP-NNN` argument，**必須**有 report，缺任何一項（folder / report）都 fail loud 不 fallback——這是 handoff 契約，silent fallback 會變成空 plan（BS#16）

### Phase 2: 討論累積

每輪使用者確認決策（說「可以」「同意」「乾淨」「好」「這樣做」等）→ Strategist 立刻更新 plan：

- 新增 Decision 條目（D{N+1}）
- 若觸發 blind spot scan，把問題 + 修法寫入 Blind Spots
- 把 Implementation Checklist 同步更新

**關鍵規則**：決策確認後，**下一個 tool call 必須是更新 plan file**。不可延後、不可批次。違反 = 回到舊的掉棒模式。

### Phase 3: Lock

使用者說「定版」「開始做」「可以執行」「lock」→ Strategist：

1. 回顧整份 plan，檢查：
   - 所有 Decisions 都有 Rationale
   - 所有 Blind Spots 都有 Mitigation + Implementation
   - Implementation Checklist 覆蓋所有 Decisions 和 Blind Spots
2. 若有缺漏 → 補完再 lock
3. Status: DISCUSSION → LOCKED
4. 填 `locked_at` 和觸發語句

### Phase 4: 實作

**實作開始前**：讀完整份 plan file，不依賴對話記憶。

#### 選擇執行模式

| 模式 | 適用 | 特色 |
|------|------|------|
| **4a. Main-agent 模式** | Checklist ≤ 3 項且每項 ≤ 1 個檔案 | Strategist 直接執行，簡單快速 |
| **4b. Sub-agent Handoff 模式** | Checklist > 3 項、跨多檔案、或分多個 phase | Dispatch sub-agents 消費 plan.md 作為 work order，main agent 只做 orchestration |

判斷準則：參照 `rules/sub-agent-delegation.md` 的 delegation threshold（> 1 個檔案、> 3 行改動）→ 超過就走 4b。

#### 4a. Main-agent 模式

Strategist 逐項勾 Implementation Checklist。每勾一項，**立刻更新 plan file**（下一個 tool call）。

#### 4b. Sub-agent Handoff 模式

LOCKED 的 plan 即 self-contained work order。跟 `breakdown → task.md → engineering` 同一個 pattern——main agent 只 dispatch + review，實作由 sub-agent 消費 plan 完成。

**Dispatch 流程**：

1. 依 Implementation Checklist 的 Phase/Section 切分工作包
2. 每個 sub-agent 的 prompt 只給：
   - Plan file 的絕對路徑（**spec 唯一來源，sub-agent 自己讀**——不要 copy plan 內容進 prompt）
   - 本 phase 的 scope 限制（可改/可讀/不可動的檔案清單）
   - Repo handbook 讀取指示（若改動涉及產品 repo）：「開工前先讀 `{repo}/.claude/rules/handbook/index.md` 及其子文件，遵循 coding conventions」
   - Completion envelope 格式（見 `skills/references/sub-agent-roles.md`）：`Status: DONE|BLOCKED|PARTIAL` / `Artifacts:` / `Detail: specs/design-plans/DP-NNN/artifacts/{phase}-{timestamp}.md` / `Summary:`
3. Main agent 等回傳後 fan-in validate envelope

**平行 vs 順序**：

| 情境 | 模式 |
|------|------|
| Phases 修改的檔案不重疊且無 interface 依賴 | 平行 dispatch（單訊息多個 Agent tool）|
| Phase 依賴前一個 phase 的 interface 或檔案結構 | 順序 dispatch（前一個回傳後再 dispatch 下一個）|
| 多個 sub-agent 可能修改相同檔案 | 平行 + `isolation: "worktree"`（見 `skills/references/sub-agent-reference.md`）|

**Sub-agent 責任**：
- 讀完整 plan.md，不跳讀
- 只做分配到的 phase scope，不越界
- 偏離 plan 立刻 STOP + 回報（不擅自決策）
- 回報時說明「下一個 phase 需要注意的 interface contract」（若有）

**Main agent 責任**：
- Dispatch 前確認 plan 為 LOCKED 狀態 + Checklist 切分合理
- 每個 sub-agent 回傳後 fan-in validate（envelope 完整 + Status == DONE + Artifacts 非空）
- 整合 Checklist 更新（tick off 對應項目 — 統一由 main agent 寫回 plan file，避免多 sub-agent 並發寫檔）
- 全部 phases 完成後進 Phase 5

#### 實作時發現需偏離 plan（兩模式通用）

1. **停下來**，不靜默改（4b 模式：sub-agent STOP + 回報給 main agent）
2. 在 plan 新增 Decision 條目說明偏離理由（例：`### D11: 實作時發現 X 不可行，改為 Y`）
3. 更新 Implementation Checklist
4. 繼續實作

**不可**：
- 口頭同意偏離但沒更新 plan
- 一次實作完所有項目最後再勾

### Phase 5: 完成

所有 Checklist 打勾 → Strategist：

1. **Checklist completeness gate（deterministic）**：
   ```bash
   grep -c '^\- \[ \]' {plan_file_path}
   ```
   - 回傳 > 0（有未勾項）→ **BLOCK**：列出未勾項，逐一確認 done/dropped 後再繼續
   - 回傳 0（全部勾完）→ proceed
   - 這是硬門檻，不可跳過。最常漏勾的是「最後一項（commit/sync）」——因為完成時注意力已離開 plan file
2. Status: LOCKED → IMPLEMENTED
3. 填 `implemented_at`
4. 加 Implementation Notes（實作過程觀察、後續 follow-up）
5. 更新 Specs Viewer sidebar：`bash scripts/generate-specs-sidebar.sh`（讓 IMPLEMENTED 顯示綠色）
6. Plan file + sidebar 跟 implementation 一起 commit

## Pivot 處理

討論過程中若 topic 顯著偏移（例：從「改 A skill」變成「重新設計整個 pipeline」）：

| 情境 | 處理 |
|------|------|
| 輕度延伸（同 topic 更深入） | 繼續用同一個 plan，新增 Decision |
| 顯著偏移（不同 topic） | **新開 plan file**，在原 plan 加「## See also」指向新 plan；原 plan 的 status 視情況 ABANDONED 或 IMPLEMENTED |

判斷準則：**新的 topic slug 會不會跟原本不一樣**。會 → 新開。

## Negative Decisions（決定不做）

討論後決定不實作，plan 檔案仍保留：

- Status: ABANDONED
- 最後一個 Decision 條目說明「Final decision: 不做 {topic}，原因：{why}」
- 不刪檔案 — 「我們考慮過 X 但不做」對未來決策有價值

## Do

- 偵測到 design discussion 就立刻建 plan，不要拖到討論完
- 每個決策確認後，**下一個 tool call** 必須更新 plan file
- Blind spot scan 的每個問題 + 修法都要進 Blind Spots section
- Implementation Checklist 覆蓋所有 Decisions 和 Blind Spots
- 實作前讀完整 plan，不依賴對話記憶
- 實作時發現偏離 → 停下 + 更新 plan + 新增 Decision
- Plan file 跟 implementation 一起 commit

## Don't

- 不要等討論完才建 plan — 決策會被後續覆蓋
- 不要口頭同意偏離但沒更新 plan — 這就是掉棒的源頭
- 不要批次打勾 Implementation Checklist — 每勾一項立刻更新檔案
- 不要在 Plan 有未勾項時宣告 done
- 不要用 design-plan 處理 ticket-scoped 設計（那是 breakdown / sasd-review 的工作）
- 不要把 Plan 檔案放在其他位置 — 統一在 `specs/design-plans/DP-NNN-{slug}/plan.md`

## Integration with Other Skills

| Skill | 互動方式 |
|-------|---------|
| `breakdown` | Ticket-scoped — 不重疊。但如果某 Epic 需要先做架構討論，可以先 design-plan → lock 後再 breakdown |
| `sasd-review` | 跨團隊可見的技術設計 — design-plan 是團隊內 / 框架層，sasd-review 是對外正式文件。兩者可並存（先 design-plan 收斂，再 sasd-review 正式化） |
| `engineering` | 實作時若存在對應 design-plan，engineering 必須讀 plan 才能開工（參考 `mechanism-registry.md` `design-plan-reference-at-impl` canary） |
| `checkpoint` | Design plan 是 checkpoint 的補充 — checkpoint 存 session 狀態，design plan 存決策脈絡 |
| `/learning` | **Seeding handoff**：當 `/learning` Step 5 使用者選擇「開 /design-plan 討論」路線，`/learning` 會分配 DP-NNN、建 `specs/design-plans/DP-NNN-{slug}/artifacts/research-report.md`、建 stub `plan.md`（`status: SEEDED`），並告知使用者輸入 `/design-plan DP-NNN` 啟動討論。`/learning` **不自動 invoke**，使用者掌握時機。`/design-plan DP-NNN` 進入 Phase 1 Mode B 消費 report，升級狀態至 DISCUSSION。同 session 可建多個獨立 DP（N recommendations → N DPs，不擠同一 plan）。參考 DP-019 |

## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
