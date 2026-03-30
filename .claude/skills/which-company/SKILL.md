---
name: which-company
description: >
  Diagnostic command that shows which company a JIRA ticket or project routes to.
  Displays the full routing resolution: root config → company match → project mapping.
  Use when: (1) user says "which company", "哪間公司", "/which-company",
  (2) user is confused about which company context is active,
  (3) debugging routing issues for a JIRA ticket or project key.
  Do NOT use for actual work on tickets — use work-on, fix-bug, etc. instead.
metadata:
  author: Polaris
  version: 1.0.0
---

# Which Company — Routing Diagnostic

A lightweight diagnostic that resolves a JIRA ticket key (or the current context) through the workspace config routing chain and displays the result.

## Input

- **Optional**: a JIRA ticket key (e.g., `PROJ-123`) or project prefix (e.g., `PROJ`)
- If no input is provided, diagnose the current working directory context

## Steps

### Step 1: Read root config

Resolve the workspace root (the directory containing `CLAUDE.md` and `.claude/`), then read `{workspace_root}/workspace-config.yaml` to get the `companies[]` list.

If the file does not exist, report: "No workspace-config.yaml found. Run `/init` to set up your workspace."

### Step 2: Resolve company

**If a JIRA key or prefix was provided:**
1. For each company in `companies[]`, read `{base_dir}/workspace-config.yaml`
2. Check `jira.projects[].key` for a match against the ticket's project prefix
3. Report the first match

**If no input was provided:**
1. Check if the current working directory is under any company's `base_dir`
2. If yes, that's the active company
3. If no, report "Not inside any company directory"

**If only one company is registered**, report it as the default.

### Step 3: Display diagnostic output

Format the output as a clear summary:

```
🔍 Routing Diagnostic

Ticket:    PROJ-123
Company:   acme
Base dir:  {base_dir}/acme
Config:    {base_dir}/acme/workspace-config.yaml

Resolved via: jira.projects[].key match ("PROJ")

Company config summary:
  GitHub org:    acme-org
  JIRA instance: acme.atlassian.net
  Projects:      3 mapped
  Rules:         .claude/rules/acme/ (X files)
  Skills:        .claude/skills/acme/ (Y files)
```

If the ticket key does not match any company, report:

```
⚠️  No company match for "PROJ-123"

Registered companies:
  - acme (JIRA projects: ACME, PROJ-A)
  - bigcorp (JIRA projects: BC, CORP)

The ticket's project prefix "PROJ" does not match any configured jira.projects[].key.
Check {company}/workspace-config.yaml to add the project mapping.
```

### Step 4: Check for potential issues

Flag any of these if detected:
- Company config file missing (`{base_dir}/workspace-config.yaml` does not exist)
- No `jira.projects` defined in a company config
- Multiple companies claim the same JIRA project prefix (ambiguous routing)
- Rules directory `.claude/rules/{company}/` does not exist (no L2 rules)
