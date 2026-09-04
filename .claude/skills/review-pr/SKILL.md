---
name: review-pr
description: |
  Review someone else's PR as a code reviewer: read the PR diff, check against
  .claude/rules, leave inline comments on issues found, and submit a review with
  APPROVE or REQUEST_CHANGES. Use when the user asks the assistant to review a
  PR (subject omitted or = self), e.g.: "review PR", "review 這個 PR",
  "review 此 PR", "review 該 PR", "幫我 review 這個 PR" (without team subject),
  "review for me", "code review", or shares a PR URL with self-directed review
  intent. NOT for "請<同仁/大家/人名>幫我 review" (subject = others) — that is
  催 review, route to request-pr-review. NOT for "review 大家的 PR" / "掃 PR"
  (object = others' PRs) — route to review-inbox. NOT for fixing review comments
  on your own PR — that needs no relay, just fix it.

  要以 reviewer 的身分看**別人的** PR：讀 diff、留 inline comment、送出
  APPROVE 或 REQUEST_CHANGES。例如「review 這個 PR」「code review」，或丟一個 PR URL
  過來要人看。

  不用於：「請〈同仁/大家〉幫我 review」——主語是別人，那是催 review，
  走 request-pr-review。
metadata:
  author: Polaris
  version: 2.1.0
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

# review-pr

以 reviewer 角色審查別人的單一 PR，依 repo rules / handbook / diff context 留 inline
comments，並送出 GitHub review。

## Contract

此 skill 只處理單一 PR review。多 PR discovery 與 batch orchestration 交給
`review-inbox`；修自己的 PR review comments 就直接修（那不需要重簽成功的定義）。

Reviewer stance：prioritize bugs、behavior regressions、security、type safety、project
rule violations、missing tests。不要用 personal style preference 擋 merge。
reviewer-side 屬 read-only lane，但對 `changes_requested`、`active unresolved comments`、
`awaiting_re_review`、`mergeable_ready` 的語義必須與 author-side mutable lane 一致；不得自行重寫。
本 skill 可輸出 reviewer 結論（`APPROVE` / `COMMENT` / `REQUEST_CHANGES`），但不得把 reviewer
結論寫成 author-side stage authority；「可 merge / 可 release / 已完成」仍必須沿用 shared PR /
workflow state，而不是 reviewer prose。

## 這支 skill 有沒有被叫對：`evals/evals.json`

上面那條界線（什麼走這支、什麼走 `review-inbox` / `request-pr-review`）不是只寫在散文裡，
它有一份**具名的案例集**：`evals/evals.json`，13 句真的會被打出來的話，7 句該觸發、6 句
不該。每一條帶著它為什麼在那裡（`notes`）。

**它是給人讀的，不是給腳本跑的**——這裡沒有 runner，也刻意不要有一支。它的用途是：改
frontmatter 的 `description` 之前先讀那 13 句，問「改完之後這 13 句的答案還一樣嗎」。負向
那 6 句尤其重要，因為觸發詞放寬的代價從來不出現在正向案例上。

**什麼時候要更新它**：這支 skill 被叫錯、或該叫沒叫到的那一刻——把那句原話補成第 14 條，
標好它該不該觸發。一句在真實對話裡走錯的話，比十句想像出來的案例有用。同一趟摩擦也記進
你手上那張單可以改的那部分（`SKILL-UTILITY`，見 `driving-work-to-done`），兩者不重複：那裡記
「這一趟它幫到還是擋到」，這裡記「這句話該路由到哪」。

## Reference Loading

| Situation | Load |
|---|---|
| Any run | `review-pr-entry-fetch-flow.md`, `pr-input-resolver.md`, `workspace-config.yaml` |
| Analysis | `review-pr-analysis-flow.md`, `library-change-protocol.md` as needed |
| Writing findings up | `review-comment-form.md` |
| Submit and notify | `review-pr-submit-flow.md`, `scripts/validate-language-policy.sh`, `external-write-gate.md`, `github-slack-user-mapping.md` |
| Re-review | `review-pr-rereview-learning-flow.md`, `review-lesson-extraction.md` |

Large PR 分批 review 可派 sub-agent。
Completion Envelope。Sub-agent 只做 analysis，不送出 review、不改檔。

## Flow

1. 從使用者輸入或 Slack context 解析 PR URL；找不到單一 PR 時停止或轉 `review-inbox`。
2. 依 `pr-input-resolver.md` 解析 owner、repo、number、本地 project path；找不到本地 repo
   時使用 remote read mode。
3. 用 `scripts/fetch-pr-info.sh <owner/repo> <pr_number> [--my-user <username>]` 取得 metadata、
   files、review strategy、existing reviews、approval state、re-review signal。它只放行
   open 且非 draft 的 PR——已合併、已關閉、還在 draft 的一律拒絕並說出是哪一種狀態。
   打 `--help` 問得到用法。
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
- 使用 `scripts/validate-language-policy.sh` 或 external write gate 驗證 final text。
- 不重複留言已由其他 reviewer 指出的同語意問題。
- Suggested change 只在能精準替換 diff range 時使用。

下面這一行是機器讀的：往別人看得到的地方送文字的其他 skill，從這裡問出「送出去之前要過
哪一道檢查」，不各自寫死一條路徑。這道關卡住在這裡，因為 review 這件事本身就是對外寫入，
它是這支 skill 的原生需求，不是為了別人才存在的。

<!-- POLARIS-EXTERNAL-WRITE-GATE: bash .claude/skills/review-pr/scripts/polaris-external-write-gate.sh -->

## Completion

輸出 PR、review result、must-fix / should-fix / nit counts、approve status、Slack
notification status，以及 handbook updates if any。


<!-- PROSE-EXTERNAL-PATHS: docs-manager/ — 動手對象：那是 specs 站台自己的 repo，這支 skill 往它寫東西、讀它的結構，不是我們抄一份放著的知識 -->
