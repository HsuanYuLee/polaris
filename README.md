# Polaris

AI that helps you navigate, build, and reach where you're going.

Your AI strategist — learns your craft, orchestrates everything behind the curtain, so you can focus on where to go next.

Inspired by Zhang Liang (張良) — the strategist who listened first, then shaped an empire from behind the scenes.

## What it does

- **Helps you build** — routes tasks to the right skill, delegates to sub-agents, quality-checks results
- **Helps you learn** — accumulates feedback from daily work, graduates patterns into rules automatically
- **Helps you scale** — multi-company support, two-layer config, project-level customization
- **Helps you evolve** — maintains its own backlog, versions itself, iterates on its own workflow

## Structure

```
polaris/
├── CLAUDE.md                  ← L1: AI Strategist persona
├── VERSION                    ← Framework version
├── CHANGELOG.md               ← Release history
├── workspace-config.yaml      ← Root config (company routing)
├── _template/                 ← New company template
│   └── workspace-config.yaml
├── .claude/
│   ├── rules/                 ← L1: Universal rules
│   │   └── {company}/         ← L2: Company-level rules
│   ├── skills/                ← Workflow skills (work-on, fix-bug, review-pr, ...)
│   └── polaris-backlog.md     ← Framework improvement tracker
├── scripts/                   ← Sync & utility scripts
│
├── {company}/                 ← Company directory
│   ├── workspace-config.yaml  ← Company config (gitignored)
│   ├── README.md              ← Company-specific guide
│   ├── setup.sh               ← One-click setup
│   ├── docs/                  ← Company workflows
│   ├── {project-a}/           ← L3: Projects (each with CLAUDE.md + .claude/rules/)
│   ├── {project-b}/
│   └── ...
```

## Three-layer architecture

| Layer | Location | Loaded | Content |
|-------|----------|--------|---------|
| **L1 — Workspace** | `CLAUDE.md` + `rules/` | Every conversation | Strategist persona, delegation rules, bash rules |
| **L2 — Company** | `rules/{company}/` | Every conversation | Skill routing, PR/Review, JIRA, scenario playbooks |
| **L3 — Project** | `{company}/{project}/CLAUDE.md` | When sub-agent enters project | Project-specific rules (lint, test, component conventions) |

Skills load on-demand (via Skill tool) — they don't consume context every conversation.

## Quick Start

1. Clone this repo
2. Run `/init` in Claude Code to set up your company directory
3. Start using skills: `做 PROJ-123`, `review PR`, `standup`, ...

See your company's `README.md` for detailed setup instructions.

## Acknowledgements

Polaris draws inspiration from these open-source projects:

| Project | Author | What we learned |
|---------|--------|----------------|
| [superpowers](https://github.com/obra/superpowers) | Jesse Vincent | Agentic skills framework, spec-first development, sub-agent task division |
| [ab-dotfiles](https://github.com/AlvinBian/ab-dotfiles) | Alvin Bian | AI-driven dev environment management, /init smartSelect interaction, audit trail |
