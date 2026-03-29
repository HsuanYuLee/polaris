# Polaris

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) workspace template that turns your AI assistant into a strategist — it learns your team's workflow, routes tasks to specialized skills, and evolves its own rules from daily usage.

> Inspired by Zhang Liang (張良) — the strategist who listened first, planned second, and shaped outcomes from behind the scenes.

## What does this actually do?

You tell Claude Code what you want. Polaris figures out how to get there.

```
You:     "work on PROJ-123"
Polaris: reads JIRA ticket → checks prerequisites → estimates story points
         → breaks into sub-tasks → creates JIRA sub-tickets
         → opens feature branch → implements code → runs tests
         → opens PR with coverage report → transitions JIRA to CODE REVIEW
```

It does this through **skills** (reusable workflows) and **rules** (accumulated team knowledge):

| Category | Skills | What they automate |
|----------|--------|--------------------|
| **Build** | `work-on`, `fix-bug`, `epic-breakdown`, `tdd` | JIRA → branch → code → PR, end-to-end |
| **Review** | `review-pr`, `review-inbox`, `fix-pr-review` | Code review, batch PR scanning, addressing feedback |
| **Quality** | `dev-quality-check`, `verify-completion`, `unit-test` | Tests, coverage, behavioral verification |
| **Plan** | `refinement`, `scope-challenge`, `sprint-planning` | Requirement analysis, estimation, sprint capacity |
| **Operate** | `standup`, `worklog-report`, `jira-worklog` | Daily reports, time tracking |
| **Learn** | `learning`, `review-lessons-graduation` | Study external resources, graduate patterns into rules |

## Prerequisites

- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** — CLI, desktop app, or IDE extension
- **Git** and **GitHub CLI** (`gh`) — authenticated with your org
- **MCP servers** (configured in Claude Code settings):
  - **Atlassian** — required for JIRA and Confluence skills (`work-on`, `fix-bug`, `epic-breakdown`, `standup`, etc.)
  - **Slack** — required for notification skills (`review-inbox`, `standup`, `worklog-report`)
  - **Google Calendar** — optional, used by `standup` for meeting context
  - **Figma** — optional, used when JIRA tickets reference Figma designs

> MCP servers are configured via Claude Code's settings. See [MCP server docs](https://docs.anthropic.com/en/docs/claude-code/mcp-servers) for setup instructions.

## Quick Start

### 1. Clone and enter the workspace

```bash
git clone <your-polaris-repo-url> ~/your-workspace
cd ~/your-workspace
```

### 2. Initialize your company directory

Open Claude Code in the workspace and run:

```
/init
```

The interactive wizard will:
- Detect your GitHub org and repos
- Create a company directory with `workspace-config.yaml`
- Set up project mappings (JIRA keys → local repo paths)

### 3. Start using skills

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
4. **Backlog tracking** — improvement candidates accumulate in `polaris-backlog.md`

### Directory structure

```
your-workspace/
├── CLAUDE.md                  # Strategist persona + delegation rules
├── workspace-config.yaml      # Company routing
├── .claude/
│   ├── rules/                 # Universal rules (L1)
│   │   └── {company}/         # Company rules (L2)
│   ├── skills/                # 29 workflow skills
│   └── polaris-backlog.md     # Framework improvement tracker
├── _template/                 # Template for new companies
├── scripts/                   # Sync utilities
└── {company}/                 # Your company directory
    ├── workspace-config.yaml  # Company config (projects, JIRA, etc.)
    ├── {project-a}/           # Project with its own CLAUDE.md (L3)
    └── {project-b}/
```

## Customization

| What | Where | How |
|------|-------|-----|
| Add a new company | Run `/init` | Interactive wizard creates everything |
| Map JIRA projects to repos | `{company}/workspace-config.yaml` | Add entries to `projects:` |
| Add company-specific rules | `.claude/rules/{company}/` | Create `.md` files — auto-loaded every conversation |
| Add project-specific rules | `{company}/{project}/CLAUDE.md` | Loaded when sub-agent enters project |
| Create a new skill | Run `/skill-creator` | Guided skill creation with eval |
| Modify skill routing | `.claude/rules/{company}/skill-routing.md` | Maps trigger phrases → skills |

## Acknowledgements

Polaris draws inspiration from these open-source projects:

| Project | Author | What we learned |
|---------|--------|----------------|
| [superpowers](https://github.com/obra/superpowers) | Jesse Vincent | Agentic skills framework, spec-first development, sub-agent task division |
| [ab-dotfiles](https://github.com/AlvinBian/ab-dotfiles) | Alvin Bian | AI-driven dev environment management, `/init` smartSelect interaction, audit trail |

## License

[MIT](LICENSE)
