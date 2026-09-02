# request-pr-review Reporting Reference

本 reference 承接 `request-pr-review/SKILL.md` 的低頻輸出細節。只有在產出報告、加 label、組通知訊息時讀取。

## Classification Report

面向使用者的 PR 編號必須用 markdown link：`[#123](https://github.com/org/repo/pull/123)`。

```markdown
🟢 可催 review（N 個）：
| # | Repo | PR | 單 | Title | Approvals | Reviewers | Label |
|---|------|----|----|-------|-----------|-----------|-------|
| 1 | repo-a | [#1786](url) | [KEY-1](ticket-url) | feat: xxx | 0/2 | — | |
| 2 | repo-b | [#302](url) | [KEY-2](ticket-url) | fix: yyy | 1/2 | reviewer-b ✅ | 👀 |

🔧 需先修正（N 個）：
| Repo | PR | 單 | 問題 |
|------|----|----|------|
| repo-a | [#1920](url) | [KEY-3](ticket-url) | CI fail (codecov/patch) |
| repo-c | [#45](url) | [KEY-4](ticket-url) | rebase conflict |
| repo-d | [#67](url) | 查不出 | 2 unresolved review comments |

✅ 已達標（N 個）：repo-a [#100](url), repo-b [#200](url)

請輸入要通知的 🟢 PR 編號（例如 `1,2` 或 `all`，輸入 `none` 跳過）：
```

Reviewers 欄位：

- `username ✅`：valid approve
- `username ⚠️ re-approve`：stale approve
- `username 🔄 changes`：REQUEST_CHANGES
- `—`：尚無人 review

問題欄可複合，例如 `CI fail + 2 unresolved comments`。排序規則：🟢 PR 依 valid approvals 升序；🔧 PR 依 conflict > CI fail > comments 排序。

「單」欄用 `ticket.key` 加 `ticket.url` 做成連結——**🔧 那一批要靠它才知道回哪裡解問題**。
`ticket` 是 `null` 時寫「查不出」，不要寫「無對應單」：前者是這一趟沒答案，後者是斷定它
本來就沒有單，而這支 skill 不知道後面那件事。同一批裡查不出來的有幾個、是哪幾個，
`attach-pr-ticket.sh` 已經逐筆印在 stderr。

## Label Handling

只對使用者選中的 🟢 PR 加 label。若已存在 review label，跳過。

先嘗試 Unicode label：

```bash
gh pr edit <number> --repo "{github_org}/<repo>" --add-label "👀 need review"
```

若 label 不存在，再嘗試 shortcode fallback：

```bash
gh pr edit <number> --repo "{github_org}/<repo>" --add-label ":eyes: need review"
```

Label 失敗不應中斷整批通知，但必須在最後回報哪些 PR label 失敗。

## 通知訊息

只通知使用者選中的那些。**這支 skill 決定訊息要說什麼，不決定它長什麼樣子**——最終格式
屬於認領那個 org 的那一層（它才知道要送去哪、那個地方的標記語法是什麼）。

### 預設就是標題與連結

**一則通知的預設內容是每個 PR 的標題與連結，加一句請人看。沒有別的。**

```
麻煩大家有空幫忙看一下 🙏
[#3070](url) fix(home): 僅無子類目入口改為 SSR anchor
[#3071](url) fix(home): Desktop 熱門類目入口改為 SSR anchor
```

多個 repo 才按 repo 分組；同一個 repo 就不要多一層標題。

**這是預設值，不是上限。** 沒有任何東西在擋一則長訊息——擋它的理由要由寫的人自己給，見
下一節。

### 什麼時候可以多說

判準只有一條：**讀的人不看那段文字，就決定不了要不要點進去。** 符合的情況少，而且說得出
名字：

- **這一則跟上一則講的是同幾個 PR**，而中間發生了什麼會改變他要不要再看一次（例如票被
  機制重置、head 換了）。要說的是「變了什麼」，不是「為什麼變」。
- **PR 的外觀會誤導人**（diff 看起來很大但其實是 merge 進來的、CI 紅燈不是這顆 PR 造成的）。
- **有人問過的問題，答案會影響他要不要看**。

不符合的（這幾種每一次都想寫，每一次都不該寫）：

- 這顆 PR 做了什麼、怎麼做的、驗了什麼——**那些在 PR 本文裡，讀的人正要去那裡**。
- 逐位 reviewer 現在是什麼狀態、approval 幾比幾。
- 這一輪的施工過程、跑了哪些量測、哪幾條紅控。
- 對讀的人打招呼、鋪陳、感謝段落。

### 多說的形狀是條列，不是段落

真的要補，**一個 PR 一行，動詞開頭，說出「變了什麼」**：

```
[#3071](url) fix(home): Desktop 熱門類目入口改為 SSR anchor
　└ 你們投票後只動了註解與型別宣告，沒有會被執行的程式碼改動
```

一行寫不完，就是它不該進這則通知——把它留在 PR 的討論串裡，讀的人到得了那裡。

### approval 與 reviewer 狀態住在報告裡，不住在通知裡

`valid_approvals`/`threshold`、逐位 reviewer 的 stale / valid / requested changes、CI 狀態、
單號——**那些是上面〈Classification Report〉那張表的內容，給使用者決定要通知誰用的。**
它們進通知的唯一時機是有人問。

理由是這兩份東西的讀者不同：報告只有使用者讀，他要拿它做決定；通知是一群人讀，他們要拿它
決定點不點進去。**把決定用的資料倒給只需要一個連結的人，就是雜訊。**

送出前必須 materialize 成 temp markdown，並通過語言關卡：

```bash
bash .claude/skills/request-pr-review/scripts/validate-language-policy.sh --blocking --mode artifact <訊息檔>
```

**那道關卡只驗語言，不驗長度。** 長度沒有任何東西在擋——這是刻意的，寫的人自己負責。

用字不使用「催促」、「催」、「趕快」；用「麻煩大家幫忙」、「有空幫忙看一下」。

## Completion Summary

最後回報：

- 已加 label 的 PR
- 通知送到哪（由宣告方回答）
- JIRA 已從 `CODE REVIEW` 轉回 `IN DEVELOPMENT` 的 ticket
- 仍需修正的 🔧 PR 與建議指令，例如 `做 TASK-3788`
- label 與通知的 warning
