---
name: validate-isolation
description: >
  Diagnostic skill that scans the workspace for multi-company isolation issues:
  L2 rules missing scope headers, memory files without company: field,
  conflicting directives across companies.
  Use when: (1) user says "validate isolation", "檢查隔離", "/validate-isolation",
  (2) after adding a new company to verify setup,
  (3) as part of a periodic workspace health check.
metadata:
  author: Polaris
  version: 1.0.0
---

# Validate Isolation — Multi-Company Diagnostic

Scans the workspace for isolation violations that could cause cross-company contamination in rules, memories, or config.

## Input

- **Optional**: a company name to focus the scan on (e.g., `acme`). If omitted, scan all companies.

## Steps

### Step 1: Load workspace config

Read `{workspace_root}/workspace-config.yaml` to get the list of configured companies.

If no config exists → report "No workspace-config.yaml found. Run `/init` first." and stop.

### Step 2: Scan L2 rule files for scope headers

For each company directory under `.claude/rules/{company}/`:

1. List all `.md` files
2. Check each file for the scope header pattern: `> **Scope: {company}**`
3. Report files **missing** the scope header as 🔴 violations

**Pass criteria**: every `.md` file in a company directory has a matching scope header.

### Step 3: Scan for cross-company directive conflicts

Read all L2 rule files across all companies. Flag if:

- Two companies define **contradictory rules** for the same topic (e.g., different PR approval counts, different branch naming conventions) → 🟡 warning (may be intentional, but worth reviewing)
- A company rule references another company's config values (hardcoded project keys, org names, Slack channels from a different company) → 🔴 violation

### Step 4: Scan memory files for company isolation

Read all memory files in the memory directory (`~/.claude/projects/*/memory/`):

1. For each file with company-specific content (references a specific company's JIRA projects, repos, workflows):
   - Check if `company:` frontmatter field is present
   - If missing → 🟡 warning: "Memory '{name}' appears company-specific but lacks `company:` field"
2. For each file with `company:` field:
   - Verify the company name matches a configured company in workspace-config.yaml
   - If not → 🔴 violation: "Memory '{name}' scoped to '{company}' which is not in workspace config"

### Step 5: Check MEMORY.md index format

Read `MEMORY.md` and check:

- Company-scoped memory files should have `[company]` prefix in their index entry
- Report entries missing the prefix as 🟡 warnings

### Step 6: Report

Output a structured report:

```
## Isolation Validation Report

### L2 Rules
✅ {company-a}: 5/5 files have scope headers
🔴 {company-b}: 2/4 files missing scope headers
   - rules/{company-b}/pr-review.md — missing scope header
   - rules/{company-b}/jira-fields.md — missing scope header

### Cross-Company Conflicts
✅ No conflicts detected
(or list of 🟡 warnings)

### Memory Isolation
✅ 12 workspace-wide memories (no company field — correct)
🟡 3 memories appear company-specific but lack company: field
   - feedback_xyz.md — references ACME JIRA projects
🔴 1 memory scoped to non-existent company
   - project_old.md — company: defunct-co (not in config)

### MEMORY.md Index
🟡 2 company-scoped entries missing [company] prefix

### Summary
{total} checks | {pass} ✅ | {warn} 🟡 | {fail} 🔴
```

If all checks pass, output: `✅ Isolation is clean. No issues found.`
