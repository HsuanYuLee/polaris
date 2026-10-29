# 整天巡檢：固定間隔掃到停止時間

使用者要一整天接住頻道進來的 review 請求時走這份（「巡檢 PR」「每 20 分鐘掃一次，掃到 18:00」「掃到下班為止」）。一輪做的事跟 Slack mode 完全一樣，這份多的只有三件：**什麼時候跑下一輪、
哪些 PR 這一輪不用看、跑完怎麼交代。**

## Contract

- **不重寫 review。** PR 的讀取、判讀、inline comment、送出結論、回 Slack thread，一律走
  `SKILL.md` 的 Flow。這份不碰那一段。
- **一次呼叫 = 一輪。** 這一輪跑完自己排下一輪，到停止時間為止。
- **只在對話裡收工。** 不對 channel 發整體 summary，只回各 PR 原本那一串（沿用
  Slack mode 的行為）。

## 參數

呼叫時可以帶，沒帶就用預設：

| 參數 | 預設 | 形狀 |
|---|---|---|
| 間隔 | `20m` | `20m` / `90s` / `1h`；純數字當分鐘 |
| 停止時間 | `18:00` | 當日的時刻，`18:00` / `1800` / `18` |
| approve 門檻 | 公司那一份 `workspace-config.yaml` 的 `scrum.approval_threshold`；讀不到就說出來，不猜 | 整數 |
| 頻道 | 跟 Slack mode 同一個 PR channel（`SKILL.md`〈Flow〉第 1 步讀的那一格） | channel ID |

使用者的話裡有「每 30 分鐘」「掃到 17 點」「掃到下班」這類說法就照它，不要再問一次。
**頻道設定讀不到就說出來並問**——這份在別的環境也會被用，那裡沒有這個 workspace 的設定。

## 一輪的流程

1. **算時間窗。** 這一步在最前面：已經過了停止時間就一輪都不跑。

   ```bash
   bash .claude/skills/review-inbox/scripts/resolve-sweep-window.sh \
     --interval <間隔> --until <停止時間>
   ```

   `should_run` 是 false 就直接報告 `reason` 並結束，不要掃、不要排下一輪。

2. **掃頻道、產 candidates。** 走 Slack mode discovery（見
   `review-inbox-discovery-flow.md`）。時間範圍用**當天**，不是預設的 7 天——這份問的是
   「今天有誰喊了 review」。掃描委派給 read-only sub-agent，raw Slack 訊息不進主 context。

3. **標出這一輪要看哪些。**

   ```bash
   python3 .claude/skills/review-inbox/scripts/filter-approved-prs.py \
     --org <github_org> --my-user <自己的 login> --threshold <門檻> \
     < candidates.json > decided.json
   ```

   自己的 login 用 `gh api user --jq .login` 動態取，不要寫死。

4. **看 `sweep_decision` 是 `review` 的那些。** 逐一走 batch review flow（`review-inbox-batch-review-flow.md`）。
   某一個 PR 掛掉就記下原因往下一個走，不要讓整輪停。

5. **出表格**（見下一節）。

6. **排下一輪。** `next_delay` 大於 0 就用 `ScheduleWakeup` 排，`prompt` 帶原本那句呼叫，
   讓下一輪參數一樣。等於 0 就報告收工總結並停。

   runtime 沒有 `ScheduleWakeup` 的話**要說出來**，別安靜地只跑一輪——改請使用者用
   `/loop <間隔> /review-inbox <原本那句巡檢指令>`。

## 每輪的表格

每一輪跑完都要出，欄位固定這幾個：

| PR | 標題 | 作者 | 有效 approve | 這輪做了什麼 | 結論 |
|---|---|---|---|---|---|
| [#101](url) | 修正結帳頁的日期格式 | alice | 1 | reviewed | APPROVE |
| [#102](url) | 導覽語言改依介面語系顯示 | bob | 0 | reviewed | COMMENT |
| [#103](url) | 搜尋結果改為整組覆蓋 | （自己） | — | 跳過 | 自己是作者 |

- PR 欄要是**可以點的連結**。
- 「這輪做了什麼」只有三種：`reviewed`、`跳過`、`失敗`。
- 跳過與失敗把原因寫在「結論」欄，不要另開一段散文重講一次。
- 這一輪什麼都沒碰到就寫一行「這一輪沒有新的 review 請求」，不要出一張空表。

## 哪些不看

| 情況 | 誰擋掉的 |
|---|---|
| 已經合併或關閉 | `scripts/filter-approved-prs.py`——頻道裡的訊息不會因為 PR 合掉而消失，每一輪都會再撈到它 |
| 自己是作者 | `scripts/filter-approved-prs.py`，以及 discovery 自己也排除 |
| 以目前 head 為準，有效 approve 已達門檻 | `scripts/filter-approved-prs.py` |
| 我已經 review 過而且 head 沒變 | `scripts/check-my-review-status.sh`（`waiting_for_author`）|

**「有效」是以目前 head 為準**：作者後來又 push，先前那些 approve 就不算數，這個 PR 還是
要看。這跟 GitHub 上「這個 PR 現在能不能合」是同一個判準。

查不到 review 資料的 PR **不跳過**——讓人去看一個可能不用看的，比安靜漏掉一個要看的便宜。

## 寫給人看的那幾段

review body 與 inline comment 寫成什麼形狀，在
`../review-pr/references/review-comment-form.md`——那份是唯一一份，這裡不抄。這一輪派出去的每一個 reviewer 都會在 packet 裡拿到它的內容。

**巡檢自己寫的 Slack 回覆與每一輪的表格，照同一份的判準。**

## Completion

每一輪：表格 + 一行「下一輪 HH:MM」或「收工」。

收工那一輪多給整段期間的總結：看了幾個、跳過幾個與各自原因、APPROVE / REQUEST_CHANGES /
COMMENT 各幾個、失敗幾個。
