---
name: request-pr-review
description: |
  "把使用者名下已經開好的 PR 蒐集起來、帶回每一個的 review 狀態、列出來讓他決定要請誰看，然後通知對的人。Trigger: '我的 PR', 'request PR review', 'ask someone to review my PR', 'PR 狀態', '催 review', '催 PR', 'PR 被 approve 了嗎', '幫我掃我的 PR', '請同仁 review', '請同仁幫我 review', '請大家 review', '請大家幫我 review', '請大家幫忙看一下', '找人 review', '找誰 review', '請[人名/角色]幫我 review', '請[人名/角色]幫忙看 PR'. 主語為同仁/大家/人名/角色的「請X幫我 review」屬於催 review 範疇，不要 route 到 review-pr。"

  使用者問**自己的** PR 現在怎麼樣，或想找人來看。例如「我的 PR」「PR 狀態」
  「催 review」「PR 被 approve 了嗎」「請同仁幫我 review」。

  「請〈某人/大家〉幫我 review」主語是別人，仍然屬這裡——那是催 review，不是自己動手 review。

  不用於：review 別人的 PR（走 review-pr）、掃團隊待看的 PR（走 review-inbox）。
metadata:
  author: ""
  version: 4.0.0
scope: universal
tools:
  - name: gh
    provision: manual
    why: 開 PR、讀 review、建 release、查 CI
    fix: 裝 GitHub CLI 並完成 `gh auth login`——二進位檔裝得起來，登入只有人做得到
  - name: jq
    provision: framework
    why: 解析 API 回應的 JSON
    install: mise:aqua:jqlang/jq
---

# request-pr-review — 請人來看已經開好的 PR

實作做完、PR 開出來了，缺的是最後一步：**請同事看**。這支 skill 承載那一步的全部——這批
總共有多少、分在哪些 repo、每一個現在被誰看了、要通知誰。

三步，順序固定，**中間那一步是人**：

1. **query** 名下所有 open PR，帶回每一個的 review 狀態。
2. **列出來問使用者要怎麼處理**——列的東西要足夠讓他當場決定，不用再去 GitHub 翻一遍。
3. **照他的決定通知對的人**。

## 這支 skill 不知道的三件事

**要看哪個 org、哪個 repo 通知誰、一張單長什麼樣。** 三者都由認領那個 org 的 skill 在
自己的 `SKILL.md` 宣告，這裡掃所有 skill 找那一行：

```
<!-- {任意前綴}-PR-CONTEXT-{org}: {命令} -->
```

鍵裡那一段就是 org 名，所以掃一次同時回答「要 query 誰」與「拿到之後問誰」。一個宣告都
沒有時說出來並停下——**不猜一個 org，不用占位字串當預設值**。

宣告的命令要認得兩個模式，第一個參數就是模式名：

| 模式 | 進 | 出 |
|---|---|---|
| `notify --repo R` | 參數 | 這個 repo 的 PR 通知誰，格式由那一層自己定 |
| `ticket` | stdin：`repo⇥number⇥title⇥branch` | `repo⇥number⇥單號⇥單的 URL` |

`ticket` 走 TSV 而不是把 PR 的 JSON 丟過去：那個資料結構是這支 skill 的事，交出去等於逼
每一家公司的知識層都得認得它。**這裡不認得任何一家公司的單號長什麼樣**，也不該認得。

所以這裡沒有前置設定要人先準備，也不需要任何環境變數。author 沒指定時自己偵測：

```bash
MY_USER="$(gh api user --jq '.login')"
```

approval threshold 這類判定門檻仍讀 workspace config 的 shared defaults。

## Bundled Scripts

路徑相對於本 skill 目錄。

| Script | 用途 | 輸出 |
|--------|------|------|
| `scripts/resolve-pr-context.sh` | `orgs` 列出被宣告的 org；`notify` / `ticket` 轉交給認領那個 org 的命令 | org 清單／那一層的答案 |
| `scripts/fetch-user-open-prs.sh` | 名下所有 open PR，含 org/base/head | PR JSON array |
| `scripts/check-pr-approval-status.sh` | approval 數、stale、被指名還沒看的 reviewer | 加上 approval 欄位 |
| `scripts/fetch-pr-review-comments.sh` | 還沒被回覆的 actionable comments | 加上 `unaddressed_comments` |
| `scripts/check-pr-ci-status.sh` | CI 狀態 | 加上 `ci` |
| `scripts/attach-pr-ticket.sh` | 這個 PR 屬於哪一張單 | 加上 `ticket` |
| `scripts/plan-pr-notify.sh` | 這批要通知哪裡，逐個 repo 給建議 | `repo⇥狀態⇥數量⇥目的地` |

Script 是 deterministic source；不要在入口重寫它們的 API、stale 或 bot filter 邏輯。

## Lazy-load Map

| 何時讀 | Reference | 用途 |
|--------|-----------|------|
| 產出報告、加 label、組通知訊息時 | `references/request-pr-review-reporting.md` | 報告表格、label 處理、訊息要說出哪幾件事 |
| 那份報告要分哪幾段、每一段寫什麼 | `references/report-format.md` | 交出去給人讀的報告共用的段落骨架 |
| 判讀 approval / stale 語意前 | `references/stale-approval-detection.md` | stale approval 的權威定義 |
| 訊息送出前 | `.claude/rules/style-and-language.md` | 語言關卡 |

## 1. Query：這批是哪些、狀態如何

一條 pipe 走完，每一段各補一類狀態：

```bash
"$SKILL_DIR/scripts/fetch-user-open-prs.sh" \
  | "$SKILL_DIR/scripts/check-pr-approval-status.sh" --threshold "$APPROVAL_THRESHOLD" \
  | "$SKILL_DIR/scripts/fetch-pr-review-comments.sh" --author "$MY_USER" \
  | "$SKILL_DIR/scripts/check-pr-ci-status.sh" \
  | "$SKILL_DIR/scripts/attach-pr-ticket.sh"
```

結果為 `[]` 就回報沒有 open PR，結束。

**問不到的東西不會被讀成「沒問題」**，這是這一步的重點：

| 欄位 | 值 | 意思 |
|---|---|---|
| `branch_status` | `unreachable` | base/head 沒問到。不是「base 是預設分支」 |
| `ci.state` | `UNREACHABLE` | 這一趟沒問到 CI。**不是 PASS，也不是 NONE** |
| `ci.state` | `NONE` | 真的沒有設任何 check |
| `ticket` | `null` | 沒查出屬於哪張單。**不是「這個 PR 沒有單」**——那幾筆會被逐個指名 |

某個 org 整個問不到時，其餘 org 的結果照常回來，問不到的那些被逐個指名；全部問不到時
非 0 退出，而不是回一個看起來像「沒有 PR」的空陣列。

## 2. 列出來，讓使用者決定

報告要讓人**當場**決定，不用再去別的地方查。逐個 PR 給出：

- repo、編號、標題、連結
- **它屬於哪一張單**（`ticket.key` 與 `ticket.url`）。卡住的 PR 要回頭解問題時，那張單就是
  去處。查不出來的標成「查不出」並且**不要寫成「沒有單」**——那是兩件事
- approval：`valid_approvals`/`threshold`，有 stale 要標出來
- 被指名但還沒回應的 reviewer（`requested_reviewers`）
- 還沒被回覆的意見數（`unaddressed_comments`）
- CI 狀態；`FAIL` 要帶上是哪幾個 check（`ci.failing`）
- 這個 PR 適不適合現在請人看，不適合的話卡在哪

最後給出總數與 repo 分布。

**然後停下來等使用者選。** 沒有得到選擇之前不通知、不加標記、不動任何一個 repo。

**不自動挑一批送出去。** 判斷可以給，決定不代做。

## 3. 通知對的人

只處理使用者選中的那些。**先給出建議，再送**：

```bash
printf '%s' "$SELECTED" | "$SKILL_DIR/scripts/plan-pr-notify.sh"
```

它逐個 repo（不是逐個 PR）算出要送去哪，輸出 `repo⇥狀態⇥數量⇥目的地`。**把這份建議連同
目的地一起給使用者看過再送**——目的地是通知的一半，一個沒被看過的目的地跟沒被選過一樣。

退出碼 4 的意思是「我答完我答得出的，剩下這幾個要你給」，**不是壞掉**：

- **`known`** → 照宣告那一支 skill 自己的說明送出。**怎麼送、送到哪，是那一層的事**——
  這支 skill 不認得任何一個目的地的形狀。
- **`unknown`** → 對使用者說出「這幾個 repo 我不知道要通知誰」，把宣告那一層印出來的
  修法原樣附上，**問他要一個目的地**。不猜一個，也不沿用別的 repo 的——同一個 org 底下
  不同 repo 送去不同地方是常態。
- 拿到答案之後**當下記下來**，照宣告那一層說的方式（訊息裡會寫）。只用在這一次的話，
  下一次會再問一次同樣的問題，而被問的人會以為自己上次沒講清楚。

一個 repo 問不到不擋其餘的：其他 repo 照常送，問不到的那幾個等答案。

送出前把訊息寫成 temp markdown 並通過語言關卡：

```bash
bash "$SKILL_DIR/scripts/validate-language-policy.sh" --blocking --mode artifact <訊息檔>
```

送完之後逐個回報：送出去的是哪幾個、送到哪、成功與否。**送不出去要說出來**，不能只報成功
的那些。

## Hard Safety Rules

- **不動任何一個 repo 的 git 狀態**：不 rebase、不 push、不切分支、不 stash。base 過期是
  報告上的一行，要不要處理是使用者的決定。
- 不自動修正 CI failure 或 review comments。
- 不代替使用者決定要通知誰、通知哪幾個。
- 不使用 `gh pr view --json reviews` 取代 bundled approval script。
- 不使用 `gh pr checks --json` 取代 bundled CI script。
- 不把問不到的狀態讀成通過——`UNREACHABLE` 不是 `PASS`。
- 不通知已達標的 PR。
- 不把「已達標」寫成「可 release / 已完成」。
- 不忽略 stale approval。
- 不把未通過語言關卡的訊息送出。
- 訊息不使用「催促」、「催」、「趕快」等字眼；用「麻煩大家幫忙」、「有空幫忙看一下」。

<!-- PROSE-EXTERNAL-PATHS: docs-manager/ — 動手對象：那是 specs 站台自己的 repo，這支 skill 往它寫東西、讀它的結構，不是我們抄一份放著的知識 -->
