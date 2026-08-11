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

每一則要說得出：

- 這是誰的 PR、日期
- 按 repo 分組，同 repo 的放一起
- 每個 PR：連結、標題、`valid_approvals`/`threshold`
- 每個 PR 的 reviewer 狀態，逐位：
  - 有 stale approve → 需要 re-approve（有新 push）
  - 有 valid approve → 已 approve
  - 有 REQUEST_CHANGES → requested changes
  - 還沒有人看 → 還需幾位
- 總共幾個 PR 需要看

送出前必須 materialize 成 temp markdown，並通過語言閘：

```bash
bash .claude/skills/request-pr-review/scripts/validate-language-policy.sh --blocking --mode artifact <訊息檔>
```

用字不使用「催促」、「催」、「趕快」；用「麻煩大家幫忙」、「有空幫忙看一下」。

## Completion Summary

最後回報：

- 已加 label 的 PR
- 通知送到哪（由宣告方回答）
- JIRA 已從 `CODE REVIEW` 轉回 `IN DEVELOPMENT` 的 ticket
- 仍需修正的 🔧 PR 與建議指令，例如 `做 TASK-3788`
- label 與通知的 warning
