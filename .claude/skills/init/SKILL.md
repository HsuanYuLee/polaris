---
name: init
description: >
  Interactive workspace initialization wizard. Creates a company directory
  with workspace-config.yaml, and registers it in the root config.
  Uses auto-detection (GitHub org, repos) and section-by-section Q&A.
  Each section is skippable.
  Use when: (1) user says "init", "initialize", "setup workspace", "初始化",
  "設定 workspace", (2) user just cloned the Xuanji template and needs to
  configure it, (3) user says "填 config", "setup config", "configure".
  Do NOT trigger for editing a single field — just edit the config directly.
metadata:
  author: Xuanji
  version: 3.0.0
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
Clone Xuanji → /init → company dir + config ready → start using skills
```

## smartSelect Interaction Pattern

All discovery-capable steps use a unified interaction model: **detect → present → confirm**.

### How it works

1. **Detect** — run auto-detection (CLI commands, MCP tools, AI analysis)
2. **Present** — show results as a table with pre-selected recommendations
3. **Confirm** — user picks one of three actions:
   - **Confirm (y)** — accept as-is, proceed to next step
   - **Adjust (e)** — user edits specific items (toggle selection, change values)
   - **Skip (s)** — skip entire section, leave config empty

### Display format

```
Step N: {Section Name}

  #   Select   Item                Tags              Keywords
  1   [✓]      your-app       [b2c]             B2C 前台, Nuxt SSR, 商品頁
  2   [✓]      your-design-system   [ds]              Design System, Vue 3, 元件庫
  3   [ ]      your-dev-proxy    [docker]           開發環境, Docker
  4   [✓]      your-backend           [member]           會員, PHP, Internal API

  Confirm (y) / Adjust (e) / Skip (s)?
```

When user picks **Adjust (e)**, ask which row(s) to change and what to change, then re-display.

### Which steps use smartSelect

| Step | Detection method | smartSelect columns |
|------|-----------------|---------------------|
| 3 JIRA | `getVisibleJiraProjects` MCP | Project key, Name, Team |
| 7 Projects | `gh repo list` + AI repo analysis | Name, Tags, Keywords |
| 8 Scrum | Static defaults | Setting, Value |

Steps 2 (GitHub), 4-6, 9 keep their current interaction (simple enough already).

## AI Repo Detection (Step 7)

When repos are selected in Step 7, analyze each repo to generate `tags` and `keywords` suggestions automatically.

### Detection sources (per repo)

| Source | What to extract |
|--------|----------------|
| `package.json` | Framework (nuxt/vue/react/next), key dependencies, project description |
| `src/` or `pages/` structure | Page names, feature areas, route patterns |
| `Dockerfile` / `docker-compose.yml` | Service type (web, api, worker) |
| Repo name | Split by `-` to derive short tag candidates |
| README.md (first 50 lines) | Project description, purpose |

### Detection flow

1. User selects repos from the `gh repo list` checklist
2. For each selected repo, dispatch a **parallel sub-agent** (model: `"haiku"`) to:
   - Read detection sources from `{base_dir}/{repo_name}/` (local path)
   - If local clone doesn't exist, use `gh api repos/{org}/{name}/contents/package.json` as fallback
   - Return: `{ tags: string[], keywords: string[] }`
3. Merge results and present via smartSelect table
4. User confirms/adjusts

### Tag generation rules

- **Tags** = short identifiers for JIRA ticket routing (1-2 words, lowercase)
  - Derive from: repo name segments, framework name, service role
  - Examples: `b2c`, `ds`, `api`, `admin`, `member`, `mobile`
- **Keywords** = human-readable descriptions for fuzzy matching (phrases)
  - Derive from: package.json description, detected framework + version, feature areas from page structure
  - Examples: `B2C 前台`, `Nuxt 3 SSR`, `商品頁`, `Design System`, `Vue 3 元件庫`

### Fallback

If analysis fails for a repo (no local clone, no package.json, API error):
- Set `tags: []`, `keywords: []`
- Mark with `[?]` in the smartSelect table so user knows to fill manually

## Audit Trail

Every step records decisions to `{company}/.init-audit.jsonl` for traceability.

### Format

One JSON object per line:
```json
{"ts": "2026-03-29T14:30:00Z", "step": 2, "section": "github", "action": "auto-detect", "value": "your-org", "source": "cli"}
{"ts": "2026-03-29T14:30:05Z", "step": 2, "section": "github", "action": "confirm", "value": "your-org", "source": "user"}
{"ts": "2026-03-29T14:31:00Z", "step": 3, "section": "jira", "action": "skip", "value": null, "source": "user"}
{"ts": "2026-03-29T14:32:00Z", "step": 7, "section": "projects", "action": "ai-detect", "value": {"repo": "your-app", "tags": ["b2c"], "keywords": ["B2C 前台", "Nuxt SSR"]}, "source": "ai"}
{"ts": "2026-03-29T14:32:30Z", "step": 7, "section": "projects", "action": "adjust", "value": {"repo": "your-app", "tags": ["b2c"], "keywords": ["B2C 前台", "Nuxt 3 SSR", "商品頁"]}, "source": "user"}
```

### Fields

| Field | Description |
|-------|-------------|
| `ts` | ISO 8601 timestamp |
| `step` | Step number (0-12) |
| `section` | Config section name (github, jira, projects, scrum, etc.) |
| `action` | What happened: `auto-detect`, `ai-detect`, `mcp-detect`, `confirm`, `adjust`, `skip`, `write` |
| `value` | The value detected/confirmed/adjusted (string, object, or null) |
| `source` | Origin: `cli` (shell command), `mcp` (MCP tool), `ai` (AI analysis), `user` (user input), `default` (static default) |

### Implementation

- Append-only — each step appends lines, never overwrites
- Write at the end of each step (not per-keystroke)
- Re-running `/init` on the same company appends a separator line: `{"ts": "...", "step": 0, "section": "init", "action": "restart", "value": null, "source": "system"}`

## Execution Flow

### Step 0: Pre-check

1. Check if root `workspace-config.yaml` exists
2. If exists → read it, show existing companies
   - Ask: "Add a new company / Edit existing company / Cancel?"
3. If not exists → will create fresh

Audit: log `action: "start"` or `action: "restart"`.

### Step 1: Company Basics

**Ask:**
```
Company name (used as directory name): e.g. "your-company", "my-startup"
```

**Auto-detect:**
- Check if `{company}/` directory already exists
- If exists and has `workspace-config.yaml` → offer to edit instead of overwrite

**Create company directory** if not exists, then copy `_template/workspace-config.yaml` as starting point.

Audit: log company name and whether it was new or existing.

### Step 2: GitHub

**Auto-detect:**
- Run `gh api user/orgs --jq '.[].login'` to list available orgs
- If only one org → pre-fill, ask to confirm
- If multiple → present as numbered list for selection

**Ask:**
```
GitHub org: (detected options or manual input)
```

Audit: log detected orgs and final selection.

### Step 3: JIRA (skippable) — smartSelect

**Auto-detect:**
1. Ask for Atlassian instance (e.g., `your-domain.atlassian.net`)
2. Use `getVisibleJiraProjects` MCP tool to fetch all visible projects

**smartSelect presentation:**
```
Step 3: JIRA Projects

  #   Select   Key      Name                    Team
  1   [✓]      GT       Growth Team Project      (enter team name)
  2   [✓]      TASK    K-Backend 2.0 CW         (enter team name)
  3   [ ]      MOB      Mobile App               —
  4   [ ]      INFRA    Infrastructure           —

  Confirm (y) / Adjust (e) / Skip (s)?
```

Pre-select heuristic: projects with recent activity (if detectable) or all if ≤ 5.

On **Confirm**: for each selected project, if team name is still empty, ask once for all teams in a batch:
```
Teams for selected projects:
  GT → ?
  TASK → ?
```

`custom_fields` → tell user this can be configured later, leave empty for now.

If user picks **Skip** → leave entire `jira:` section with empty/default values.

Audit: log detected projects, selections, and team assignments.

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

Audit: log instance, selected space.

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

Audit: log resolved channel IDs.

### Step 6: Kibana (skippable)

**Ask:**
```
Do you use Kibana/Elasticsearch for log querying? (y/n)
```

If yes → ask for host, index pattern, environments.
If no → leave empty.

Audit: log hosts and patterns.

### Step 7: Projects — smartSelect + AI Repo Detection

**Phase 1: Repo selection**
- Run `gh repo list {org} --limit 50 --json name,url --jq '.[] | .name'` to list repos
- Present as checklist: "Select repos you work on (space to toggle, enter to confirm)"

**Phase 2: AI analysis**
- For each selected repo, dispatch parallel sub-agents (model: `"haiku"`) to analyze
- See "AI Repo Detection" section above for detection sources and rules

**Phase 3: smartSelect presentation**
```
Step 7: Projects — AI-detected tags & keywords

  #   Select   Repo                  Tags        Keywords
  1   [✓]      your-app         [b2c]       B2C 前台, Nuxt 3 SSR, 商品頁
  2   [✓]      your-design-system     [ds]        Design System, Vue 3, 元件庫
  3   [✓]      your-backend             [member]    會員, PHP, Internal API
  4   [?]      your-dev-proxy      []          (analysis failed — fill manually)

  Confirm (y) / Adjust (e) / Skip (s)?
```

On **Adjust**: user specifies which row(s) to change tags/keywords, then re-display.

Audit: log AI-detected values (source: `ai`), final confirmed values (source: `user`).

### Step 8: Scrum Settings — smartSelect

**Pre-fill with defaults:**

```
Step 8: Scrum Settings

  #   Setting                Value
  1   PR approval threshold  2
  2   Need review label      "need review"
  3   Sprint capacity        20 points
  4   Excluded bots          ["github-actions[bot]"]

  Confirm (y) / Adjust (e)?
```

On **Confirm** → use defaults as-is.
On **Adjust** → ask which row(s) to change, then re-display.

Audit: log final values and whether defaults were used or adjusted.

### Step 9: Infra (skippable)

**Ask:**
```
Do you have ansible repos for deployment? (y/n)
```

If yes → ask for repo paths, dev host/port.
If no → leave empty.

Audit: log infra settings.

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

Audit: log `action: "write"` with the config file path.

### Step 11: Generate Genericize Mapping Files

Generate `{company}/genericize-map.sed` and `{company}/genericize-jira.sed` from the config values just collected. These are used by `sync-from-upstream.sh` to strip company-specific references before syncing to Xuanji upstream.

1. Copy `_template/genericize-map.sed` and `_template/genericize-jira.sed` to `{company}/`
2. Uncomment and fill patterns based on config values:

**genericize-map.sed** — derived from:
- `jira.instance` → domain replacement (e.g., `s/myco\.atlassian\.net/your-domain.atlassian.net/g`)
- `github.org` → org replacement (e.g., `s/my-org/your-org/g`)
- `projects[].name` → repo name replacements (longer names first to avoid partial matches)
- `projects[].repo` → full repo path replacements
- Company name → brand replacements (specific before general)
- Path replacement: `s|~/work/{company}|~/work/company|g`

**genericize-jira.sed** — derived from:
- `jira.projects[].key` → ticket key replacements (e.g., `s/PROJ-[0-9]\{1,\}/PROJ-123/g`)
- `confluence.space` → space replacement
- `slack.channels.*` → channel ID replacements
- `confluence.pages.*` → page ID replacements (non-empty values only)
- `jira.projects[].team` → team name replacements

3. Print: "Mapping files generated at `{company}/genericize-*.sed`. Review and add any patterns /init couldn't detect (internal URLs, teammate names, etc.)"

Audit: log generated file paths.

### Step 12: Done

Print: "Done! {company} is configured. Skills will now use these settings."

Audit: log `action: "complete"`.

## Important Rules

- **Never guess values** — if auto-detection fails, ask the user
- **Every section is skippable** — empty = feature disabled, skills degrade gracefully
- **Show what was detected** — user should see and confirm auto-detected values
- **Idempotent** — running `/init` again on an existing company should offer to edit, not destroy
- **No secrets in config** — company config is gitignored but should still not contain secrets
- **Use MCP tools when available** — prefer `getVisibleJiraProjects`, `getConfluenceSpaces`, `slack_search_channels` over manual input for discovery
- **Multi-company safe** — root config is append-only; adding a new company never touches existing entries
- **smartSelect is the default** — any step with auto-detection should use the detect → present → confirm pattern
- **AI detection is best-effort** — analysis failures are marked `[?]`, never block the wizard
- **Audit trail is append-only** — never overwrite `.init-audit.jsonl`, re-runs append a restart separator

## Output Format

The generated company config follows `_template/workspace-config.yaml` structure, with:
- Inline comments explaining each field
- Empty strings `""` for skipped optional fields
- Proper YAML formatting (2-space indent, no trailing spaces)
