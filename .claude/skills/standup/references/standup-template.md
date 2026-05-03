# Standup Entry 模板

每日 standup entry 的完整格式範例。產出時依此模板填入實際資料。

## 格式規則

1. **日期標題**：`## YYYYMMDD`（無斜線、無空格）
2. **大區塊**：`* **粗體標題**`（YDY / TDT / BOS / 口頭同步）
3. **團隊分組**：`* Team A` / `* Team B` / `* 自定義標題（NO-JIRA）` / `* meeting`
4. **Epic 巢狀**：Epic → Task → Sub-task，依序縮排
5. **Sub-task 折疊**：同一 Task 下 sub-task 全部通過時，折成一行 `（N/N 驗證子單通過）`；有失敗或 blocker 的才展開
6. **團隊歸屬**：JIRA prefix 與 team 的對應由 workspace config 定義；無 JIRA → 自定義標題；會議 → meeting
7. **口頭同步**：用 `_斜體_` 格式（Confluence 不支援 list 內 blockquote）
8. **每段結尾**：加 `---` 分隔線
9. **省略空區塊**：某團隊沒項目就不列；BOS 沒項目只留標題

## 模板

```markdown
## YYYYMMDD

* **YDY – Yesterday I Did**

    * Team A

        * [EPIC-100 Epic 標題](https://your-domain.atlassian.net/browse/EPIC-100) `✅ planned`
            * [TASK-aaa](https://your-domain.atlassian.net/browse/TASK-aaa) Task 標題 — 動作摘要 ✅（N/N 驗證子單通過）
            * [TASK-bbb](https://your-domain.atlassian.net/browse/TASK-bbb) Task 標題 — 開放
            * [TASK-ccc](https://your-domain.atlassian.net/browse/TASK-ccc) Task 標題 — 開放
        * [EPIC-200 Epic 標題](https://your-domain.atlassian.net/browse/EPIC-200) `✅ planned`
            * [TASK-ddd](https://your-domain.atlassian.net/browse/TASK-ddd) Task 標題 — 完成 ✅
            * [TASK-eee](https://your-domain.atlassian.net/browse/TASK-eee) Task 標題 — 進行中

    * Team B

        * [TASK-fff](https://your-domain.atlassian.net/browse/TASK-fff) 獨立 Task 標題 — 動作摘要 `🟢 additional`

    * AI 工具改善（NO-JIRA）

        * 一行摘要描述改了什麼 `🟢 additional`

    * meeting

        * 會議名稱
          M月 D日 (星期X) · 上午/下午H:MM - H:MM
        * 會議名稱
          M月 D日 (星期X) · 上午/下午H:MM - H:MM
          地點：XXX

* **TDT – Today's Tasks**

    * Team A

        * [EPIC-100 Epic 標題](https://your-domain.atlassian.net/browse/EPIC-100)
            * [TASK-aaa](https://your-domain.atlassian.net/browse/TASK-aaa) — 計畫動作
        * [EPIC-200 Epic 標題](https://your-domain.atlassian.net/browse/EPIC-200)
            * [TASK-eee](https://your-domain.atlassian.net/browse/TASK-eee) — 計畫動作

    * meeting

        * 會議名稱
          M月 D日 (星期X) · 上午/下午H:MM - H:MM

* **BOS – Blockers or Struggles**

    * [PROJ-zzz](https://your-domain.atlassian.net/browse/PROJ-zzz) — 阻擋原因

* **口頭同步**

    * _昨天主要把 XXX 做完了，YYY 成果_
    * _AAA 佔滿下午，BBB 延後_
    * _今天預計 ZZZ，另外啟動 WWW_

---
```

## Sub-task 折疊規則

**全部通過**（折成一行）：
```markdown
* [PROJ-3461](URL) Nuxt SSR API parallel — Code Review ✅（7/7 驗證子單通過）
```

**部分失敗或有 blocker**（展開列出）：
```markdown
* [PROJ-3461](URL) Nuxt SSR API parallel — Code Review（5/7 驗證子單通過）
    * [PROJ-3493](URL) [驗證] Error isolation — ❌ 失敗，需修正
    * [PROJ-3495](URL) [驗證] Hydration mismatch — ❌ 失敗，待排查
```

## NO-JIRA 項目精簡規則

無 JIRA ticket 的工作（AI 工具改善、文件更新等）用**一行摘要**帶過，不逐一列出。

**精簡**：
```markdown
* AI 工具改善（NO-JIRA）
    * Claude Code skills + workspace docs 更新 `🟢 additional`
```

**不要這樣**：
```markdown
* AI 工具 / Skills 改善（NO-JIRA）
    * Claude Code skills 多項強化：engineering verification workflow、parallel Explore subagent pattern... `🟢 additional`
    * Workspace CLAUDE.md 更新：Explore-then-Implement / Plan-first / batch Worktree 規則 `🟢 additional`
```

## Plan vs Actual 標記

- `✅ planned` — 前一天 TDT 有計畫、實際有做
- `🟢 additional` — 前一天 TDT 沒計畫、額外做的
- `🔴 loss: [原因]` — 前一天 TDT 有計畫但沒做（問使用者原因）
- 會議和 meeting 項目不標記
