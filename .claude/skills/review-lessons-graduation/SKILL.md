---
name: review-lessons-graduation
description: >
  Consolidates review-lessons into main .claude/rules/ when entry count >= 15.
  Auto-invoked by review-pr, fix-pr-review, check-pr-approvals after lesson extraction.
  Also trigger manually: "整理 review lessons", "organize review lessons", "graduate lessons",
  "review lessons 畢業", "consolidate lessons", "lesson 整理", "clean up lessons",
  "畢業 review lessons", "promote review lessons".
  Make sure to use this skill whenever review-lessons consolidation, graduation,
  or cleanup is mentioned — even if the user just says "lessons 太多了", "too many lessons",
  "rules 整理一下", or "tidy up rules".
metadata:
  author: Polaris
  version: 1.0.0
---

# Review Lessons Graduation

Review-lessons 是從 PR review 萃取的 coding patterns，存在各專案的 `.claude/rules/review-lessons/`。隨著累積，條目會越來越多，增加每次對話的 context token 消耗。這個 skill 定期把成熟的 lesson「畢業」併入主 rules，刪除重複的，保留尚未驗證的，維持 review-lessons 目錄精簡。

## 0. 判斷觸發來源

| 來源 | 行為 |
|------|------|
| **其他 skill invoke**（review-pr / fix-pr-review / check-pr-approvals） | 先執行 Step 1 gate check；未達門檻就靜默結束 |
| **使用者手動觸發** | 跳過 gate check，直接進 Step 2 |

若為 invoke 觸發，需要知道是哪個 repo 的 review-lessons。從 invoke context 或當前工作目錄推斷 `<repo>` 路徑。

## 1. Count & Gate

掃描 `~/work/<repo>/.claude/rules/review-lessons/` 下所有 `.md` 檔案：

1. 讀取每個檔案，計算頂層 bullet 數量（以 `^- ` 開頭的行 = 1 條 entry）
2. 加總所有檔案的 entry 數

```
若總數 < 15 且非手動觸發 → 靜默結束（不輸出任何訊息）
若總數 >= 15 或手動觸發 → 繼續 Step 2
```

## 2. 讀取主 Rules 與 Review Lessons

平行讀取：

1. **所有 review-lessons 檔案**：完整讀取每個 `.md`，解析每條 entry 的：
   - 規則內容（bullet 主文）
   - Why 說明
   - Source PR URLs（一條 entry 可能有多個 Source）
   - 所屬檔案名

2. **所有主 rule 檔案**（`.claude/rules/*.md`，不含 `review-lessons/` 子目錄）：完整讀取，理解每個 rule 檔的主題範圍和已有規則

## 3. 逐條分類

對每條 review-lesson entry，依以下條件分類：

### 併入（Graduate）

同時滿足：
- Source PR 數量 **>= 2**（被不同 PR 驗證過，代表是通用 pattern）
- 主 rules 中**尚未涵蓋**相同語意的規則

→ 動作：併入對應的主 rule 檔案

### 刪除（Delete）

滿足任一：
- 主 rules 中**已有語意相同**的規則（重複）
- 規則已過時（框架版本升級、API 已變更、pattern 不再適用）

→ 動作：從 review-lessons 移除

### 保留（Keep）

- Source PR 僅 1 個，尚不確定是否為通用 pattern
- 無法明確歸類到上述兩類

→ 動作：不動，繼續觀察

**原則：不確定時歸類為「保留」，寧可多觀察一輪也不要誤畢業。**

### 合併跨檔重複（Consolidate）

分類完成後，額外掃描所有「保留」的 entry，找出**跨檔語意重複**的條目（例如 `error-handling.md` 和 `nuxt-ssr-caching.md` 各有一條描述 `defineCachedEventHandler` error handling）。

對重複組：
- 保留主題最貼切的檔案中的那條（例如 SSR caching 相關放 `nuxt-ssr-caching.md`）
- 合併所有 Source PR URLs 到保留的那條
- 刪除另一條
- 合併後 Source 數量重新計算——若合併後 >= 2 PRs，重新評估是否可以 Graduate

在審查表中用「合併」標記這類操作。

## 4. 自動執行畢業

分類完成後**直接執行**，不需等待使用者確認。分類邏輯已足夠保守（不確定 → 保留），不會誤畢業。

執行步驟：

### 4.1 併入

把 entry 內容融入目標主 rule 檔案：

- **匹配目標檔的格式風格**：主 rule 用編號章節（### 3.1）就用編號；用 bullet list 就用 bullet
- **自然融入**：不加 `<!-- Graduated -->` 註解，讓畢業的規則看起來和原本的規則一樣
- **保留技術細節**：code example、Why 的核心理由都要帶過去，但改寫成主 rule 的行文風格
- **放在語意最接近的章節**：例如泛型相關放 typescript-guideline.md 的 §3.1 泛型使用規範

### 4.2 刪除

從 review-lessons 檔案中移除該 entry（包含其 Why 和 Source 子 bullet）。

### 4.3 保留

不做任何操作。

### 4.4 清理空檔案

如果某個 review-lessons 檔案的所有 entry 都被併入或刪除，刪除該檔案。
如果只剩 H1 標題沒有 entry，也刪除。

### 4.5 不 commit

所有變更屬於 AI 開發環境（`chore/ai-enhancements`），不在此 skill 中 commit。等使用者說「發 AI PR」統一處理。

## 5. 輸出摘要

執行完畢後輸出審查表和摘要（讓使用者知道做了什麼）：

```
📋 Review Lessons 畢業完成（<repo> — 原 <N> 條 → 剩 <M> 條）

| # | Lesson 摘要 | 來源檔 | Sources | 動作 | 目標 |
|---|------------|--------|---------|------|------|
| 1 | getQuery 泛型取代 as string | typescript-type-safety.md | 2 PRs | 併入 | typescript-guideline.md §3.1 |
| 2 | .util.ts 命名規範 | naming-conventions.md | 1 PR | 刪除 | 與 naming-guideline.md 重複 |
| 3 | defineCachedEventHandler error handling | error-handling.md | 1 PR | 合併 | → nuxt-ssr-caching.md |
| 4 | vi.hoisted() workaround | vitest-testing-patterns.md | 1 PR | 保留 | — |

✅ 併入 X 條 ｜ 刪除 Y 條 ｜ 合併 Z 條 ｜ 保留 W 條
```

**Lesson 摘要**用一句話概括規則重點，不是完整內容。
**目標**欄位：併入的標明目標檔案和章節；刪除的標明重複來源；合併的標明目標檔案；保留的寫「—」。
保留的條目可以省略不列（只列有動作的），除非使用者手動觸發（手動觸發時列完整表格）。

若併入了規則，額外列出每條併入的去向：

```
  併入明細：
  - 「getQuery 泛型取代 as string」→ typescript-guideline.md §3.1
  - 「defineCachedEventHandler error handling」→ api-guideline.md §2.2
```

## 6. 觸發自我修正（靜默）

畢業完成且有實際異動（併入 > 0 或合併 > 0 或刪除 > 0）時，自動 invoke `check-pr-approvals`。它會掃自己的 open PR、rebase、用更新後的 rules 檢查 diff 並 auto-fix，讓 reviewer 看到的 code 已經符合最新 rules。

若無實際異動（全部保留），跳過此步驟。

```
Invoke check-pr-approvals to scan my open PRs with the updated rules.
```

---

## Do

- 比對語意而非字面：主 rule 說「使用泛型」和 review-lesson 說「用 getQuery 泛型」算重複
- 一條 entry 有多個 Source PR 時，計為多個佐證（即使同一天）
- 併入時保留實用的 code example，轉成主 rule 的格式（fenced code block + `// ✅` / `// ❌`）

## Don't

- 不要把「保留」的 entry 併入主 rules — 一次只被一個 PR 提到的 pattern 可能只是特例
- 不要在主 rule 檔案中提及 Source PR URL — 那是 review-lessons 的追蹤機制，不屬於 rule
- 不要改變主 rule 檔案的既有結構（章節編號、H 層級、frontmatter）
- 不要在非手動觸發時輸出「未達門檻」之類的訊息 — 靜默結束就好
