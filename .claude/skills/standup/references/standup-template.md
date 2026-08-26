# Standup Entry 模板

每日 standup entry 的完整格式範例，外加**每一塊收什麼**的判準。產出時依此模板填入實際資料。

## 形狀：四個區塊，分組掛在區塊底下

<!-- STANDUP-CONTRACT: four-blocks -->

一天一筆，每筆四塊：**YDY**（昨天做了什麼）、**TDT**（今天要做什麼）、**BOS**（被什麼
卡住）、**口頭同步**。分組（Epic、主題、沒有單號的工作、會議）掛在區塊底下，不是反過來
以 epic 為主體。

**這是這支 skill 自己的形狀，不是任何一個平台的。** 某個看板、某個表單要的是別的樣子時，
由拿它去填的那一步自己轉。2026-08-13 這裡曾經反過來——為了對齊一個平台的表單，形狀被改成
一張 epic 三格——結果是「每一塊收什麼」沒有人寫，填的人只能照 PR 的機械狀態填。

`口頭同步` 是講給人聽的，不是寫進報告主體的。它跟著本地那份檔案走。

## 每一塊收什麼

<!-- STANDUP-CONTRACT: block-admission -->

形狀不會告訴人一件事該進哪一塊。這一節會。

### YDY——做完了的

**判準是「這件事在我這邊結束了沒」，不是「它有沒有出現在別人的清單上」。**

- **發出 PR 就是那件事做完了。** 之後有沒有人看、看了說什麼，是另一件事。
- 一張單推進到下一個狀態、一份報告交出去、一個問題查出答案——都是做完。
- **不要把工具的狀態當成工作的狀態。** 「commit 還在本機沒推」「PR 的 reviewDecision 是
  CHANGES_REQUESTED」講的是工具現在長什麼樣，不是這個人昨天做了什麼。昨天處理完那些意見
  並推上去，那就是做完了。

### TDT——我自己動得了的下一步

- **沒有人看我的 PR，下一步是去請人看。** 那是 TDT，不是 BOS。
- 收到意見要改、CI 紅了要修、資料被誤設要清——都是 TDT，我自己動得了。
- 已經 approved 還沒合，下一步是去合——TDT。

### BOS——我自己動不了的

准入判準與逐條措辭表在 `standup-planning-flow.md` 的〈准入判準：我在等誰〉，這裡不抄第二
份。一句話：**我現在還有沒有下一步動作可做**。有，就是 TDT；沒有，才是 BOS。

**空著是一個答案。** 沒有符合的就留白，不寫「無」，也不要把 TDT 搬過來填。

## 格式規則

1. **日期標題**：`## YYYYMMDD`（無斜線、無空格）
2. **大區塊**：`* **粗體標題**`（YDY / TDT / BOS / 口頭同步），順序固定
3. **分組**：`* **群組名**`——Epic、主題、沒有單號的工作、會議
4. **巢狀**：Epic → Task → Sub-task，依序縮排
5. **Sub-task 折疊**：同一 Task 下 sub-task 全部通過時折成一行 `（N/N 驗證子單通過）`；
   有失敗或 blocker 的才展開
6. **口頭同步**：用 `_斜體_`，放在所有區塊之後、分隔線之前
7. **每段結尾**：加 `---` 分隔線
8. **空的區塊留標題**：那一塊沒東西就只留標題，不寫「無」

## 怎麼寫：產出物精簡，證據不精簡

<!-- STANDUP-CONTRACT: terse-output -->

站會的每一塊是給人掃一眼的，不是給人讀的。五條規則，全部只管**產出物**：

1. **第一句就是可以動手的事。** 不是背景、不是計劃。「請大家看 PR #2917」不是「PR #2917
   完成了修法並開好了」。
2. **留下一件兩分鐘內做得到的事。** 還沒收掉的東西，指名一件小到現在就能做的下一步；
   「打開那個檔案」也算。
3. **一件事講一次。** 第二件事另外列一條，不夾在第一件的句子裡。
4. **清單超過五項就切。** 切成「現在做／之後」或「必須／可以」，不要給人一串十一項。
5. **沒有開場白、沒有回顧、沒有收尾客套。** 從答案開始，答案講完就停。

<!-- STANDUP-CONTRACT: evidence-exempt -->

**工程證據不套這五條。** 量測條件、成因推導、驗證紀錄、對照表格、失敗案例——這一類的價值
就在於完整：看的人要靠量測條件判斷那個數字可不可信。把它們精簡掉等於把它們作廢。

判準是**這段文字是拿來掃的，還是拿來驗的**：

| 拿來掃的（套五條） | 拿來驗的（不套） |
|---|---|
| 站會報告的四個區塊 | 單上的量測留言 |
| 口頭同步 | root cause 推導與驗證紀錄 |

**精簡不得丟掉可追的東西**：單號、連結、數字、命令字串在任何精簡之後都還在。精簡砍的是
鋪陳，不是憑據。

## 模板

```markdown
## YYYYMMDD

* **YDY – Yesterday I Did**（週X MM-DD）

    * **Epic 或主題名**

        * [EPIC-100 Epic 標題](https://your-domain.atlassian.net/browse/EPIC-100)
            * [TASK-aaa](https://your-domain.atlassian.net/browse/TASK-aaa) Task 標題 — 動作摘要 ✅（N/N 驗證子單通過）`✅ planned`
            * [TASK-bbb](https://your-domain.atlassian.net/browse/TASK-bbb) Task 標題 — 動作摘要 `🟢 additional`

    * **沒有單號的工作** — 一行摘要描述改了什麼 `🟢 additional`
    * **會議** — 會議名稱、會議名稱

* **TDT – Today's Tasks**（週X MM-DD）

    * **Epic 或主題名**

        * [TASK-bbb](https://your-domain.atlassian.net/browse/TASK-bbb) — 計畫動作

    * **會議** — 會議名稱

* **BOS – Blockers or Struggles**

    * [TASK-ccc](https://your-domain.atlassian.net/browse/TASK-ccc) — 等 PM 拍板兩個方案選哪個

* **口頭同步**

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

## 沒有單號的項目

無 ticket 的工作（工具改善、文件更新等）用**一行摘要**帶過，不逐一列出。

**精簡**：
```markdown
* **內部開發工具** — 工作流升版三版，收掉兩條治理修正 `🟢 additional`
```

**不要這樣**：
```markdown
* **內部開發工具**
    * 多項強化：驗證流程、subagent pattern、workspace 文件更新⋯ `🟢 additional`
    * 又一條⋯ `🟢 additional`
```

## Plan vs Actual 標記

標在 **YDY** 每一項後面：

- `✅ planned` — 前一份 standup 的 TDT 有計畫、實際有做
- `🟢 additional` — 前一份沒計畫、額外做的
- `🔴 loss: [原因]` — 前一份有計畫但沒做（問使用者原因）
- 會議項目不標記
