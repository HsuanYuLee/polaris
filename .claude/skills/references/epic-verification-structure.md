# Epic 驗證結構

Epic 拆單時自動產生的驗證相關 sub-tasks，確保每個 task 有測試紀錄、每個 Epic 有驗收證明。

## 三層驗證架構

| 層級 | 目的 | 時機 | 形式 |
|------|------|------|------|
| **Task 測試計劃** | PR 品質紀錄，讓 reviewer 知道每個 task 怎麼通過測試 | task branch → feature PR | 每張實作子單底下的 sub-task（紀錄用，非驗收） |
| **Epic per-AC 驗收單** | 業務目標達標證明 | 所有 task merge 回 feature 後 | KB2CW Task × N，Playwright E2E 逐條跑 |
| **Feature 整合測試** | task 之間沒有互相打架 | 同上 | 驗收單的一部分或獨立一張 |

## 驗收單規則

### 大 / 小 Epic 分流

| 條件 | 驗收單做法 |
|------|----------|
| **大 Epic**（> 8 pts 或 > 2 task） | per-AC 拆驗收單，每條 AC 一張 |
| **小 Epic**（≤ 8 pts 或 ≤ 2 task） | 合併成一張「[EPIC_KEY][驗證] Epic 驗收」 |

### 驗收單格式

每張驗收單的 description：

```markdown
## 驗收目標

對應 AC：AC#N — {AC 描述}

## 驗證步驟

1. {具體操作步驟}
2. → 預期結果：{什麼算通過}

## 環境要求

- [ ] 可在 feature branch 驗
- [ ] 需要 stage 環境
```

### 驗收單排序

驗收單排在所有實作子單之後：

```
Task 1-N: 實作子單
Task N+1: [EPIC_KEY][驗證] AC#1 — {描述}
Task N+2: [EPIC_KEY][驗證] AC#2 — {描述}
...
（或合併為一張 [EPIC_KEY][驗證] Epic 驗收）
```

### 驗收單估點

- per-AC 驗收單：每張 1 pt（啟動環境 + 跑測試 + 截圖紀錄）
- 合併驗收單：AC 數量 ≤ 3 → 1 pt，AC 數量 > 3 → 2 pt

## Task 測試計劃 sub-task

每張**實作子單**底下自動建立一張測試計劃 sub-task（穩定測資單除外）。

### 格式

- **Summary**：`[TASK_KEY][測試計劃] {task summary 簡寫}`
- **Points**：不估點（紀錄用）
- **Description**：

```markdown
## 測試場景

從實作子單的「測試計畫」章節複製：
- [ ] 場景 1：...
- [ ] 場景 2：...

## 測試紀錄

（開發完成後填入）
- 測試方式：unit test / Playwright / curl / 手動
- 測試結果：pass / fail
- 截圖或 log（如適用）
```

### 建立時機

- `epic-breakdown` / `jira-estimation`：拆單建立子單時，每張實作子單完成後立刻建立對應的測試計劃 sub-task
- 測試計劃 sub-task 的 `parent` 指向實作子單（不是 Epic）

## Assignee 規則

所有子單（實作 + 驗收 + 測試計劃）的 assignee 預設為**母單的 assignee**。若母單無 assignee，從 memory `user_scrum_role.md` 取得使用者的 JIRA accountId。

## 觸發流程

```
epic-breakdown / jira-estimation 拆單完成
  ├─ 每張實作子單 → 建立 [測試計劃] sub-task
  ├─ 判斷大/小 Epic
  │   ├─ 大 → per-AC 建立 [驗證] 子單
  │   └─ 小 → 合併一張 [驗證] 子單
  └─ 更新母單估點（含驗收單點數）
```

## 來源

設計決策：2026-04-04，GT-483 試跑驗證。個別 task 都通過但 merge 回 feature 後出問題，證實 Feature 整合測試的必要性。
