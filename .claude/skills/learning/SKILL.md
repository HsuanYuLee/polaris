---
name: learning
description: >
  Five modes: (1) External — researches URLs, repos, articles and analyzes applicability to
  our workspace. (2) PR — extracts review patterns from merged PRs into review-lessons.
  (3) Queue — processes daily learning queue articles in batch.
  (4) Setup — configure or update the daily learning scanner (RemoteTrigger).
  (5) Batch — scans a repo's full PR history, finds unextracted review comments, and
  batch-fills review-lessons. Automatically triggers graduation afterward.
  Trigger: "學習", "learn", "研究一下", "research this", "借鑑", "看看這個",
  "學習 PR", "learn from PR", "每日學習", "daily learning", "消化 queue",
  "digest queue", "learning queue", "設定學習", "learning setup", "更新學習主題",
  "掃 review", "batch learn", "批次學習", "掃歷史 PR", "scan PR history",
  "補齊 review lessons", "backfill lessons",
  or user shares a URL asking to analyze/evaluate it. Do NOT trigger
  for internal codebase exploration (use Explore subagent directly), JIRA ticket analysis (use
  work-on), or PR review (use review-pr for reviewing someone else's code — this skill
  is for LEARNING from already-merged PRs, not reviewing open ones).
metadata:
  author: Polaris
  version: 1.5.0
---

# learning

Five modes of learning:
- **External mode** — Research external content (articles, repos, talks) and distill actionable insights for our workspace
- **Queue mode** — Process articles from the daily learning queue, batch-analyze, and archive
- **PR mode** — Learn from merged PRs by extracting review patterns into review-lessons (feeds into the existing graduation mechanism)
- **Setup mode** — Configure or update the daily learning scanner schedule and topic preferences
- **Batch mode** — Scan a repo's full merged-PR history, skip already-extracted PRs, batch-extract review-lessons from the rest, then trigger graduation

> **首次使用？** 如果你還沒設定每日學習掃描，輸入 `設定學習` 或 `learning setup` 開始設定。設定後每天自動推薦文章到 Slack。

## Step 0: Mode Detection

Determine which mode based on the user's input:

| Signal | Mode | Example |
|---|---|---|
| PR number, PR URL, or mentions "PR" + "學習/learn" | **PR mode** | `學習 PR #123`, `learn from my-app 最近的 PR` |
| Mentions a person's PRs | **PR mode** | `學習 daniel 最近的 PR`, `研究 PR review` |
| Time-range + PR | **PR mode** | `學習最近一週 merge 的 PR` |
| External URL, repo, article | **External mode** | `看看這個 github.com/...`, `研究這篇文章` |
| Mentions "每日學習", "今天有什麼可以學的", "看看今天的推薦", "有新文章嗎", "讀文章", "daily learning", "queue", "消化", or bare "學習" without URL/PR context | **Queue mode** | `每日學習`, `今天有什麼可以學的`, `看看今天的推薦`, `有新文章嗎`, `讀文章` |
| Mentions "設定學習", "learning setup", "更新學習主題", "update learning topics", "scanner 設定", "調整掃描", "learning scanner" | **Setup mode** | `設定學習`, `learning setup`, `更新學習主題` |
| Mentions "掃 review", "batch learn", "批次學習", "掃歷史 PR", "scan PR history", "補齊 review lessons", "backfill lessons" | **Batch mode** | `掃 b2c-web 的 review`, `batch learn member-ci`, `補齊 review lessons` |
| Ambiguous | Ask the user | `學習一下` without context |

**PR mode** → jump to [PR Learning Flow](#pr-learning-flow)
**Batch mode** → jump to [Batch Learning Flow](#batch-learning-flow)
**Queue mode** → jump to [Queue Learning Flow](#queue-learning-flow)
**Setup mode** → jump to [Setup Learning Flow](#setup-learning-flow)
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

Spawn Researcher sub-agents (`model: "sonnet"`). Each sub-agent uses the **Researcher** role defined in `skills/references/sub-agent-roles.md` — read the Researcher section and include it in the sub-agent prompt.

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

When a recommendation targets the **Polaris framework itself** (skill flow, rule mechanism, config structure, interaction patterns) rather than company-specific business logic:

- **User confirms and executes now** → normal Step 5 execution + update `CHANGELOG.md` if significant
- **User says "worth tracking" / "之後再做" / defers** → append to `.claude/polaris-backlog.md` under the appropriate priority section:
  ```
  - [ ] **{title}** — {one-line description} — source: learning ({source URL})
  ```
- **User explicitly rejects** → don't add to backlog

## Meta: Role Discovery

When researching external content, watch for division-of-labor patterns that could map to a new sub-agent role. This is how the talent pool grows organically — external inspiration surfaces new specializations we haven't formalized yet.

**Detection**: During Step 4 (Synthesis), if a recommendation involves a type of sub-agent work that doesn't fit any role in `skills/references/sub-agent-roles.md`, flag it:

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

After executing confirmed changes in Step 5, append a row to `{base_dir}/README.md`'s Acknowledgements table:

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

Process articles from the daily learning queue delivered via Slack (sent by the scheduled `daily-learning-scan` agent). This mode batch-processes the latest queue message, presents unified recommendations, and archives processed items.

## Step Q1: Read Slack Queue and Filter

Search for the most recent daily learning queue message. Use `slack_search_public` with query `"📚 Daily Learning Queue"` to find the latest queue message (within 7 days).

If no queue message found within 7 days, tell the user "最近 7 天沒有 Daily Learning Queue 訊息，可能 scanner 還沒跑或發送失敗。可以用 `learning setup` 設定或重新啟用。" and stop.

Parse the article list from the Slack message (each `### N. {Title}` block contains URL, Category, Tags, Relevant Repos, Summary).

Show the user a summary of items with the Repos column:

```markdown
| # | Title | Category | Repos |
|---|-------|----------|-------|
| 1 | ... | ai-agent | my-skills-repo |
| 2 | ... | performance | my-app |
| 3 | ... | framework | all |
```

The user may filter by repo: "只看 b2c-web 相關的" → only process articles where `Relevant Repos` contains `my-app` or `all`. If no filter specified, process all.

Ask: "要全部處理，還是選幾篇？可以用 repo 篩選（如：只看 b2c-web 和 docker 相關的）"

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

2. **Archive ALL processed articles** (regardless of outcome) — append to `learning-archive.md` (local file for dedup):
   - Add a row to the table in `learning-archive.md`:
     ```
     | {today's date} | {title} | {url} | {result} | {one-line note} |
     ```
   - Result values: `applied` (recommendation executed), `noted` (interesting but deferred), `skipped` (not applicable)

## Step Q5: Summary

Report what was done:
- X articles processed
- Y recommendations applied (list them)
- Z articles archived

## Edge Cases (Queue Mode)

- **Article URL is dead or returns 404**: Mark as `skipped` with note "URL unavailable", archive it, move on
- **Article content is behind a paywall**: Same as External mode — tell the user, ask them to paste key content, or skip
- **User wants to skip specific articles without reading**: Allow it — mark as `skipped` with note "user skipped" and archive

---

# Setup Learning Flow

Configure or update the daily learning scanner — the scheduled agent that delivers article recommendations to Slack.

## Step S1: Check Existing Scanner

Use `RemoteTrigger list` to check for existing daily-learning-scan triggers (name contains `daily-learning-scan`).

If found and enabled:
```
目前已有 daily learning scanner：
- Trigger: {name} ({trigger_id})
- 排程: {cron_expression}
- 狀態: enabled

要更新設定還是停用？(更新 / 停用 / 取消)
```

- 更新 → continue to Step S2
- 停用 → `RemoteTrigger update` → `{"enabled": false}`, done
- 取消 → stop

If not found or disabled: continue to Step S2.

## Step S2: Collect Preferences

Auto-detect as much as possible, then let user confirm/adjust.

### 2a. Slack Channel (from workspace config)

Read the company workspace-config.yaml（使用 `skills/references/workspace-config-reader.md` 流程）to get `slack.channels.ai_notifications`.

If found: show the channel and confirm.
If not found: ask the user for channel ID or name. If user provides a name, use `slack_search_channels` to resolve to channel ID.

### 2b. Tech Stack (auto-detect first)

Read company workspace-config.yaml `projects` block. For each project, extract tech stack from `tags`, `keywords`, and `tech_stack` fields. Present the detected result:

```
從 workspace config 偵測到的技術棧：
  Nuxt 3, Vue 3, TypeScript, Vitest, Turborepo, Docker

要調整嗎？（直接 Enter 確認，或輸入修改版）
```

If no workspace config or no tags found: ask the user to input manually.

### 2c. Active Repos (auto-detect first)

From the same `projects` block, extract repo names and their tech stacks:

```
偵測到的 repos：
  my-app (Nuxt 3, SSR, TypeScript)
  my-api (Node, Express)
  web-design-system (Vue 3)

要調整嗎？（直接 Enter 確認，或輸入修改版）
```

### 2d. Custom Topics (optional)

```
有特別想關注的主題嗎？（選填）
例如：SSR performance, testing patterns, AI code review

直接輸入，或 Enter 跳過：
```

### 2e. Schedule

```
掃描排程？（預設：每天 21:57，cron: 57 13 * * *）
直接 Enter 用預設，或輸入自訂 cron expression：
```

## Step S3: Assemble Trigger Prompt

Read `skills/references/daily-learning-scan-spec.md` for the template structure.

Assemble the RemoteTrigger prompt by filling in user preferences:

1. **AI/Agent searches** (mandatory, always included):
   - `Claude Code tips tricks {year}`
   - `Claude Code MCP server tutorial`
   - `AI coding agent workflow patterns {year}`
   - `multi-agent orchestration LLM {year}`
   - `AI-assisted development best practices`

2. **Tech stack searches** (from Step S2a):
   - For each tech in the stack, generate 1-2 search queries
   - Example: if tech = "Nuxt", generate `Nuxt 4 performance optimization`, `Nuxt SSR best practices {year}`

3. **Custom topic searches** (from Step S2c, if provided)

4. **Repo tagging rules** (from Step S2b):
   - Build a topic → repos mapping table

5. **Channel ID** (from Step S2d) — hardcoded in prompt

6. **Dedup**: prompt reads `learning-archive.md` from repo (skip if not found)

The prompt must:
- Use `slack_send_message` to send to the channel
- Follow the Slack message format from the spec template
- NOT commit or push anything to git
- Include the full search queries (not just "read the spec")

## Step S4: Create RemoteTrigger

1. If updating: disable old trigger with `RemoteTrigger update` → `{"enabled": false}`
2. Determine the workspace repo URL (read from git remote)
3. Create new trigger:

```
RemoteTrigger create:
  name: daily-learning-scan-v{N}
  cron_expression: {from Step S2e}
  model: claude-sonnet-4-6
  allowed_tools: Read, Glob, Grep, WebSearch, WebFetch, mcp__claude_ai_Slack__slack_send_message
  sources: [{workspace_repo_url}]
  mcp_connections: [{connector_uuid: "Slack connector UUID", name: "Slack", url: "https://mcp.slack.com/mcp"}]
  prompt: {assembled prompt from Step S3}
```

**Slack connector 注意事項：**
- `mcp_connections` 必須包含 Slack connector，否則 remote agent 無法發送訊息
- Slack connector 需要使用者在 Anthropic 帳號中**至少授權過一次**。首次使用的使用者必須先手動授權：
  ```
  ⚠ 首次設定需要手動授權 Slack connector（只需一次）：

  1. 到 claude.ai/code/scheduled
  2. 找到剛建立的 daily-learning-scan trigger
  3. 點 Schedule 區塊 → Connectors → Add connector → 選 Slack
  4. 完成 OAuth 授權 → Save

  授權一次後，之後的 setup 都會自動帶上，不需要再手動設定。
  ```
- **永遠顯示此提示**（無論 trigger 建立是否成功帶上 `mcp_connections`），因為無法偵測使用者是否已授權過

4. Confirm trigger created, show trigger ID and next run time

## Step S5: Test Run (optional)

```
Scanner 已建立。要現在試跑一次嗎？(y/n)
```

If yes: `RemoteTrigger run` → tell user to check Slack for the queue message.

## Step S6: Summary

```
✅ Daily Learning Scanner 設定完成

- Trigger: {name} ({trigger_id})
- 排程: {cron_expression} ({human readable time})
- Slack Channel: {channel_name or ID}
- 技術棧: {tech stack}
- 自訂主題: {custom topics or "無"}

每天會自動掃描文章推薦到 Slack。
用 `每日學習` 消化推薦文章，用 `learning setup` 更新設定。
```

---

# PR Learning Flow

Learn from merged PRs by extracting review patterns into review-lessons. The value: knowledge that was exchanged in PR reviews (corrections, suggestions, pattern enforcement) gets systematically captured so the whole team benefits — not just the PR author and reviewer.

## Step P1: Resolve Target PRs

Determine which PRs to study based on the user's input:

| Input | How to resolve |
|---|---|
| Specific PR number (`PR #123`) | Direct: `gh pr view 123 --repo {org}/{repo}` |
| Specific PR URL | Extract owner/repo and number from URL |
| Person's PRs (`daniel 最近的 PR`) | `gh pr list --repo {org}/{repo} --state merged --author <github-username> --limit 10` |
| Time-range (`最近一週的 PR`) | `gh pr list --repo {org}/{repo} --state merged --search "merged:>YYYY-MM-DD" --limit 20` |
| Repo-specific (`my-app 最近的 PR`) | Target that repo specifically |
| No repo specified | Use the repo mapping from CLAUDE.md to infer, or ask the user |

**Filtering**: Only include PRs that have review comments (PRs with 0 review comments have nothing to learn from). Use `gh api repos/{org}/{repo}/pulls/<number>/reviews` to check.

**Cap**: Maximum 10 PRs per invocation. If the query returns more, take the 10 most recent and tell the user.

## Step P2: Extract Review Data

For each PR, collect:

1. **Review comments** — `gh api repos/{org}/{repo}/pulls/<number>/comments --paginate` (inline comments on specific lines)
2. **Review summaries** — `gh api repos/{org}/{repo}/pulls/<number>/reviews --paginate` (top-level review body with APPROVE/REQUEST_CHANGES)
3. **PR diff** — `gh pr diff <number> --repo {org}/{repo}` (to understand what was changed and how the fix addressed the review)

For **batch mode** (multiple PRs): spawn one sub-agent per PR (`model: "sonnet"`) to extract in parallel. Each sub-agent returns structured findings (see Step P3 format). Maximum 5 parallel sub-agents — if more than 5 PRs, process in batches.

Sub-agent prompt template:

```
You are analyzing a merged PR to extract learnable patterns from its review comments.

## PR Info
- Repo: {org}/{repo}
- PR: #<number>
- URL: https://github.com/{org}/{repo}/pull/<number>

## Your Task
1. Read the PR review comments: `gh api repos/{org}/{repo}/pulls/<number>/comments --paginate`
2. Read the review summaries: `gh api repos/{org}/{repo}/pulls/<number>/reviews --paginate`
3. Read the PR diff: `gh pr diff <number> --repo {org}/{repo}`
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
    "source_pr": "https://github.com/{org}/{repo}/pull/<number>",
    "source_date": "YYYY-MM-DD"
  }
]
If no learnable patterns found, return an empty array [].
```

## Step P3: Deduplicate Against Existing Knowledge

Before writing any lessons, load existing knowledge to avoid duplicates:

1. **Read all review-lesson files** in `{base_dir}/<repo>/.claude/rules/review-lessons/*.md`
2. **Read all main rule files** in `{base_dir}/<repo>/.claude/rules/*.md` (excluding `review-lessons/` subdirectory)
3. Also check `{base_dir}/.claude/rules/*.md` (workspace-level rules)

For each extracted pattern, compare against existing lessons and rules:
- **Semantically identical** (same rule, same reasoning) → skip, count as duplicate
- **Related but adds a new angle** (same topic, different aspect) → keep, will be appended to existing topic file
- **Entirely new** → keep, will create a new topic file or append to the closest existing one

## Step P4: Write Review Lessons

Write extracted patterns to `{base_dir}/<repo>/.claude/rules/review-lessons/` using the **exact same format** as `review-pr` Step 6.5:

**File naming**: Topic-based, kebab-case `.md` files (e.g., `typescript-type-safety.md`, `error-handling.md`). Append to existing files of the same topic — do not create a new file if one with the matching topic already exists.

**Entry format** (each top-level `- ` counts as 1 entry):

```markdown
# {Topic Title}

- {Rule description — clear, actionable, generalizable}
  - Why: {reasoning from the reviewer or inferred from the fix}
  - Source: https://github.com/{org}/{repo}/pull/<number> (YYYY-MM-DD)
```

When appending to an existing file, add new entries after the last existing entry (before EOF). Do not modify existing entries.

### Reverse Sync

寫入完成後，執行 reverse-sync 將 review-lessons 寫回 ai-config（source of truth）：

```bash
{base_dir}/polaris-sync.sh --reverse {project-name}
```

其中 `{project-name}` 從 repo 目錄名推導（例如 `kkday-b2c-web`）。

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

---

# Batch Learning Flow

Scan a repo's merged-PR history, automatically find PRs whose review comments haven't been extracted yet, batch-extract them into review-lessons, then trigger graduation. This is the "backfill" mode — it closes the gap when review-lessons weren't collected in real time (e.g., PRs fixed manually without `fix-pr-review`, or the repo was onboarded after months of existing PRs).

### Difference from PR mode

| | PR mode | Batch mode |
|---|---|---|
| **Who picks the PRs** | User specifies PR numbers, person, or time range | Automatic — all merged PRs with unextracted review comments |
| **Goal** | Study specific PRs for learning | Fill the review-lessons pipeline so graduation can fire |
| **Dedup** | Semantic only (Step P3) | Layer 1 (Source URL) + Layer 2 (semantic) |
| **Post-extraction** | Graduation check (count >= 15) | Graduation with Step 2.5 semantic grouping (always) |

## Step B1: Resolve Target Repos

Determine which repos to scan:

| Input | Resolution |
|---|---|
| Specific repo name (`掃 b2c-web 的 review`) | Target that repo |
| No repo specified | Read workspace config (`workspace-config.yaml` → `projects` block), scan all configured repos |
| Multiple repos (`掃所有 repo`) | Process each repo sequentially |

For each repo, resolve the `{org}/{repo}` from workspace config or git remote.

### Time Range

Default: **3 months** (`merged:>YYYY-MM-DD` where date = today - 90 days).

The user can override: `掃 b2c-web 最近半年` → 6 months. Cap at 12 months to avoid excessive API calls.

## Step B2: Collect Already-Extracted Source PRs

For each repo, read all files in `{base_dir}/<repo>/.claude/rules/review-lessons/*.md`.

Extract every `Source:` line and collect all PR URLs/numbers into a set. These are the PRs that have already been processed — they will be skipped entirely (Layer 1 dedup).

## Step B3: Find Candidate PRs

Query merged PRs within the time range. Two passes to cover both authored and reviewed PRs:

1. **Authored by the user**: `gh search prs --repo {org}/{repo} --author @me --state closed --merged --limit 30 --json number,title,url,closedAt`
2. **Reviewed by the user**: `gh search prs --repo {org}/{repo} --reviewed-by @me --state closed --merged --limit 20 --json number,title,url,closedAt`

Merge both lists (deduplicate by PR number). Remove any PR already in the Layer 1 set from Step B2.

**Cap**: 30 PRs per repo. If more remain after dedup, take the 30 most recent and inform the user.

## Step B4: Filter PRs With Review Comments

For each candidate PR, check if it has qualifying review comments:

```
gh api repos/{org}/{repo}/pulls/{number}/comments --paginate
```

Filter out:
- Comments by the PR author
- Bot comments (changeset-bot, codecov-commenter, GitHub Actions)
- Keep: human reviewer comments and code review bots (Copilot, CodeRabbit)

If 0 qualifying comments after filtering → skip, no lesson to extract.

Report progress: `掃描中... {N}/{total} PRs 有可萃取的 review comments`

## Step B5: Batch Extract

For PRs with qualifying comments, spawn sub-agents to extract in parallel. Reuse the exact same sub-agent prompt from PR mode Step P2, with the same extraction criteria (what to extract / what to skip).

**Parallelism**: maximum 5 sub-agents at a time. If more than 5 PRs, process in batches of 5.

Each sub-agent:
1. Reads review comments + review summaries
2. Extracts generalizable patterns
3. Returns structured JSON (same format as PR mode)

## Step B6: Deduplicate & Write

Collect all extracted patterns from all sub-agents.

**Layer 2 dedup** (same as PR mode Step P3):
- Compare against existing review-lessons
- Compare against main rule files
- Skip semantically identical patterns
- Append new angles to existing topic files

Write to `{base_dir}/<repo>/.claude/rules/review-lessons/` using the same format as PR mode Step P4.

### Reverse Sync

```bash
{base_dir}/polaris-sync.sh --reverse {project-name}
```

## Step B7: Summary & Graduation

### Summary output

```markdown
## Batch 學習摘要 — {repo}

**掃描範圍**：最近 {N} 個月 merged PRs
**候選 PR**：{total found} 個（已萃取 {skipped} 個跳過 → 實際掃描 {scanned} 個）
**有 review comments**：{with_comments} 個
**新增 lessons**：{new_count} 條

### 新增明細
| Topic | Rule | Source PR |
|-------|------|-----------|
| ... | ... | #123 |

### 跳過的 PR（已在 review-lessons 中）
{count} 個 — Layer 1 dedup
```

### Auto-trigger graduation

Batch mode always triggers graduation after extraction (unlike PR mode which only checks the count threshold). The rationale: batch mode is specifically designed to fill the pipeline, so graduation should run immediately to maximize the yield.

```
Invoke review-lessons-graduation for {repo} (manual trigger — includes Step 2.5 semantic grouping).
```

If scanning multiple repos, trigger graduation for each repo after its extraction completes.

## Edge Cases (Batch Mode)

- **No unextracted PRs found**: Report "所有 merged PRs 的 review comments 都已萃取完畢，{repo} 的 review-lessons 管線是完整的。" and skip graduation
- **Rate limiting**: If `gh api` hits rate limits, pause and retry with exponential backoff. Report to user if wait exceeds 30 seconds
- **Large repos (> 100 merged PRs in range)**: The 30-PR cap applies. Tell the user: "共 {N} 個未萃取的 PR，本次掃描前 30 個。再跑一次 `batch learn {repo}` 可以繼續處理剩餘的。"
- **Mixed repos**: If scanning all configured repos, report per-repo summaries and a final aggregate
