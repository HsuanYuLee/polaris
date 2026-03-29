# Challenger Audit — New User UX Review

A sub-agent that reviews the Polaris GitHub repo from an outsider's perspective, reporting usability friction.

## When to run

- After each version bump (post-release)
- Before sharing the repo publicly or with a new team
- When the user says "跑挑戰者", "challenger", "audit UX", "新使用者角度"

## Sub-agent setup

- **Model**: `"sonnet"`
- **Role**: First-time developer who just discovered the repo
- **Persona rules**:
  - Senior developer who uses Claude Code daily
  - 5 minutes of patience — if they can't understand and start in 5 minutes, they leave
  - Be HARSH, not polite

## What the challenger checks

### 1. First impression (README, description, repo structure)
- Can I tell what this IS in 10 seconds?
- Is the one-liner description concrete (not tagline soup)?
- Are GitHub topics, license, stars/social proof present?

### 2. Getting started (can I actually set this up?)
- Are prerequisites complete and explicit?
- Will the clone/setup commands succeed on a fresh machine?
- Are there hidden dependencies (MCP servers, CLI tools)?

### 3. Understanding (do I know what this does for ME?)
- Is there a concrete walkthrough (input → what happens → output)?
- Are trigger commands/phrases documented in a language I can read?
- Can I tell which files to customize vs. leave alone?

### 4. Trust (does this look maintained, professional, safe?)
- License present?
- Version history sensible?
- No leaked internal references?

## Output format

Severity ratings:
- 🔴 **Blocking**: user would leave / give up
- 🟡 **Confusing**: user can figure it out but shouldn't have to
- 🟢 **Suggestion**: nice to have

Each finding: severity + category + one-line description + what to fix.

## After the audit

Results flow into `.claude/polaris-backlog.md`:
- 🔴 items → **High**
- 🟡 items → **High** or **Medium** (by judgment)
- 🟢 items → **Low**

Tag source as `challenger v{version}`.
