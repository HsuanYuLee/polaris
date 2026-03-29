# Polaris

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) workspace template that turns your AI assistant into a strategist — it learns your team's workflow, routes tasks to specialized skills, and evolves its own rules from daily usage.

> **中文使用者：** [中文快速上手指南](docs/quick-start-zh.md)

## Who is this for?

- **Developers** — automate the JIRA → branch → code → PR loop, enforce team conventions through AI
- **Tech leads** — standardize estimation, code review, and sprint planning across the team
- **PMs and Scrum Masters** — generate standups, track worklogs, run sprint planning — no coding required
- **Multi-company freelancers** — manage multiple clients in one workspace with isolated rules, skills, and config

> Not sure? If your team uses JIRA + GitHub and you want Claude Code to follow your workflow instead of improvising, Polaris is for you.

## What does this actually do?

You tell Claude Code what you want. Polaris figures out how to get there.

```
You:     "work on PROJ-123"
Polaris: reads JIRA ticket → checks prerequisites → estimates story points
         → breaks into sub-tasks → creates JIRA sub-tickets
         → opens feature branch → implements code → runs tests
         → opens PR with coverage report → transitions JIRA to CODE REVIEW
```

PMs and Scrum Masters get their own workflows too:

```
You:     "standup"
Polaris: collects JIRA activity + calendar meetings → formats standup report
         → posts to Confluence

You:     "sprint planning"
Polaris: pulls JIRA backlog → calculates team capacity → detects carry-overs
         → suggests priority order → drafts Release page
```

It does this through **skills** (reusable workflows) and **rules** (accumulated team knowledge):

Skills are pre-built workflows you invoke by name or natural language:

| Category | Skills | What they automate | Who uses it |
|----------|--------|--------------------|-------------|
| **Plan** | `refinement`, `scope-challenge`, `sprint-planning` | Requirement analysis, estimation, sprint capacity | PM, Tech Lead, Dev |
| **Operate** | `standup`, `worklog-report`, `jira-worklog` | Daily reports, time tracking | Everyone |
| **Build** | `work-on`, `fix-bug`, `epic-breakdown`, `tdd` | JIRA → branch → code → PR, end-to-end | Dev |
| **Review** | `review-pr`, `review-inbox`, `fix-pr-review` | Code review, batch PR scanning, addressing feedback | Dev |
| **Quality** | `dev-quality-check`, `verify-completion`, `unit-test` | Tests, coverage, behavioral verification | Dev |
| **Learn** | `learning`, `review-lessons-graduation` | Study external resources, graduate patterns into rules | Everyone |

## What is Claude Code?

[Claude Code](https://docs.anthropic.com/en/docs/claude-code) is Anthropic's coding agent — it runs in your terminal, IDE (VS Code / JetBrains), or as a desktop app. You chat with it, and it reads files, writes code, runs commands, and calls external services. Polaris is a workspace template that sits on top of Claude Code, giving it your team's skills and rules.

> If you've used Claude on claude.ai, Claude Code is the same AI but with access to your codebase and tools. Polaris teaches it your team's specific workflow.

## Prerequisites

**Everyone needs:**
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** — CLI, desktop app, or IDE extension. Requires a Claude Pro, Team, or Enterprise plan

> **Important:** Most Polaris skills use sub-agents, which require the **Max plan** ($100/mo) or API access. On Pro/Team plans, only single-step skills will work.
- **Atlassian MCP** — connects Claude Code to JIRA and Confluence
- **Slack MCP** — for notifications and reports (`standup`, `review-inbox`, `worklog-report`)

**Developers also need:**
- **Git** and **GitHub CLI** (`gh`) — authenticated with your org

**Optional:**
- **Google Calendar MCP** — adds meeting context to `standup`
- **Figma MCP** — used when JIRA tickets reference Figma designs

> **MCP setup**: MCP servers connect Claude Code to external services. Add them in Claude Code settings or via CLI:
> ```
> claude mcp add atlassian -- npx -y @anthropic-ai/claude-code-mcp-atlassian
> claude mcp add slack -- npx -y @anthropic-ai/claude-code-mcp-slack
> ```
> See [MCP server docs](https://docs.anthropic.com/en/docs/claude-code/mcp-servers) for Google Calendar and Figma setup.

## Quick Start

### 1. Clone and enter the workspace

```bash
# Create your workspace from the Polaris template (GitHub → "Use this template")
# Then clone your new repo:
git clone https://github.com/YOUR-ORG/your-polaris-workspace ~/polaris-workspace
cd ~/polaris-workspace
```

> **Tip**: Choose a dedicated directory name. Avoid `~/work` — many developers already use that path for other projects.

> **PMs and non-developers:** See the [PM Setup Checklist](docs/pm-setup-checklist.md) — it tells you exactly what to ask your developer and what to do after setup. Then jump straight to Step 4.

### 2. Set up workspace config

```bash
cp workspace-config.yaml.example workspace-config.yaml
```

You don't need to edit this file — `/init` will populate it in the next step.

### 3. Initialize your company directory

> **Note:** `/commands` like `/init` are typed inside Claude Code conversations, not in your terminal shell.

Open Claude Code inside the workspace — in your terminal, run `claude` from the workspace directory (or open the folder in VS Code with the Claude Code extension). Then type:

```
/init
```

The interactive wizard will:
- Detect your GitHub org and repos
- Create a company directory with `workspace-config.yaml`
- Set up project mappings (JIRA keys → local repo paths)

After `/init` completes, verify setup by trying: `"work on PROJ-123"` (replace with a real ticket key). If Polaris reads the ticket successfully, you're good to go.

### 4. Start using skills

Once initialized, just talk to Claude Code naturally — English or 中文 both work:

```
"work on PROJ-123"    /「做 PROJ-123」       → full development workflow / 完整開發流程
"fix bug PROJ-456"    /「修 bug PROJ-456」    → root cause → fix → PR / 根因分析 → 修復 → 發 PR
"review PR"           /「review 這個 PR」     → code review with inline comments
"estimate PROJ-789"   /「估點 PROJ-789」      → story point estimation / Story point 估算
"standup"             /「standup」            → generate daily standup report / 產出站會報告
"sprint planning"     /「排 sprint」          → pull tickets, calculate capacity / 拉票、算容量
"learn from <url>"    /「學習這個」            → study external resource, extract patterns
```

### Start here

Don't try all 30 skills at once. Pick one that matches your role:

| If you are a... | Try this first | What happens |
|-----------------|----------------|--------------|
| **Developer** | `"work on PROJ-123"` / `「做 PROJ-123」` | Reads JIRA → estimates → creates branch → codes → opens PR |
| **PM / Scrum Master** | `"standup"` / `「standup」` | Collects yesterday's JIRA + git activity → formats report |
| **Tech Lead** | `"sprint planning"` / `「排 sprint」` | Pulls backlog → calculates capacity → suggests priority |

Everything else builds on these. Explore more skills as you get comfortable.

### PM & Scrum workflow

Polaris covers the full sprint lifecycle — no coding or git knowledge required. All PM skills require the **Max plan** ($100/mo) or API access due to sub-agent usage.

```
Sprint planning    →  "sprint planning" / 「排 sprint」
                      Pulls JIRA backlog → calculates team capacity → detects carry-overs
                      → suggests priority order → drafts Release page

Daily standup      →  "standup" / 「standup」
                      Collects JIRA status changes + git commits + calendar meetings
                      → groups by team → formats as YDY/TDT/BOS
                      (Yesterday Did / Today Do / Blockers or Shoutouts)

Refinement         →  "refinement EPIC-100" / 「refinement EPIC-100」
                      Reads Epic content → identifies gaps (Polaris reads the codebase for you)
                      → drafts AC, scope, edge cases → writes back to JIRA

Breakdown          →  "work on EPIC-100" / 「做 EPIC-100」
                      Epic → sub-tasks with story point estimates → batch-creates in JIRA

Worklog report     →  "worklog report 2w" / 「worklog report 2w」
                      Queries completed tickets from past 2 weeks → groups by assignee → posts to Slack
```

> **PMs and Scrum Masters:** Everything below this point is for developers and framework maintainers. You're all set!
> If a skill isn't working, check that your Atlassian MCP and Slack MCP connections are active in Claude Code settings — that covers 90% of PM setup issues.
>
> 中文版包含完整 PM 工作流程說明：[docs/quick-start-zh.md](docs/quick-start-zh.md#pm-與-scrum-工作流程)

## How it works

### Three-layer architecture

| Layer | Location | When loaded | What it contains |
|-------|----------|-------------|------------------|
| **L1 — Workspace** | `CLAUDE.md` + `.claude/rules/` | Every conversation | Strategist persona, delegation rules |
| **L2 — Company** | `.claude/rules/{company}/` | Every conversation | Skill routing, PR conventions, JIRA workflow |
| **L3 — Project** | `{company}/{project}/CLAUDE.md` | When working in project | Lint config, test patterns, component conventions |

Rules are always loaded. Skills load on-demand — they don't consume context until triggered.

### Self-evolution

Polaris improves itself through daily use:

1. **Feedback capture** — when you correct Claude's approach, it saves the lesson
2. **Pattern graduation** — feedback referenced 3+ times auto-promotes to a permanent rule
3. **Challenger audit** — a sub-agent periodically reviews the workspace from a new user's perspective
4. **Backlog tracking** — improvement candidates accumulate over time (maintainers track these separately)

### Directory structure

```
your-workspace/
├── CLAUDE.md                  # Strategist persona + delegation rules
├── workspace-config.yaml      # Company routing (gitignored; copy from .example)
├── .claude/
│   ├── rules/                 # Universal rules (L1)
│   │   └── {company}/         # Company rules (L2)
│   └── skills/                # 29 workflow skills
├── _template/                 # Template for new companies + rule examples
├── scripts/                   # Sync utilities
└── {company}/                 # Your company directory
    ├── workspace-config.yaml  # Company config (projects, JIRA, etc.)
    ├── {project-a}/           # Project with its own CLAUDE.md (L3)
    └── {project-b}/
```

## Multi-company setup

Polaris supports multiple companies in a single workspace. Each company gets its own config, rules, and skills:

```
your-workspace/
├── workspace-config.yaml          # Routes JIRA keys to companies
├── .claude/rules/
│   ├── *.md                       # Universal rules (all companies)
│   ├── acme/                      # Acme-specific rules
│   └── bigcorp/                   # BigCorp-specific rules
├── .claude/skills/
│   ├── *.md (or dirs)             # Shared skills (version-controlled)
│   ├── acme/                      # Acme-only skills (gitignored)
│   └── bigcorp/                   # BigCorp-only skills (gitignored)
├── acme/                          # Acme projects + config
└── bigcorp/                       # BigCorp projects + config
```

**How isolation works:**

- **Config routing** — `workspace-config.yaml` maps JIRA project prefixes to companies. When you say "work on ACME-123", Polaris reads Acme's config
- **Rules scoping** — all rules load into every conversation (Claude Code limitation), but company rules include a scope header. The Strategist only applies rules matching the active company
- **Skills isolation** — shared skills are in `.claude/skills/` (tracked in git). Company-specific skills go under `.claude/skills/{company}/` (gitignored)
- **Diagnostics** — run `/which-company PROJ-123` to see which company a ticket routes to, `/use-company` to explicitly set context, or `/validate-isolation` to scan for scope header issues and memory tag violations

**Adding a second company:**

```
/init
```

The wizard detects existing companies and creates the new one alongside them. After setup, run `/validate-isolation` to verify no rules are missing scope headers.

> **Note:** If two companies share the same JIRA project prefix, use `/use-company` to explicitly set context — automatic routing cannot distinguish them.
>
> See `.claude/rules/multi-company-isolation.md` for the full scoping strategy.

## Customization

| What | Where | How |
|------|-------|-----|
| Add a new company | Run `/init` | Interactive wizard creates everything |
| Map JIRA projects to repos | `{company}/workspace-config.yaml` | Add entries to `projects:` |
| Add company-specific rules | `.claude/rules/{company}/` | Create `.md` files — auto-loaded every conversation |
| Add project-specific rules | `{company}/{project}/CLAUDE.md` | Loaded when sub-agent enters project |
| Create a new skill | Run `/skill-creator` | Guided skill creation with eval |
| Modify skill routing | `.claude/rules/{company}/skill-routing.md` | Maps trigger phrases → skills |

## What not to touch

These are framework internals. Edit them only if you're modifying the Polaris framework itself:

| Path | Why |
|------|-----|
| `.claude/skills/*/SKILL.md` | Skill definitions — use `/skill-creator` to modify |
| `.claude/skills/references/` | Shared data (estimation scales, templates) used by skills |
| `.claude/rules/*.md` (L1) | Universal rules — loaded every conversation |
| `_template/` | Templates for `/init` wizard |
| `scripts/` | Sync utilities between template and instances |
| `CLAUDE.md` | Strategist persona — the brain of the framework |

**Safe to edit:**

| Path | What to customize |
|------|-------------------|
| `.claude/rules/{company}/` | Your company's conventions, routing, JIRA workflow |
| `{company}/workspace-config.yaml` | JIRA projects, Slack channels, repo mappings |
| `{company}/{project}/CLAUDE.md` | Project-specific rules (L3) |

## Upgrading

If you cloned from the Polaris template and want to pull framework updates:

```bash
# From the Polaris template repo:
./scripts/sync-from-polaris.sh --polaris ~/path-to-polaris-template [--dry-run]
```

This syncs skills, rules, and references while preserving your company config, L2 rules, and project-specific files. Use `--dry-run` to preview changes before applying.

> See `scripts/sync-from-polaris.sh --help` for full options.

## About the name

> Polaris — inspired by Zhang Liang (張良), the strategist who listened first, planned second, and shaped outcomes from behind the scenes.

## Acknowledgements

Polaris draws inspiration from these open-source projects:

| Project | Author | What we learned |
|---------|--------|----------------|
| [superpowers](https://github.com/obra/superpowers) | Jesse Vincent | Agentic skills framework, spec-first development, sub-agent task division |
| [ab-dotfiles](https://github.com/AlvinBian/ab-dotfiles) | Alvin Bian | AI-driven dev environment management, `/init` smartSelect interaction, audit trail |

## License

[MIT](LICENSE)
