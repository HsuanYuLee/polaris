# Framework Self-Iteration

How Polaris improves itself. Three cadences, each with its own mechanism.

> Detailed procedures (Iteration Cadence Map, Post-Version-Bump Chain steps, Backlog Hygiene scan rules, Validated Pattern Promotion steps, Framework Experience frontmatter template) are in `skills/references/framework-iteration-procedures.md`.

## Target-State First Framework Development

Framework planning starts from the clean target state. Compatibility can be a delivery tool, but it must be temporary by contract.

Rules:

- Define the durable target architecture before splitting work. The target must describe the final source of truth, runtime ownership, and contract boundaries.
- Phases are allowed only as delivery slices toward that target. A phase is not acceptable if it leaves a mirror, fallback, compatibility alias, or dual-source contract as the intended steady state.
- Short-lived migration aids must have an owner, explicit removal criteria, verification method, and follow-up task in the same plan.
- When AI-assisted development makes a direct migration cheaper than maintaining compatibility, prefer the direct migration and pay the verification cost instead of carrying transitional complexity.
- If the direct migration would break external users, document the breakage and release path explicitly; do not hide it behind silent fallback behavior.

This does not ban phased migration, safety checks, or graceful runtime handling. It bans using compatibility scaffolding as a substitute for completing the design.

## Viewer Availability Convention

Keep the docs-manager viewer available for the user whenever framework work
touches specs, design plans, docs-manager, or release validation.

Rules:

- Treat `http://127.0.0.1:8080/docs-manager/` as the user's default browsing
  surface. Do not leave it stopped after validation or release work.
- If runtime verification needs preview/search mode, prefer a separate port
  such as `3334` instead of taking over the user's long-lived dev viewer.
- If a stale or incompatible viewer on `8080` must be stopped to unblock a
  deterministic check, restart the dev viewer afterward with:
  `bash scripts/polaris-viewer.sh --mode dev --port 8080 --no-open`
- Before final response on docs-manager/specs work, confirm whether a viewer is
  listening on `8080`; if not, either start it or explicitly report why it was
  left down.

## Challenger Audit: Milestone Self-Check

Challenger Audit (see `skills/references/challenger-audit.md`) launches 6 persona sub-agents to review the framework from external-user perspectives. It is **expensive** (6 parallel sonnet sub-agents) and produces **simulated** signals (AI reviewing AI).

**When to run:**
- Before a major version release that will be publicly shared
- Before sharing the repo with a new team or audience
- When the user explicitly says "challenger", "跑挑戰者", "audit UX"

**When NOT to run:**
- After individual PRs or daily tasks
- As a substitute for post-task reflection
- As a routine iteration driver

Findings flow into `polaris-backlog.md` per the severity rules in `challenger-audit.md`.

## Framework Experience Collection

The Micro cadence collects **pain points** (corrections, blocks, failures). This section adds **positive signal** collection — what framework patterns work and why.

### Storage

`type: framework-experience` memory files in the workspace memory directory. No `company:` field (framework experience is always workspace-wide). Indexed in MEMORY.md with `[fx]` tag.

### When to Write

During the existing post-task reflection pass (feedback-and-memory.md § item 6), if the signal is **framework-level** (not project code quality), write a `type: framework-experience` memory instead of `type: feedback`:

| Signal | What to record |
|--------|---------------|
| Skill flow completes with zero user corrections | Which skill, what flow design held up, why |
| Feedback confirmed correct and promoted to rule/reference | Which feedback, promotion target, how fast |
| User explicitly praises framework behavior | What the Strategist did, which rule/skill enabled it |
| Mechanism canary NOT triggered when it could have been | Mechanism ID, the condition that was correctly handled |
| Same skill works across 2+ companies unmodified | Skill name, universality evidence |

### Constraints

- **At most 1 framework-experience memory per task** — if multiple signals fire, combine into one entry
- **Optional, not mandatory** — only write when the signal is clear and non-obvious. If in doubt, skip
- **No rule promotion** — framework-experience memories are observations, not corrections. They do not trigger the direct-write-to-rule workflow

## Version Bump Reminder

During post-task reflection, if the completed task modified files under `rules/` or `skills/`:

- Remind the user: "這次改動涉及框架規則/技能，要升版嗎？"
- If user confirms → bump `VERSION`, update `CHANGELOG.md`, commit, then execute the **Post-Version-Bump Chain** (see `skills/references/framework-iteration-procedures.md` § Post-Version-Bump Chain)
- If user declines → no action. Multiple small changes can be batched into one version later

This is a **reminder**, not an automatic bump. The user decides when and how to group changes into a release.
