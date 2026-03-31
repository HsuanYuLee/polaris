# Stale Approval Detection

判斷 PR approval 是否因新 push 而失效的共用規則。

## 核心規則

APPROVED review 的 `submitted_at` 早於 PR 的 `pushed_at` → **stale**（無效）

```
valid_approval = review.state == "APPROVED" && review.submitted_at > pr.pushed_at
stale_approval = review.state == "APPROVED" && review.submitted_at < pr.pushed_at
```

## 計算方式

```
valid_approvals = count(reviews where state == "APPROVED" && submitted_at > pushed_at)
stale_approvals = count(reviews where state == "APPROVED" && submitted_at <= pushed_at)
```

## 顯示格式

| 情境 | 顯示 |
|------|------|
| 2 valid approvals, threshold 2 | `2/2 ✅` |
| 0 valid, 2 stale | `0/2 (stale)` |
| 1 valid, 1 stale | `1/2 ⚠️` |

### Reviewer 狀態標示

- `username ✅` — valid approve（`submitted_at > pushed_at`）
- `username ⚠️ re-approve` — stale approve，需要重新 approve

## 應用場景

| Skill | 用途 |
|-------|------|
| `check-pr-approvals` | 篩選 valid approve 數 < threshold 的 PR，催 re-approve |
| `review-inbox` | 分類為 `needs_re_approve` 狀態，決定是否需要 re-review |
| `epic-status` | 識別 review 卡住的 blocker（0 valid approved 超過 2 天） |

## 不可忽略

- approve 時間早於最後 push 時間的一律視為無效
- 必須計入需要 re-approve 的清單
- 不同 skill 的 threshold 可能不同（check-pr-approvals 預設 2，其他依情境判斷）
