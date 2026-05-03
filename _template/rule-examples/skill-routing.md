# Skill Routing Decision Tree

When receiving a user request, match against this table top-down to determine which skill to trigger.

## Quick Reference by Role

**PM / Scrum Master — start here:**

| What you say | Skill | What it does |
|-------------|-------|-------------|
| "standup" / 「站會」「今天做了什麼」 | `/standup` | Collects JIRA + git + calendar → standup report |
| "sprint planning" / 「排 sprint」 | `/sprint-planning` | Pulls backlog, calculates capacity, suggests priority |
| "refinement PROJ-123" / 「討論需求」 | `/refinement` | Enriches Epic into estimation-ready spec |
| "estimate PROJ-123" / 「估點」 | `/breakdown` | Story point estimation + work-order packing |
| "learn from \<url\>" / 「研究一下」 | `/learning` | Study external resource, extract patterns |

**Developer — full routing table below.**

## Full Routing Table

| Input Pattern (English / 中文) | Skill | Notes |
|-------------------------------|-------|-------|
| "init" / 「初始化」 | `/init` | Interactive workspace-config.yaml wizard |
| "which company" / 「哪間公司」 | `/use-company` | Routing diagnostic |
| "work on PROJ-123" / 「做 PROJ-123」「接這張」 | `/engineering` | Smart router: resolve plan/work order → branch/dev |
| "estimate PROJ-123" / 「估點 PROJ-123」「這張幾點」 | `/breakdown` | Estimation + task.md work-order packing |
| "fix bug PROJ-456" / 「修 bug PROJ-456」「修正這張」 | `/bug-triage` | Root cause diagnosis → breakdown → engineering |
| "review PR" / 「review 這個 PR」「幫我 review」 | `/review-pr` | Code review with inline comments |
| "fix review" / 「修正 review」「處理 review comments」 | `/engineering` | Revision mode: fix review comments on your own PR |
| "review all PRs" / 「掃大家的 PR」「review inbox」 | `/review-inbox` | Batch review others' PRs |
| "breakdown Epic" / 「拆單」「拆解」 | `/breakdown` | Epic / DP / ticket → task.md work orders |
| "start dev" / 「開始開發」「開工」 | `/engineering` | Create branch/worktree and execute the work order |
| "create PR" / 「發 PR」 | `/engineering` | Run delivery flow gates, then create PR |
| "standup" / 「站會」「今天做了什麼」「YDY」 | `/standup` | Git/JIRA/Calendar → standup report |
| "sprint planning" / 「排 sprint」「下個 sprint」 | `/sprint-planning` | Pull tickets, calculate capacity |
| "refinement" / 「討論需求」「brainstorm」 | `/refinement` | Requirement elaboration + approach discussion |
| "scope challenge" / 「挑戰需求」 | `/breakdown` | Pre-estimation scope check (advisory mode) |
| "TDD" / 「先寫測試」「紅綠燈」 | `/unit-test` | Red-Green-Refactor cycle |
| "verify" / 「驗證」「確認改好了」 | `/verify-AC` | AC verification; task-level verify runs inside engineering delivery flow |
| "quality check" / 「品質檢查」「跑測試」 | `/engineering` | Runs Local CI Mirror and delivery gates |
| "learn from \<url\>" / 「研究一下」「學習」 | `/learning` | External learning mode |
| "learn from PRs" / 「學習 PR」 | `/learning` | PR learning mode |

## Common Misroutes

- "estimate PROJ-448" (「估點 PROJ-448」) → `/breakdown`
- "do PROJ-448" (「做 PROJ-448」) → `/engineering` (routes to planning first if no work order exists)
- "do PROJ-100 PROJ-101 PROJ-102" → `/engineering` batch mode (not individual bug-triage calls)
- "fix this" + JIRA key (「修正這張」+ JIRA key) → `/bug-triage`
- "fix this" + PR URL → `/engineering` revision mode
- "review all PRs" (「掃大家的 PR」) → `/review-inbox` (not `/review-pr`, which is for single PRs)
- Never self-review your own PR — review is only for others' code

## Skill Chain Conventions

Skills can invoke the next skill in chain via natural language. Common chains:
- **Scrum/PM**: `refinement` → `breakdown` → `sprint-planning`
- **Implementation**: `refinement` → `breakdown` → `engineering` → `unit-test` (optional TDD mode) → `engineer-delivery-flow` → PR
- **Bug fix**: `bug-triage` → `breakdown` → `engineering` → PR

Each skill can run independently; chains are not mandatory but recommended for complex tasks.
