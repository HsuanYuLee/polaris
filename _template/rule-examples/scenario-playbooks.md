# Scenario Playbooks

## Estimation → Implementation Loop

**Phase A: Estimation Agent**
1. Read JIRA Epic → verify completeness (path, Figma, AC, API doc)
2. Confirm project (mapping)
3. Break down sub-tasks, each with story points + Happy Flow verification scenario
4. Present in a table → **discuss and adjust with the user until the final version is confirmed**
5. After confirmation, use sub-agent to batch-create JIRA sub-tasks in parallel
6. Ask whether to produce SA/SD → if yes, generate and push to Confluence

**Phase B: Implementation Agent**
7. Read sub-tasks + SA/SD (from JIRA/Confluence) + codebase
8. Plan the implementation approach, determine whether there are **technical blockers**:
   - The planned approach doesn't work (API doesn't exist, component doesn't support required props)
   - The impact scope is much larger than the sub-task describes (changing A affects B, C)
   - Cross-project changes required (must change shared library before consumer app can use it)
   - ⚠️ Not a technical blocker: simply writing a few more lines of code, needing to check API docs for parameters
9. **No blockers** → proceed to development
10. **Blockers found** → bring specific issues back to Estimation Agent for re-estimation

**Re-estimation Guardrails:**
- After re-estimation, update JIRA sub-tasks + Confluence SA/SD (update the original page, do not create a new one)
- If story points change by > 30% from original, pause and ask the user to confirm
- **Maximum 2 re-estimation rounds**; escalate to the user for manual handling if exceeded
- JIRA / Confluence serve as shared memory between agents — do not rely on agent context

## Dependent Branches (Based on an Unmerged Branch)

When a JIRA ticket depends on another ticket that has not yet been merged:

1. **Detect dependency**: Before creating a branch, check JIRA comments for dependency markers (`base on`, `depends on`, `needs XX to merge`)
2. **Find the dependent branch**: Use `gh pr list --search "<dependent JIRA key>"` to locate the corresponding PR and branch
3. **Create new branch from the dependent branch**: `create-branch.sh <TICKET> <DESC> <dependent-branch>`
4. **Set PR base to the dependent branch** (not develop) → diff shows only this ticket's changes
5. **After the dependency merges**: rebase develop → change PR base back to develop
6. **If the dependency PR is rejected / heavily revised**: rebase to the latest version of the dependent branch, resolve conflicts

⚠️ Always confirm the dependency relationship and base branch with the user before creating a branch — do not decide automatically

## Feature Development

1. Read JIRA ticket → confirm project (mapping) → navigate to the project directory
2. Estimation Agent breaks down sub-tasks with story points → create JIRA sub-tasks → SA/SD (optional)
3. Implementation Agent feasibility check (if blockers found, return to Estimation Agent for re-estimation, max 2 rounds)
4. Auto-enter development: create the parent branch from develop (`{task-type}/{EPIC-KEY}-{description}`), produce the sub-task dependency graph
5. **Each sub-task must have its own branch cut from the parent branch** (`task/{SUB-TICKET-KEY}-{description}`) → develop → quality check → Pre-PR review loop → **open PR against the parent branch**
   - ⚠️ **Forbidden**: committing sub-task changes directly on the parent branch
   - Sub-tasks with dependencies may be developed on the same branch, but **must be split into separate commits**
   - Sub-task PR base branch is the parent branch, not develop
6. After all sub-tasks are merged, the parent branch → develop PR is opened manually by the developer. Parent PR uses the dedicated template (`pr-convention` Step 4a)

## Bug Fix

> **One-click trigger**: `help me fix PROJ-432` / `fix bug PROJ-432`

1. Read JIRA ticket → confirm project (mapping) → navigate to the project directory
2. Analyze root cause → produce Root Cause + Solution + story points (initial version) → leave JIRA comment after developer confirmation
3. Transition to IN DEVELOPMENT + create branch
4. Implement (if situation differs from initial analysis, add a JIRA comment with the revised version; pause for confirmation if story points change > 30%)
5. Quality check → Pre-PR review loop → open PR

⚠️ **"help me fix" + JIRA URL/ticket key → fix-bug**; **"help me fix" + PR URL → fix-pr-review**

## Refactor / Optimization

1. Developer opens the ticket → sync impact scope with QA
2. Follow "Feature Development" Steps 2–6

## PR Review

1. Confirm the repo (from PR URL or user-specified)
2. Read diff + `.claude/rules/` standards for that project
3. Check: type safety, boundary handling, test coverage, code style
4. Leave a structured review on the PR (blocking / suggestion / good)

## Workflow Refinement

1. Stay in the `work/` directory — do not switch projects
2. Discuss improvement points → update `docs/rd-workflow.md` or `CLAUDE.md`
3. Once stable, the user notifies to sync back to Confluence
