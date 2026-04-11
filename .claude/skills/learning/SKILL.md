---
name: learning
description: "Use when the user wants to learn from external resources (URLs, repos, articles), extract patterns from merged PRs, process a learning queue, configure the daily learning scanner, or backfill review lessons. Trigger: '學習', 'learn', '研究', 'deep dive', '學習 PR', '每日學習', 'daily learning', '設定學習', '批次學習', '掃歷史 PR', or when user shares a URL to analyze."
metadata:
  author: Polaris
  version: 3.0.0
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
| Mentions "掃 review", "batch learn", "批次學習", "掃歷史 PR", "scan PR history", "補齊 review lessons", "backfill lessons" | **Batch mode** | `掃 your-app 的 review`, `batch learn your-backend`, `補齊 review lessons` |
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
| User mentions a specific project name ("用在 b2c", "your-backend 可以學") | `project:{name}` | project rules, code patterns, project CLAUDE.md |
| User is on a project branch | `project:{name}` (inferred) | same as above |
| Content is about a specific tech stack (Nuxt, Vue, testing) without framework mention | `project` (ask which project) | same as above |
| Ambiguous | Ask: "這個學習要用在 Polaris 框架，還是特定產品 repo？" | — |

The target determines which gap sources to scan (Step 1.5) and where recommendations land (Step 5).

## Step 1.1: Security Pre-Scan (GitHub repos only)

When the input is a **GitHub repo** that contains skill files (`.claude/skills/`, `SKILL.md`, or `skills/` directory), run `scripts/skill-sanitizer.py` before proceeding to exploration.

### Trigger condition

After Step 1 identifies the input as a GitHub repo, check if it contains skill-related files:

```bash
gh api repos/{org}/{repo}/contents/.claude/skills --jq '.[].name' 2>/dev/null
gh api repos/{org}/{repo}/contents/ --jq '.[].name' 2>/dev/null | grep -i skill
```

If skill files exist → run the pre-scan. If no skill files → skip to Step 1.5.

### Scan process

1. **Fetch SKILL.md files** from the repo (use `gh api` to get content, base64 decode)
2. **Pipe each file** through the sanitizer:
   ```bash
   echo "$content" | python3 /Users/hsuanyu.lee/work/scripts/skill-sanitizer.py scan "$skill_name"
   ```
3. **Report results** to the user:

If all CLEAN/LOW/MEDIUM:
```
🔒 Security pre-scan: {N} skill files scanned — no high-risk findings. Proceeding.
```

If any HIGH/CRITICAL:
```
⚠️ Security pre-scan found high-risk patterns:

| Skill | Risk | Findings |
|-------|------|----------|
| {name} | HIGH | telemetry_pipeline (x3), eval_subshell (x2) |

This repo contains potentially dangerous skill content.
Continue learning? (y/n — learning will analyze patterns only, not install anything)
```

4. **User decides**: if user says yes → continue but add a `⚠️ Security Note` section to the final report. If no → stop.

### Why pre-LLM matters

By the time skill content enters the LLM context window, prompt injection or instruction override patterns could alter the agent's behavior. Scanning first means we can flag risks before they have any effect.

### Skip conditions

- Input is an article/blog URL → skip (no executable skill content)
- Input is a local file → skip (user's own content)
- Input is a text description → skip
- Repo has no skill files → skip

## Step 1.5: Baseline Scan — Know Where We Stand

Before exploring external content, scan our current state as a **comparison baseline** (not as an exploration filter). The scan results are used in Step 4 (Synthesis) to distinguish "known gap confirmed" from "new discovery", not to narrow the exploration.

> **v3 重要改動**：v2 用 gap scan 引導探索方向（「帶著問題去看」），結果會錯過 unknown unknowns。v3 改為先全面理解外部內容，再拿 baseline 比對。探索階段不帶預設。

### Accumulated learnings (both targets)

Query existing cross-session learnings related to the topic being studied:

```bash
POLARIS_WORKSPACE_ROOT={workspace_root} polaris-learnings.sh query --top 10 --min-confidence 3
```

Filter results by relevance to the external content's domain (e.g., if studying SSR patterns, pull learnings with keys matching SSR/rendering/hydration). These become the **knowledge baseline** — what we already know about this topic from prior sessions.

This is the most important baseline source: it captures what we've **already learned and validated**. Without it, each learning session starts from zero and may re-discover known insights or miss contradictions with prior knowledge.

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

Output: a **baseline snapshot** — our current state organized by category, used for comparison in Step 4. Example:

```
Baseline Snapshot (framework target):
  Prior learnings (from polaris-learnings.sh):
    - [pattern] sub-agent completion envelope prevents silent failures (confidence: 8)
    - [pitfall] worktree path translation missed in 2 sessions (confidence: 6)
  Delegation: self-regulation scoring, worktree isolation, model tiers
  Quality gates: dev-quality-check, verify-completion iron rule, re-test-after-fix
  Feedback loop: post-task reflection, graduation pipeline, mechanism registry
  Known gaps: context monitor hook (blocked), wave-based parallel (backlog)
```

```
Baseline Snapshot (project target: your-app):
  Prior learnings (from polaris-learnings.sh):
    - [architecture] Nuxt useHead runs at setup time, not render time (confidence: 7)
    - [pitfall] useSchemaOrg requires nuxt-schema-org plugin registered (confidence: 9)
  Composables: useProduct, useCart, useAuth — setup-only constraint
  SSR: defineCachedEventHandler, Nitro routes
  Testing: Vitest + coverage-v8, component + unit
  Known gaps: E2E coverage (backlog), composable lifecycle docs (review-lessons)
```

This snapshot is NOT used to guide exploration (Step 2-3). It is used in Step 4 to compare findings against our current state.

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
- **Discovery-first**: note what's different or novel, not just what matches known gaps

**Deep** — multi-round, up to 3 Researchers per round:
- Round 1: Structure scan — build a comprehensive map
- Round 2: Selective deep-dives guided by **novelty/unknown signals** from Round 1
- Round 3: Compare findings against Step 1.5 baseline

## Step 3: Research

### Quick path

Read the content yourself. Extract core concepts, notable techniques, and applicability assessment. Skip to Step 4.

### Standard path

Research the content **without filtering by known gaps**. Explore broadly, noting everything that's interesting, novel, or different from how we work. The Step 1.5 baseline is used later in Step 4 for comparison — not here for filtering.

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

**Round 2: Selective deep-dives** (up to 3 parallel Researcher sub-agents)

Based on Round 1 findings, dispatch Researchers to areas with **novelty or unknown signals** — things that look different from how we work, or concepts we don't have at all:

```
Researcher A: {area where their approach differs most from ours}
Researcher B: {concept/mechanism we have no equivalent for}
Researcher C: {area that seems sophisticated — worth understanding why}
```

**Deep-dive signal priority:**
1. 「我們沒有對應概念」(unknown) → highest priority, always deep-dive
2. 「做法明顯不同」(novelty) → deep-dive to understand the tradeoff
3. 「做法類似但更成熟」(refinement) → deep-dive if time allows

Each Researcher reads 3-5 files in their area and extracts findings using the target-specific categories above.

**Round 3: Compare against baseline** (Strategist, no sub-agent)

Merge Round 1+2 findings. For each finding, compare against the Step 1.5 baseline snapshot:

- **Known gap confirmed** → finding addresses an item already in baseline snapshot. Mark: `✅ confirms: {baseline item}`
- **New discovery** → finding reveals something not in our baseline at all (unknown unknown). Mark: `🔍 new: {description}`
- **Refinement** → we have the concept but their approach is more mature. Mark: `📈 refines: {our current approach}`
- **Not applicable** → interesting but doesn't fit our context. Mark: `⏭️ skip: {reason}`

Also map each finding to which specific file in our workspace it would modify, and check backlog for duplicates.

## Step 4: Synthesis — Connect to Our Workspace

### 4a. Comparison Matrix

```markdown
| Aspect | External Approach | Our Current State | Gap / Opportunity | Discovery Type |
|--------|------------------|-------------------|-------------------|---------------|
| ... | ... | ... | ... | ✅ confirms / 🔍 new / 📈 refines / ⏭️ skip |
```

The **Discovery Type** column (from Round 3 classification) makes it immediately clear which findings are **new discoveries (unknown unknowns)** vs confirmations of known gaps. Present `🔍 new` items first — these are the highest-value output of the discovery-first approach.

To fill "Our Current State" accurately: read relevant workspace files rather than relying on memory. Spawn an Explore subagent if needed.

### 4b. Compile — Collide With Accumulated Knowledge

Cross-reference findings against the **prior learnings** from the Step 1.5 baseline. For each finding, determine its relationship to what we already know:

| Relationship | Signal | Action |
|---|---|---|
| **Confirm** | Finding validates an existing learning | `polaris-learnings.sh confirm --key {key}` to reset decay and optionally `--boost 1` |
| **Contradict** | Finding conflicts with an existing learning | Flag explicitly in the matrix. Present both sides to user — this is high-value signal |
| **Extend** | Finding adds depth or nuance to an existing learning | Update the learning via `polaris-learnings.sh add` (merge mode) with enriched content |
| **New** | Finding covers a topic with no prior learning | Candidate for a new learning entry (written in Step 5 if user confirms) |

**Why this matters**: without this step, each `/learning` session is independent. With it, knowledge compounds — confirmations strengthen confidence, contradictions surface errors, extensions deepen understanding.

Present the compile results as a section in the synthesis:

```markdown
### Knowledge Compile Results
- ✅ Confirmed: {learning key} — "{finding}" validates this
- ⚠️ Contradicts: {learning key} — prior: "{old}", new: "{finding}". Which is correct?
- 📈 Extends: {learning key} — adds: "{new nuance}"
- 🆕 New: "{finding}" — no prior knowledge on this topic
```

### 4c. Backlog cross-reference

Before generating recommendations, check `polaris-backlog.md` (framework target) or project issue tracker (project target) for existing items that match:

- **Existing item found** → mark recommendation as "validates existing: {backlog item title}" — this confirms direction, doesn't duplicate
- **No existing item** → new recommendation

### 4d. Recommendations

For each gap/opportunity:

```markdown
### Recommendation: {title}

**What**: One-sentence description
**Why**: Problem solved or improvement
**How**: Concrete actions (files to create/modify, patterns to adopt)
**Landing**: {target-specific: e.g., "rules/sub-agent-delegation.md § Safety Hooks" or "your-app composables/useProduct.ts"}
**Effort**: Low / Medium / High
**Priority**: Worth doing now / Nice to have / Worth tracking
**Validates**: {backlog item title, if applicable}
```

Be honest about what's NOT worth borrowing. Explicitly call out things that look cool but don't fit.

### 4e. Present to User

Present the lens match summary, comparison matrix, knowledge compile results, and recommendations. Wait for user reaction.

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

## Meta: Dispatch Pattern Discovery

During Step 4, watch for division-of-labor patterns that could become new **specialized protocols** (multi-step interaction patterns worth standardizing). Only flag when the pattern has a distinct protocol — not just "another sub-agent that reads/writes":

```markdown
🎭 **Potential new protocol: {Name}**
- Protocol: {multi-round? challenge loop? structured return format?}
- Model: sonnet / haiku
- Would be used by: {which skills}
```

See `skills/references/sub-agent-roles.md` § Specialized Protocols for existing examples (QA Challenger, Architect Challenger, Critic).

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
- **User just wants a summary**: Skip Step 4b-4e, present research findings only
- **Repo has no README or sparse docs**: Escalate to Deep mode automatically — read source files directly
- **External approach conflicts with our conventions**: Note the conflict explicitly, recommend only if the external approach is demonstrably better with evidence

## Step 6: Lint — What Should We Learn Next?

After executing recommendations (or saving them), analyze the **combined knowledge landscape** — prior learnings + new findings — to identify gaps and suggest future learning directions. This is the "看得更廣" step.

### 6a. Knowledge Gap Analysis

Review the full set of learnings (`polaris-learnings.sh list`) plus the findings from this session. Look for:

| Gap type | Signal | Example |
|---|---|---|
| **Adjacent unknown** | New finding references a concept we have no learnings about | Learned about SSR caching, but no learnings about hydration mismatch |
| **Stale knowledge** | Existing learning has low effective confidence (decayed) in an area the new finding touches | Learning about Nuxt 2 middleware pattern, but we're now on Nuxt 3 |
| **Contradiction unresolved** | Step 4b flagged a contradiction but user deferred resolution | Two learnings disagree on whether `useHead` runs at setup or render time |
| **Depth gap** | We have surface-level knowledge (1-2 learnings) in an area that now appears critical | Only 1 learning about JSON-LD, but we're now working on structured data across 3 Epics |

### 6b. Suggest Next Reads

Based on the gap analysis, generate 1-3 concrete suggestions:

```markdown
### 🔭 Suggested Next Learning

1. **{Topic}** — {why this gap matters now}
   - Suggested source: {URL, repo, or search query}
   - Priority: {High / Medium / Low} based on active work relevance

2. ...
```

**Constraints:**
- Only suggest if gaps are real and connected to active work (not academic completionism)
- Max 3 suggestions — quality over quantity
- If no meaningful gaps are found, say so explicitly: "目前知識覆蓋完整，沒有明顯盲點"
- Suggestions are informational only — do not auto-execute or add to any queue

### 6c. Write Learnings

For each **New** item from Step 4b that was confirmed or executed by the user, write a cross-session learning:

```bash
polaris-learnings.sh add --key "{key}" --type {type} \
  --content "{actionable insight}" --confidence {N} --source "learning: {URL}"
```

For each **Confirm** item, refresh the existing learning:

```bash
polaris-learnings.sh confirm --key "{key}" --boost 1
```

For each **Extend** item, merge updated content:

```bash
polaris-learnings.sh add --key "{key}" --type {type} \
  --content "{enriched content}" --confidence {N} --source "learning: {URL}"
```

This step ensures every learning session leaves a trace in the knowledge base, enabling future sessions to build on it.

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

The user may filter by repo: "只看 your-app 相關的" → only process articles where `Relevant Repos` contains `my-app` or `all`. If no filter specified, process all.

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
  your-design-system (Vue 3)

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

Sub-agent prompt, dedup logic, write format, and reverse sync are defined in `@reference review-lesson-extraction.md`. Use that reference for Steps P2–P4.

## Step P3: Deduplicate Against Existing Knowledge

Follow `review-lesson-extraction.md` § Deduplication Logic.

## Step P4: Write Review Lessons

Follow `review-lesson-extraction.md` § Write Format + § Reverse Sync.

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

Follow `review-lesson-extraction.md` § Graduation Check (PR mode: threshold >= 15).

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
| Specific repo name (`掃 your-app 的 review`) | Target that repo |
| No repo specified | Read workspace config (`workspace-config.yaml` → `projects` block), scan all configured repos |
| Multiple repos (`掃所有 repo`) | Process each repo sequentially |

For each repo, resolve the `{org}/{repo}` from workspace config or git remote.

### Time Range

Default: **3 months** (`merged:>YYYY-MM-DD` where date = today - 90 days).

The user can override: `掃 your-app 最近半年` → 6 months. Cap at 12 months to avoid excessive API calls.

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

For PRs with qualifying comments, spawn sub-agents to extract in parallel. Use the sub-agent prompt from `@reference review-lesson-extraction.md` § Sub-agent Prompt Template.

**Parallelism**: maximum 5 sub-agents at a time. If more than 5 PRs, process in batches of 5.

## Step B6: Deduplicate & Write

Collect all extracted patterns from all sub-agents. Follow `review-lesson-extraction.md` § Deduplication Logic + § Write Format + § Reverse Sync.

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

Follow `review-lesson-extraction.md` § Graduation Check (Batch mode: always trigger). If scanning multiple repos, trigger graduation for each repo after its extraction completes.

## Edge Cases (Batch Mode)

- **No unextracted PRs found**: Report "所有 merged PRs 的 review comments 都已萃取完畢，{repo} 的 review-lessons 管線是完整的。" and skip graduation
- **Rate limiting**: If `gh api` hits rate limits, pause and retry with exponential backoff. Report to user if wait exceeds 30 seconds
- **Large repos (> 100 merged PRs in range)**: The 30-PR cap applies. Tell the user: "共 {N} 個未萃取的 PR，本次掃描前 30 個。再跑一次 `batch learn {repo}` 可以繼續處理剩餘的。"
- **Mixed repos**: If scanning all configured repos, report per-repo summaries and a final aggregate


## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
