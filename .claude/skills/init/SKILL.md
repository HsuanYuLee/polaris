---
name: init
description: >
  Interactive workspace initialization wizard. Creates a company directory
  with workspace-config.yaml, and registers it in the root config.
  Uses auto-detection (GitHub org, repos) and section-by-section Q&A.
  Each section is skippable.
  Use when: (1) user says "init", "initialize", "setup workspace", "初始化",
  "設定 workspace", (2) user just cloned the Polaris template and needs to
  configure it, (3) user says "填 config", "setup config", "configure".
  Do NOT trigger for editing a single field — just edit the config directly.
metadata:
  author: Polaris
  version: 2.0.0
---

# /init — Workspace Initialization Wizard

Interactive wizard that creates a company directory with `workspace-config.yaml` and registers it in the root config.

## Two-Layer Config Architecture

```
~/work/workspace-config.yaml              ← Root config (company routing)
~/work/{company}/workspace-config.yaml    ← Company config (full settings)
~/work/_template/workspace-config.yaml    ← Template for new companies
```

## Overview

```
Clone Polaris → /init → company dir + config ready → start using skills
```

## Execution Flow

### Step 0: Pre-check

1. Check if root `workspace-config.yaml` exists
2. If exists → read it, show existing companies
   - Ask: "Add a new company / Edit existing company / Cancel?"
3. If not exists → will create fresh

### Step 1: Company Basics

**Ask:**
```
Company name (used as directory name): e.g. "your-company", "my-startup"
```

**Auto-detect:**
- Check if `{company}/` directory already exists
- If exists and has `workspace-config.yaml` → offer to edit instead of overwrite

**Create company directory** if not exists, then copy `_template/workspace-config.yaml` as starting point.

### Step 2: GitHub

**Auto-detect:**
- Run `gh api user/orgs --jq '.[].login'` to list available orgs
- If only one org → pre-fill, ask to confirm
- If multiple → present as numbered list for selection

**Ask:**
```
GitHub org: (detected options or manual input)
```

### Step 3: JIRA (skippable)

**Ask:**
```
Do you use JIRA? (y/n)
```

If yes:
1. Ask for Atlassian instance (e.g., `your-domain.atlassian.net`)
2. Try `getVisibleJiraProjects` MCP tool to list projects → present as checklist
3. For each selected project, ask team name
4. `custom_fields` → tell user this can be configured later, leave empty for now

If no → leave entire `jira:` section with empty/default values.

### Step 4: Confluence (skippable)

**Ask:**
```
Do you use Confluence? (y/n)
```

If yes:
1. Instance is usually same as JIRA → pre-fill from Step 3
2. Try `getConfluenceSpaces` MCP tool to list spaces → select one
3. `folders` and `pages` → tell user: "Page IDs can be added later as you discover them. Skills will prompt when needed."

If no → leave empty.

### Step 5: Slack (skippable)

**Ask:**
```
Do you use Slack with Claude? (y/n)
```

If yes:
1. Ask for channel names/purposes, use `slack_search_channels` to find IDs
2. Map to: `pr_review`, `ai_notifications`, `worklog_report`
3. Not all channels are required — skip any that don't apply

If no → leave empty.

### Step 6: Kibana (skippable)

**Ask:**
```
Do you use Kibana/Elasticsearch for log querying? (y/n)
```

If yes → ask for host, index pattern, environments.
If no → leave empty.

### Step 7: Projects

**Auto-detect:**
- Run `gh repo list {org} --limit 50 --json name,url --jq '.[] | .name'` to list repos
- Present as checklist: "Select repos you work on (space to toggle, enter to confirm)"

**For each selected repo:**
1. `name`: repo name (pre-filled)
2. `repo`: `{org}/{name}` (pre-filled)
3. `tags`: ask "Short tag for JIRA matching (e.g., 'b2c', 'api')?" — can be empty
4. `keywords`: ask "Keywords for fuzzy matching?" — can be empty

### Step 8: Scrum Settings

**Pre-fill with defaults:**
```
PR approval threshold: 2
Need review label: "need review"
Sprint capacity (points): 20
Excluded bots: ["github-actions[bot]"]
```

Ask user to confirm or adjust each.

### Step 9: Infra (skippable)

**Ask:**
```
Do you have ansible repos for deployment? (y/n)
```

If yes → ask for repo paths, dev host/port.
If no → leave empty.

### Step 10: Review & Write

1. Show the complete generated company config YAML
2. Ask: "Write to {company}/workspace-config.yaml? (y/n)"
3. If yes → write company config file
4. Update root `workspace-config.yaml` — add/update the company entry:
   ```yaml
   companies:
     - name: {company}
       base_dir: "~/work/{company}"
   ```
5. Print: "Done! {company} is configured. Skills will now use these settings."

## Important Rules

- **Never guess values** — if auto-detection fails, ask the user
- **Every section is skippable** — empty = feature disabled, skills degrade gracefully
- **Show what was detected** — user should see and confirm auto-detected values
- **Idempotent** — running `/init` again on an existing company should offer to edit, not destroy
- **No secrets in config** — company config is gitignored but should still not contain secrets
- **Use MCP tools when available** — prefer `getVisibleJiraProjects`, `getConfluenceSpaces`, `slack_search_channels` over manual input for discovery
- **Multi-company safe** — root config is append-only; adding a new company never touches existing entries

## Output Format

The generated company config follows `_template/workspace-config.yaml` structure, with:
- Inline comments explaining each field
- Empty strings `""` for skipped optional fields
- Proper YAML formatting (2-space indent, no trailing spaces)
