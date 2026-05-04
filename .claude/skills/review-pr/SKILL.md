---
name: review-pr
description: >
  Review someone else's PR as a code reviewer: read the PR diff, check against
  .claude/rules, leave inline comments on issues found, and submit a review with
  APPROVE or REQUEST_CHANGES. Use when: (1) user says "review PR", "review 這個 PR",
  "幫我 review", "review for me", "code review", (2) user shares a PR URL and asks
  to review it, (3) user says "看一下這個 PR", "take a look at this PR", "檢查 PR",
  "check this PR", "review pull request". This skill is
  for REVIEWING someone else's code — not for fixing review comments on your own PR
  (use engineering revision mode for that).
metadata:
  author: Polaris
  version: 2.1.0
---

# review-pr

以 reviewer 角色審查別人的單一 PR，依 repo rules / handbook / diff context 留 inline
comments，並提交 GitHub review。

## Contract

此 skill 只處理單一 PR review。多 PR discovery 與 batch orchestration 交給
`review-inbox`；修自己的 PR review comments 交給 `engineering` revision mode。

Reviewer stance：prioritize bugs、behavior regressions、security、type safety、project
rule violations、missing tests。不要用 personal style preference 擋 merge。

## Reference Loading

| Situation | Load |
|---|---|
| Any run | `review-pr-entry-fetch-flow.md`, `pr-input-resolver.md`, `workspace-config-reader.md`, `shared-defaults.md` |
| Analysis | `review-pr-analysis-flow.md`, `repo-handbook.md`, `library-change-protocol.md` as needed |
| Submit and notify | `review-pr-submit-flow.md`, `workspace-language-policy.md`, `external-write-gate.md`, `github-slack-user-mapping.md` |
| Re-review | `review-pr-rereview-learning-flow.md`, `review-lesson-extraction.md`, `repo-handbook.md` |

Large PR 分批 review 可派 sub-agent；所有 dispatch 必須注入 `sub-agent-roles.md` 的
Completion Envelope。Sub-agent 只做 analysis，不提交 review、不改檔。

## Flow

1. 從使用者輸入或 Slack context 解析 PR URL；找不到單一 PR 時停止或轉 `review-inbox`。
2. 依 `pr-input-resolver.md` 解析 owner、repo、number、本地 project path；找不到本地 repo
   時使用 remote read mode。
3. 用 bundled fetch script 取得 metadata、files、review strategy、existing reviews、approval
   state、re-review signal。
4. 讀 repo rules、workspace handbook、PR description、changed files、diff、既有 review
   comments，建立去重清單。
5. Review changed files；large PR 依 reference 分組派 sub-agent fan-out。
6. 合併 findings，依 severity 決定 `APPROVE`、`COMMENT`、或 `REQUEST_CHANGES`。
7. Review body、inline comments、Slack notification 送出前跑 language gate。
8. Submit GitHub review，查詢 approve status，輸出摘要。
9. 若有 validated repo-specific pattern，依 standard-first rule 更新 handbook。
10. Slack source 時回覆原始 thread。

## Severity Boundary

`must-fix` 必須是可從 code / diff / rules 直接證明會造成 bug、安全風險、型別錯誤、
或違反關鍵規範。外部 API 行為、language/library behavior、或僅基於慣例的推論，在未驗證前
最多是 `should-fix`。

## Write Rules

- GitHub review、inline comments、Slack replies 都是 external write。
- 使用 `workspace-language-policy.md` 或 external write gate 驗證 final text。
- 不重複留言已由其他 reviewer 指出的同語意問題。
- Suggested change 只在能精準替換 diff range 時使用。

## Completion

輸出 PR、review result、must-fix / should-fix / nit counts、approve status、Slack
notification status，以及 handbook updates if any。

## Post-Task Reflection (required)

Execute `post-task-reflection-checkpoint.md` before reporting completion.
