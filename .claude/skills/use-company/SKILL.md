---
name: use-company
description: >
  Sets the active company context or diagnoses company routing.
  Two modes: (1) Set — declare which company to work with, bypassing auto-detection.
  (2) Diagnose — show which company a JIRA ticket or project routes to.
  Trigger keywords: "use company", "switch company", "切換公司", "用這間", "/use-company",
  "set company", "公司切換", "我要做 X 公司的", "which company", "哪間公司", "/which-company".
user-invocable: true
---

# /use-company — Active Company Context Switcher

## Purpose

Explicitly sets which company context to use for the current conversation, avoiding repeated auto-detection or ambiguity when working across multiple companies.

## Workflow

### Step 1 — Resolve Target Company

**If the user provides a company name:**
1. Read `{workspace_root}/workspace-config.yaml` → get `companies[]` list
2. Match the provided name against company entries (case-insensitive, partial match OK)
3. If no match → list available companies and ask the user to choose

**If no company name provided:**
1. Read `{workspace_root}/workspace-config.yaml` → get `companies[]` list and `default_company` field
2. If `default_company` is set → use it as the target company (skip user prompt, proceed to Step 2)
3. Otherwise → list all available companies with their key info (base_dir, GitHub org, JIRA projects) and ask the user to select one

### Step 2 — Load and Validate Company Config

1. Read `{base_dir}/workspace-config.yaml` for the selected company
2. Validate the config exists and has required fields (github.org, jira.projects)
3. If config is missing or invalid → warn the user and suggest running `/init`

### Step 3 — Confirm Context

Display a brief summary:

```
✓ Active company: {company_name}
  Base dir:     {base_dir}
  GitHub org:   {github_org}
  JIRA projects: {project_keys}
  Slack:        {configured channels or "not configured"}
```

### Step 4 — Inform Strategist

State explicitly: "For the remainder of this conversation, route all work through **{company_name}** context. Apply L2 rules from `.claude/rules/{company_name}/` and resolve config from `{base_dir}/workspace-config.yaml`."

## Notes

- This sets context for the CURRENT conversation only — it does not persist across conversations
- If the user later references a ticket from a different company, warn them about the context mismatch

## Diagnostic Mode

When the user provides a JIRA ticket key or project prefix and wants to know routing (not set context), display the routing resolution:

```
🔍 Routing Diagnostic

Ticket:    PROJ-123
Company:   acme
Base dir:  {base_dir}
Config:    {base_dir}/workspace-config.yaml

Resolved via: jira.projects[].key match ("PROJ")
```

If no match found, list all registered companies and their JIRA project keys.

Flag potential issues: missing config files, undefined `jira.projects`, multiple companies claiming the same project prefix.


## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
