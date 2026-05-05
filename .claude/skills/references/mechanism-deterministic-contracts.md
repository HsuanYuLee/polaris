---
title: "Mechanism Deterministic Contracts"
description: "Contract-lane mechanism groups that are enforced by Polaris validators, hooks, wrappers, or helper scripts instead of routine manual audit."
---

# Mechanism Deterministic Contracts

This reference keeps deterministic mechanism groups out of the hot
`rules/mechanism-registry.md` payload. Post-task audit should inspect these only
when an agent ignored, bypassed, or misinterpreted deterministic evidence.

## Contract Groups

| Contract group | Covered invariants | Deterministic source | Disposition |
|----------------|--------------------|----------------------|-------------|
| Artifact schemas | refinement/task artifact shape, task dependency closure, breakdown readiness, fixture paths, design-plan checklist closure | `pipeline-artifact-gate.sh`, `validate-refinement-json.sh`, `validate-task-md.sh`, `validate-task-md-deps.sh`, `validate-breakdown-ready.sh`, `design-plan-checklist-gate.sh` | `already_deterministic_reduce_audit` |
| Handoff and L2 gates | refinement handoff, carry-forward, version bump reminders, feedback reflection signals | `l2-embedding-registry.md`, `refinement-handoff-gate.sh`, `check-carry-forward.sh`, `check-version-bump-reminder.sh`, `check-feedback-signals.sh` | `already_deterministic_reduce_audit` |
| Delivery wrappers | PR body template preservation, workspace language policy, verification evidence, ci-local evidence, revision rebase evidence, base resolution | `deterministic-hooks-registry.md`, `polaris-pr-create.sh`, `gate-pr-body-template.sh`, `gate-pr-language.sh`, `gate-commit-language.sh`, `verification-evidence-gate.sh`, `ci-local-gate.sh`, `gate-revision-rebase.sh`, `resolve-task-base.sh` | `already_deterministic_reduce_audit` |
| PR review state routing | `CHANGES_REQUESTED` is not automatically a code-fix state; CI-green PRs with no active actionable review threads route to reviewer re-review | `pr-review-state-classifier.sh`, `pr-review-state-classifier-selftest.sh` | `already_deterministic_reduce_audit` |
| Local specs tracking guard | `docs-manager/src/content/docs/specs/**` is local-only; tracked/staged specs are blocked before commit / push / PR create | `gate-no-tracked-specs.sh`, `gate-no-tracked-specs-selftest.sh`, `polaris-pr-create.sh`, `install-copilot-hooks.sh` | `already_deterministic_reduce_audit` |
| Handbook config runtime contract | project handbook machine fields schema, handbook-first runtime config resolution, workspace-config fallback / conflict detection | `handbook-config-reader.sh`, `handbook-config-validator.sh`, `handbook-config-selftest.sh`, `start-test-env.sh --resolve-config-only`, `deterministic-hooks-registry.md` | `already_deterministic_reduce_audit` |
| Framework release closeout | DP-backed framework task `extension_deliverable`, local-extension completion gate, task move-first closeout, parent DP closeout, implementation worktree cleanup | `framework-release-closeout.sh`, `framework-release-closeout-selftest.sh`, `check-local-extension-completion.sh`, `engineering-clean-worktree.sh` | `already_deterministic_reduce_audit` |
| Session and safety hooks | context pressure, cross-session warm scan, safety gate, no hooks in local settings | `deterministic-hooks-registry.md`, hook wrappers under `.claude/hooks/`, safety scripts under `scripts/` | `already_deterministic_reduce_audit` |
| Model tier policy | raw provider model policy outside the central mapping, `.agents/skills` mirror drift | `validate-model-tier-policy.sh`, `check-skills-mirror-mode.sh`, `model-tier-policy.md` | `already_deterministic_reduce_audit` |

## Script Candidates

These rows are not fully deterministic yet. Keep them visible from the main
registry priority order until a validator or hook owns the invariant.

| Contract group | Covered invariants | Current source | Disposition |
|----------------|--------------------|----------------|-------------|
| Post-implementation flow gap audit | bypass/fallback/false-pass/ignored-runtime-artifact review before handoff; Polaris config migration closure | `engineer-delivery-flow.md` Step 3.2, `validate-polaris-config-migration.sh` | `script_candidate` |

## Audit Rule

Do not manually re-audit every deterministic row by default. The semantic audit
question is: did the agent respect and interpret deterministic evidence
correctly?
