# AC Closure Constraints (4 Gates)

> **Scope: kkday** — applies only when working on kkday tickets or projects.

AC flows in from the ticket → traced during breakdown → verified during development → presented in the PR. If AC is dropped at any stage, it gets blocked:

1. **Readiness Gate** (work-on Step 3): ticket must have verifiable AC; blocked if quality is insufficient. Epic / cross-project / multi-feature tickets automatically trigger refinement
2. **AC ↔ Sub-task Traceability** (epic-breakdown): produces a traceability matrix after breakdown; blocked if any AC is not covered by a sub-task
3. **Line-by-line AC Verification** (verify-completion Step 1.5): each AC criterion is verified after development completes; blocked from raising a PR if any ❌ remains
4. **AC Coverage Checklist** (pr-convention / git-pr-workflow): PR description automatically embeds an AC checklist so reviewers can see coverage at a glance
