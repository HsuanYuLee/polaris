# AC Closure Constraints (4 Gates)

AC flows in from the ticket → traced during breakdown → verified during development → presented in the PR. If AC is dropped at any stage, it gets blocked:

1. **Readiness Gate** (engineering start): source must have verifiable AC or a valid task.md work order; blocked if quality is insufficient. Epic / cross-project / multi-feature work routes to refinement first
2. **AC ↔ Sub-task Traceability** (breakdown): produces a traceability matrix after breakdown; blocked if any AC is not covered by a task.md work order
3. **Per-AC / task verification** (engineering delivery flow + verify-AC): task-level Verify Command blocks PR; Epic-level AC verification is handled by verify-AC
4. **AC Coverage Checklist** (engineering delivery flow): PR description automatically embeds an AC checklist so reviewers can see coverage at a glance
