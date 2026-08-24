# Standup Entry 模板

每日 standup entry 的完整格式範例。產出時依此模板填入實際資料。

## 形狀：以 epic 為主體，一張 epic 三格

<!-- STANDUP-CONTRACT: epic-three-cells -->

**產出的主體是 epic，不是區塊。** 每一張 epic 一筆，每一筆帶三格：**昨日**、**今日**、
**卡關**。站會被問到的就是這三件事，所以報告直接長成那個形狀——不先產一份別的東西再
現場翻譯一次。

以前這裡是四個區塊（YDY／TDT／BOS／口頭同步）加團隊分組。**那四個名字沒有消失，它們
變成格**，對映關係只有這一份：

| 舊區塊 | 現在在哪 |
|---|---|
| YDY – Yesterday I Did | 每張 epic 的 **昨日** 格 |
| TDT – Today's Tasks | 每張 epic 的 **今日** 格 |
| BOS – Blockers or Struggles | 每張 epic 的 **卡關** 格 |
| 口頭同步 | **只留在本地那份檔案**——它是講給人聽的，不是報告的一格 |

**這張表是唯一一份說法。** 兩套形狀並存的話，下一個人不知道該照哪一套產出，而兩套都
看起來像現行版本。

**沒有 epic 的東西不散落。** 獨立 ticket、NO-JIRA 的工作、會議，全部集中在最後一筆
具名的非 epic 條目（`### 其他（無 Epic）`）底下，一樣是三格。它們不會因為沒有 epic 就
掉出報告。

**本地檔案就是產出物本身。** 列給人看的內容跟寫進檔案的是同一個東西，中間沒有第二次
翻譯——唯一的差別是 `口頭同步` 那一段是講的，不是寫進報告主體的。

## 格式規則

1. **日期標題**：`## YYYYMMDD`（無斜線、無空格）
2. **每張 epic 一個 `### [KEY 標題](URL)`**，沒有 epic 的集中在 `### 其他（無 Epic）`
3. **三格用 `* **昨日**` / `* **今日**` / `* **卡關**`**，順序固定，一格都不省略
4. **格底下是 ticket 或一行摘要**，依序縮排
5. **Sub-task 折疊**：同一 Task 下 sub-task 全部通過時，折成一行 `（N/N 驗證子單通過）`；
   有失敗或 blocker 的才展開
6. **空的格留白**：那一張 epic 昨天沒動就 `* **昨日**` 底下留白，不寫「無」
7. **口頭同步**：用 `_斜體_`，放在所有 epic 之後、分隔線之前，標明是口頭講的
8. **每段結尾**：加 `---` 分隔線

## 怎麼寫：產出物精簡，證據不精簡

<!-- STANDUP-CONTRACT: terse-output -->

站會的每一格是給人掃一眼的，不是給人讀的。五條規則，全部只管**產出物**：

1. **第一句就是可以動手的事。** 不是背景、不是計劃。「請大家看 PR #2917」不是「PR #2917
   完成了修法並開好了」。
2. **留下一件兩分鐘內做得到的事。** 還沒收掉的東西，指名一件小到現在就能做的下一步；
   「打開那個檔案」也算。
3. **一格講一件事。** 第二件事另外開一格或另外提，不夾在第一件的句子裡。
4. **清單超過五項就切。** 切成「現在做／之後」或「必須／可以」，不要給人一串十一項。
5. **沒有開場白、沒有回顧、沒有收尾客套。** 從答案開始，答案講完就停。

<!-- STANDUP-CONTRACT: evidence-exempt -->

**工程證據不套這五條。** 量測條件、成因推導、驗證紀錄、對照表格、失敗案例——這一類的價值
就在於完整：看的人要靠量測條件判斷那個數字可不可信。把它們精簡掉等於把它們作廢。

判準是**這段文字是拿來掃的，還是拿來驗的**：

| 拿來掃的（套五條） | 拿來驗的（不套） |
|---|---|
| 站會報告的三格 | 單上的量測留言 |
| 看板欄位（昨日／今日／卡關） | root cause 推導 |
| 口頭同步 | 驗證紀錄與對照表 |

**精簡不得丟掉可追的東西**：單號、連結、數字、命令字串在任何精簡之後都還在。精簡砍的是
鋪陳，不是憑據。

## 模板

```markdown
## YYYYMMDD

### [EPIC-100 Epic 標題](https://your-domain.atlassian.net/browse/EPIC-100)

* **昨日**
    * [TASK-aaa](https://your-domain.atlassian.net/browse/TASK-aaa) Task 標題 — 動作摘要 ✅（N/N 驗證子單通過）`✅ planned`
    * [TASK-bbb](https://your-domain.atlassian.net/browse/TASK-bbb) Task 標題 — 動作摘要 `🟢 additional`
* **今日**
    * [TASK-bbb](https://your-domain.atlassian.net/browse/TASK-bbb) — 計畫動作
* **卡關**
    * [TASK-bbb](https://your-domain.atlassian.net/browse/TASK-bbb) — 等 PM 拍板兩個方案選哪個

### [EPIC-200 Epic 標題](https://your-domain.atlassian.net/browse/EPIC-200)

* **昨日**
    * [TASK-ddd](https://your-domain.atlassian.net/browse/TASK-ddd) Task 標題 — 完成 ✅ `✅ planned`
* **今日**
    * [TASK-eee](https://your-domain.atlassian.net/browse/TASK-eee) — 計畫動作
* **卡關**

### 其他（無 Epic）

* **昨日**
    * [TASK-fff](https://your-domain.atlassian.net/browse/TASK-fff) 獨立 Task 標題 — 動作摘要 `🟢 additional`
    * AI 工具改善（NO-JIRA）：一行摘要描述改了什麼 `🟢 additional`
    * 會議名稱
      M月 D日 (星期X) · 上午/下午H:MM - H:MM
* **今日**
    * 會議名稱
      M月 D日 (星期X) · 上午/下午H:MM - H:MM
      地點：XXX
* **卡關**

* **口頭同步**（口頭講的，不進報告主體）

    * _昨天主要把 XXX 做完了，YYY 成果_
    * _AAA 佔滿下午，BBB 延後_
    * _今天預計 ZZZ，另外啟動 WWW_

---
```

`口頭同步` 用 3-4 條 italic bullets，口語化摘要：昨日精華 1-2 條、插曲或損失 0-1 條、
今日計畫 1 條。不要逐條複述上面已經有的東西。

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
* AI 工具改善（NO-JIRA）：Claude Code skills + workspace docs 更新 `🟢 additional`
```

**不要這樣**：
```markdown
* AI 工具 / Skills 改善（NO-JIRA）
    * Claude Code skills 多項強化：驗證流程、parallel Explore subagent pattern... `🟢 additional`
    * Workspace CLAUDE.md 更新：Explore-then-Implement / Plan-first / batch Worktree 規則 `🟢 additional`
```

## Plan vs Actual 標記

標在**昨日**格的每一項後面：

- `✅ planned` — 前一份 standup 的今日格有計畫、實際有做
- `🟢 additional` — 前一份沒計畫、額外做的
- `🔴 loss: [原因]` — 前一份有計畫但沒做（問使用者原因）
- 會議項目不標記
