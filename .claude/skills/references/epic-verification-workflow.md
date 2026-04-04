# Epic Verification Workflow

Reference doc for the three-layer verification structure. Not yet integrated into skills — validate with 2 Epic cycles before graduating to skill changes.

## Status: Draft (pre-graduation)

**Graduation criteria:**
- [ ] Epic #1 試跑完成，記錄調整項
- [ ] Reference doc 根據 Epic #1 修正
- [ ] Epic #2 驗證完成，無結構性修改
- [ ] 畢業 → 改進 epic-breakdown, epic-status, work-on, jira-estimation

**Graduation signal:** 連續 2 個 Epic 走完流程且 doc 核心流程不需修改。

---

## Three-Layer Verification

| Layer | Purpose | Timing | Form |
|-------|---------|--------|------|
| **Task test plan** | PR 品質紀錄，留存讓人 review | task branch → feature PR | Sub-task（紀錄用，在 PR gate 內，非獨立驗收） |
| **Epic per-AC verification** | 業務目標達標證明 | 所有 task merge 回 feature 後 | KB2CW Task × N，Playwright E2E 逐條跑 |
| **Feature integration test** | task 之間互動沒問題 | 同上 | 驗收單之一或獨立一張 |

## Layer 1: Task Test Plan (sub-task)

**What:** 每張實作 task 開一張 sub-task 記錄測試計劃。

**Purpose:** 不是驗收 gate，而是品質紀錄。讓其他人 review 這個 Epic 時，能確認每張 task 是如何通過框架定下的測試計劃的。未來可以與時俱進增強或調整。

**Content:**
```
測試計劃 — {TICKET_KEY}

1. 品質檢查：lint ✓ / test ✓ / coverage ✓
2. VR：{triggered / not applicable}（理由）
3. 驗證：{verify-completion 結果 or 手動驗證步驟}
4. PR review：{approved by X}
```

**Trigger:** `work-on` 或 `jira-estimation` 建立 task 時自動建 sub-task。dev-quality-check 和 verify-completion 跑完後更新內容。

**Not a blocker:** task 的 PR merge 不依賴 sub-task 狀態。sub-task 是事後記錄。

## Layer 2: Epic per-AC Verification (KB2CW Task)

**What:** Epic 的每個 AC 開一張驗收 ticket。

**Source of AC items:**
- QA/PM 提供的 happy flow 和驗收標準
- RD 補充 Polaris 推斷的重要檢查（VR、效能指標、邊界條件）

**Size threshold:**
- Epic > 8 pts 或 > 2 tasks → per-AC 拆驗收單
- Epic ≤ 8 pts 或 ≤ 2 tasks → 合併成一張「Epic 驗收」

**When to create:**
- `epic-breakdown` 拆單時自動在最後產生
- Status 設為 Open / Waiting for Development
- 標記依賴：depends on 所有實作單

**When to run:**
- `epic-status` 偵測所有實作單 PR merged 回 feature branch 後提醒
- 驗收前先 rebase develop（確保 feature branch 是最新的）

**Environment tagging:**
每張驗收單標記可在哪個環境驗：

| Tag | Meaning | Example |
|-----|---------|---------|
| `env:feature` | 可在 feature branch 驗 | VR zero-diff, code structure check |
| `env:stage` | 需要 stage 環境 | 真實 TTFB 數字, 真實 API response |
| `env:both` | feature 初步驗 + stage 最終驗 | 效能指標（local 初步, stage 最終） |

同一張驗收單可跑兩次：feature branch 初步通過 → stage 最終通過。更新結果在 ticket comment。

**Execution:**
- Playwright E2E 逐條跑，結果更新在各驗收 task 上
- 結果作為 evidence 給 QA/PM 確認標準達到

## Layer 3: Feature Integration Test

**What:** 所有 task merge 回 feature 後，跑一次整合測試確認 task 互動沒問題。

**Why:** GT-483 試跑實證 — 個別 task 都通過但 merge 回 feature 後出問題。

**Content:**
- VR 截圖比對（feature branch vs main/develop baseline）
- E2E smoke test（key user flows）
- 如果 Epic 涉及效能 → 效能基準對比

**Form:** 可以是驗收單之一（如「Feature 整合 VR」），或獨立一張。

## Feature Branch Flow

```
feature/{EPIC_KEY}-{description}
  │
  │  ── 實作階段 ──
  ├── task/{TICKET_KEY}-{desc} → PR to feature branch
  │     └── sub-task: 測試計劃（Layer 1, 品質紀錄）
  ├── task/{TICKET_KEY}-{desc} → PR to feature branch
  │     └── sub-task: 測試計劃
  ├── ...
  │
  │  ── 驗收階段（所有 task merge 回 feature 後）──
  │  ── Step 0: rebase develop ──
  ├── {TICKET_KEY} — 驗收 AC1 (Layer 2)
  ├── {TICKET_KEY} — 驗收 AC2 (Layer 2)
  ├── {TICKET_KEY} — Feature 整合測試 (Layer 3)
  │
  └── feature → develop PR（全部驗收通過 = 功能完整驗收的 PR）
```

## Skill Integration Map (post-graduation)

| Skill | Change needed |
|-------|--------------|
| `epic-breakdown` | 拆單最後自動產生 per-AC 驗收單 + 整合測試單 |
| `epic-status` | Phase 1 偵測「所有 task merged → 提醒開始驗收」。Phase 2 路由驗收 gap |
| `work-on` | 建 task 時自動建測試計劃 sub-task |
| `jira-estimation` | 估點時產生測試計劃 template |
| `dev-quality-check` | Step 8b VR 條件觸發（已完成 v1.52.0） |
| `git-pr-workflow` | 驗收前 auto-rebase develop（待做） |

## Edge Cases

| Situation | Handling |
|-----------|---------|
| Epic 只有 1 張 task | 合併所有驗證為一張，不拆 per-AC |
| AC 只能在 stage 驗 | 標記 `env:stage`，feature branch 階段跳過，stage deploy 後跑 |
| 驗收跑出非預期差異 | 評估是否開 fix ticket 或接受差異，記錄在驗收 ticket comment |
| Feature branch 跟 develop 衝突 | rebase + 解衝突後重跑整合測試 |
| 某張 task PR 一直沒 merge | `epic-status` Phase 2 路由 → fix-pr-review 或催 review |
| QA/PM 沒提供 happy flow | RD 根據 Epic AC 自擬，標記「RD 推斷，待 PM 確認」 |
