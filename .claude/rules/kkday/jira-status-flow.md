---

> **Scope: your-company** — applies only when working on your-company tickets or projects.
description: JIRA status transition rules, loaded when operating JIRA ticket status changes
---

# JIRA Status Flow

## Main Flow

```
Open → IN DEVELOPMENT → CODE REVIEW → WAITING FOR QA → QA TESTING → WAITING FOR STAGE → REGRESSION → WAITING FOR RELEASE → Released
```

## AI Auto-transitions

| Trigger | Auto-transition | Skill |
|---------|----------------|-------|
| Developer says "start dev" | Open → **IN DEVELOPMENT** | start-dev |
| PR created | IN DEVELOPMENT → **CODE REVIEW** | git-pr-workflow |

All other status transitions (including transitioning to WAITING FOR QA) are performed manually by the developer or QA.

## All Status Descriptions

| Status | Description |
|--------|-------------|
| **Open** | Newly created ticket, not yet started |
| **SA/SD** | Solution Architecture / Solution Design review and planning phase (transitioned from Open) |
| **DISCUSS** | Topics requiring discussion (can be entered from any status) |
| **IN DEVELOPMENT** | Under active development (from Open, or from SA/SD after design is complete) |
| **CODE REVIEW** | Code is under review (transitioned from IN DEVELOPMENT) |
| **WAITING FOR QA** | Developer has notified QA; waiting for testing to begin |
| **QA TESTING** | QA is actively testing in the SIT environment |
| **WAITING FOR STAGE** | Passed SIT testing; waiting for a code freeze and deployment to Stage |
| **REGRESSION** | Regression testing in progress on the Stage environment |
| **WAITING FOR RELEASE** | Regression passed; waiting to go live |
| **Released** | Successfully deployed to production |
| **Done** | Task completed (sub-task development finished, discussion concluded, etc.) |
| **PENDING** | On hold (transitioned from Open; can be re-opened back to Open) |
| **Closed** | Will not be worked on (transitioned from PENDING) |

## Required Fields

> **Config first**: field IDs and option values are defined in the company config under `jira.custom_fields.requirement_source` (see `references/workspace-config-reader.md`).

When transitioning to IN DEVELOPMENT, JIRA requires filling in the "Requirement Source" field:

| Ticket Type | Requirement Source Value |
|------------|------------------------|
| Tech debt / refactor / AI config | Read from `jira.custom_fields.requirement_source.options.tech_maintain` in workspace config |
| Bug fix | Read from `jira.custom_fields.requirement_source.options.tech_bug` in workspace config |
| Other | Determine from ticket description or ask the user |

> Field ID and option IDs are defined in workspace config under `jira.custom_fields.requirement_source` (see `references/workspace-config-reader.md`). Use `editJiraIssue` to set this field first, then `transitionJiraIssue` to transition status (transition screen does not include this field).

## Transition Details

**Normal development flow:**

- Open → (start development) → IN DEVELOPMENT 🤖 _auto-transition_
- Open → (proceed to design review) → SA/SD → (start development) → IN DEVELOPMENT
- IN DEVELOPMENT → (code review) → CODE REVIEW 🤖 _auto-transition_
- CODE REVIEW → (notify QA) → WAITING FOR QA 👤 _manual by developer_
- WAITING FOR QA → (testing starts) → QA TESTING
- QA TESTING → (passes SIT, awaiting code freeze) → WAITING FOR STAGE
- WAITING FOR STAGE → (regression testing begins) → REGRESSION
- REGRESSION → (awaiting release) → WAITING FOR RELEASE
- WAITING FOR RELEASE → (deployed to production) → Released

**Special paths:**

- IN DEVELOPMENT → (roll back) → Open (requirements changed or need re-evaluation)
- IN DEVELOPMENT → (sub-task development complete) → Done (when closing a sub-task)
- CODE REVIEW → (sub-task code review approved, parent ticket development complete) → Done
- WAITING FOR QA → (config-only change or non-functional change going live) → WAITING FOR RELEASE (skip QA testing)
- SA/SD → (discussion concluded) → Done
- DISCUSS → (discussion concluded and ticket resolved) → Done
- Open → (defer issue) → PENDING → (will not be addressed) → Closed
