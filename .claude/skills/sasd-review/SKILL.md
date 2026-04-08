---
name: sasd-review
description: >
  Generates a SA/SD (System Analysis / System Design) document for a JIRA ticket —
  a structured implementation plan produced before coding begins. Use this skill
  whenever the user mentions SASD, SA/SD, 寫 SA, 出 SA/SD, SA 文件, SD 文件,
  架構文件, implementation plan, 系統分析, 系統設計, 技術設計, 異動範圍,
  dev scope, design doc, technical design, or asks to analyze what changes are needed
  for a ticket, plan the implementation approach, or produce a technical design
  document — even if they don't explicitly say "SA/SD".
metadata:
  author: Polaris
  version: 1.0.0
---

# SA/SD Review — Design-First Gate

Produce a structured System Analysis / System Design document for a JIRA ticket
before any code is written. The goal is to **align on approach first** — catching
misunderstandings, surfacing ambiguities, and choosing among alternatives is far
cheaper at the design stage than after implementation.

## Why Design-First

- "Simple" requirements are the most dangerous — unchecked assumptions waste work
- Exploring the codebase before writing forces you to understand the real impact
- A short design doc (even 5 lines for a 3-point bug fix) makes the PR review faster
- The task list becomes the sub-task breakdown — no duplicate work

## SA/SD Template Structure

### Metadata Table

| Field | Description |
|-------|-------------|
| Create date | Document creation date |
| Author | Responsible developer |
| JIRA ticket | Link to the JIRA Epic / Story / Bug |
| PRD | Product requirements document link (if available) |
| Design | Design mockup links (Figma, Zeplin, etc.) |
| API doc | API documentation link (if available) |
| Discussion | Slack thread, meeting notes, etc. |
| Reference | Any additional reference materials |

### Required Sections

1. **Requirements** — What problem are we solving? Why is this needed?
2. **Dev Scope** — Which files, modules, and services will be changed?
3. **System Flow** — How does the change flow through the system? (sequence diagram, data flow, or prose)
4. **Implementation Design** — What components/functions/modules are created or modified? What patterns are used?
5. **Task List with Estimates** — Actionable work items with file paths and story points
6. **Timeline** — Total estimated days based on task points

### Optional Sections

7. **Alternatives Considered** — Other approaches evaluated and why they were rejected
8. **Risk & Mitigation** — What could go wrong and how to handle it
9. **Reference** — Additional materials

## Design-First Gate Flow

**Before writing any code, complete the design alignment.** This is not a formality —
it is the primary quality gate for preventing wasted work.

The design can be brief (a 3-point bug fix needs only a few sentences), but it must
go through this flow:

1. **Understand requirements** — Read the ticket fully. Confirm you understand the problem
2. **Surface ambiguities** — List what is unclear or missing. Ask before assuming
3. **Propose 2–3 approaches** (for medium/large scope) — Include trade-offs and a recommendation
4. **Get developer confirmation** — Align on the approach before proceeding to output

> If the ticket already contains a clear implementation plan (e.g., the developer
> described the approach in the description), confirm it and proceed to SA/SD output.
> But always confirm — never assume.

## Workflow

### Pre-step: Read workspace config

Read workspace config (see `references/workspace-config-reader.md`).
Required values: `jira.instance`, `confluence.space` (optional).
If config is missing, use `references/shared-defaults.md` fallback values.

### Step 1: Fetch JIRA ticket

Get the ticket key from (in priority order):
1. User-provided issue key
2. Current git branch name
3. Ask the user

Read the ticket via MCP:

```
mcp__claude_ai_Atlassian__getJiraIssue
  cloudId: {config: jira.instance}
  issueIdOrKey: <TICKET>
```

### Step 2: Identify the target project

Extract the `[...]` tag from the ticket Summary and match against
`references/project-mapping.md` to find the local project path. Case-insensitive.

If no tag is found or no match, ask the user to specify the project.

All subsequent codebase analysis uses this project path as the root.

### Step 3: Analyze ticket requirements

Read Summary, Description, and Acceptance Criteria to understand:
- What problem is being solved
- Expected behavior changes
- Related PRD / Design / API doc links

### Step 4: Explore the codebase (adaptive)

Use `references/explore-pattern.md` to scan the codebase.

**Goal**: Find all files related to the requirements. Understand the current
architecture and identify the impact of the change.

Dispatch 1 Explore sub-agent with the ticket summary and project path.
The sub-agent will auto-calibrate scope — small tickets get a quick scan,
large tickets spawn multiple parallel sub-explores.

**After receiving the exploration summary**, proceed directly to Step 5.
Do not re-read source files. If a specific area needs more detail, dispatch
a targeted single Explore sub-agent — do not restart a full scan.

### Step 5: Produce the SA/SD document

Based on the analysis, fill in the template sections:

#### 5.1 Requirements
Summarize the requirements, referencing the ticket description.

#### 5.2 Dev Scope
List every file/module that needs to change:
- Existing files: what to modify and why
- New files: purpose and location
- Deleted files: reason for removal

#### 5.3 System Flow
Describe the implementation flow using a mermaid sequence diagram or prose.
Include the full request path if multiple services are involved.

#### 5.4 Implementation Design
Explain the technical approach:
- Which components/functions/modules are created or modified
- Which patterns, hooks, utilities are used
- Data flow between layers

#### 5.5 Task List with Estimates

Present as a table. Each task should be an independently deliverable unit
(one task = one PR):

| Task | Files changed | Verification | Points |
|------|---------------|-------------|--------|
| Description | Specific file paths | How to confirm completion (test command, expected result) | Estimate |

**Task granularity principles:**
- Points **must be Fibonacci** (1, 2, 3, 5, 8, 13). No decimals or off-scale integers
- Target 2–5 points per task (one PR's worth of work)
- List **specific file paths** (not "modify the API" — write `server/api/users/get-profile.ts`)
- Each task needs a **verification method** so completion is objectively checkable

> Estimation scale reference: `references/estimation-scale.md`

If `epic-breakdown` has already produced sub-tasks, reuse them — do not re-split.

#### 5.6 Timeline
Total days = total points / daily velocity (typically 2–3 points/day).

### Step 6: Review and next steps

Present the SA/SD to the user and ask:
- Any sections to adjust?
- Add to JIRA as a comment?
- Create a Confluence page? (see `references/sasd-confluence.md` for location conventions)

### Step 7: Scope calibration

- **Small changes (≤ 3 points, single module)**: A full SA/SD is overkill. Produce a brief
  implementation plan (requirements + dev scope + one task) instead
- **Medium changes (5–13 points)**: Standard SA/SD with all required sections
- **Large changes (> 13 points or cross-service)**: Full SA/SD with alternatives considered
  and risk analysis


## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
