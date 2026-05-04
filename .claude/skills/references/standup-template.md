---
title: "Standup Template"
description: "standup entry 的固定 section、巢狀格式、口頭同步 bullet 與 Confluence markdown conventions。"
---

# Standup Entry Template

這份 reference 定義 standup entry 的穩定輸出格式。

## Skeleton

```markdown
## YYYYMMDD

* **YDY – Yesterday I Did**
  * **Team / Epic / Group**
    * [KEY title](https://example.atlassian.net/browse/KEY) — action summary

* **TDT – Today's Tasks**
  * **Team / Epic / Group**
    * [KEY title](https://example.atlassian.net/browse/KEY) — plan summary

* **BOS – Blockers or Struggles**
  * blocker summary when any

* **口頭同步**
  * _昨天主要完成..._
  * _今天預計..._

---
```

## Rules

- Heading date 使用 `PRESENT_DATE`。
- YDY/TDT/BOS/口頭同步四區塊缺一不可。
- 沒有 blockers 時，BOS 只留 heading，不加「無」。
- Team group 內可巢狀 Epic。
- Sub-task 全部通過時可折疊成一行。
- NO-JIRA 或 framework work 用簡短摘要，不展開 internal details。
- 口頭同步每條一句，使用 italic markdown，方便站會口述。
- 保留 `---` 分隔線。
