# Polaris

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) workspace template that turns your AI assistant into a strategist — it learns your team's workflow, routes tasks to specialized skills, and evolves its own rules from daily usage.

## Who is this for?

- **Developers** — automate the JIRA → branch → code → PR loop, enforce team conventions through AI
- **Tech leads** — standardize estimation, code review, and sprint planning across the team
- **PMs and Scrum Masters** — generate standups, track worklogs, run sprint planning — no coding required

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
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** — CLI, desktop app, or IDE extension. Requires a Claude Pro, Team, or Enterprise plan. Sub-agent features (used by most skills) need the Max plan or API access
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
> ```
> See [MCP server docs](https://docs.anthropic.com/en/docs/claude-code/mcp-servers) for Slack, Google Calendar, and Figma setup.

## Quick Start

### 1. Clone and enter the workspace

```bash
git clone <your-polaris-repo-url> ~/polaris-workspace
cd ~/polaris-workspace
```

> **Tip**: Choose a dedicated directory name. Avoid `~/work` — many developers already use that path for other projects.

### 2. Set up workspace config

```bash
cp workspace-config.yaml.example workspace-config.yaml
```

### 3. Initialize your company directory

Open Claude Code inside the workspace — in your terminal, run `claude` from the workspace directory (or open the folder in VS Code with the Claude Code extension). Then type:

```
/init
```

The interactive wizard will:
- Detect your GitHub org and repos
- Create a company directory with `workspace-config.yaml`
- Set up project mappings (JIRA keys → local repo paths)

### 4. Start using skills

Once initialized, just talk to Claude Code naturally:

```
"work on PROJ-123"          → full development workflow
"fix bug PROJ-456"          → root cause → fix → PR
"review PR"                 → code review with inline comments
"estimate PROJ-789"         → story point estimation
"standup"                   → generate daily standup report
"sprint planning"           → pull tickets, calculate capacity
"learn from <url>"          → study external resource, extract patterns
```

Chinese works too — 中文也通：

```
「做 PROJ-123」              → 完整開發流程
「修 bug PROJ-456」          → 根因分析 → 修復 → 發 PR
「估點 PROJ-789」            → Story point 估算
「standup」                  → 產出每日站會報告
「sprint planning」          → 拉票、算容量、排優先級
```

### Start here

Don't try all 30 skills at once. Pick one that matches your role:

| If you are a... | Try this first | What happens |
|-----------------|----------------|--------------|
| **Developer** | `"work on PROJ-123"` | Reads JIRA → estimates → creates branch → codes → opens PR |
| **PM / Scrum Master** | `"standup"` | Collects yesterday's JIRA + git activity → formats report |
| **Tech Lead** | `"sprint planning"` | Pulls backlog → calculates capacity → suggests priority |

Everything else builds on these. Explore more skills as you get comfortable.

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
- **Diagnostics** — run `/which-company PROJ-123` to see which company a ticket routes to

**Adding a second company:**

```
/init
```

The wizard detects existing companies and creates the new one alongside them.

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
