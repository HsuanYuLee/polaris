# Skill Routing Decision Tree

When receiving a user request, match against this table top-down to determine which skill to trigger.

## Quick Reference by Role

**PM / Scrum Master — start here:**

| What you say | Skill | What it does |
|-------------|-------|-------------|
| "standup" / 「站會」「今天做了什麼」 | `/standup` | Collects JIRA + git + calendar → standup report |
| "sprint planning" / 「排 sprint」 | `/sprint-planning` | Pulls backlog, calculates capacity, suggests priority |
| "refinement PROJ-123" / 「討論需求」 | `/refinement` | Enriches Epic into estimation-ready spec |
| "estimate PROJ-123" / 「估點」 | `/work-on` | Story point estimation (auto-detected) |
| "learn from \<url\>" / 「研究一下」 | `/learning` | Study external resource, extract patterns |

**Developer — full routing table below.**

## Full Routing Table

| Input Pattern (English / 中文) | Skill | Notes |
|-------------------------------|-------|-------|
| "init" / 「初始化」 | `/init` | Interactive workspace-config.yaml wizard |
| "which company" / 「哪間公司」 | `/which-company` | Routing diagnostic |
| "work on PROJ-123" / 「做 PROJ-123」「接這張」 | `/work-on` | Smart router: estimate/breakdown/branch/dev |
| "estimate PROJ-123" / 「估點 PROJ-123」「這張幾點」 | `/work-on` | Estimation is integrated, not standalone |
| "fix bug PROJ-456" / 「修 bug PROJ-456」「修正這張」 | `/fix-bug` | Root cause → fix → PR |
| "review PR" / 「review 這個 PR」「幫我 review」 | `/review-pr` | Code review with inline comments |
| "fix review" / 「修正 review」「處理 review comments」 | `/fix-pr-review` | Fix review comments on your own PR |
| "review all PRs" / 「掃大家的 PR」「review inbox」 | `/review-inbox` | Batch review others' PRs |
| "breakdown Epic" / 「拆單」「拆解」 | `/epic-breakdown` | Epic → sub-tasks with estimates |
| "start dev" / 「開始開發」「開工」 | `/start-dev` | Transition to IN DEVELOPMENT |
| "create PR" / 「發 PR」 | `/pr-convention` | Following team PR conventions |
| "standup" / 「站會」「今天做了什麼」「YDY」 | `/standup` | Git/JIRA/Calendar → standup report |
| "sprint planning" / 「排 sprint」「下個 sprint」 | `/sprint-planning` | Pull tickets, calculate capacity |
| "refinement" / 「討論需求」「brainstorm」 | `/refinement` | Requirement elaboration + approach discussion |
| "scope challenge" / 「挑戰需求」 | `/scope-challenge` | Pre-estimation scope check (advisory) |
| "TDD" / 「先寫測試」「紅綠燈」 | `/tdd` | Red-Green-Refactor cycle |
| "verify" / 「驗證」「確認改好了」 | `/verify-completion` | Behavioral verification before PR |
| "quality check" / 「品質檢查」「跑測試」 | `/dev-quality-check` | Tests + coverage + lint |
| "learn from \<url\>" / 「研究一下」「學習」 | `/learning` | External learning mode |
| "learn from PRs" / 「學習 PR」 | `/learning` | PR learning mode |
| "graduate lessons" / 「整理 review lessons」 | `/review-lessons-graduation` | Consolidate lessons into rules |

## Common Misroutes

- "estimate PROJ-448" (「估點 PROJ-448」) → `/work-on` (estimation is integrated, do **not** trigger `/jira-estimation` directly)
- "do PROJ-448" (「做 PROJ-448」) → `/work-on` (auto-detects whether estimation is needed)
- "do PROJ-100 PROJ-101 PROJ-102" → `/work-on` (batch mode, not individual fix-bug calls)
- "fix this" + JIRA key (「修正這張」+ JIRA key) → `/fix-bug` (not `/fix-pr-review`)
- "fix this" + PR URL → `/fix-pr-review` (not `/fix-bug`)
- "review all PRs" (「掃大家的 PR」) → `/review-inbox` (not `/review-pr`, which is for single PRs)
- Never self-review your own PR — review is only for others' code

## Skill Chain Conventions

Skills can invoke the next skill in chain via natural language. Common chains:
- **Scrum/PM**: `refinement` → `epic-breakdown` → `sprint-planning`
- **Implementation**: `refinement` → `epic-breakdown` / `jira-estimation` → `work-on` → `tdd` (optional) → `dev-quality-check` → `verify-completion` → `git-pr-workflow`
- **Bug fix**: `fix-bug` → `tdd` (optional) → `dev-quality-check` → `verify-completion` → PR

Each skill can run independently; chains are not mandatory but recommended for complex tasks.
