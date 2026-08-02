---
title: "Learning Queue Flow"
description: "learning Queue mode 的 Slack daily queue 處理、condensed summary、recommendation 與 archive 流程。"
---

# Queue Mode Flow

這份 reference 是 `learning/SKILL.md` Queue mode 的延後載入流程。用於處理 daily
learning scanner 發到 Slack 的文章 queue。

## Step Q1. Read Queue

搜尋最近 7 天的 daily learning queue message：

```text
slack_search_public query: "Daily Learning Queue"
```

找不到時，回覆：

```text
最近 7 天沒有 Daily Learning Queue 訊息，可能 scanner 還沒跑或發送失敗。可以用 `learning setup` 設定或重新啟用。
```

解析每篇文章的 title、URL、Category、Tags、Relevant Repos、Summary，先顯示 summary
table：

```markdown
| # | Title | Category | Repos |
|---|---|---|---|
```

若使用者用 repo 篩選，只保留 `Relevant Repos` 包含該 repo 或 `all` 的文章。未指定時
預設列出全部，並詢問要全部處理、選幾篇，或用 repo 篩選。

## Step Q2. Process Articles

每篇 selected article 走 External mode Step 1-4，但有三個差異：

- input type 固定為 Article / Blog URL。
- depth 預設 single-agent direct research，除非文章連到 large repo。
- synthesis 先 batch，不要每篇文章都停下問 confirmation。

多篇文章時可平行處理最多 3 篇。每個 sub-agent 回傳：

- 一句話 summary。
- workspace 可參考重點。
- 不適用或需跳過的理由。
- 若有 recommendation，給 landing zone 與 effort。

## Step Q2.5. Condensed Summary

先一次呈現所有文章的 condensed summary：

```markdown
## Learning Queue 精簡摘要

處理了 N 篇文章

### 1. {Article Title}
- 簡述：...
- 可參考：...
- 不適用：...
```

接著詢問：

```text
要針對哪些做詳細推薦分析，還是直接歸檔？
```

使用者選部分文章 -> 只對 those articles 跑 Q3。全部歸檔 -> 直接 Q4。全部分析 ->
所有文章跑 Q3。

## Step Q3. Detailed Recommendations

只對使用者選中的文章輸出 unified recommendation summary：

```markdown
## Learning Queue 詳細推薦

### Worth doing now
| Article | Recommendation | Effort | Action |
|---|---|---|---|

### Nice to have
| Article | Recommendation | Effort |
|---|---|---|

### Not applicable
| Article | Reason |
|---|---|
```

等使用者確認後才執行任何 write。

## Step Q4. Execute And Archive

執行使用者確認的 recommendation。Framework 變更遵守 skill/reference/rule conventions；
project 變更遵守 project handbook。

所有 processed articles 都要 append 到 `learning-archive.md`：

```markdown
| {date} | {title} | {url} | {result} | {one-line note} |
```

`result` 使用：

- `applied`：recommendation 已實作。
- `noted`：有價值但 deferred。
- `skipped`：不適用或讀取失敗。

## Step Q5. Summary

回報：

- processed article count。
- applied recommendation count 與清單。
- archived article count。

## Edge Cases

- URL dead / 404：標 `skipped`，note 寫 URL unavailable。
- paywall / login：請使用者貼 key content，或標 `skipped`。
- 使用者直接 skip：標 `skipped`，note 寫 user skipped。
