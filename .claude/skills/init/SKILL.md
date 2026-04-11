---
name: init
description: "Use when the user wants to set up a new company workspace from scratch — creating its config directory and registering it. Trigger: 'init', 'initialize', 'setup workspace', '初始化', or when a new company needs to be onboarded."
metadata:
  author: Polaris
  version: 3.1.0
---

# /init — Workspace Initialization Wizard

Interactive wizard that creates a company directory with `workspace-config.yaml` and registers it in the root config.

## Two-Layer Config Architecture

```
{workspace_root}/workspace-config.yaml              ← Root config (company routing)
{workspace_root}/{company}/workspace-config.yaml    ← Company config (full settings)
{workspace_root}/_template/workspace-config.yaml    ← Template for new companies
```

## Overview

```
Clone Polaris → /init → company dir + config ready → start using skills
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
  1   [✓]      your-repo            [b2c]             B2C frontend, Nuxt SSR, product page
  2   [✓]      your-design-system   [ds]              Design System, Vue 3, component library
  3   [ ]      your-dev-docker      [docker]          Dev environment, Docker
  4   [✓]      your-api-repo        [member]          Member, PHP, Internal API

  Confirm (y) / Adjust (e) / Skip (s)?
```

When user picks **Adjust (e)**, ask which row(s) to change and what to change, then re-display.

### Which steps use smartSelect

| Step | Detection method | smartSelect columns |
|------|-----------------|---------------------|
| 3 JIRA | `getVisibleJiraProjects` MCP | Project key, Name, Description, Team |
| 4c Confluence pages | `searchConfluenceUsingCql` | Field, Found title, Page ID |
| 7 Projects | `gh repo list` + local scan + AI repo analysis | Name, Status, Tags, Keywords |
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
{"ts": "2026-03-29T14:30:00Z", "step": 2, "section": "github", "action": "auto-detect", "value": "acme-org", "source": "cli"}
{"ts": "2026-03-29T14:30:05Z", "step": 2, "section": "github", "action": "confirm", "value": "acme-org", "source": "user"}
{"ts": "2026-03-29T14:31:00Z", "step": 3, "section": "jira", "action": "skip", "value": null, "source": "user"}
{"ts": "2026-03-29T14:32:00Z", "step": 7, "section": "projects", "action": "ai-detect", "value": {"repo": "my-app", "tags": ["frontend"], "keywords": ["front-end", "Nuxt SSR"]}, "source": "ai"}
{"ts": "2026-03-29T14:32:30Z", "step": 7, "section": "projects", "action": "adjust", "value": {"repo": "my-app", "tags": ["frontend"], "keywords": ["front-end", "Nuxt 3 SSR", "product page"]}, "source": "user"}
```

### Fields

| Field | Description |
|-------|-------------|
| `ts` | ISO 8601 timestamp |
| `step` | Step number (0-14) |
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
   - Ask: "Add a new company / Edit existing company / Re-init (run new sections) / Cancel?"
3. If not exists → will create fresh

**Re-init mode** (for existing users after Polaris upgrades):

When user selects "Re-init" or says "re-init", "重跑 init", "補跑 init":

1. Read the existing company workspace-config.yaml
2. Scan which sections are **missing or empty** by checking for key fields:
   | Section | Check field | If missing → run |
   |---------|------------|-----------------|
   | Dev Environment (9a) | `projects[].dev_environment` | Step 9a |
   | Visual Regression (9b) | `visual_regression.domains[]` | Step 9b |
   | Scrum (8) | `scrum.*` | Step 8 |
   | Daily Learning (13) | `daily_learning_scan` | Step 13 |
3. Show which sections would be added:
   ```
   Re-init: {company}

   已有設定：GitHub ✓, JIRA ✓, Projects ✓, Scrum ✓, Slack ✓
   缺少設定：
     → Step 9a: Dev Environment（偵測 dev server 啟動方式）
     → Step 9b: Visual Regression（截圖比對設定）

   要補跑這些 section 嗎？(y/n)
   ```
4. Only run the missing sections — skip all others
5. Merge new config into existing file (do not overwrite existing fields)

This is the recommended path for users upgrading from pre-v1.46.0 who want the new dev environment and VR capabilities without re-running the full wizard.

Audit: log `action: "re-init"` with list of sections to run.

### Step 0a: Language Preference

After the pre-check, check if `language:` exists in root `workspace-config.yaml`.

**If `language` exists:**
- Read the value and announce: "Language: {language} (from workspace config)"
- Use this language for all subsequent prompts in this wizard

**If `language` does NOT exist:**
- Ask the user:
  ```
  Preferred language for AI responses?
  Common options: zh-TW, en, ja, ko
  
  Enter language code: 
  ```
- Write the value to root `workspace-config.yaml` (top-level field, before `companies:`)
- Use this language for all subsequent prompts in this wizard

**Format in config:**
```yaml
# Preferred language for AI responses. Set during /init.
language: zh-TW
```

Audit: log `{"step": 0, "section": "language", "action": "detect" or "set", "value": "{language}", "source": "config" or "user"}`.

### Step 1: Company Basics

**Ask:**
```
Company name (used as directory name): e.g. "acme", "my-startup"
```

**Validation:**
- Company name must be ASCII lowercase + hyphens only (e.g., `acme`, `my-startup`)
- Auto-convert simple cases: trim whitespace, lowercase
- If the result still contains non-ASCII characters, spaces, or uppercase: reject and explain: "Company name is used as a directory name. Please use lowercase ASCII characters and hyphens only (e.g., 'acme', 'my-company')."

**Auto-detect:**
- Check if `{company}/` directory already exists
- If exists and has `workspace-config.yaml` → offer to edit instead of overwrite

**Create company directory** if not exists, then copy `_template/workspace-config.yaml` as starting point.

**Scaffold company rules:**
1. Create `.claude/rules/{company_name}/` directory
2. Copy every `.md` file from `_template/rule-examples/` into `.claude/rules/{company_name}/`
3. In each copied file, insert a scope header after the first `# Title` line:
   ```
   > **Scope: {company_name}** — applies only when working on {company_name} tickets or projects.
   ```
4. Print: "Scaffolded L2 rules at `.claude/rules/{company_name}/` — customize these to match your team's conventions."

Audit: log company name, whether it was new or existing, and scaffolded rule files.

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

Include the project **Description** column from `getVisibleJiraProjects` to help distinguish similar-named projects (e.g., GROW "Growth" vs GT "Growth Team" vs GROWAD "Growth-Adtech"):

```
Step 3: JIRA Projects

  #   Select   Key      Name                    Description                          Team
  1   [✓]      GT       Growth Team             Web team growth & SEO initiatives     (enter team name)
  2   [✓]      TEAM    Acme Web App           B2C frontend development              (enter team name)
  3   [ ]      GROW     Growth                  Growth marketing campaigns            —
  4   [ ]      INFRA    Infrastructure          DevOps and infra                      —

  Confirm (y) / Adjust (e) / Skip (s)?
```

Pre-select heuristic: projects with recent activity (if detectable) or all if ≤ 5.

On **Confirm**: for each selected project, if team name is still empty, ask once for all teams in a batch:
```
Teams for selected projects:
  GT → ?
  TEAM → ?
```

**Ticket prefix verification** — after team assignment, confirm the selected keys match what the user actually types in ticket numbers. This catches key-vs-name confusion (common when multiple projects share similar names):

```
You selected: GT, TEAM

Quick check — when you reference tickets, do you use these prefixes?
  e.g., PROJ-123, TEAM-456

Correct (y) / Fix (e)?
```

If user picks **Fix** → show the full project list again for re-selection.

`custom_fields` → tell user this can be configured later, leave empty for now.

If user picks **Skip** → leave entire `jira:` section with empty/default values.

Audit: log detected projects, selections, team assignments, and prefix verification result.

### Step 4: Confluence (skippable)

**Ask:**
```
Do you use Confluence? (y/n)
```

If yes:

**4a. Space selection:**
1. Instance is usually same as JIRA → pre-fill from Step 3
2. Try `getConfluenceSpaces` MCP tool to list spaces → select primary space

**4b. Additional spaces:**
After selecting the primary space, ask if the user works with other spaces:
```
Primary space: AW (Acme Web)

Do you use other Confluence spaces regularly? (y/n)
```
If yes → let user select from the remaining spaces list. Write to `additional_spaces` array.

**4c. Page ID guided discovery:**
Instead of deferring all page IDs, use `searchConfluenceUsingCql` to search for common structures within the selected space. For each config field, run a targeted CQL query:

| Config field | CQL query | Match logic |
|---|---|---|
| `folders.sasd` | `space = "{space}" AND title ~ "SA" AND type = folder` | Look for SA/SD folder |
| `pages.standup_parent` | `space = "{space}" AND title ~ "Standup" AND type = page` | Find parent of monthly standup pages |
| `pages.release_parent` | `space = "{space}" AND title ~ "Release" AND type = page` | Find parent of sprint release pages |
| `pages.rd_workflow` | `space = "{space}" AND title ~ "RD workflow" AND type = page` | Direct match |
| `pages.skills_reference` | `space = "{space}" AND title ~ "skill" AND type = page` | Direct match |
| `pages.estimation_guide` | `space = "{space}" AND title ~ "estimation" AND type = page` | Direct match |

Present discovered items via smartSelect:
```
Step 4c: Confluence Page IDs — auto-detected from space "KW"

  #   Select   Field              Found                              Page ID
  1   [✓]      SA/SD folder       SA/SD                              425689183
  2   [?]      Standup parent     (multiple matches — pick one)      —
  3   [?]      Release parent     (multiple matches — pick one)      —
  4   [ ]      RD workflow        (not found)                        —
  5   [ ]      Skills reference   (not found)                        —
  6   [ ]      Estimation guide   (not found)                        —

  Confirm (y) / Adjust (e) / Skip (s)?
```

**Handling multiple matches:** When CQL returns multiple results (e.g., multiple "Standup" pages from different months), display the top results and ask the user to pick the parent page — not the individual monthly/sprint pages.

**Handling no match:** Mark as `[ ]` with "(not found)" — user can fill in manually via Adjust, or leave empty. Fields left empty are still deferred, but the user has been actively guided rather than silently skipped.

If no → leave entire `confluence:` section empty.

Audit: log instance, selected spaces, CQL results, and final page ID selections.

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

**Phase 0: Local repo scan**
Before fetching from GitHub, scan `{base_dir}/` for existing directories that look like git repos:
- Run `ls` on `{base_dir}/` to list directories
- For each directory, check if it contains `.git/` (is a cloned repo)
- Record these as `local_repos` for cross-referencing in Phase 1

**Phase 1: Repo selection**
- Run `gh repo list {org} --limit 50 --json name,url --jq '.[] | .name'` to list repos
- **Cross-reference with local_repos**: mark repos that exist locally with `[local]`, and flag local repos that are NOT in the GitHub list with `[local only]`
- Present as checklist with local status:

```
Step 7a: Repo Selection

  #   Select   Repo                  Status
  1   [✓]      your-repo             [local]
  2   [✓]      your-design-system    [local]
  3   [ ]      your-api-repo         (not cloned)
  4   [ ]      your-dev-docker       (not cloned)
  ──  Local repos not in GitHub top 50  ──
  5   [ ]      your-legacy-app       [local only]
  6   [ ]      your-web-skills       [local only]

  Confirm (y) / Adjust (e) / Skip (s)?
```

The `[local only]` section ensures repos already cloned but not returned by `gh repo list` (archived, different org, or beyond the 50-repo limit) are still visible. If a `[local only]` repo is selected, derive its `repo` field from `git -C {base_dir}/{name} remote get-url origin`.

**Phase 2: AI analysis**
- For each selected repo, dispatch parallel sub-agents (model: `"haiku"`) to analyze
- See "AI Repo Detection" section above for detection sources and rules

**Phase 3: smartSelect presentation**
```
Step 7b: Projects — AI-detected tags & keywords

  #   Select   Repo                  Tags        Keywords
  1   [✓]      your-repo             [b2c]       B2C frontend, Nuxt 3 SSR, product page
  2   [✓]      your-design-system    [ds]        Design System, Vue 3, component library
  3   [✓]      your-api-repo         [member]    Member, PHP, Internal API
  4   [?]      your-dev-docker       []          (analysis failed — fill manually)

  Confirm (y) / Adjust (e) / Skip (s)?
```

On **Adjust**: user specifies which row(s) to change tags/keywords, then re-display.

Audit: log local scan results, GitHub list, cross-reference matches, AI-detected values (source: `ai`), final confirmed values (source: `user`).

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

### Step 9a: Dev Environment (skippable)

Discover how to start the local development environment for each selected project. This information powers visual regression and verify-completion skills.

**Auto-detect per project:**

For each project selected in Step 7, dispatch parallel sub-agents (model: `"haiku"`) to scan:

1. `docker-compose.yml` / `docker-compose.*.yml` → `docker compose up` variant
2. `package.json` → `scripts.dev`, `scripts.start`, `scripts.serve`
3. `Makefile` → `dev`, `serve`, `start` targets
4. `README.md` → setup/development section (regex: `/## *(setup|development|getting started|local)/i`)

**Monorepo detection**: if `package.json` has `workspaces` or `pnpm-workspace.yaml` exists, list all apps/packages with dev scripts and present them for selection — don't assume which app is the "main" one:

```
Step 9a-0: Monorepo — your-your-app

  Multiple apps detected:

  #   App                 Dev Script        Port
  1   apps/main           pnpm dev:main     3001
  2   apps/trans          pnpm dev:trans    3002
  3   apps/demo           pnpm dev:demo    3003

  Which app(s) are your primary development targets? (comma-separated, e.g. 1,2)
```

**Cross-repo dependency detection**: after scanning all repos individually, check for dependencies between them:

1. Scan each `docker-compose.yml` for volume mounts pointing to other repos (e.g., `../acme-member-api:/app`)
2. Scan `.env` / `.env.example` files for references to other repos' ports or services
3. Check README for "requires X to be running" patterns
4. If a repo's HTTP server depends on another repo (e.g., nginx proxies to an app server), mark the dependency

Present dependencies as a warning:

```
Step 9a-1: Cross-Repo Dependencies

  ⚠ Detected dependencies:

    your-your-backend → requires your-web-docker (nginx proxy)
    your-your-app   → requires your-web-docker (Docker dev environment)
    your-web-docker is a prerequisite for 2 projects

  This means: start your-web-docker FIRST, then the individual app dev servers.

  Confirm (y) / Adjust (e)?
```

Output: `projects[].dev_environment.requires` field listing prerequisite repos.

**Missing .env template warning**: if a project has `--dotenv .env.local` or similar in its start script, but no `.env.example` / `.env.template` exists:

```
  ⚠ your-your-app requires .env.local but has no template file.
    New developers will need environment values from a teammate.
    Consider adding a .env.example to the repo.
```

**smartSelect presentation:**

```
Step 9a-2: Dev Environment

  #   Project              Start Command                          Ready Signal        Base URL          Requires
  1   your-your-app         pnpm dev:main                          Listening on        http://localhost:3001  web-docker
  2   your-web-docker      docker compose up -d                   started             https://dev.example.com  —
  3   your-design-system   pnpm dev:3                             VITE ready          http://localhost:3000  —
  4   your-your-backend       pnpm dev (watch mode, no server)       compiled            (via web-docker)  web-docker

  Confirm (y) / Adjust (e) / Skip (s)?
```

On **Adjust** → user specifies which row(s) to change. Common adjustments: base_url, ready_signal, env vars, requires.

On **Skip** → leave `dev_environment` block empty. Visual regression will ask at runtime.

**Health check field**: for each project, also infer a health check URL (typically `{base_url}/` or `{base_url}/health`). For projects that depend on another repo's server (e.g., your-backend via web-docker), use the prerequisite's base_url as health check.

**Output**: populates `projects[].dev_environment` in the company workspace-config:

```yaml
projects:
  - name: your-your-app
    dev_environment:
      start_command: "pnpm dev:main"
      ready_signal: "Listening on"
      base_url: "http://localhost:3001"
      health_check: "http://localhost:3001/"
      requires: ["your-web-docker"]  # must be running first
      env: {}  # user can add env vars later
```

Audit: log detected values (source: `ai`), dependencies found, missing env templates, final confirmed values (source: `user`).

### Step 9b: Visual Regression (skippable)

Configure visual regression testing for web-facing domains.

**Pre-condition**: only show this step if at least one selected project has a web frontend (detected by tags containing `b2c`, `web`, `frontend`, or by the presence of a framework like Nuxt/Next/Vue/React in Step 7 AI analysis).

**Ask:**
```
你的專案有 web 前端，要設定 visual regression 嗎？
（截圖比對，確保改動不破壞既有頁面）

  (y) 設定  (n) 跳過
```

If yes:

**Phase 1: Domain mapping**

Map web projects to their production domains. **Always ask the user to confirm or enter the domain** — auto-detection from code is unreliable (`.env` typically contains dev URLs, not production; deploy-time templates are unresolvable).

```
Step 9b-1: Domain Mapping

  Which domain does each web project serve?
  （.env 裡的 URL 是 dev 環境，這裡要填 production domain）

  #   Project              Domain (suggested)       Source
  1   your-your-app         _______________          (無法從代碼偵測 — 請輸入)
  2   your-web-docker      (provides dev infra, skip)

  Enter domain for #1:
```

The AI may suggest a domain if found in README, `nuxt.config.*` hostname, or `package.json` homepage — but it must be presented as a suggestion requiring explicit confirmation, never auto-applied. If nothing is found, leave blank and require user input.

**Phase 2: Key pages**

For each domain, suggest key pages based on the project's routes.

Auto-detect pages from: `pages/` directory structure (Nuxt/Next), router config, sitemap.xml reference.

**Dynamic route handling**: routes with parameters (e.g., `/product/[id]`, `/destination/[slug]`) need concrete example values to be testable. For each dynamic route detected:
- Present the route pattern so the user understands the structure
- **Ask the user to provide an example URL** that works on the SIT/dev environment
- Skip redirect-only pages (detected by component names like `Forward.vue`, `Redirect.vue`, or containing only `navigateTo`/`redirect`)

**Locale handling**: if the project uses i18n, read the locale list from the i18n config file (e.g., `nuxt.config.ts` → `i18n.locales`) and use the exact locale codes (case-sensitive). Default to testing the primary locale only; user can expand.

```
Step 9b-2: Key Pages — www.example.com

  Auto-detected from pages/ directory. Dynamic routes need example URLs.

  #   Select   Page            Path                        Viewports
  1   [✓]      homepage        /                           [1280, 375]
  2   [✓]      product-page    /product/___  (enter ID)    [1280, 375]
  3   [✓]      destination     /destination/___ (enter slug) [1280, 375]
  4   [✓]      category        /category/tag/outdoor        [1280, 375]
  5   [ ]      promo           /promo/___ (enter slug)      [1280, 375]

  Locale: zh-TW (from i18n config, 17 locales available — test primary only by default)

  Enter example ID for #2 (product page): ____
  Enter example slug for #3 (destination): ____

  Confirm (y) / Adjust (e) / Add more (a)?
```

**Phase 3: SIT URL**

**Always ask the user** — do NOT auto-detect from `.env` files. The `.env` typically contains local dev URLs (e.g., `dev.example.com`), not the actual SIT/staging environment URL. These are different things and confusing them causes VR to compare against the wrong baseline.

```
Step 9b-3: SIT/Staging Environment

  VR 的 before/after 比對需要一個穩定的「改動前」基準。
  SIT/Staging 環境可以作為這個基準（不需要 git stash）。

  ⚠ 注意：這裡要填 staging/SIT 環境的 URL，不是 local dev URL。
     例如：https://www.sit.example.com（不是 https://dev.example.com）

  Does {domain} have a SIT/staging URL?

  (1) Yes → enter SIT URL: _______________
  (2) No → will use git stash local mode
```

**Phase 3.5: Locale expansion**

After confirming pages, ask whether to test additional locales:

```
  Primary locale: zh-TW (will be tested by default)
  Available: zh-TW, en, ja, ko, ... (18 locales)

  Test additional locales? (enter codes comma-separated, or press Enter for primary only)
  > ____
```

**Output: Server config resolution**

The `server` block in the VR config describes how to access the domain for screenshots. This is NOT necessarily the same as the app's own dev command from Step 9a.

**Resolution logic:**
1. Check Step 9a-1 dependencies: does this project **require an infrastructure repo** (e.g., Docker stack with nginx)?
2. **If yes** → the infrastructure repo is the HTTP entry point for this domain. Use its `start_command` and `base_url`:
   - `start_command` = infrastructure repo's start command (e.g., `docker compose ... up -d`)
   - `base_url` = infrastructure repo's base URL (e.g., `https://dev.example.com`)
   - The app's own dev command (`pnpm dev:main`) runs separately as a background process
3. **If no** (app has its own standalone dev server) → use the app's own `start_command` and `base_url` from Step 9a

Present this to the user for confirmation:

```
Step 9b-4: VR Server Config — www.example.com

  How should VR access this domain for screenshots?

  acme-web-app depends on acme-web-docker (detected in Step 9a).
  → 建議使用 Docker stack 的 URL 作為截圖目標（完整整合環境）。

  Option A (recommended): Docker stack — full integrated environment
    start_command: docker compose -f .../docker-compose.yml up -d
    base_url: https://dev.example.com
    （需同時跑 pnpm dev:main 提供 Nuxt HMR）

  Option B: Standalone Nuxt dev server
    start_command: pnpm dev:main
    base_url: http://localhost:3001
    （部分功能可能缺失 — 無 PHP routes、無 nginx proxy）

  Choose (A/B):
```

**Output**: populates `visual_regression.domains[]` in the company workspace-config:

```yaml
visual_regression:
  domains:
    - name: "www.example.com"
      server:
        start_command: "docker compose -f .../docker-compose.yml up -d"  # from infra repo
        ready_signal: "ready"
        base_url: "https://dev.example.com"  # from infra repo
        sit_url: "https://www.sit.example.com"  # from Phase 3
      global_masks:
        - "[data-testid*='date']"
        - "[data-testid*='price']"
        - ".ad-banner"
      locales: ["zh-TW"]  # from Phase 2 + 3.5
      locale_strategy: "url_prefix"
      pages:
        - name: "homepage"
          path: "/"
          source_project: "your-your-app"
          viewports: [1280, 375]
          scroll_before_capture: true
```

**Phase 4: Generate test files**

After config is written (Step 10), generate initial test files:

```
ai-config/{company}/visual-regression/{domain}/
  ├── playwright.config.ts
  └── pages.spec.ts
```

Use the templates from the existing `ai-config/acme/visual-regression/www.example.com/` as reference. Generate based on the configured pages and settings.

If `package.json` doesn't exist at `ai-config/{company}/visual-regression/`, create it with `@playwright/test` dependency.

Audit: log domain mappings, page counts, whether SIT URL was provided, test files generated.

### Step 10: Review & Write

1. Show the complete generated company config YAML
2. **Verify `default_company` is NOT in the company config** — `default_company` belongs in the root `workspace-config.yaml`, not the company config. If the user wants to set a default company, write it to the root config in step 4 below
3. Ask: "Write to {company}/workspace-config.yaml? (y/n)"
4. If yes → write company config file
5. Update root `workspace-config.yaml` — add/update the company entry:
   ```yaml
   companies:
     - name: {company}
       base_dir: "{actual_path_to_company_dir}"
   ```
   Use the actual absolute path where the company directory was created — do NOT hardcode `~/work/`. If the workspace root is `/home/user/projects/polaris`, then `base_dir` should be `/home/user/projects/polaris/{company}`.
6. **Set default company** — if this is the only company in root config, ask:
   ```
   This is your only configured company. Set "{company}" as default? (y/n)
   ```
   If yes → add `default_company: {company}` to root `workspace-config.yaml` (top-level field, not inside `companies[]`)

Audit: log `action: "write"` with the config file path.

### Step 10a: Clone Missing Repos

Compare the repos selected in Step 7 against what actually exists under `{base_dir}/`:

```
Step 10a: Repo Clone

  These selected repos are not cloned locally:

    your-api-repo       → gh repo clone {org}/your-api-repo {base_dir}/your-api-repo
    your-dev-docker     → gh repo clone {org}/your-dev-docker {base_dir}/your-dev-docker

  Clone all (a) / Select which to clone (s) / Skip (n)?
```

- **Clone all (a)** → run `gh repo clone` for each missing repo sequentially
- **Select (s)** → let user toggle which repos to clone
- **Skip (n)** → no cloning, continue

Cloning happens sequentially (not parallel) to avoid GitHub rate limits. Show progress as each repo completes.

Audit: log which repos were cloned, which were skipped.

### Step 11: Generate Genericize Mapping Files

Generate `{company}/genericize-map.sed` and `{company}/genericize-jira.sed` from the config values just collected. These are used by `sync-from-upstream.sh` to strip company-specific references before syncing to Polaris.

1. Copy `_template/genericize-map.sed` and `_template/genericize-jira.sed` to `{company}/`
2. Uncomment and fill patterns based on config values:

**genericize-map.sed** — derived from:
- `jira.instance` → domain replacement (e.g., `s/myco\.atlassian\.net/your-domain.atlassian.net/g`)
- `github.org` → org replacement (e.g., `s/my-org/your-org/g`)
- `projects[].name` → repo name replacements (longer names first to avoid partial matches)
- `projects[].repo` → full repo path replacements
- Company name → brand replacements (specific before general)
- Path replacement: `s|{base_dir}/{company}|{base_dir}/company|g`

**genericize-jira.sed** — derived from:
- `jira.projects[].key` → ticket key replacements (e.g., `s/PROJ-[0-9]\{1,\}/PROJ-123/g`)
- `confluence.space` → space replacement
- `slack.channels.*` → channel ID replacements
- `confluence.pages.*` → page ID replacements (non-empty values only)
- `jira.projects[].team` → team name replacements

3. Print: "Mapping files generated at `{company}/genericize-*.sed`. Review and add any patterns /init couldn't detect (internal URLs, teammate names, etc.)"

Audit: log generated file paths.

### Step 12: MCP Health Check

Verify that configured MCP servers are reachable. Run each check silently and report results:

| MCP Server | Check method | Required? |
|------------|-------------|-----------|
| **Atlassian** | Call `getAccessibleAtlassianResources` — expect non-empty response | If JIRA or Confluence configured |
| **Slack** | Call `slack_search_channels` with a known channel name — expect results | If Slack configured |
| **Google Calendar** | Call `gcal_list_calendars` — expect non-empty response | Optional |
| **Figma** | Call `whoami` — expect authenticated response | Optional |

**Display format:**
```
MCP Health Check:
  ✓ Atlassian  — connected (3 accessible resources)
  ✓ Slack      — connected
  ✗ Google Cal — not configured (optional — adds meeting context to standup)
  — Figma      — skipped (not configured)
```

**Rules:**
- Never block the wizard on a health-check failure — warn and continue
- If a required MCP fails → print: "⚠ {server} is not responding. Skills that depend on it (e.g., {skill_list}) will not work until fixed. See MCP setup in README."
- If an optional MCP fails → print: "ℹ {server} is not configured. This is optional."
- Record results in audit trail: `{"step": 12, "section": "mcp_health", "action": "check", "value": {"atlassian": "ok", "slack": "ok", "gcal": "not_configured"}, "source": "mcp"}`

### Step 13: Daily Learning Scanner (skippable)

```
每日技術文章掃描（Daily Learning Scanner）

Polaris 可以每天自動掃描技術文章，推薦到你的 Slack channel。
設定過程中會請你確認：

  1. Slack channel — 從你的 workspace config 讀取 ai_notifications channel
  2. 技術棧 — 從你的 projects 設定自動偵測（可調整）
  3. Active repos — 從 config 偵測，用來標記文章跟哪個 repo 相關
  4. 自訂主題 — 選填，額外關注的技術領域
  5. 排程時間 — 預設每天 21:57

要現在設定嗎？(y/n)
```

| 回應 | 動作 |
|------|------|
| `y` | 執行 learning skill 的 Setup mode（讀取 `skills/learning/SKILL.md` 的 Setup Learning Flow，從 Step S2 開始執行，因為 S1 check 不需要） |
| `n` | 跳過。使用者之後可用 `learning setup` 或 `設定學習` 啟用 |

Audit: log `action: "daily-learning"`, value: `{"enabled": true/false, "trigger_id": "..." or null}`.

### Step 13.5: Install Framework Dependencies

Install Polaris framework tools (Playwright for E2E, Mockoon CLI for mock fixtures):

```bash
{workspace_root}/scripts/install-deps.sh
```

This installs:
1. `scripts/e2e/node_modules/` — Playwright test runner
2. `scripts/mockoon/node_modules/` — Mockoon CLI
3. Playwright Chromium browser

If install fails (network issue), log warning but don't block — skills degrade gracefully without these tools.

Audit: log `action: "install-deps"`, value: `{"e2e": true/false, "mockoon": true/false, "chromium": true/false}`.

### Step 14: Done

**14a. Deferred fields summary** — scan the generated company config for empty string values. If any exist, list them with guidance:

```
Done! {company} is configured.

⚠ The following fields were left empty — you can fill them in later:

  Section        Field                How to fill
  ──────────     ──────────           ──────────
  confluence     pages.rd_workflow    Find the page in Confluence → copy page ID from URL
  confluence     pages.estimation_guide  Same as above
  jira           custom_fields        Run /init again and select "Edit existing"

  To edit: open {company}/workspace-config.yaml directly, or run /init → Edit existing.
```

Only show this table if there are actually empty fields. If everything was filled, skip it.

**14b. Next steps:**
```
What's next — try your first command:
  "work on PROJ-123" / 「做 PROJ-123」  → reads JIRA, estimates, codes, opens PR
  "standup"                              → generates daily standup report

Skills degrade gracefully — missing config fields won't break anything,
but filling them in unlocks the full workflow.
```

Audit: log `action: "complete"`, include list of deferred fields.

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

## Optional Final Step: Repo Handbook Generation

After the init wizard completes (config written, projects mapped), offer to generate handbooks for the configured repos:

> "要不要為已設定的 repo 建立 handbook？Handbook 是給 AI 看的架構文件，幫助 sub-agent 理解每個 repo 的結構，減少每次重新探索的成本。（可以之後再做，第一次 work-on 時會自動觸發）"

If user accepts:

1. For each repo in the company's `projects` block that has a local path:
   a. Explore the repo — detect repo type per `skills/references/repo-handbook.md` § Step 1
   b. Generate handbook draft per § Step 2
   c. Present to user for confirmation/correction per § Step 3
   d. Write to `{repo}/.claude/handbook.md`
2. If multiple repos, process sequentially (each needs user Q&A)
3. Skip repos where `{repo}/.claude/handbook.md` already exists

If user declines: skip entirely. Handbooks will be auto-generated on first `work-on`.

## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
