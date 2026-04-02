---
name: learning
description: >
  Five modes: (1) External — gap-driven deep exploration of URLs, repos, articles with
  dual-target support (framework or product project). Three depth tiers (Quick/Standard/Deep),
  gap pre-scan before exploration, and Polaris-specific extraction categories.
  (2) PR — extracts review patterns from merged PRs into review-lessons.
  (3) Queue — processes daily learning queue articles in batch.
  (4) Setup — configure or update the daily learning scanner (RemoteTrigger).
  (5) Batch — scans a repo's full PR history, finds unextracted review comments, and
  batch-fills review-lessons. Automatically triggers graduation afterward.
  Trigger: "學習", "learn", "研究一下", "research this", "借鑑", "看看這個",
  "深入學", "deep dive", "像 gstack 那樣學", "全面研究",
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
  version: 2.0.0
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

## Step 1: Understand the Input + Detect Target

Identify what the user shared and classify the input type:

| Input Type | How to Access | Example |
|---|---|---|
| GitHub repo URL | WebFetch README, then `gh` CLI for structure | `github.com/org/repo` |
| Article / Blog URL | WebFetch | tech blog, Medium, dev.to |
| Local file | Read tool | PDF, markdown, code file |
| Text description | Already in conversation | user describes a pattern verbally |
| Video / Talk | Ask user for key takeaways (can't watch videos) | YouTube, conference talk |

For URLs that fail to fetch: tell the user and ask them to paste the key content directly.

### Target detection

Determine whether learnings should land in the **framework** or a **product project**:

| Signal | Target | Landing zone |
|---|---|---|
| User mentions "Polaris", "框架", "機制", or content is about AI agent patterns | `framework` | rules/, skills/, scripts/, polaris-backlog.md |
| User mentions a specific project name ("用在 b2c", "member-ci 可以學") | `project:{name}` | project rules, code patterns, project CLAUDE.md |
| User is on a project branch | `project:{name}` (inferred) | same as above |
| Content is about a specific tech stack (Nuxt, Vue, testing) without framework mention | `project` (ask which project) | same as above |
| Ambiguous | Ask: "這個學習要用在 Polaris 框架，還是特定產品 repo？" | — |

The target determines which gap sources to scan (Step 1.5) and where recommendations land (Step 5).

## Step 1.5: Gap Pre-Scan — Know What We're Looking For

Before exploring external content, scan our own gaps to give the exploration direction. This is the key difference from v1 — **explore with questions, not just curiosity**.

### Framework target gaps

| Source | What to extract | How |
|---|---|---|
| `polaris-backlog.md` | Open items — these are known improvement candidates | Read, extract unchecked `- [ ]` items |
| `mechanism-registry.md` | High-drift mechanisms — areas where rules are frequently violated | Read, filter by `Drift: High` |
| Recent feedback memories | Pain points from daily usage | Scan MEMORY.md for `type: feedback` entries from last 14 days |

### Project target gaps

| Source | What to extract | How |
|---|---|---|
| Project `.claude/rules/review-lessons/` | Recurring review patterns — things reviewers keep flagging | Read lesson files, look for high-source-count entries |
| Recent PR review comments | Patterns reviewers catch | `gh pr list --state merged --limit 5` → read review comments |
| Project CLAUDE.md | Known conventions and pain points | Read the project's AI operating manual |
| Test coverage gaps | Areas with low coverage | Read coverage config if available |

Output: a **lens list** — 5-10 specific questions/topics to look for during exploration. Example:

```
Gap Pre-Scan Results (framework target):
  1. Sub-agent safety enforcement (backlog: PreToolUse hooks) ✅ done
  2. Context window monitoring (backlog: PostToolUse hook) — blocked by platform
  3. Review-lesson semantic dedup (backlog: entry consolidation)
  4. PR description language detection (backlog: default_language config)
  5. Feedback: sub-agents sometimes modify files outside scope
```

This list guides Step 2-3 exploration — look for how the external source addresses these specific gaps.

## Step 2: Depth Assessment

### Depth tiers

| Tier | Trigger | Exploration scope | Time |
|------|---------|-------------------|------|
| **Quick** | "快速看一下", article/blog, small tool | README only, single-agent | ~5 min |
| **Standard** | Default for repos, no depth signal | README + key configs + 2-3 source files, single or multi-agent | ~15 min |
| **Deep** | "深入學", "像 gstack 那樣", "全面研究", large framework repo, or user explicitly asks | Multi-round, multi-agent, comprehensive scan | ~30 min |

Auto-escalate to Deep when: repo has its own `.claude/`, `CLAUDE.md`, `rules/`, or `hooks/` directory (signals a structured AI framework worth deep-diving).

### Scope decision (Standard/Deep)

**Standard** — single-agent or up to 2 Researchers:
- README + directory structure overview
- 2-3 key files identified from structure
- Compare against lens list from Step 1.5

**Deep** — multi-round, up to 3 Researchers per round:
- Round 1: Structure scan (see below)
- Round 2: Targeted deep-dives guided by lens list
- Round 3: Cross-reference with our workspace

## Step 3: Research

### Quick path

Read the content yourself. Extract core concepts, notable techniques, and applicability assessment. Skip to Step 4.

### Standard path

Research the content with focus on the lens list from Step 1.5. For each gap in the lens list, actively look for how the external source addresses it (or doesn't).

Extract using **target-specific categories**:

**Framework target categories:**

| Category | Maps to | Look for |
|---|---|---|
| Rules & mechanisms | `rules/*.md`, `mechanism-registry.md` | Behavioral constraints, enforcement patterns, canary signals |
| Skill patterns | `skills/` | Workflow design, step sequencing, error handling |
| Delegation strategies | `sub-agent-delegation.md` | Task splitting, model selection, isolation patterns |
| Quality enforcement | `verify-completion`, `dev-quality-check` | Verification gates, test requirements, anti-patterns |
| Scripts & automation | `scripts/` | Deterministic logic, hook scripts, CLI tools |
| Context management | `context-monitoring.md` | Window management, compression strategies, state preservation |

**Project target categories:**

| Category | Maps to | Look for |
|---|---|---|
| Code patterns | Source code conventions | Component structure, state management, error handling |
| Testing strategies | Test files, coverage config | Mock patterns, integration tests, fixture management |
| Performance | Build config, SSR setup | Bundle optimization, caching, lazy loading |
| Architecture | Directory structure, module boundaries | Feature organization, shared utilities, API design |
| DX tooling | Config files, scripts | Dev server, linting, formatting, CI pipeline |

### Deep path — Multi-round exploration

**Round 1: Structure scan** (1 Researcher sub-agent, `model: "sonnet"`)

Explore the repo's overall structure:
- README (full read)
- Directory listing (top 2 levels)
- Key config files: `CLAUDE.md`, `.claude/rules/`, `package.json`, `tsconfig.json`, hooks, scripts
- Identify 5-8 "interesting areas" — files or directories that likely contain the deepest insights

**Round 2: Targeted deep-dives** (up to 3 parallel Researcher sub-agents)

Based on Round 1 findings + lens list from Step 1.5, dispatch Researchers to specific areas:

```
Researcher A: {area aligned with gap #1 from lens list}
Researcher B: {area aligned with gap #2 from lens list}
Researcher C: {most unique/novel aspect of the repo}
```

Each Researcher reads 3-5 files in their area and extracts findings using the target-specific categories above.

**Round 3: Cross-reference** (Strategist, no sub-agent)

Merge Round 1+2 findings. For each finding, explicitly map to:
- Which lens list gap it addresses (or "new insight — not in our gap list")
- Which specific file in our workspace it would modify
- Whether we already have something similar (check backlog for duplicates)

## Step 4: Synthesis — Connect to Our Workspace

### 4a. Comparison Matrix

```markdown
| Aspect | External Approach | Our Current State | Gap / Opportunity | Lens Match |
|--------|------------------|-------------------|-------------------|------------|
| ... | ... | ... | ... | Gap #N or "new" |
```

The **Lens Match** column connects each finding back to the gap pre-scan, making it clear which items address known problems vs. surface new ideas.

To fill "Our Current State" accurately: read relevant workspace files rather than relying on memory. Spawn an Explore subagent if needed.

### 4b. Backlog cross-reference

Before generating recommendations, check `polaris-backlog.md` (framework target) or project issue tracker (project target) for existing items that match:

- **Existing item found** → mark recommendation as "validates existing: {backlog item title}" — this confirms direction, doesn't duplicate
- **No existing item** → new recommendation

### 4c. Recommendations

For each gap/opportunity:

```markdown
### Recommendation: {title}

**What**: One-sentence description
**Why**: Problem solved or improvement
**How**: Concrete actions (files to create/modify, patterns to adopt)
**Landing**: {target-specific: e.g., "rules/sub-agent-delegation.md § Safety Hooks" or "b2c-web composables/useProduct.ts"}
**Effort**: Low / Medium / High
**Priority**: Worth doing now / Nice to have / Worth tracking
**Validates**: {backlog item title, if applicable}
```

Be honest about what's NOT worth borrowing. Explicitly call out things that look cool but don't fit.

### 4d. Present to User

Present the lens match summary, comparison matrix, and recommendations. Wait for user reaction.

## Step 5: Execute (Only After User Confirmation)

| User says | Action |
|---|---|
| Confirms specific recommendations | Execute changes per target landing zone |
| Wants to discuss further | Refine recommendations |
| Save for later | Save a project or reference memory |
| "Worth tracking" / defers | Route to appropriate backlog (see below) |
| Disagrees | Acknowledge, adjust, don't push |

### Backlog routing by target

| Target | Backlog location | Format |
|---|---|---|
| `framework` | `.claude/polaris-backlog.md` | `- [ ] **{title}** — {description} — source: learning ({URL})` |
| `project:{name}` | Project issue tracker or project-level backlog | Create JIRA ticket or project TODO |

### Execution conventions

- Framework changes: use `/skill-creator` for skills, edit rules directly, use `skills/references/` for docs
- Project changes: follow project conventions (CLAUDE.md, coding standards, PR workflow)

## Meta: Role Discovery

During Step 4, watch for division-of-labor patterns that map to new sub-agent roles. If a recommendation involves sub-agent work that doesn't fit any role in `skills/references/sub-agent-roles.md`, flag it:

```markdown
🎭 **Potential new role: {RoleName}**
- Does: {what this role would do}
- Model: sonnet / haiku
- Would be used by: {which skills}
```

Only flag when clearly distinct from existing roles. Don't force it.

## Meta: Attribution

When learning leads to **actual workspace changes** (Step 5), credit the source in `README.md`'s Acknowledgements table.

**Trigger**: source is a GitHub repo or named OSS project, at least one recommendation was executed, project not already listed.

```markdown
| [{project name}]({url}) | {author} | {one-line: what we learned / adopted} |
```

Articles and blog posts don't get table entries — too granular. Update existing entries if new insights were adopted later from the same source.

## Edge Cases (External Mode)

- **Content behind paywall/login**: Ask user to paste key sections
- **Non-English content**: Best effort, flag uncertainty
- **Very large repo**: Deep mode handles this via multi-round. If Quick/Standard, focus on README + user-specified aspect
- **Outdated/deprecated content**: Note in analysis — old patterns may be superseded
- **User just wants a summary**: Skip Step 4b-4d, present research findings only
- **Repo has no README or sparse docs**: Escalate to Deep mode automatically — read source files directly
- **External approach conflicts with our conventions**: Note the conflict explicitly, recommend only if the external approach is demonstrably better with evidence

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
