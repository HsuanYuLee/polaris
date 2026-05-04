---
title: "Learning PR And Batch Flow"
description: "learning PR / Batch mode 的 merged PR review lesson extraction、dedup 與 handbook write 流程。"
---

# PR And Batch Mode Flow

這份 reference 是 `learning/SKILL.md` PR mode 與 Batch mode 的延後載入流程。
兩者都從 merged PR review comments 萃取可重用 review lessons，並寫入 repo
handbook。

## Shared Rules

- 只從 completed review cycle 萃取。Open PR 預設不處理；使用者堅持時先提示風險。
- PR 必須有 review comments。只有 approval / LGTM / bot-only noise 時跳過。
- 萃取、dedup、write format、reverse sync 以 `review-lesson-extraction.md` 為準。
- 多 PR 可 dispatch sub-agent，但每個 sub-agent 必須使用 Completion Envelope。
- Review comments 多語時，lesson 使用 repo handbook 既有語言風格。
- Reviewer disagreement 無法判斷時，跳過或列出雙方讓使用者決定。

## PR Mode

### Step P1. Resolve Target PRs

| Input | Resolution |
|---|---|
| specific PR number | `gh pr view {number} --repo {org}/{repo}` |
| PR URL | parse owner / repo / number |
| person's PRs | `gh pr list --repo {org}/{repo} --state merged --author <github-username> --limit 10` |
| time range | `gh pr list --repo {org}/{repo} --state merged --search "merged:>YYYY-MM-DD" --limit 20` |
| repo-specific | use that repo |
| no repo | infer from repo mapping or ask |

每次最多 10 個 PR；超過時取最近 10 個並告知使用者。

### Step P2. Extract Review Data

每個 PR 收集：

```bash
gh api repos/{org}/{repo}/pulls/{number}/comments --paginate
gh api repos/{org}/{repo}/pulls/{number}/reviews --paginate
gh pr diff {number} --repo {org}/{repo}
```

多 PR 時最多 5 個 sub-agents 平行，每個 PR 回傳 structured findings。

### Step P3-P4. Dedup And Write

依 `review-lesson-extraction.md`：

- semantic dedup。
- write handbook lesson。
- reverse sync if required by project policy。

### Step P5. Summary

輸出：

```markdown
## PR 學習摘要

分析了 N 個 PR：...

### 新增 lesson（M 條）
| Topic | Rule | Source PR |
|---|---|---|

### 跳過（K 條重複）
- ...

### 無可學習 pattern 的 PR
- #456 — ...
```

## Batch Mode

Batch mode 掃 repo 的 merged PR history，跳過已萃取來源，批次補齊 handbook lessons。

### Step B1. Resolve Target Repos

| Input | Resolution |
|---|---|
| specific repo | target that repo |
| no repo | read workspace config projects and scan configured repos |
| multiple repos | process each repo sequentially |

每個 repo 從 workspace config 或 git remote 解析 `{org}/{repo}`。

Time range 預設 3 個月；使用者可指定，最多 12 個月。

### Step B2. Layer 1 Dedup

讀 `{base_dir}/<repo>/.claude/rules/handbook/*.md`，抽所有 `Source:` PR URL /
number，建立 already-extracted set。這些 PR 直接跳過。

### Step B3. Find Candidate PRs

兩路查 merged PR：

```bash
gh search prs --repo {org}/{repo} --author @me --state closed --merged --limit 30 --json number,title,url,closedAt
gh search prs --repo {org}/{repo} --reviewed-by @me --state closed --merged --limit 20 --json number,title,url,closedAt
```

合併後依 PR number dedup，再移除 Layer 1 已萃取來源。每 repo cap 30 個 candidate。

### Step B4. Filter Qualifying Comments

對 candidate PR 查 inline comments：

```bash
gh api repos/{org}/{repo}/pulls/{number}/comments --paginate
```

過濾：

- 排除 PR author 自己的 comments。
- 排除純 bot noise，例如 changeset-bot、codecov-commenter、GitHub Actions。
- 保留 human reviewer comments 與 code review bots（例如 Copilot、CodeRabbit）。

0 qualifying comments 時跳過。

### Step B5-B6. Batch Extract And Write

對有 qualifying comments 的 PR dispatch sub-agent，最多 5 個平行。每個 sub-agent
使用 `review-lesson-extraction.md` prompt template。收斂後依該 reference 做
semantic dedup、write、reverse sync。

### Step B7. Summary

輸出：

```markdown
## Batch 學習摘要 — {repo}

掃描範圍：最近 {N} 個月 merged PRs
候選 PR：{total found} 個（已萃取 {skipped} 個跳過 -> 實際掃描 {scanned} 個）
有 review comments：{with_comments} 個
新增 lessons：{new_count} 條

### 新增明細
| Topic | Rule | Source PR |
|---|---|---|

### 跳過的 PR（已在 handbook 中）
{count} 個 — Layer 1 dedup
```

## Batch Edge Cases

- No unextracted PRs：回報 handbook extraction pipeline 已完整，然後停止。
- Rate limit：pause and retry with exponential backoff；超過 30 秒要告知使用者。
- Large repo：cap 30；告知可再次執行處理剩餘 PR。
- Mixed repos：逐 repo summary，最後給 aggregate。
