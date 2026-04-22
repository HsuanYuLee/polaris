# Polaris for Codex (Compatibility Layer)

This workspace is built for Claude Code first, but you can run the same Polaris workflow in Codex.

## Scope

- Reuse existing Polaris assets: `CLAUDE.md`, `.claude/rules/`, `.claude/skills/`
- Keep the same trigger language (`"work on PROJ-123"`, `"standup"`, `"refinement EPIC-100"`)
- Let Codex execute skill steps by reading `SKILL.md` files directly
- Maintain a single source of truth in `.claude/**`; treat `.agents/**` and `.codex/**` as generated outputs

## What changes in Codex

| Claude Code behavior | Codex equivalent |
|---|---|
| Slash commands like `/init` | Ask Codex in plain language: "initialize Polaris workspace for {company}" |
| Skill tool invocation (`Skill("engineering", ...)`) | Codex reads `.claude/skills/engineering/SKILL.md` and executes the steps |
| MCP setup via Claude settings | Use MCP connectors available in your Codex runtime |

## Quick start

### 1. Clone workspace

```bash
git clone https://github.com/YOUR-ORG/your-polaris-workspace ~/polaris-workspace
cd ~/polaris-workspace
```

### 2. Run compatibility doctor

```bash
bash scripts/polaris-codex-doctor.sh
```

This checks:
- required tools (`git`, `gh`, `rg`)
- required Polaris files (`CLAUDE.md`, `.claude/rules/`, `.claude/skills/`)
- whether `workspace-config.yaml` exists

### 2.5 Sync skills to Codex path

Codex reads repository skills from `.agents/skills`. Mirror existing Polaris skills:

```bash
bash scripts/sync-skills-cross-runtime.sh --to-agents
```

Use `--link` if you prefer a symlink (`.agents/skills -> .claude/skills`).
The sync exports **public shared skills only** (excludes `scope: maintainer-only` and company-specific skill folders).

### 2.6 Verify mechanism parity

Run parity audit to ensure Claude/Codex skill trees are aligned:

```bash
bash scripts/mechanism-parity.sh --strict
```

### 2.7 Sync MCP baseline for Codex

Preview MCP changes first:

```bash
bash scripts/sync-codex-mcp.sh --dry-run
```

Apply and run OAuth login:

```bash
bash scripts/sync-codex-mcp.sh --apply --login
```

This sets up baseline Polaris MCP servers in Codex:
- `claude_ai_Atlassian`
- `claude_ai_Slack`

### 2.8 Transpile rules to Codex AGENTS

Generate Codex-side rule mirror from `.claude/rules`:

```bash
bash scripts/transpile-rules-to-codex.sh
```

This generates:
- `.codex/AGENTS.md`
- `.codex/.generated/rules-manifest.txt`

### 2.9 Verify cross-LLM parity (CI-friendly)

Run one command to verify both skill and rule parity:

```bash
bash scripts/verify-cross-llm-parity.sh
```

## Troubleshooting

### `invalid YAML` while loading a skill

This means a `SKILL.md` frontmatter block is malformed. Run:

```bash
bash scripts/polaris-codex-doctor.sh
```

If `.claude/skills` and `.agents/skills` are out of sync, refresh the Codex mirror:

```bash
bash scripts/sync-skills-cross-runtime.sh --to-agents
```

### `MCP startup incomplete` or `server is not logged in`

This is an MCP connector auth issue, not a Polaris skill issue.

- `claude_ai_Atlassian` and `claude_ai_Slack` are the Polaris baseline connectors.
- `figma` is optional. Keep it only if you use Figma-linked workflows.

Fix options:

```bash
codex mcp login claude_ai_Slack
codex mcp login claude_ai_Atlassian
codex mcp login figma
```

If you do not need an optional connector, remove it:

```bash
codex mcp remove figma
```

### 3. Initialize config (Codex prompt)

If `workspace-config.yaml` is missing, ask Codex:

```text
Please create workspace-config.yaml from workspace-config.yaml.example
and add my company mapping.
```

Then add your company-level config at `{company}/workspace-config.yaml`.

### 4. Start from high-signal prompts

Use the same Polaris intent prompts:

```text
work on PROJ-123
fix bug PROJ-456
review PR https://github.com/org/repo/pull/123
standup
sprint planning
```

## Recommended operating pattern in Codex

When invoking a Polaris workflow, use this framing:

```text
Follow Polaris skill workflow.
Read .claude/skills/<skill>/SKILL.md and required references.
Execute steps, run quality gates, then report outcomes.
```

This keeps Codex behavior aligned with Polaris deterministic gates.
