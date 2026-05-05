<p align="center">
  <img src="docs-manager/src/assets/polaris-logo.png" alt="Polaris" width="320">
</p>

# Polaris

English | [中文](./README.zh-TW.md)

Polaris is a Claude Code / Codex workspace harness for teams that run work through JIRA, GitHub, Slack, and Confluence. It gives your coding agent durable workflow skills, local team context, deterministic gates, and a learning loop so it follows your operating model instead of improvising every session.

Polaris is intentionally an add-on layer. It owns framework instructions, skills, hooks, and ignored local company context under `{company}/`; product repositories keep ownership of their tracked `CLAUDE.md`, `AGENTS.md`, `.github/**`, and repo-owned AI configuration.

## What You Can Do

| Workflow | Prompt | Outcome |
|---|---|---|
| Build from a ticket | `work on PROJ-123` / `做 PROJ-123` | Reads JIRA, checks prerequisites, estimates, branches, implements, tests, and opens a PR |
| Diagnose a bug | `fix bug PROJ-456` / `修 bug PROJ-456` | Finds root cause, proposes the fix, verifies behavior, and delivers the patch |
| Review a PR | `review PR` / `review 這個 PR` | Reads the diff and leaves inline review comments grounded in project rules |
| Plan a sprint | `sprint planning` / `排 sprint` | Pulls backlog, checks capacity, detects carry-over, and drafts release planning output |
| Generate standup | `standup` | Collects JIRA, git, and calendar activity into a team update |
| Learn from sources | `learn from <url>` / `學習這個 <url>` | Studies external material or merged PRs and turns useful patterns into workspace knowledge |

Start with one workflow. The full skill catalog is available in [Developer Workflow Guide](docs/workflow-guide.md) and [Chinese Triggers](docs/chinese-triggers.md).

## How Polaris Works

Polaris organizes agent behavior into three layers:

| Layer | Source | Purpose |
|---|---|---|
| Workspace | `CLAUDE.md`, `.claude/rules/`, `.claude/skills/` | Shared strategist behavior, skills, hooks, and deterministic rules |
| Company | ignored `.claude/rules/{company}/`, `{company}/workspace-config.yaml` | Company-specific JIRA, Slack, GitHub, and workflow conventions |
| Project | ignored `{company}/polaris-config/{project}/handbook/` | Repo handbook, generated scripts, test commands, runtime hints, and local context |

Skills load only when triggered. Rules and hooks provide the always-on guardrails: language policy, safety checks, PR body validation, task artifact validation, context continuity, and workflow gates.

## Requirements

Everyone needs:

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) or Codex configured with [Polaris for Codex](docs/codex-quick-start.md)
- Atlassian MCP for JIRA and Confluence
- Slack MCP for notifications, standups, and review workflows

Use a coding-agent runtime from the workspace root, not the ordinary browser chat. The prompts below are typed into Claude Code or Codex conversations.

Developers also need:

- Git
- GitHub CLI (`gh`) authenticated with the organization

Optional integrations:

- Google Calendar MCP for meeting-aware standups
- Figma MCP for tickets that reference designs

Most multi-step workflows use sub-agents. In Claude Code, that requires the Max plan or API access.

### MCP Setup

Claude Code can connect MCP servers through `/mcp`:

- Slack: `https://mcp.slack.com/mcp`
- Atlassian: `https://mcp.atlassian.com/v1/mcp`

Codex can mirror the same connectors:

```bash
codex mcp add claude_ai_Slack --url https://mcp.slack.com/mcp
codex mcp add claude_ai_Atlassian --url https://mcp.atlassian.com/v1/mcp
codex mcp login claude_ai_Slack
codex mcp login claude_ai_Atlassian
codex mcp list
```

Legacy stdio `npx @anthropic-ai/claude-code-mcp-*` setup is deprecated in this framework.

## Quick Start

### 1. Create a workspace

Use the [Polaris template repo](https://github.com/HsuanYuLee/polaris) on GitHub, then clone your new workspace:

```bash
git clone https://github.com/YOUR-ORG/your-polaris-workspace ~/polaris-workspace
cd ~/polaris-workspace
```

Choose a dedicated directory name. Avoid `~/work` if you already use that path for product repositories.

### 2. Onboard your company

Open Claude Code or Codex from the workspace root, then type this into the agent conversation:

```text
onboard Polaris workspace for my company
```

The onboard flow detects your GitHub org and repos, creates ignored company context, maps JIRA keys to local repos, and finishes with a readiness dashboard: `ready`, `partial`, or `blocked`.

If the dashboard is not `ready`, run:

```text
onboard repair
```

### 3. Try one real workflow

Use a real ticket key from your JIRA project:

```text
work on PROJ-123
```

PMs and Scrum Masters can start with:

```text
standup
```

For a role-specific setup checklist, see [PM Setup Checklist](docs/pm-setup-checklist.md). For Codex runtime setup, see [Polaris for Codex](docs/codex-quick-start.md).

## Repository Layout

```text
your-workspace/
├── CLAUDE.md                  # Strategist instructions
├── AGENTS.md                  # Generated runtime bootstrap for coding agents
├── workspace-config.yaml      # Local company routing, ignored by git
├── .claude/
│   ├── rules/                 # Universal and company-scoped rules
│   └── skills/                # Workflow skills
├── docs/                      # Public guides
├── scripts/                   # Deterministic gates and workflow helpers
└── {company}/                 # Ignored local company context
    ├── workspace-config.yaml
    ├── polaris-config/
    │   └── {project}/handbook/
    └── {project}/             # Product repo; repo-owned files stay owned by the repo
```

## Guides

| Need | Read |
|---|---|
| Full developer lifecycle | [Developer Workflow Guide](docs/workflow-guide.md) |
| Chinese trigger phrases | [Chinese Triggers](docs/chinese-triggers.md) |
| PM and non-developer setup | [PM Setup Checklist](docs/pm-setup-checklist.md) |
| Codex setup | [Polaris for Codex](docs/codex-quick-start.md) |
| Traditional Chinese quick start | [中文快速上手](docs/quick-start-zh.md) |

## Customization

Safe places to customize:

| What | Where |
|---|---|
| Company routing and integrations | `{company}/workspace-config.yaml` |
| Company workflow conventions | `.claude/rules/{company}/` |
| Project handbook and generated scripts | `{company}/polaris-config/{project}/` |
| New workflow skills | Use `skill-creator` |

Framework internals such as `.claude/skills/*/SKILL.md`, `.claude/skills/references/`, `.claude/rules/*.md`, hooks, and scripts should only be changed when you are modifying Polaris itself.

## Upgrading

To pull framework updates from a Polaris template checkout:

```bash
./scripts/sync-from-polaris.sh --polaris ~/path-to-polaris-template --dry-run
./scripts/sync-from-polaris.sh --polaris ~/path-to-polaris-template
```

The sync preserves ignored company context, company rules, and project-specific files. Apply mode also runs cross-runtime parity checks for Claude Code and Codex.

## Security

Polaris is designed for local-first operation:

- No telemetry, analytics, or usage reporting
- No framework phone-home behavior
- Local storage for memories, learnings, timelines, and checkpoints
- Shell-level safety hooks for dangerous commands
- Workspace language gates before downstream PR, JIRA, Slack, Confluence, commit, and release prose
- Plaintext skills, rules, and scripts that can be audited in git

Network activity comes from tools you explicitly invoke, such as git, `gh`, JIRA, Slack, Confluence, or MCP connectors.

## Acknowledgements

Polaris draws inspiration from these open-source projects:

| Project | Author | What we learned |
|---|---|---|
| [superpowers](https://github.com/obra/superpowers) | Jesse Vincent | Agentic skills framework, spec-first development, sub-agent task division |
| [ab-dotfiles](https://github.com/AlvinBian/ab-dotfiles) | Alvin Bian | AI-driven dev environment management, onboarding smartSelect interaction, audit trail |
| [get-shit-done](https://github.com/gsd-build/get-shit-done) | TÂCHES | Context engineering patterns, goal-backward verification, sub-agent completion envelope, complexity tier routing |
| [skill-sanitizer](https://github.com/cyberxuan-XBX/skill-sanitizer) | cyberxuan-XBX | Pre-LLM security scanning, code block context awareness, severity scoring with false-positive reduction |
| [Kubernetes](https://github.com/kubernetes/kubernetes), [Vite](https://github.com/vitejs/vite), [VS Code](https://github.com/microsoft/vscode), [Home Assistant](https://github.com/home-assistant/core) | OSS communities | README structure: concise project identity, role-based entry points, short setup path, and links to detailed docs |

## License

[MIT](LICENSE)
