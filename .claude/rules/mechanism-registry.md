title: "機制治理 Registry"
description: "Polaris 行為機制的 post-task semantic canary registry。"
---

# 機制治理 Registry

這份文件是仍需要人類或 LLM 判斷的行為機制精簡 audit index。已由 script、hook、
wrapper 強制的 contract-lane checks 則收斂到 shared references，避免 hot rule payload
膨脹。

## 使用方式

- 每個 task 結束後，依下方 priority audit order 檢查本輪對話是否有 judgment drift。
- 一旦發現 drift，寫 feedback memory，帶上 mechanism ID 與觀察到的 canary signal。
- 常見逃逸模式請讀
  `skills/references/mechanism-rationalizations.md`.
- hook-level enforcement 請讀
  `skills/references/deterministic-hooks-registry.md`.
- contract-lane checks 請讀
  `skills/references/mechanism-deterministic-contracts.md`.

## Disposition 圖例

| Disposition | Meaning | Manual audit posture |
|-------------|---------|----------------------|
| `semantic_only` | Requires intent, context, or tradeoff judgment | Keep in priority audit when high impact |
| `script_candidate` | Observable invariant without sufficient enforcement yet | Audit until it graduates to a validator or hook |
| `contract_pointer` | Covered by deterministic tooling | Inspect only when a tool failure was ignored, bypassed, or misread |
| `reference_only` | Rationale/background, not a live canary | Keep in references |
| `obsolete` | Superseded by stronger mechanism | Remove after review |

## Runtime Annotation Registry

DP-188 將 mechanism / hook / script runtime metadata 集中在這張表，PR-time
`scripts/validate-mechanism-runtime-annotations.sh` 以此作為 cross-LLM portability gate。

| mechanism | path | kind | runtime | fallback_script | governance_role |
|-----------|------|------|---------|-----------------|-----------------|
| ci-local-gate | .claude/hooks/ci-local-gate.sh | hook | portable | N/A | governance |
| cross-session-warm-scan | .claude/hooks/cross-session-warm-scan.sh | hook | portable | N/A | governance |
| feedback-read-logger | .claude/hooks/feedback-read-logger.sh | hook | portable | N/A | observability |
| feedback-reflection-stop | .claude/hooks/feedback-reflection-stop.sh | hook | portable | N/A | governance |
| feedback-trigger-advisory | .claude/hooks/feedback-trigger-advisory.sh | hook | portable | N/A | observability |
| memory-decay-scan | .claude/hooks/memory-decay-scan.sh | hook | portable | N/A | observability |
| no-direct-evidence-write | .claude/hooks/no-direct-evidence-write.sh | hook | portable | N/A | governance |
| no-manual-work-order-search | .claude/hooks/no-manual-work-order-search.sh | hook | portable | N/A | governance |
| pipeline-artifact-gate | .claude/hooks/pipeline-artifact-gate.sh | hook | portable | N/A | governance |
| post-compact-context-restore | .claude/hooks/post-compact-context-restore.sh | hook | portable | N/A | governance |
| pr-base-gate | .claude/hooks/pr-base-gate.sh | hook | portable | N/A | governance |
| pre-push-quality-gate | .claude/hooks/pre-push-quality-gate.sh | hook | portable | N/A | governance |
| session-summary-precompact | .claude/hooks/session-summary-precompact.sh | hook | portable | N/A | observability |
| session-summary-stop | .claude/hooks/session-summary-stop.sh | hook | portable | N/A | observability |
| specs-sidebar-sync | .claude/hooks/specs-sidebar-sync.sh | hook | portable | N/A | governance |
| stop-todo-check | .claude/hooks/stop-todo-check.sh | hook | portable | N/A | governance |
| version-bump-reminder | .claude/hooks/version-bump-reminder.sh | hook | portable | N/A | governance |
| version-docs-lint-gate | .claude/hooks/version-docs-lint-gate.sh | hook | portable | N/A | governance |
| framework-pr-gate | scripts/check-framework-pr-gate.sh | script | portable | N/A | governance |
| mechanism-runtime-annotations | scripts/validate-mechanism-runtime-annotations.sh | script | portable | N/A | governance |
| mechanism-graduation-audit | scripts/audit-mechanism-graduation.sh | script | portable | N/A | governance |
| reference-line-count-lint | scripts/lint-reference-line-count.sh | script | portable | N/A | governance |
| quarantine-duplication-check | scripts/check-quarantine-duplication.sh | script | portable | N/A | governance |
| learning-seed-contract | scripts/validate-learning-seed-contract.sh | script | portable | N/A | governance |
| agents-mirror-portable-smoke | scripts/verify-agents-mirror-portable.sh | script | portable | N/A | governance |

## Mechanism Canary Entries

| mechanism | disposition | canary signal | expected deterministic evidence |
|-----------|-------------|---------------|---------------------------------|
| gate-fail-self-correct-disposition | contract_pointer | gate exit 2 後 agent 只用口頭說明「已修正」，沒有逐筆處理 gate failure ledger | `scripts/gate-hook-adapter.sh` 寫入 `.polaris/evidence/gate-failures/{task_id}.jsonl`；post-task reflection 產出 `self_correct_disposition[]`，每筆標 `fixed` / `accepted-workaround` / `escalated` |

## Script Candidate Graduation Schedule

`script_candidate` 不可只停在 prose audit；每筆都要有 milestone 與 owner。`M-future`
可存在，但比例必須 ≤ 40%，避免把所有 graduation 都推給未來。

| mechanism | disposition | graduation_milestone | owner | deterministic target |
|-----------|-------------|----------------------|-------|----------------------|
| cross-llm-runtime-annotation | script_candidate | M1 | Polaris | scripts/validate-mechanism-runtime-annotations.sh |
| script-candidate-schedule | script_candidate | M1 | Polaris | scripts/audit-mechanism-graduation.sh |
| quarantine-single-source | script_candidate | M2 | Polaris | scripts/check-quarantine-duplication.sh |
| reference-size-policy | script_candidate | M2 | Polaris | scripts/lint-reference-line-count.sh |
| rule-retention-metric | script_candidate | M3 | Polaris | scripts/rule-retention-scan.sh |
| memory-retention-metric | script_candidate | M3 | Polaris | scripts/memory-retention-scan.sh |
| codex-portable-smoke | script_candidate | M3 | Polaris | scripts/verify-agents-mirror-portable.sh |
| follow-up-reference-bracket | script_candidate | M-future | Polaris | future DP for 500-1000 line references |

## Priority Audit Order

1. DP-backed change flow (`semantic_only`, Critical): `design-plan-creation`,
   `design-plan-decision-capture`, `design-plan-reference-at-impl`,
   `semantic-code-change-flow-gate`.
2. Worktree and delivery isolation (`semantic_only`, Critical):
   `all-code-changes-require-worktree`, `delivery-flow-step-order`,
   `delivery-flow-single-backbone`.
3. Verification judgment (`semantic_only`, Critical):
   `test-env-hard-gate`, `engineering-reads-test-env`,
   `local-verification-hard-gate`, `verify-command-immutable-execute`,
   `fresh-verification-before-completion`.
4. Review and revision state (`semantic_only`, Critical):
   `pr-review-thread-disposition-required`, `codecov-patch-fail-is-blocker`,
   `ac-fail-bug-branch-from-feature`.
5. Skill routing and reference discovery (`semantic_only`, Critical/High):
   `skill-first-invoke`, `no-manual-skill-steps`, `reference-index-scan`.
6. User correction and repo knowledge (`semantic_only`, Critical/High):
   `correction-driven-handbook-update`,
   `repo-knowledge-to-handbook-not-feedback`, `feedback-pre-write-dedup`.
7. Library and dependency judgment (`semantic_only`, Critical/High):
   `api-docs-before-replace`, `lib-exhaust-before-replace`,
   `lib-replace-is-t3`, `lib-reviewer-upgrade-pause`.
8. Planning blind spots and deferred work (`semantic_only`, High/Medium):
   `target-state-first-planning`, `blind-spot-scan`,
   `defer-immediate-capture`, `checklist-before-done`.
9. Deterministic contract failures (`contract_pointer`): 只有在 agent 忽略、繞過、或誤讀 failed gate 時才 audit。See
   `skills/references/mechanism-deterministic-contracts.md`,
   `skills/references/deterministic-hooks-registry.md`, and
   `skills/references/l2-embedding-registry.md`.
10. PR governance readiness claims (`contract_pointer`, Critical):
    只有在 agent 忽略 shared PR state evidence、繞過 final assignee /
    verify-report metadata closure、或在 deterministic contract 之外自行發明
    `mergeable_ready` 語義時才 audit。

## Semantic Canary Sources

| Area | Source of truth |
|------|-----------------|
| Skill routing | `rules/skill-routing.md` |
| Sub-agent delegation and worktree isolation | `rules/sub-agent-delegation.md`, `skills/references/worktree-dispatch-paths.md` |
| Feedback and memory | `rules/feedback-and-memory.md`, `skills/references/feedback-memory-procedures.md` |
| Context and checkpointing | `rules/context-monitoring.md`, `skills/references/checkpoint-*.md` |
| Delivery and verification | `skills/references/engineer-delivery-flow.md`, `skills/references/pipeline-handoff.md` |
| Library changes | `rules/library-change-protocol.md`, `skills/references/library-change-protocol.md` |
| Framework iteration | `rules/framework-iteration.md`, `skills/references/framework-iteration-procedures.md` |
