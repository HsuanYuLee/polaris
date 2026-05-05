# Polaris for Codex

Polaris supports Codex as a first-class runtime by sharing the same `.claude/**` source assets and generating Codex-facing mirrors for skills, rules, and MCP setup.

## Scope

- Reuse existing Polaris assets: `CLAUDE.md`, `.claude/rules/`, `.claude/skills/`
- Keep the same trigger language (`"work on PROJ-123"`, `"standup"`, `"refinement EPIC-100"`)
- Let Codex execute skill steps by reading `SKILL.md` files directly
- Maintain a single source of truth in `.claude/**`; treat `.agents/**` and `.codex/**` as generated outputs

## What changes in Codex

| Claude Code behavior | Codex equivalent |
|---|---|
| Claude Code slash shortcuts | Ask Codex in plain language: "onboard Polaris workspace for {company}" |
| Skill tool invocation (`Skill("engineering", ...)`) | Codex reads `.claude/skills/engineering/SKILL.md` and executes the steps |
| MCP setup via Claude settings | Use MCP connectors available in your Codex runtime |

## Quick start

### 1. Clone workspace

```bash
git clone https://github.com/YOUR-ORG/your-polaris-workspace ~/polaris-workspace
cd ~/polaris-workspace
```

### 2. Run Codex doctor

First verify the Polaris runtime toolchain. This checks the minimum local environment (Node >= 20, pnpm, Python 3) and required capabilities for the docs viewer, Mockoon fixtures, and Playwright:

```bash
bash scripts/polaris-toolchain.sh doctor --required
```

If required tools are missing:

```bash
bash scripts/polaris-toolchain.sh install --required
bash scripts/polaris-toolchain.sh doctor --required
```

Then run the Codex compatibility doctor:

```bash
bash scripts/polaris-codex-doctor.sh
```

This checks:
- required tools (`git`, `gh`, `rg`)
- required Polaris files (`CLAUDE.md`, `.claude/rules/`, `.claude/skills/`)
- whether `workspace-config.yaml` exists

### 2.5 Sync skills to Codex path

Codex reads repository skills from `.agents/skills`. The recommended mode is a symlink so Claude and Codex share one source of truth:

```bash
bash scripts/sync-skills-cross-runtime.sh --to-agents --link
```

This makes `.agents/skills -> ../.claude/skills`.

If you explicitly need a copied mirror instead of a symlink:

```bash
bash scripts/sync-skills-cross-runtime.sh --to-agents
```

The copy sync exports **public shared skills only** (excludes `scope: maintainer-only` and company-specific skill folders), but it is considered a degraded mode because copied mirrors can drift. `scripts/check-skills-mirror-mode.sh` and cross-LLM parity checks expect symlink mode.

If you are on Windows or your clone uses `core.symlinks=false`, see the Platform Notes in `.claude/rules/cross-llm-skill-source-of-truth.md` for recovery steps.

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

If `.claude/skills` and `.agents/skills` are out of sync, restore the shared symlink:

```bash
bash scripts/sync-skills-cross-runtime.sh --to-agents --link
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

### 3. Onboard workspace (Codex prompt)

If `workspace-config.yaml` is missing, ask Codex:

```text
Please onboard Polaris workspace for my company.
Create workspace-config.yaml from workspace-config.yaml.example,
add my company mapping, then run the readiness doctor.
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
