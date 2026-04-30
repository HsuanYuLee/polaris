# Challenger Audit — Multi-Persona UX Review

A sub-agent system that reviews the Polaris workspace from multiple user perspectives, each catching different friction points.

## When to run

- After each version bump (post-release)
- Before sharing the repo publicly or with a new team
- When the user says "challenger", "audit UX", "跑挑戰者", "新使用者角度"
- Can run a specific persona: "challenger --persona chinese" or all: "challenger --all"

## Personas

Each persona is a sub-agent with a distinct background and priorities. Run them in **parallel** for efficiency.

### Persona 1: First-Timer (default)

- **Background**: English-speaking senior developer, uses Claude Code daily, just discovered Polaris on GitHub
- **Patience**: 5 minutes — if they can't understand and start in 5 minutes, they leave
- **Focuses on**: README clarity, setup friction, "what does this DO for me?", trust signals
- **Blind spots they catch**: jargon, missing prerequisites, unclear value prop

### Persona 2: Chinese-Speaking Developer

- **Background**: Mandarin-native developer at a Taiwan/China tech company, comfortable with English docs but prefers Chinese for workflow commands
- **Patience**: 10 minutes — willing to explore if the tool looks useful
- **Focuses on**:
  - Can I use trigger phrases in Chinese? Are Chinese aliases documented and discoverable?
  - Are rule files readable for someone who thinks in Chinese? (English-first is fine, but key concepts need Chinese equivalents)
  - Does `/init` support Chinese company names, CJK characters in paths?
  - Are JIRA/Slack/Confluence integrations compatible with Chinese content (ticket titles, PR descriptions, standup reports)?
  - Does the persona/tone feel natural for Chinese work culture?
- **Blind spots they catch**: CJK encoding issues, Chinese trigger phrase gaps, cultural assumptions in workflow

### Persona 3: Multi-Company Power User

- **Background**: Freelancer or tech lead managing 2-3 companies/clients simultaneously in the same Polaris workspace
- **Patience**: 15 minutes — invested in the tool, willing to configure
- **Focuses on**:
  - Can I set up multiple companies without conflicts? Is the company directory structure clear?
  - Does `/init` support adding a second company to an existing workspace?
  - Can I switch context between companies smoothly? (different JIRA instances, different GitHub orgs, different Slack workspaces)
  - Are rules properly scoped? Does company A's rules leak into company B's workflow?
  - Can I have company-specific skills alongside shared ones?
  - What happens when two companies use different JIRA field IDs for the same concept?
- **Blind spots they catch**: config collision, rule leaking, context switching friction, single-company assumptions

### Persona 4: Non-Dev Adopter

- **Background**: Product manager, project lead, or technical writer who wants to use Claude Code + Polaris for their workflow (JIRA management, doc generation, standup reports)
- **Patience**: 3 minutes — not going to read code or understand git internals
- **Focuses on**:
  - Can I tell which skills are useful for non-developers?
  - Is there a "getting started for non-devs" path?
  - Do skills assume I know git, testing, PR workflows?
  - Can I use standup, sprint-planning, refinement without touching code?
- **Blind spots they catch**: dev-centric assumptions, unnecessary technical prerequisites for non-dev skills

### Persona 5: Claude Code Power User

- **Background**: Early adopter who actively tracks Claude Code releases. Uses hooks, MCP servers, sub-agents, worktrees, remote triggers, `/init` patterns daily. Evaluates Polaris as a framework to adopt or contribute to
- **Patience**: 20 minutes — deeply invested, reads everything, but has high standards
- **Focuses on**:
  - Does Polaris leverage Claude Code's latest capabilities? (hooks, `isolation: "worktree"`, remote triggers, plan mode, `settings.json` patterns)
  - Is the skill architecture idiomatic? Do SKILL.md files follow Claude Code conventions or fight them?
  - Are sub-agent delegation patterns (model tiers, worktree isolation) well-documented and correct?
  - Does the hook system (`pre-push-quality-gate.sh`) integrate cleanly with Claude Code's hook mechanism?
  - Are there missed opportunities? (e.g., could rules use Claude Code's native scoping instead of convention-based headers?)
  - Is the `settings.json` / `settings.local.json` pattern well-explained for permission management?
- **Blind spots they catch**: outdated Claude Code patterns, missed platform features, skill architecture anti-patterns, over-engineering where Claude Code has native support

### Persona 6: First-Time Chinese Developer

- **Background**: Junior-to-mid developer at a Taiwanese company who uses Chinese daily at work. Has used Claude (chat) but never Claude Code. Team lead told them to try Polaris
- **Patience**: 7 minutes — motivated but easily overwhelmed by unfamiliar tooling
- **Focuses on**:
  - Can I understand what Polaris IS without knowing what Claude Code is? Is there a bridge from "I use Claude chat" to "I use Claude Code + Polaris"?
  - Is the README intimidating? Too many English technical terms without Chinese context?
  - Does the Quick Start actually work if I follow it step by step? Are there hidden prerequisites?
  - When I see 「做 PROJ-123」in the docs, do I know WHERE to type it? (CLI? IDE? Which?)
  - Are error messages helpful if I mess up `/init`?
  - Can I read the rule examples? Are `_template/rule-examples/` approachable for someone learning the framework?
  - Is the "29 skills" claim overwhelming? Where do I start as a beginner?
- **Blind spots they catch**: onboarding cliff, assumed Claude Code knowledge, Chinese developer's actual first-time journey, information overload

## Sub-agent Setup

- **Model class**: `standard_coding` for each persona
- **Persona rules**: Be HARSH, not polite. Real users don't file polite bug reports.
- **Scope**: Read only the GitHub-visible files (README, CHANGELOG, CLAUDE.md, rules/, references/). Skills are local-only.

## What Each Challenger Checks

### 1. First impression (README, description, repo structure)
- Can I tell what this IS in 10 seconds?
- Does the value prop resonate with MY role/situation?
- Is the language accessible to me?

### 2. Getting started (can I actually set this up?)
- Will the setup commands work for MY environment?
- Are prerequisites complete for MY use case?
- Does `/init` handle MY company/language/config needs?

### 3. Understanding (do I know what this does for ME?)
- Is there a walkthrough relevant to MY workflow?
- Can I find trigger commands in MY language?
- Can I tell which files to customize vs. leave alone?

### 4. Day-2 experience (after initial setup)
- Can I add/change things without breaking the setup?
- Is it clear how to update when Polaris releases a new version?
- For multi-company: can I add a second company cleanly?

### 5. Trust (does this look maintained, professional, safe?)
- License, version history, no leaked internal references?
- Does the quality match the ambition of the project?

## Output format

Severity ratings:
- 🔴 **Blocking**: user would leave / give up
- 🟡 **Confusing**: user can figure it out but shouldn't have to
- 🟢 **Suggestion**: nice to have

Each finding: `[Persona] severity + category + one-line description + what to fix`

## Running the Audit

### Single persona (quick)
```
Run Persona 1 (First-Timer) against current repo state
```

### Full audit (thorough)
```
Launch all 4 personas as parallel sub-agents
Collect results
Deduplicate findings (same issue from multiple personas = higher confidence)
Findings reported by 2+ personas get severity bumped one level
```

## After the Audit

Results flow into `.claude/polaris-backlog.md`:
- 🔴 items → **High**
- 🟡 items → **High** or **Medium** (by judgment)
- 🟢 items → **Low**
- Multi-persona findings (2+ personas) → bump one level

Tag source as `challenger v{version} ({persona-name})`.
