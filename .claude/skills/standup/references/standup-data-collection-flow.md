---
title: "Standup Data Collection Flow"
description: "standup 的 config/defaults、日期計算、git/JIRA/Calendar 昨日 data collection。"
---

# Standup Data Contract

這份 reference 負責 standup 原始資料收集。

## Config And Defaults

讀取 workspace config，取得：

- `jira.instance`
- `github.org`
- `jira.projects`
- `projects[].path`
- `teams`

Config 不存在時使用 `workspace-config.yaml` 的 `defaults` 區塊 fallback。GitHub username 動態取得。Timezone 預設
Asia/Taipei。

## 排序：沒有生產者的輸入不留在契約裡

<!-- STANDUP-CONTRACT: no-orphan-input -->

**這一步以前讀一份沒有人在寫的檔案。** 產生它的那支 skill 早就不在了，本機那份停在
2026-06-16，而契約每天照著說一次「今日沒有那份排序狀態」——那句話沒有收件人。

一個**永遠只有一種答案**的輸入不是輸入，它是儀式。所以那一條讀取整個拿掉了，排序改由
仍然存在的依據決定（priority、in development 優先），寫在 `standup-planning-flow.md`。

這跟下面〈問不到就說出來〉不衝突，兩者問的是不同的問題：那一節管**有生產者但這次問不到**
的來源，這一節管**根本沒有生產者**的來源。前者要說出來，後者要拿掉。

## Date Semantics

Standup 有三個日期：

| Date | Meaning |
|---|---|
| `PRESENT_DATE` | 報告標題日期與當天會議來源 |
| `YDY_DATE` | 收集 git / JIRA / Calendar activity 的日期 |
| `TDT_PLAN_DATE` | 今日格工作項目的規劃目標日 |

週一：`YDY_DATE` 是上週五；`PRESENT_DATE` 與 `TDT_PLAN_DATE` 是週一。

週二到週四：`YDY_DATE` 是昨天；`PRESENT_DATE` 與 `TDT_PLAN_DATE` 是今天。

週五：`YDY_DATE` 是週四；`PRESENT_DATE` 是週五；`TDT_PLAN_DATE` 是下週一。

使用者指定日期時，以使用者指定為準，並明確回報三個日期。

## Git Activity

掃描 config projects 指定的 local git repos；若 config 未列，fallback 掃 company base
directory 下有 `.git` 的 repos。

收集 YDY_DATE 使用者 authored commits，排除 merge commits。從 commit messages 擷取符合
configured JIRA project keys 的 ticket keys，並記錄 repo 與 commit summary。

## 收集視窗：邊界在拿進來的那一刻

<!-- STANDUP-CONTRACT: evidence-window -->

**視窗是收集的邊界，不是事後過濾。** 每一種來源都在查詢那一層綁 `YDY_DATE`，不要「先全部
拿進來再挑」——一張活躍的單累積的敘述超過一次讀得完的量：EPIC-100 一張單的描述加六則留言，
2026-08-12 實測就大到必須落檔，而那一天要看的單有十一張。

視窗綁在**那一段敘述自己的時間**上，不是綁在單的 `updated` 上：一張單昨天被動過，不代表
它身上每一段都是昨天寫的。

## JIRA Activity

用 Atlassian MCP 查詢 YDY_DATE 由 current user 更新的 tickets，限制在 configured JIRA
projects。需要欄位包含 summary、status、issue type、priority、parent，**以及 comment**。

JIRA response 過大被落檔時，用 deterministic parser 提取 key、summary、status、parent；
不要把整個大型 response 讀進 context。

用途：

- 補 git 沒抓到的 status-only work。
- 補 ticket title。
- 提供今日格的 fallback candidates。

### 留言：一張單最新的話在這裡

<!-- STANDUP-CONTRACT: comments-are-collected -->

**單的留言要收，而且要用 `created >= YDY_DATE` 過濾。** 只收窗內那幾則，窗外的不進來。

這一段是量出來的，不是預防性的：2026-08-12 寫當天的 standup 時，EPIC-100 的描述寫著「尚未
量到 opendate／有場次／多規格三種 flow，需在部署環境上補看」，而**同一晚 01:00 與 02:21
兩則留言已經把三格都補上了**（有場次 0.1575 → 0.0344、多規格 0.1575 → 0、opendate 0 → 0）。
報告照描述寫成「今日要補量」，被使用者當場退回。

### 描述與留言打架時，留言贏

<!-- STANDUP-CONTRACT: newest-wins -->

同一張單的兩處敘述講同一件事而互相矛盾時，**帶時間、只能追加的那一份勝過可以被原地覆寫、
不帶時間的那一份**——也就是留言勝過描述。

理由不是「留言比較重要」，是**只有留言證明得了自己什麼時候寫的**：描述可以被任何人在任何
時候改掉，改完看不出來改過；留言 append-only 而且每一則帶 `created`。所以兩者衝突時，能
排出先後的那一邊才有資格當現況。

**而且要說出來。** 報告裡不要只寫贏的那一版，要讓看的人知道單上還躺著一段舊的——那一段
就是下面〈落差〉那一節的輸入。

## Branch And PR Activity

<!-- STANDUP-CONTRACT: ydy-includes-pr -->

**昨天發生的事包含分支上的事**，不是只算今天還沒做完的部分。YDY_DATE 視窗內要收三類：

| 收什麼 | 為什麼它進昨日格而不是今日格 |
|---|---|
| 被 merge 的 PR | 那是昨天真正完成的交付。少了它，一張已經結束的單會被寫成「還在進行」 |
| 收到的 review comment | 別人昨天對我的東西說了什麼，是昨天發生在我身上的事 |
| CI 狀態變化 | 昨天推上去的東西綠了還是紅了，決定今天第一件事是什麼 |

`standup-planning-flow.md` 的 §PR Status Supplements 收的是**自己還開著的** PR → 今日格。
兩者不重疊：那一節回答「今天還要處理什麼」，這一節回答「昨天發生了什麼」。2026-08-12 缺的
就是這一節——EPIC-200 / EPIC-300 兩條分支昨天各自被 merge，而報告一開始把它們寫成還在進行中。

## 狀態不是意圖

<!-- STANDUP-CONTRACT: status-is-not-intent -->

**外部系統給一件事的狀態名稱，不構成「還有什麼要做」。** 今天要做什麼由人說，或由那個人
昨天留下的痕跡推出來——推出來的要標明是推的。

這三種都不是待辦的來源：

1. **狀態名。** `Ready for Stage`、`Waiting for QA` 這種名字描述的是那件事現在在哪一格，
   不是「我還要對它做什麼」。2026-08-12 從這兩個名字生出「追 QA、排 stage」，使用者的回覆
   是「merge 進去就結束了，沒有什麼追 QA 的工作」。
2. **單上的現況表。** 描述裡的拆單表、進度表、狀態欄同樣會 stale，而且它們長得比散文更像
   事實。2026-08-12 從 EPIC-200 一張過期的拆單表生出「AC-5 未交付」，實際上那張子單掛在別的
   Epic 底下、由別人負責、PR 早就進了。
3. **一個結構上答不了那個問題的查詢回空。** 同一次還用 `--author <自己>` 去濾別人的 PR，
   濾不到就下「沒人做」的結論——那個過濾條件永遠找不到別人的東西。**回空不等於不存在**，
   先問這個查詢答不答得了這個問題。

一句用來驅動下一步的話（「這條還沒交付」「這件事在等某個人」），沒有證據就標成待驗，不要
寫成事實。

## 問不到就說出來

<!-- STANDUP-CONTRACT: unmeasurable-is-not-silent -->

任何一類來源問不到的時候（工具不在、沒登入、遠端回非 0、查詢逾時），**在報告裡說出缺的是
哪一類**，然後照常收其餘的。

三件不准做：

- **不沿用上一次的答案。** 昨天的資料不是今天的資料，而它在報告裡長得一模一樣。
- **不用推論補上。** 猜出來的東西看起來跟量到的一樣，只是它是假的。
- **不當成「沒有」。** 一個問不到的來源回空，跟一個真的空的來源，在輸出上長得一樣——`0` 這
  個數字自己不會說它是哪一種。

這一條與上面〈排序〉那一節互為對照：**有生產者而這次問不到，要說出來；根本沒有生產者，
要拿掉。** 兩者都不准變成一個安靜的洞。

## Calendar Activity

用 Calendar MCP 分別讀 YDY_DATE 與 PRESENT_DATE。YDY_DATE 的會議放進昨日格；PRESENT_DATE
的會議放進今日格。週五今日格的會議仍是週五當天會議，不是下週一。

過濾 all-day events。列出 meeting title、日期、weekday、time range、timezone、location
when available。Calendar MCP 沒有 `conferenceData` 時，不猜 Meet URL。
