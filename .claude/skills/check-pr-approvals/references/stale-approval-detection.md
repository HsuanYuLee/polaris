# Stale Approval Detection

判斷 PR approval 是否因 head commit 變動而失效的共用規則。

## 核心規則

APPROVED review 綁定的 `commit_id` 與 PR 當前 `head.sha` **不相等** → **stale**（無效）。
相等才視為對「當前 head」有效的 approval。

```
valid_approval = review.state == "APPROVED" && review.commit_id == pr.head.sha
stale_approval = review.state == "APPROVED" && review.commit_id != pr.head.sha
```

`commit_id` 為 null / 缺失，或 `head.sha` 取值失敗時，一律 **fail-closed 判 stale**——不得因兩者皆空而誤判 valid，也不得 crash。

正規實作（單一 writer path）：`scripts/lib/approval-staleness.sh` 的 `approval_staleness`
函式。consumer script 一律呼叫此 helper，不得各自 inline 重算 staleness。

## 計算方式

```
valid_approvals = count(reviews where state == "APPROVED" && commit_id == head.sha)
stale_approvals = count(reviews where state == "APPROVED" && commit_id != head.sha)
```

## 顯示格式

| 情境 | 顯示 |
|------|------|
| 2 valid approvals, threshold 2 | `2/2 ✅` |
| 0 valid, 2 stale | `0/2 (stale)` |
| 1 valid, 1 stale | `1/2 ⚠️` |

### Reviewer 狀態標示

- `username ✅` — valid approve（`commit_id == head.sha`）
- `username ⚠️ re-approve` — stale approve，需要重新 approve

## 應用場景

| Skill | 用途 |
|-------|------|
| `check-pr-approvals` | 篩選 valid approve 數 < threshold 的 PR，催 re-approve |
| `review-inbox` | 分類為 `needs_re_approve` 狀態，決定是否需要 re-review |
| `converge` | 識別 review 卡住的 blocker（0 valid approved 超過 2 天） |

三個 consumer 一律引用本檔 canonical 定義與 `approval-staleness.sh` helper；不得各自維護第二套 staleness 計算。

## 不可忽略

- approve 綁定的 commit 與當前 head 不一致的一律視為無效（涵蓋 force-push / rebase / 新 commit）。
- 必須計入需要 re-approve 的清單。
- **禁止**改用 `head.repo.pushed_at`、`submitted_at` 或 committer-date 作為 staleness 依據——shared repo 中他人 push 不相干 branch 會 bump `pushed_at`，用時間戳會把仍對當前 head 有效的 approval 誤標 stale。`commit_id == head.sha` 的判定不受此影響。
- 不同 skill 的 threshold 可能不同（check-pr-approvals 預設 2，其他依情境判斷）。
