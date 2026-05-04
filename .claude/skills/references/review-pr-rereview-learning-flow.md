---
title: "Review PR Rereview Learning Flow"
description: "review-pr re-review 模式：確認上一輪 comments 修正狀況、re-approve 判定、自動學習 false positives / accepted patterns / severity calibration。"
---

# Re-review Contract

這份 reference 負責作者修正後的 re-review 與 learning。

## Entry

當使用者提到 re-review、已修正、重新 review，或 fetch result 顯示自己曾 REQUEST_CHANGES
且作者已有回覆時，進入 re-review。

Re-review 必須重新 fetch latest diff 與 latest comments；不可沿用首次 review 時的 cached
diff。

## Comment Resolution Check

逐一讀上一輪自己的 review comments 與作者 replies，對照 latest diff 判斷：

| State | Action |
|---|---|
| fixed | reply confirmation when needed |
| author disagrees with reason | evaluate reason；合理則接受，不合理則回覆說明 |
| not fixed and no reply | mark unresolved |
| already confirmed by self and unchanged | skip duplicate reply |

只有真正新發現的問題才留新的 inline comment。Re-review 不是重新審一遍並大量新增 comments。

## Re-approve Decision

| Condition | Action |
|---|---|
| all prior must-fix resolved or accepted, no new must-fix | `APPROVE` |
| unresolved prior must-fix or new must-fix | `REQUEST_CHANGES` |
| prior should-fix / nit resolved | `APPROVE` |

提交 review 前，先向使用者說明判斷與理由，取得確認後再送出。

Review body 保持簡短，不重複每個 thread 已經回覆的內容。

## Learning Extraction

Re-review 完成 comment resolution 後，萃取可避免未來誤報的 learning：

| Situation | Learning |
|---|---|
| author disagreed and reviewer accepted | false positive |
| author fixed differently and better | accepted pattern |
| reviewer realizes severity was too high | severity calibration |

沒有這類情況時，跳過 learning output。

## Persistence

優先依 `repo-handbook.md` standard-first flow 寫入 company handbook。若現有流程仍需要 legacy
`review-learnings.md`，只能作 compatibility output，不得取代 handbook source of truth。

寫入前做 semantic dedup。同類 entries 過多時，合併成通用 rule。

## Output

Re-review summary 包含：

- resolved / unresolved prior comments
- new findings if any
- final review action
- learning updates if any
- handbook or compatibility file path when written
