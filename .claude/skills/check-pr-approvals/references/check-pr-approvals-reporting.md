# check-pr-approvals Reporting Reference

本 reference 承接 `check-pr-approvals/SKILL.md` 的低頻輸出細節。只有在產出分類報告、加 label、送 Slack、處理 🔧 remediation 或 merged PR side effects 時讀取。

## Classification Report

面向使用者的 PR 編號必須用 markdown link：`[#123](https://github.com/org/repo/pull/123)`。

```markdown
🟢 可催 review（N 個）：
| # | Repo | PR | Title | Approvals | Reviewers | Label |
|---|------|----|-------|-----------|-----------|-------|
| 1 | repo-a | [#1786](url) | feat: xxx | 0/2 | — | |
| 2 | repo-b | [#302](url) | fix: yyy | 1/2 | reviewer-b ✅ | 👀 |

🔧 需先修正（N 個）：
| Repo | PR | Ticket | 問題 |
|------|----|--------|------|
| repo-a | [#1920](url) | TASK-3788 | CI fail (codecov/patch) |
| repo-c | [#45](url) | TASK-3801 | rebase conflict |
| repo-d | [#67](url) | 無對應 ticket | 2 unresolved review comments |

✅ 已達標（N 個）：repo-a [#100](url), repo-b [#200](url)

請輸入要通知的 🟢 PR 編號（例如 `1,2` 或 `all`，輸入 `none` 跳過）：
```

Reviewers 欄位：

- `username ✅`：valid approve
- `username ⚠️ re-approve`：stale approve
- `username 🔄 changes`：REQUEST_CHANGES
- `—`：尚無人 review

問題欄可複合，例如 `CI fail + 2 unresolved comments`。排序規則：🟢 PR 依 valid approvals 升序；🔧 PR 依 conflict > CI fail > comments 排序。

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

Label 失敗不應中斷整批 Slack reminder，但必須在最後回報哪些 PR label 失敗。

## Slack Reminder

只通知使用者選中的 🟢 PR。Slack message 送出前必須 materialize 成 temp markdown，並通過：

```bash
bash scripts/validate-language-policy.sh --blocking --mode artifact <check-pr-approvals-slack.md>
```

Slack wording 不使用「催促」、「催」、「趕快」。用「麻煩大家幫忙」、「有空幫忙看一下」。

Template：

```text
:mag: *PR Review 進度*
時間：{YYYY-MM-DD}
作者：{author}

以下 PR 麻煩大家有空幫忙 review / re-approve，感謝 :pray:

*{repo_name}*
• <{pr_url}|#{number}> {title} — _{valid_approvals}/{threshold} approve(s)_
  {reviewer_details}

共 {selected_count} 個 PR 需要 review / re-approve
```

Reviewer details：

- 有 stale approve：`⚠️ {username} 需 re-approve（有新 push）`
- 有 valid approve：`✅ {username} 已 approve`
- 有 REQUEST_CHANGES：`🔄 {username} requested changes`
- 尚無人 review：`還需 {threshold} 位同仁 review`
- 已有部分 valid approval：`還需 {remaining} 位同仁 review`

按 repo 分組；同 repo PR 放在同一組。

## JIRA Remediation Routing

🔧 PR 必須從 branch name 或 PR title 萃取 ticket key。Pattern：`[A-Z]+-\d+`。

若 ticket key 存在，查 JIRA 狀態：

- 狀態是 `CODE REVIEW`：轉回 `IN DEVELOPMENT`，並留言記錄原因。
- 已在 `IN DEVELOPMENT` 或其他狀態：不轉狀態，只在報告中列出。
- 轉狀態失敗：不阻塞報告，但必須列為 warning。

Comment 範例：

```text
PR #{number} 目前仍需修正：{reason}。已轉回 IN DEVELOPMENT，方便後續使用 engineering 修正。
```

若 ticket key 萃取不到，不做 JIRA routing，報告中標 `無對應 ticket`。

## Merged PR Side Effects

掃描過程發現 merged PR 時才處理本段。

### Feature Branch PR Gate

讀 `../references/feature-branch-pr-gate.md`，依該 reference 執行偵測與回報。不要在本 reference 重寫 gate 語意。

### Spec Done Marker

從 branch / title 萃取 ticket key。若是 Epic key（例如 `GT-*`），不在此標 parent implemented；Epic closeout 由 verify-AC / parent lifecycle 處理。

若是 Bug 或 ad-hoc task，且 `specs/companies/{company}/{TICKET}/` container 存在，執行：

```bash
scripts/mark-spec-implemented.sh {TICKET}
```

此操作 idempotent。若 container 不存在，靜默略過或在最後摘要列為 no-op。

## Completion Summary

最後回報：

- 已加 label 的 PR
- Slack 發送 channel
- JIRA 已從 `CODE REVIEW` 轉回 `IN DEVELOPMENT` 的 ticket
- 仍需修正的 🔧 PR 與建議指令，例如 `做 TASK-3788`
- label / JIRA / Slack 的 warning
