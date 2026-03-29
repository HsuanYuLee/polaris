---
name: learning
description: >
  Three modes: (1) Researches external content (GitHub repos, articles, blog posts, tech talks,
  architecture patterns) and analyzes what's applicable to our workspace. (2) Learns from merged
  PRs — extracts review patterns and coding lessons from team PR review comments and fix diffs,
  then writes them into review-lessons for graduation into rules. (3) Queue mode — processes articles
  from the daily learning queue (populated by scheduled daily-learning-scan agent), batch-analyzes
  them, and archives processed items. Dispatches sub-agents for parallel deep-dive when scope is large.
  Make sure to use this skill whenever the user mentions: "學習", "learn", "研究一下", "借鑑",
  "看看這個", "研究這個", "study this", "learn from this", "這個不錯", "有什麼可以學的", "可以參考",
  "take inspiration", "學習 PR", "learn from PR", "研究 PR review", "學習最近的 PR", "PR 學習",
  "學習 merge 的 PR", "研究別人的 PR", "今天有什麼可以學的", "每日學習", "看看今天的推薦",
  "今天推薦什麼", "有新文章嗎", "讀文章", "學習報到", "daily learning", "消化 queue", "learning queue",
  "處理 queue", "學習 queue", "處理今天的文章", "queue 有什麼", "看看 queue", or shares an external
  URL/resource and asks to
  analyze, research, or evaluate it — even if they don't explicitly say "learn". Also trigger when
  the user shares a link and says something casual like "看一下這個" or "幫我看看". Do NOT trigger
  for internal codebase exploration (use Explore subagent directly), JIRA ticket analysis (use
  work-on), or PR review (use review-pr for reviewing someone else's code — this skill
  is for LEARNING from already-merged PRs, not reviewing open ones).
metadata:
  author: ""
  version: 1.4.0
---

# learning

Three modes of learning:
- **External mode** — Research external content (articles, repos, talks) and distill actionable insights for our workspace
- **Queue mode** — Process articles from the daily learning queue, batch-analyze, and archive
- **PR mode** — Learn from merged PRs by extracting review patterns into review-lessons (feeds into the existing graduation mechanism)

## Step 0: Mode Detection

Determine which mode based on the user's input:

| Signal | Mode | Example |
|---|---|---|
| PR number, PR URL, or mentions "PR" + "學習/learn" | **PR mode** | `學習 PR #123`, `learn from your-app 最近的 PR` |
| Mentions a person's PRs | **PR mode** | `學習 daniel 最近的 PR`, `研究 PR review` |
| Time-range + PR | **PR mode** | `學習最近一週 merge 的 PR` |
| External URL, repo, article | **External mode** | `看看這個 github.com/...`, `研究這篇文章` |
| Mentions "每日學習", "今天有什麼可以學的", "看看今天的推薦", "有新文章嗎", "讀文章", "daily learning", "queue", "消化", or bare "學習" without URL/PR context | **Queue mode** | `每日學習`, `今天有什麼可以學的`, `看看今天的推薦`, `有新文章嗎`, `讀文章` |
| Ambiguous | Ask the user | `學習一下` without context |

**PR mode** → jump to [PR Learning Flow](#pr-learning-flow)
**Queue mode** → jump to [Queue Learning Flow](#queue-learning-flow)
**External mode** → continue to Step 1 below

---

# External Learning Flow

## Step 1: Understand the Input

Identify what the user shared and classify the input type:

| Input Type | How to Access | Example |
|---|---|---|
| GitHub repo URL | WebFetch README, then `gh` CLI for structure | `github.com/org/repo` |
| Article / Blog URL | WebFetch | tech blog, Medium, dev.to |
| Local file | Read tool | PDF, markdown, code file |
| Text description | Already in conversation | user describes a pattern verbally |
| Video / Talk | Ask user for key takeaways (can't watch videos) | YouTube, conference talk |

For GitHub repos: fetch the README first, then assess if you need to explore the repo structure (directory listing, key source files) for deeper understanding.

For URLs that fail to fetch: tell the user and ask them to paste the key content directly.

## Step 2: Scope Assessment — Do We Need Parallel Research?

After reading the initial content, assess the scope:

**Single-agent (direct research)** when:
- Content is a single article or blog post
- README covers the full picture
- One clear topic area (e.g., "a new testing pattern")

**Multi-agent (parallel Researchers)** when:
- GitHub repo with multiple distinct modules or concepts worth studying
- Content spans 3+ distinct topic areas
- Cross-referencing needed (e.g., repo + its documentation site + related articles)
- User explicitly shares multiple URLs

When in doubt, start with single-agent. You can always spawn additional Researchers if the first pass reveals more depth than expected.

## Step 3: Research — Facts Only

### Single-agent path

Research the content yourself. Focus on extracting:

1. **Core concepts** — What is this thing? What problem does it solve?
2. **Architecture / patterns** — How is it structured? What design decisions were made?
3. **Notable techniques** — Specific implementations worth noting
4. **Trade-offs acknowledged** — What limitations or costs does the author mention?

### Multi-agent path

Spawn Researcher sub-agents (`model: "sonnet"`). Each sub-agent uses the **Researcher** role defined in `~/work/.claude/skills/references/sub-agent-roles.md` — read the Researcher section and include it in the sub-agent prompt.

Sub-agent prompt template:

```
{引用 references/sub-agent-roles.md 的 Researcher 角色定義}

## 研究對象
{content description + URL or path}

## 你負責的範圍
{specific aspect to research — e.g., "architecture and module organization", "testing strategy", "CI/CD pipeline design"}
```

Split strategies (similar to explore-pattern.md):

| Strategy | When | Example |
|---|---|---|
| By topic area | Content covers multiple distinct concepts | Agent A: architecture, Agent B: testing, Agent C: deployment |
| By source | User shared multiple URLs | One agent per URL |
| By depth | Broad overview + deep dive needed | Agent A: high-level structure, Agent B: deep dive into specific module |

Maximum 3 Researcher sub-agents. If the content needs more, you're probably researching too broadly — narrow the focus with the user first.

## Step 4: Synthesis — Connect to Our Workspace

This is where the value is created. After collecting research findings (from yourself or sub-agents), analyze through this lens:

### 4a. Comparison Matrix

Build a comparison between the external content and our current workspace:

```markdown
| Aspect | External Approach | Our Current Approach | Gap / Opportunity |
|--------|------------------|---------------------|-------------------|
| ... | ... | ... | ... |
```

To fill "Our Current Approach" accurately: read relevant workspace files (CLAUDE.md, skills, references, rules) rather than relying on memory alone. If you need to explore our codebase for a specific aspect, spawn a single Explore subagent (per explore-pattern.md) — don't guess.

### 4b. Recommendations

For each gap/opportunity identified, provide:

```markdown
### Recommendation: {title}

**What**: One-sentence description of the change
**Why**: What problem it solves or what improvement it brings
**How**: Concrete action items (files to create/modify, patterns to adopt)
**Effort**: Low / Medium / High
**Priority**: Worth doing now / Nice to have / Worth tracking
```

Prioritization guidance:
- **Worth doing now**: Addresses a known pain point, low effort, or prevents a recurring issue
- **Nice to have**: Genuine improvement but no urgency
- **Worth tracking**: Interesting idea but needs more evidence or a trigger event

Be honest about what's NOT worth borrowing. Not everything from an external source applies to our context. Explicitly call out things that look cool but don't fit — this builds trust and saves the user from chasing shiny objects.

### 4c. Present to User

Present the comparison matrix and recommendations. Wait for the user to react before taking any action.

## Step 5: Execute (Only After User Confirmation)

Based on the user's response:

| User says | Action |
|---|---|
| Confirms specific recommendations | Execute those changes (edit files, create references, update CLAUDE.md) |
| Wants to discuss further | Continue the conversation, refine recommendations |
| Wants to save for later | Save a project or reference memory with the key insights |
| Says "worth tracking" or defers | Add to `.claude/polaris-backlog.md` (see below) |
| Disagrees with some points | Acknowledge, adjust, don't push |

For any workspace changes: follow existing conventions (use `/skill-creator` for new skills, edit CLAUDE.md for rules, use `skills/references/` for reference docs).

### Backlog routing

When a recommendation targets the **Xuanji framework itself** (skill flow, rule mechanism, config structure, interaction patterns) rather than company-specific business logic:

- **User confirms and executes now** → normal Step 5 execution + update `CHANGELOG.md` if significant
- **User says "worth tracking" / "之後再做" / defers** → append to `.claude/polaris-backlog.md` under the appropriate priority section:
  ```
  - [ ] **{title}** — {one-line description} — source: learning ({source URL})
  ```
- **User explicitly rejects** → don't add to backlog

## Meta: Role Discovery

When researching external content, watch for division-of-labor patterns that could map to a new sub-agent role. This is how the talent pool grows organically — external inspiration surfaces new specializations we haven't formalized yet.

**Detection**: During Step 4 (Synthesis), if a recommendation involves a type of sub-agent work that doesn't fit any role in `~/work/.claude/skills/references/sub-agent-roles.md`, flag it:

```markdown
### Recommendation: {title}
...
🎭 **Potential new role: {RoleName}**
- Does: {what this role would do}
- Doesn't: {what it explicitly avoids}
- Model: sonnet / haiku
- Would be used by: {which existing skills}
```

**Execution**: If the user confirms the new role, append it to `sub-agent-roles.md` following the existing format (職責、不做、回傳格式、Model、適用場景). See the Role Lifecycle section in that file for the full process.

Don't force role discovery — most research won't surface new roles, and that's fine. Only flag it when the pattern is clearly distinct from existing roles.

## Meta: Attribution

When learning from external content leads to **actual workspace changes** (Step 5), credit the source in `README.md`'s Acknowledgements table.

### When to trigger

- The source is a **GitHub repo or a named open-source project** (not a generic blog post or documentation page)
- At least one recommendation was **confirmed and executed** (files were created or modified)
- The project is **not already listed** in the Acknowledgements table

Articles, blog posts, and documentation don't get table entries — they're too granular. If an article leads to a significant change, credit the underlying project or author if identifiable.

### How to add

After executing confirmed changes in Step 5, append a row to `~/work/README.md`'s Acknowledgements table:

```markdown
| [{project name}]({url}) | {author} | {one-line: what we learned / adopted} |
```

- **Project name**: repo name or project title
- **Author**: GitHub username or real name (from README/profile)
- **What we learned**: concise — what concept or pattern was adopted, not a full summary

If multiple recommendations were adopted from the same source, combine into one row with a comma-separated description.

### What NOT to add

- Sources where we only read but didn't change anything
- Internal repos (our own org's projects)
- Generic tools everyone uses (Node.js, Vue, etc.)
- Sources already listed — instead, update the "What we learned" column if new insights were adopted later

## Edge Cases (External Mode)

- **Content is behind a paywall or login**: Tell the user you can't access it, ask them to paste the key sections
- **Content is in a language you can't read well**: Proceed with best effort, flag uncertainty
- **User shares a very large repo**: Don't try to read everything. Focus on README, architecture docs, and 2-3 key source files. Ask the user what aspect interests them most
- **Content is outdated or deprecated**: Note this in your analysis — old patterns may have been superseded for good reasons
- **User just wants a summary, not recommendations**: That's fine. Skip Step 4b-4c and just present the research findings

---

# Queue Learning Flow

Process articles from the daily learning queue (populated by the scheduled `daily-learning-scan` agent). This mode batch-processes pending articles, presents unified recommendations, and archives processed items.

## Step Q1: Read Queue and Filter

Read `~/work/.claude/skills/references/learning-queue.md` and parse all pending items (entries under `## Pending Items`).

If queue is empty, tell the user "Queue 是空的，沒有待處理的文章。" and stop.

Show the user a summary of pending items with the Repos column:

```markdown
| # | Title | Category | Repos | Added |
|---|-------|----------|-------|-------|
| 1 | ... | ai-agent | your-company-web-skills | ... |
| 2 | ... | performance | your-app | ... |
| 3 | ... | framework | all | ... |
```

The user may filter by repo: "只看 your-app 相關的" → only process articles where `Relevant Repos` contains `your-app` or `all`. If no filter specified, process all.

Ask: "要全部處理，還是選幾篇？可以用 repo 篩選（如：只看 your-app 和 docker 相關的）"

## Step Q2: Process Each Article

For each selected article, follow the **External Learning Flow** (Step 1-4) using the article's URL as input. Key differences from manual external learning:
- Step 1 input type is always "Article / Blog URL" — use WebFetch to read the article
- Step 2 scope assessment: each article is single-agent (direct research) unless it links to a large repo
- Step 4 synthesis: compare against our workspace as usual, but **batch the findings** — don't ask for confirmation after each article

For efficiency with multiple articles:
- Process up to 3 articles in parallel using Researcher sub-agents (`model: "sonnet"`)
- Each sub-agent reads one article, extracts facts (Step 3), and returns findings
- **Sub-agent must return enough info for the condensed summary**: one-line description, what's applicable to our stack (bullet points), and what's not applicable — so we don't need to re-read the article later
- Main agent collects all sub-agent results, then presents the condensed summary (Step Q2.5)

## Step Q2.5: Present Condensed Summary

After all articles are processed, present a per-article condensed summary in one shot — the user needs to see everything together to make decisions:

```markdown
## Learning Queue 精簡摘要

**處理了 N 篇文章**

### 1. {Article Title}
- **簡述**：一句話描述文章核心內容
- **可參考**：與我們 workspace 相關的重點（條列，每點一句話）
- **不適用**：不符合我們情境的部分（一句話說明原因）

### 2. {Article Title}
- **簡述**：...
- **可參考**：...
- **不適用**：...

（...每篇文章重複此格式）
```

Present all articles together, then ask: **「要針對哪些做詳細推薦分析，還是直接歸檔？」**

Based on the user's response:
- **選擇部分文章** → 只對選中的文章跑 Step Q3 詳細推薦分析
- **全部歸檔** → 跳過 Q3，直接到 Q4 歸檔（每篇標記為 `noted` 或 `skipped`）
- **全部分析** → 對所有文章跑 Step Q3 完整推薦流程

## Step Q3: Present Detailed Recommendations (Optional)

Only runs for articles the user selected in Step Q2.5. Present a unified recommendation summary for the selected articles:

```markdown
## Learning Queue 詳細推薦

### Worth doing now
| Article | Recommendation | Effort | Action |
|---------|---------------|--------|--------|
| ... | ... | Low/Med/High | edit rules / create reference / update skill |

### Nice to have
| Article | Recommendation | Effort |
|---------|---------------|--------|
| ... | ... | ... |

### Not applicable (skip)
| Article | Reason |
|---------|--------|
| ... | Stack mismatch / outdated / too generic |
```

Wait for user confirmation before executing any changes.

## Step Q4: Execute and Archive

After user confirms which recommendations to execute:

1. **Execute** confirmed changes (edit files, create references, update CLAUDE.md/rules). Follow existing conventions (use `/skill-creator` for skill changes, `skills/references/` for reference docs).

2. **Archive ALL processed articles** (regardless of outcome) — move from `learning-queue.md` to `learning-archive.md`:
   - Remove the entry from the `## Pending Items` section in `learning-queue.md`
   - Add a row to the table in `learning-archive.md`:
     ```
     | {today's date} | {title} | {url} | {result} | {one-line note} |
     ```
   - Result values: `applied` (recommendation executed), `noted` (interesting but deferred), `skipped` (not applicable)

3. **Commit** changes to your-company-web-skills: `chore: process learning queue YYYY-MM-DD`

## Step Q5: Summary

Report what was done:
- X articles processed
- Y recommendations applied (list them)
- Z articles archived
- Queue items remaining: N

## Edge Cases (Queue Mode)

- **Article URL is dead or returns 404**: Mark as `skipped` with note "URL unavailable", archive it, move on
- **Article content is behind a paywall**: Same as External mode — tell the user, ask them to paste key content, or skip
- **Queue has > 10 items**: Process the 5 most recent first. Tell the user "Queue 有 N 篇，先處理最近 5 篇，剩下的下次再處理。"
- **User wants to skip specific articles without reading**: Allow it — mark as `skipped` with note "user skipped" and archive

---

# PR Learning Flow

Learn from merged PRs by extracting review patterns into review-lessons. The value: knowledge that was exchanged in PR reviews (corrections, suggestions, pattern enforcement) gets systematically captured so the whole team benefits — not just the PR author and reviewer.

## Step P1: Resolve Target PRs

Determine which PRs to study based on the user's input:

| Input | How to resolve |
|---|---|
| Specific PR number (`PR #123`) | Direct: `gh pr view 123 --repo your-org/<repo>` |
| Specific PR URL | Extract owner/repo and number from URL |
| Person's PRs (`daniel 最近的 PR`) | `gh pr list --repo your-org/<repo> --state merged --author <github-username> --limit 10` |
| Time-range (`最近一週的 PR`) | `gh pr list --repo your-org/<repo> --state merged --search "merged:>YYYY-MM-DD" --limit 20` |
| Repo-specific (`your-app 最近的 PR`) | Target that repo specifically |
| No repo specified | Use the repo mapping from CLAUDE.md to infer, or ask the user |

**Filtering**: Only include PRs that have review comments (PRs with 0 review comments have nothing to learn from). Use `gh api repos/your-org/<repo>/pulls/<number>/reviews` to check.

**Cap**: Maximum 10 PRs per invocation. If the query returns more, take the 10 most recent and tell the user.

## Step P2: Extract Review Data

For each PR, collect:

1. **Review comments** — `gh api repos/your-org/<repo>/pulls/<number>/comments --paginate` (inline comments on specific lines)
2. **Review summaries** — `gh api repos/your-org/<repo>/pulls/<number>/reviews --paginate` (top-level review body with APPROVE/REQUEST_CHANGES)
3. **PR diff** — `gh pr diff <number> --repo your-org/<repo>` (to understand what was changed and how the fix addressed the review)

For **batch mode** (multiple PRs): spawn one sub-agent per PR (`model: "sonnet"`) to extract in parallel. Each sub-agent returns structured findings (see Step P3 format). Maximum 5 parallel sub-agents — if more than 5 PRs, process in batches.

Sub-agent prompt template:

```
You are analyzing a merged PR to extract learnable patterns from its review comments.

## PR Info
- Repo: your-org/<repo>
- PR: #<number>
- URL: https://github.com/your-org/<repo>/pull/<number>

## Your Task
1. Read the PR review comments: `gh api repos/your-org/<repo>/pulls/<number>/comments --paginate`
2. Read the review summaries: `gh api repos/your-org/<repo>/pulls/<number>/reviews --paginate`
3. Read the PR diff: `gh pr diff <number> --repo your-org/<repo>`
4. For each review comment that teaches something generalizable, extract:
   - The pattern/rule (what should be done)
   - Why it matters (from the reviewer's explanation or inferred from context)
   - The topic category (e.g., typescript-type-safety, error-handling, nuxt-ssr-caching, vitest-testing-patterns, naming-conventions, code-organization, vue-component-patterns, server-api-patterns)

## What to Extract
- Framework idiomatic patterns (Vue/Nuxt/TypeScript correct usage)
- Error handling conventions
- Type safety patterns
- Performance decisions
- Testing conventions
- Component design principles
- Architecture patterns
- Naming and code organization conventions

## What to Skip
- Typos, missing imports, copy-paste errors (one-off mistakes, not patterns)
- Pure formatting issues (handled by linters)
- One-off business-logic-specific comments (not generalizable)
- Nit-level style suggestions
- Comments that are questions or discussions without a clear conclusion
- "LGTM" or approval-only reviews with no substantive comments

## Return Format
Return a JSON array:
[
  {
    "rule": "Description of the pattern/rule",
    "why": "Why this matters",
    "topic": "topic-category-kebab-case",
    "source_pr": "https://github.com/your-org/<repo>/pull/<number>",
    "source_date": "YYYY-MM-DD"
  }
]
If no learnable patterns found, return an empty array [].
```

## Step P3: Deduplicate Against Existing Knowledge

Before writing any lessons, load existing knowledge to avoid duplicates:

1. **Read all review-lesson files** in `~/work/<repo>/.claude/rules/review-lessons/*.md`
2. **Read all main rule files** in `~/work/<repo>/.claude/rules/*.md` (excluding `review-lessons/` subdirectory)
3. Also check `~/work/.claude/rules/*.md` (workspace-level rules)

For each extracted pattern, compare against existing lessons and rules:
- **Semantically identical** (same rule, same reasoning) → skip, count as duplicate
- **Related but adds a new angle** (same topic, different aspect) → keep, will be appended to existing topic file
- **Entirely new** → keep, will create a new topic file or append to the closest existing one

## Step P4: Write Review Lessons

Write extracted patterns to `~/work/<repo>/.claude/rules/review-lessons/` using the **exact same format** as `review-pr` Step 6.5:

**File naming**: Topic-based, kebab-case `.md` files (e.g., `typescript-type-safety.md`, `error-handling.md`). Append to existing files of the same topic — do not create a new file if one with the matching topic already exists.

**Entry format** (each top-level `- ` counts as 1 entry):

```markdown
# {Topic Title}

- {Rule description — clear, actionable, generalizable}
  - Why: {reasoning from the reviewer or inferred from the fix}
  - Source: https://github.com/your-org/<repo>/pull/<number> (YYYY-MM-DD)
```

When appending to an existing file, add new entries after the last existing entry (before EOF). Do not modify existing entries.

## Step P5: Summary & Graduation Check

### Summary output

Present a summary to the user:

```markdown
## PR 學習摘要

**分析了 N 個 PR**：{list PR numbers with titles}

### 新增 lesson（M 條）
| Topic | Rule | Source PR |
|-------|------|-----------|
| ... | ... | #123 |

### 跳過（K 條重複）
- {brief description of skipped patterns and why they're duplicates}

### 無可學習 pattern 的 PR
- #456 — {reason: e.g., "only LGTM comments", "all comments were typo fixes"}
```

### Graduation check

After writing, count total entries across all review-lesson files in the repo (`^- ` lines). If total >= 15, invoke `review-lessons-graduation`:

```
Invoke review-lessons-graduation to consolidate review-lessons in <repo>.
```

If count < 15, mention the current count: "目前 {repo} 有 X 條 review-lessons，累積到 15 條後會自動觸發 graduation。"

## Edge Cases (PR Mode)

- **PR has no review comments**: Skip it, note in summary as "no review comments"
- **PR is not merged**: Warn the user — learning is designed for merged PRs where the review cycle is complete. Open PRs may have unresolved discussions. Proceed if the user insists
- **Cannot determine repo**: Ask the user which repo to target
- **User wants to learn from their own PRs**: That's fine — same flow. Their own PRs may have received valuable feedback from reviewers
- **Review comments are in a mix of languages**: Extract the pattern in whichever language makes it clearest (Chinese or English), matching the style of existing review-lessons in that repo
- **Reviewer disagreement** (reviewer A says X, reviewer B says Y): Skip the conflicting pattern, or note both sides and let the user decide which to keep
