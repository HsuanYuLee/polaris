title: "機制 Deterministic Contracts"
description: "由 Polaris validator、hook、wrapper、helper script 強制的 contract-lane mechanism groups。"
---

# 機制 Deterministic Contracts

這份 reference 把 deterministic mechanism groups 從 hot
`rules/mechanism-registry.md` payload 拆出。post-task audit 只有在 agent 忽略、
繞過、或誤讀 deterministic evidence 時才需要回頭檢查這裡。

## Contract Groups

| Contract group | Covered invariants | Deterministic source | Disposition |
|----------------|--------------------|----------------------|-------------|
| Artifact schemas | refinement/task artifact shape, task dependency closure, breakdown readiness, fixture paths, design-plan checklist closure | `pipeline-artifact-gate.sh`, `validate-refinement-json.sh`, `validate-task-md.sh`, `validate-task-md-deps.sh`, `validate-breakdown-ready.sh`, `design-plan-checklist-gate.sh` | `already_deterministic_reduce_audit` |
| Handoff and L2 gates | refinement handoff, carry-forward, version bump reminders, feedback reflection signals | `l2-embedding-registry.md`, `refinement-handoff-gate.sh`, `check-carry-forward.sh`, `check-version-bump-reminder.sh`, `check-feedback-signals.sh` | `already_deterministic_reduce_audit` |
| Delivery wrappers | PR body template preservation, workspace language policy, verification evidence, ci-local evidence, revision rebase evidence, base resolution | `deterministic-hooks-registry.md`, `polaris-pr-create.sh`, `gate-pr-body-template.sh`, `gate-pr-language.sh`, `gate-commit-language.sh`, `verification-evidence-gate.sh`, `ci-local-gate.sh`, `gate-revision-rebase.sh`, `resolve-task-base.sh` | `already_deterministic_reduce_audit` |
| PR review state routing | `CHANGES_REQUESTED` is not automatically a code-fix state; CI-green PRs with no active actionable review threads route to reviewer re-review | `pr-review-state-classifier.sh`, `pr-review-state-classifier-selftest.sh` | `already_deterministic_reduce_audit` |
| PR governance readiness | shared PR state producer/classifier, completion-time assignee closure, task-bound verify-report freshness, and governed `awaiting_re_review` / `mergeable_ready` claims | `resolve-pr-work-source.sh`, `pr-state-snapshot.sh`, `pr-action-classifier.sh`, `check-delivery-completion.sh`, `gate-pr-assignee.sh` | `already_deterministic_reduce_audit` |
| Local specs tracking guard | `docs-manager/src/content/docs/specs/**` is local-only; tracked/staged specs are blocked before commit / push / PR create | `gate-no-tracked-specs.sh`, `gate-no-tracked-specs-selftest.sh`, `polaris-pr-create.sh`, `install-copilot-hooks.sh` | `already_deterministic_reduce_audit` |
| Handbook config runtime contract | project handbook machine fields schema, handbook-first runtime config resolution, workspace-config fallback / conflict detection | `handbook-config-reader.sh`, `handbook-config-validator.sh`, `handbook-config-selftest.sh`, `start-test-env.sh --resolve-config-only`, `deterministic-hooks-registry.md` | `already_deterministic_reduce_audit` |
| Framework release closeout | DP-backed framework task `extension_deliverable`, local-extension completion gate, task move-first closeout, parent DP closeout, implementation worktree cleanup | `framework-release-closeout.sh`, `framework-release-closeout-selftest.sh`, `check-local-extension-completion.sh`, `engineering-clean-worktree.sh` | `already_deterministic_reduce_audit` |
| Session and safety hooks | context pressure, cross-session warm scan, safety gate, no hooks in local settings | `deterministic-hooks-registry.md`, hook wrappers under `.claude/hooks/`, safety scripts under `scripts/` | `already_deterministic_reduce_audit` |
| Model tier policy | raw provider model policy outside the central mapping, `.agents/skills` mirror drift | `validate-model-tier-policy.sh`, `check-skills-mirror-mode.sh`, `model-tier-policy.md` | `already_deterministic_reduce_audit` |

## Script Candidates

這些 row 還沒有完全 deterministic。在 validator 或 hook 正式接手 invariant 前，
仍要留在 main registry 的 priority order。

| Contract group | Covered invariants | Current source | Disposition |
|----------------|--------------------|----------------|-------------|
| Post-implementation flow gap audit | bypass/fallback/false-pass/ignored-runtime-artifact review before handoff; Polaris config migration closure | `engineer-delivery-flow.md` Step 3.2, `validate-polaris-config-migration.sh` | `script_candidate` |

## Audit Rule

預設不要人工重 audit 每一列 deterministic row。真正的 semantic audit 問題是：
agent 是否正確尊重並解讀 deterministic evidence？
