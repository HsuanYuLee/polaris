---
title: "DP-242 audit-scripts：多語言 hot path executable 清單"
description: "盤點與分類 Polaris framework workspace 內 scripts/、.claude/skills/、.claude/hooks/ 三個 root 的所有 .sh / .py / .mjs / .ts hot path executable。"
draft: true
sidebar:
  hidden: true
---

# DP-242 Audit: Scripts（多語言 hot path executable inventory）

> Source: DP-242 | Task: DP-242-T1 | Workspace: polaris-framework
> Generated: 2026-05-30

## Scope

Roots：`scripts/**`（top-level + `selftests/` + `lib/` + `gates/` + `e2e/` + `mockoon/`）、`.claude/skills/**/scripts/**`、`.claude/hooks/**`。副檔名：`.sh` / `.py` / `.mjs` / `.ts`。**workspace 內無任何 framework hot path `.ts`**——`scripts/e2e/*.ts` 為 Playwright test fixture，非 framework hot path。

**方法論**：scripts/ top-level 重用 `bash scripts/script-ownership-audit.sh --root . --format json`；其他 root + 子目錄採 grep callsite scan + 檔名 pattern 分類。同質群（selftests / lib / gates）以 group entry 呈現（8 欄 schema 完整，`path` 為 glob + 檔案數）。compliance 欄聚焦 `hdr:yes/no`（前 20 行 Purpose 註解或 docstring）；categorization、reuse_dup 為 DP-243 follow-up。

## Inventory

### Root 1: scripts/ (.sh / .py / .mjs / .ts)

#### Root 1a：scripts/ top-level（audit-driven，269 entries）

> Entry 來自 `script-ownership-audit.sh` `classification`：`root_contract` / `keep_root_with_reason` → `keep`，`sunset_orphan` → `sunset`（DP-243）。`path` 省 `scripts/` 前綴。

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| aggregate-release-lane-selftest.sh | selftest | framework | none | in_use | hdr:no | keep | none |
| allocate-design-plan-number.sh | support | framework | none | in_use | hdr:no | keep | none |
| append-auto-pass-friction.sh | writer | framework | none | orphan | hdr:no | sunset | DP-243 |
| archive-spec.sh | writer | framework | none | orphan | hdr:no | sunset | DP-243 |
| audit-dogfood-evidence.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| audit-legacy-script-governance.sh | support | framework | none | in_use | hdr:yes | keep | none |
| audit-mechanism-graduation.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| auto-pass-counter-race-recovery.sh | writer | framework | none | orphan | hdr:no | sunset | DP-243 |
| auto-pass-increment-counter.sh | writer | framework | none | orphan | hdr:no | sunset | DP-243 |
| auto-pass-probe.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| auto-pass-runner.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| backfill-locked-dp-changed-files.sh | writer | framework | none | orphan | hdr:no | sunset | DP-243 |
| backfill-refinement-predecessor-audit.sh | writer | framework | none | in_use | hdr:no | keep | none |
| breakdown-emit-task-snapshot.sh | writer | framework | none | orphan | hdr:no | sunset | DP-243 |
| cascade-rebase-chain.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| changeset-clean-inherited.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-base-fresh.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-carry-forward.sh | gate | framework | none | orphan | hdr:yes | sunset | DP-243 |
| check-consecutive-reads.sh | gate | framework | none | in_use | hdr:yes | keep | none |
| check-delivery-completion-selftest.sh | selftest | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-delivery-completion.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-docs-sync-complete.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-dp196-diff-scope.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-engineering-first-cut-worktree-contract.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-feedback-signals.sh | gate | framework | none | in_use | hdr:yes | keep | none |
| check-feedback-trigger-count.sh | gate | framework | none | in_use | hdr:yes | keep | none |
| check-flow-gap-audit.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-framework-pr-gate-selftest.sh | selftest | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-framework-pr-gate.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-js-import-package-graph.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-local-extension-completion.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-main-chain-compliance.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-no-cd-in-bash.sh | gate | framework | none | in_use | hdr:yes | keep | none |
| check-no-file-reread.sh | gate | framework | none | in_use | hdr:yes | keep | none |
| check-no-independent-cmd-chaining.sh | gate | framework | none | in_use | hdr:yes | keep | none |
| check-pr-scope.sh | support | framework | none | in_use | hdr:no | keep | none |
| check-python-third-party.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-quarantine-duplication.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-release-completed-selftest.sh | selftest | framework | none | in_use | hdr:no | keep | none |
| check-release-completed.sh | gate | framework | none | in_use | hdr:no | keep | none |
| check-release-eligible-selftest.sh | selftest | framework | none | in_use | hdr:no | keep | none |
| check-release-eligible.sh | gate | framework | none | in_use | hdr:no | keep | none |
| check-runtime-asset.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-runtime-cache-residue.sh | gate | framework | none | orphan | hdr:yes | sunset | DP-243 |
| check-scope-headers.sh | gate | framework | none | in_use | hdr:no | keep | none |
| check-scope.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-script-manifest-selftest.sh | selftest | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-script-manifest.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-skills-mirror-mode.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-source-template-drift.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-sunset-broken-refs-selftest.sh | selftest | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-sunset-broken-refs.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-sunset-candidates-selftest.sh | selftest | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-sunset-candidates.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-t4-api-leak.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-tool-direct-call.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-verification-passed.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| check-version-bump-reminder.sh | gate | framework | none | in_use | hdr:yes | keep | none |
| checkpoint-todo-diff.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| ci-contract-discover.sh | support | framework | none | in_use | hdr:no | keep | none |
| ci-local-env-classify.py | support | framework | none | in_use | hdr:no | keep | none |
| ci-local-generate-selftest.sh | selftest | framework | none | in_use | hdr:no | keep | none |
| ci-local-generate.sh | support | framework | none | in_use | hdr:no | keep | none |
| ci-local-run.sh | support | framework | none | in_use | hdr:no | keep | none |
| close-parent-spec-if-complete-selftest.sh | selftest | framework | none | orphan | hdr:no | sunset | DP-243 |
| close-parent-spec-if-complete.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| codex-guarded-bash.sh | support | framework | none | in_use | hdr:no | keep | none |
| codex-guarded-gh-pr-create.sh | support | framework | none | in_use | hdr:no | keep | none |
| codex-guarded-git-commit.sh | support | framework | none | in_use | hdr:no | keep | none |
| codex-guarded-git-push.sh | support | framework | none | in_use | hdr:no | keep | none |
| codex-mark-design-plan-implemented.sh | support | framework | none | in_use | hdr:no | keep | none |
| collect-evidence-upload-bundle.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| compile-runtime-instructions.sh | writer | framework | none | orphan | hdr:no | sunset | DP-243 |
| context-pressure-monitor.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| contract-check.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| create-branch.sh | writer | framework | none | orphan | hdr:no | sunset | DP-243 |
| create-design-plan.sh | writer | framework | none | orphan | hdr:no | sunset | DP-243 |
| cross-session-warm-scan-selftest.sh | selftest | framework | none | orphan | hdr:no | sunset | DP-243 |
| derive-task-md-from-refinement-json.sh | writer | framework | none | orphan | hdr:no | sunset | DP-243 |
| design-plan-checklist-gate.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| detect-stacked-delivery-lane.mjs | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| distribute-static-evidence.mjs | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| doctor-mise-check.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| engineering-branch-setup-selftest.sh | selftest | framework | none | orphan | hdr:no | sunset | DP-243 |
| engineering-branch-setup.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| engineering-clean-worktree.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| engineering-rebase.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| engineering-revision-worktree-setup.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| engineering-worktree-cleanup.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| finalize-engineering-delivery-selftest.sh | selftest | framework | none | orphan | hdr:no | sunset | DP-243 |
| finalize-engineering-delivery.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| framework-release-closeout-folder-native-selftest.sh | selftest | framework | none | in_use | hdr:no | keep | none |
| framework-release-closeout-selftest.sh | selftest | framework | none | in_use | hdr:no | keep | none |
| framework-release-closeout.sh | release | framework | none | in_use | hdr:no | keep | none |
| framework-release-pr-lane-selftest.sh | selftest | framework | none | in_use | hdr:no | keep | none |
| framework-release-pr-lane.sh | release | framework | none | in_use | hdr:no | keep | none |
| framework-release-preflight-selftest.sh | selftest | framework | none | in_use | hdr:no | keep | none |
| framework-release-preflight.sh | release | framework | none | in_use | hdr:no | keep | none |
| gate-hook-adapter-selftest.sh | selftest | framework | none | orphan | hdr:no | sunset | DP-243 |
| gate-hook-adapter.sh | gate | framework | none | in_use | hdr:no | keep | none |
| generate-verify-report.mjs | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| handbook-config-reader.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| handbook-config-selftest.sh | selftest | framework | none | orphan | hdr:no | sunset | DP-243 |
| handbook-config-validator.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| install-copilot-hooks.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| jira-upload-attachment.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| lint-bash-variable-utf8-boundary.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| lint-reference-line-count.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| lint-skill-size.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| mark-spec-implemented.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| measure-bootstrap-tokens.sh | support | framework | none | in_use | hdr:no | keep | none |
| mechanism-parity.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| memory-hygiene-tiering.py | support | framework | none | in_use | hdr:no | keep | none |
| memory-retention-scan.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| migrate-epic-frontmatter.sh | support | framework | none | in_use | hdr:no | keep | none |
| migrate-epic-refinement-handoff.sh | support | framework | none | in_use | hdr:no | keep | none |
| migrate-pm-epic-mapping.sh | support | framework | none | in_use | hdr:no | keep | none |
| migrate-refinement-json.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| migrate-spec-container-layout.mjs | support | framework | none | in_use | hdr:no | keep | none |
| migrate-spec-container-layout.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| migrate-specs-artifact-frontmatter.sh | support | framework | none | in_use | hdr:no | keep | none |
| onboard-doctor-selftest.sh | selftest | framework | none | orphan | hdr:no | sunset | DP-243 |
| onboard-doctor.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| parse-task-md.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| pipeline-artifact-gate.sh | support | framework | none | in_use | hdr:no | keep | none |
| polaris-bootstrap.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| polaris-changeset.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| polaris-codex-doctor.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| polaris-doctor-selftest.sh | selftest | framework | none | orphan | hdr:no | sunset | DP-243 |
| polaris-doctor.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| polaris-embed-setup.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| polaris-embed.py | support | framework | none | in_use | hdr:no | keep | none |
| polaris-env-selftest.sh | selftest | framework | none | in_use | hdr:no | keep | none |
| polaris-env.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| polaris-external-write-gate.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| polaris-jira-transition.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| polaris-learnings.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| polaris-pr-create-selftest.sh | selftest | framework | none | orphan | hdr:no | sunset | DP-243 |
| polaris-pr-create.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| polaris-timeline.sh | support | framework | none | in_use | hdr:no | keep | none |
| polaris-toolchain-selftest.sh | selftest | framework | none | orphan | hdr:no | sunset | DP-243 |
| polaris-toolchain.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| polaris-viewer.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| pr-action-classifier.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| pr-create-guard.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| pr-review-state-classifier-selftest.sh | selftest | framework | none | orphan | hdr:no | sunset | DP-243 |
| pr-review-state-classifier.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| pr-review-thread-disposition-gate.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| pr-state-snapshot.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| publish-delivery-evidence.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| publish-jira-evidence.mjs | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| readme-lint.py | support | framework | none | in_use | hdr:no | keep | none |
| reconcile-spec-lifecycle.mjs | gate | framework | none | in_use | hdr:no | keep | none |
| refinement-handoff-gate.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| refresh-baseline-snapshot.sh | writer | framework | none | orphan | hdr:no | sunset | DP-243 |
| render-refinement-md.sh | writer | framework | none | orphan | hdr:no | sunset | DP-243 |
| resolve-branch-chain.sh | resolver | framework | none | in_use | hdr:no | keep | none |
| resolve-company-context.sh | resolver | framework | none | orphan | hdr:no | sunset | DP-243 |
| resolve-pr-work-source.sh | resolver | framework | none | orphan | hdr:no | sunset | DP-243 |
| resolve-refinement-template.sh | resolver | framework | none | orphan | hdr:no | sunset | DP-243 |
| resolve-release-surface-selftest.sh | selftest | framework | none | in_use | hdr:no | keep | none |
| resolve-release-surface.sh | resolver | framework | none | in_use | hdr:no | keep | none |
| resolve-specs-root.sh | resolver | framework | none | orphan | hdr:no | sunset | DP-243 |
| resolve-task-base.sh | resolver | framework | none | in_use | hdr:no | keep | none |
| resolve-task-branch.sh | resolver | framework | none | in_use | hdr:no | keep | none |
| resolve-task-md-by-branch.sh | resolver | framework | none | in_use | hdr:no | keep | none |
| resolve-task-md.sh | resolver | framework | none | in_use | hdr:no | keep | none |
| resolve-task-worktree.sh | resolver | framework | none | orphan | hdr:no | sunset | DP-243 |
| resolve-workspace-overlay.sh | resolver | framework | none | orphan | hdr:no | sunset | DP-243 |
| revision-rebase-selftest.sh | selftest | framework | none | in_use | hdr:no | keep | none |
| revision-rebase.sh | support | framework | none | in_use | hdr:no | keep | none |
| rule-retention-scan.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| run-behavior-contract.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| run-governed-script-tests.sh | gate | framework | none | in_use | hdr:no | keep | none |
| run-verify-command-selftest.sh | selftest | framework | none | orphan | hdr:no | sunset | DP-243 |
| run-verify-command.sh | support | framework | none | in_use | hdr:no | keep | none |
| run-visual-snapshot.sh | support | framework | none | in_use | hdr:no | keep | none |
| safety-gate.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| scan-template-leaks.sh | support | framework | none | in_use | hdr:no | keep | none |
| scan-user-data-leak.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| script-ownership-audit.py | support | framework | none | in_use | hdr:no | keep | none |
| script-ownership-audit.sh | support | framework | none | in_use | hdr:no | keep | none |
| skill-progressive-disclosure-audit.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| skill-resource-ownership-audit.sh | support | framework | none | in_use | hdr:no | keep | none |
| skill-routing-canary.sh | support | framework | none | in_use | hdr:no | keep | none |
| skill-sanitizer.py | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| skill-workflow-boundary-gate.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| snapshot-scrub.py | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| spec-source-resolver.sh | resolver | framework | none | orphan | hdr:no | sunset | DP-243 |
| stack-replay-manifest-check.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| start-test-env.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| sync-codex-mcp.sh | writer | framework | none | orphan | hdr:no | sunset | DP-243 |
| sync-from-polaris.sh | writer | framework | none | in_use | hdr:no | keep | none |
| sync-from-upstream.sh | writer | framework | none | in_use | hdr:no | keep | none |
| sync-skills-cross-runtime.sh | writer | framework | none | orphan | hdr:no | sunset | DP-243 |
| sync-spec-sidebar-metadata.sh | writer | framework | none | orphan | hdr:no | sunset | DP-243 |
| sync-to-polaris-clean-source-selftest.sh | selftest | framework | none | in_use | hdr:no | keep | none |
| sync-to-polaris.sh | writer | framework | none | in_use | hdr:no | keep | none |
| test-sequence-tracker.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| tool-attribution-selftest.sh | selftest | framework | none | orphan | hdr:no | sunset | DP-243 |
| tool-direct-call-inventory.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| tool-resolution-selftest.sh | selftest | framework | none | orphan | hdr:no | sunset | DP-243 |
| transpile-rules-to-codex.sh | support | framework | none | in_use | hdr:no | keep | none |
| validate-auto-pass-ledger.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-auto-pass-proof.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-auto-pass-report.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-auto-pass-resume.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-bootstrap-budget.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-breakdown-escalation-intake.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-breakdown-ready-selftest.sh | selftest | framework | none | in_use | hdr:no | keep | none |
| validate-breakdown-ready.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-completion-envelope.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-dispatch-bundle.sh | gate | framework | none | in_use | hdr:no | keep | none |
| validate-dp-metadata.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-dp-number-uniqueness.sh | gate | framework | none | in_use | hdr:no | keep | none |
| validate-dp-plan-authoring.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-escalation-sidecar.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-framework-handbook-routing.sh | gate | framework | none | orphan | hdr:yes | sunset | DP-243 |
| validate-handbook-path-contract.sh | gate | framework | none | in_use | hdr:no | keep | none |
| validate-l2-embedding.sh | gate | framework | none | orphan | hdr:yes | sunset | DP-243 |
| validate-language-policy.sh | gate | framework | none | orphan | hdr:yes | sunset | DP-243 |
| validate-learning-seed-contract.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-manifest-parity.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-mechanism-runtime-annotations.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-memory-hygiene-plan.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-memory-write.sh | gate | framework | none | in_use | hdr:no | keep | none |
| validate-mise-dependency-change.sh | gate | framework | none | orphan | hdr:yes | sunset | DP-243 |
| validate-model-tier-policy.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-polaris-command-catalog.sh | gate | framework | none | in_use | hdr:no | keep | none |
| validate-polaris-config-migration.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-polaris-toolchain-consumers.sh | gate | framework | none | in_use | hdr:no | keep | none |
| validate-polaris-toolchain-manifest.sh | gate | framework | none | in_use | hdr:no | keep | none |
| validate-public-onboarding-contract.sh | gate | framework | none | in_use | hdr:no | keep | none |
| validate-refinement-ac-coverage.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-refinement-artifact-parity.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-refinement-inbox-record.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-refinement-json.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-refinement-locked-scope.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-root-package-governance.sh | gate | framework | none | in_use | hdr:no | keep | none |
| validate-route-safe-spec-paths.sh | gate | framework | none | in_use | hdr:no | keep | none |
| validate-script-categorization.sh | gate | framework | none | orphan | hdr:yes | sunset | DP-243 |
| validate-script-dependencies.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-script-header-comment.sh | gate | framework | none | orphan | hdr:yes | sunset | DP-243 |
| validate-skill-contracts.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-spec-boundary.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-spec-primary-doc-authoring.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-spec-source-parity.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-specs-bound-write-contract.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-specs-collection-shape.sh | gate | framework | none | in_use | hdr:no | keep | none |
| validate-starlight-authoring.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-task-md-deps.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-task-md-selftest.sh | selftest | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-task-md.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| validate-verify-evidence-layout.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| verification-evidence-gate.sh | support | framework | none | orphan | hdr:no | sunset | DP-243 |
| verify-ac-docs-health.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| verify-ac-feedback-signals.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| verify-ac-newbie-challenger.sh | gate | framework | none | orphan | hdr:no | sunset | DP-243 |
| verify-agents-mirror-portable.sh | gate | framework | none | in_use | hdr:no | keep | none |
| verify-cross-llm-parity.sh | support | framework | none | in_use | hdr:no | keep | none |
| verify-docs-manager-direct-source.sh | support | framework | none | in_use | hdr:no | keep | none |
| verify-docs-manager-runtime.sh | support | framework | none | in_use | hdr:no | keep | none |
| verify-refinement-convergence.sh | support | framework | none | in_use | hdr:no | keep | none |
| write-ac-verification.sh | writer | framework | none | orphan | hdr:no | sunset | DP-243 |
| write-completion-gate-marker.sh | writer | framework | none | orphan | hdr:no | sunset | DP-243 |
| write-deliverable.sh | writer | framework | none | orphan | hdr:no | sunset | DP-243 |
| write-extension-deliverable.sh | writer | framework | none | orphan | hdr:no | sunset | DP-243 |
| write-producer-owned-artifact.sh | writer | framework | none | orphan | hdr:no | sunset | DP-243 |
| write-task-verify-report.sh | writer | framework | none | orphan | hdr:no | sunset | DP-243 |

#### Root 1b：scripts/selftests/（group entries，191 .sh + 5 .mjs + 1 lib helper）

> selftest 同質，group entry 呈現；`path` 為 glob，`callers` 為典型 caller。

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| selftests/*-selftest.sh (N=191) | selftest | framework | scripts/selftests/run-all.sh, mise tasks | in_use | hdr:mixed | keep | none |
| selftests/*-selftest.mjs (N=5) | selftest | framework | mise run cross-runtime-sync | in_use | hdr:mixed | keep | none |
| selftests/lib/*.sh (N=1) | helper | framework | sourced by selftest scripts | in_use | hdr:no | keep | none |

#### Root 1c：scripts/lib/（group + per-file，27 entries）

> `scripts/lib/` 是 sourced helper；group entry + 細項清單。

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| lib/*.sh (N=12) | helper | framework | sourced by scripts/**.sh | in_use | hdr:mixed | keep | none |
| lib/*.py (N=15) | helper | framework | imported by scripts/**.py / scripts/**.mjs | in_use | hdr:mixed | keep | none |

細項清單：

- `scripts/lib/ci-local-path.sh` (.sh, sourced helper)
- `scripts/lib/github-rest.sh` (.sh, sourced helper)
- `scripts/lib/main-checkout.sh` (.sh, sourced helper)
- `scripts/lib/pr-review-label.sh` (.sh, sourced helper)
- `scripts/lib/selftest-bootstrap.sh` (.sh, sourced helper)
- `scripts/lib/specs-root.sh` (.sh, sourced helper)
- `scripts/lib/tool-attribution.sh` (.sh, sourced helper)
- `scripts/lib/tool-resolution.sh` (.sh, sourced helper)
- `scripts/lib/verification-evidence.sh` (.sh, sourced helper)
- `scripts/lib/workspace-config-fixture.sh` (.sh, sourced helper)
- `scripts/lib/workspace-config-root.sh` (.sh, sourced helper)
- `scripts/lib/worktree-classifier.sh` (.sh, sourced helper)
- `scripts/lib/migrate-refinement-json-to-strong-bound.py` (.py, importable helper)
- `scripts/lib/polaris_toolchain_manifest.py` (.py, importable helper)
- `scripts/lib/refinement-ac-id-shape.py` (.py, importable helper)
- `scripts/lib/refinement-decision-ac-coverage.py` (.py, importable helper)
- `scripts/lib/refinement-intra-dp-consistency.py` (.py, importable helper)
- `scripts/lib/refinement-md-generator.py` (.py, importable helper)
- `scripts/lib/refinement-md-hand-edit-detector.py` (.py, importable helper)
- `scripts/lib/refinement-module-ac-coverage.py` (.py, importable helper)
- `scripts/lib/refinement-referrer-cascade.py` (.py, importable helper)
- `scripts/lib/refinement-release-surface-advisory.py` (.py, importable helper)
- `scripts/lib/refinement-script-help-advisory.py` (.py, importable helper)
- `scripts/lib/refinement-section-presence-advisory.py` (.py, importable helper)
- `scripts/lib/refinement-selftest-parity.py` (.py, importable helper)
- `scripts/lib/refinement_common.py` (.py, importable helper)
- `scripts/lib/tool_resolution.py` (.py, importable helper)

#### Root 1d：scripts/gates/（per-file，23 entries）

> `scripts/gates/` 是 PR/commit/push gate；per-file 以便 DP-243 review。

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| gates/gate-artifact-schema.sh | gate | framework | 2: scripts/install-copilot-hooks.sh, scripts/manifest.json | in_use | hdr:no | keep | none |
| gates/gate-base-check.sh | gate | framework | 5: skills/references/engineer-delivery-flow-R4-pr-jira.md, skills/references/engineer-delivery-flow-R5-completion-cleanup.md+3 | in_use | hdr:no | keep | none |
| gates/gate-changed-files-scope.sh | gate | framework | 3: skills/references/engineer-delivery-flow.md, scripts/selftests/gate-changed-files-scope-selftest.sh+1 | in_use | hdr:no | keep | none |
| gates/gate-changeset.sh | gate | framework | 9: hooks/pre-push-quality-gate.sh, skills/references/engineer-delivery-flow-R4-pr-jira.md+7 | in_use | hdr:no | keep | none |
| gates/gate-ci-local.sh | gate | framework | 11: hooks/pre-push-quality-gate.sh, skills/references/engineer-delivery-flow-R1-ci-verify.md+9 | in_use | hdr:no | keep | none |
| gates/gate-commit-language-selftest.sh | selftest | framework | 2: skills/references/deterministic-hooks-registry.md, scripts/manifest.json | in_use | hdr:no | keep | none |
| gates/gate-commit-language.sh | gate | framework | 6: skills/references/deterministic-hooks-registry.md, skills/references/mechanism-deterministic-contracts.md+4 | in_use | hdr:no | keep | none |
| gates/gate-evidence-producer-whitelist.sh | gate | framework | 4: hooks/pre-push-quality-gate.sh, scripts/selftests/validate-auto-pass-proof-selftest.sh+2 | in_use | hdr:no | keep | none |
| gates/gate-evidence.sh | gate | framework | 12: hooks/pre-push-quality-gate.sh, skills/references/engineer-delivery-flow.md+10 | in_use | hdr:no | keep | none |
| gates/gate-no-tracked-specs-selftest.sh | selftest | framework | 2: skills/references/mechanism-deterministic-contracts.md, scripts/manifest.json | in_use | hdr:no | keep | none |
| gates/gate-no-tracked-specs.sh | gate | framework | 6: skills/references/mechanism-deterministic-contracts.md, scripts/gates/gate-no-tracked-specs-selftest.sh+4 | in_use | hdr:no | keep | none |
| gates/gate-pr-assignee.sh | gate | framework | 5: skills/references/deterministic-hooks-registry.md, skills/references/mechanism-deterministic-contracts.md+3 | in_use | hdr:no | keep | none |
| gates/gate-pr-body-template.sh | gate | framework | 13: .claude/rules/handbook/framework/script-governance.md, skills/references/authoring-preflight.md+11 | in_use | hdr:no | keep | none |
| gates/gate-pr-language-selftest.sh | selftest | framework | 2: skills/references/deterministic-hooks-registry.md, scripts/manifest.json | in_use | hdr:no | keep | none |
| gates/gate-pr-language.sh | gate | framework | 10: skills/references/deterministic-hooks-registry.md, skills/references/engineer-delivery-flow-R5-completion-cleanup.md+8 | in_use | hdr:no | keep | none |
| gates/gate-pr-review-label.sh | gate | framework | 2: scripts/check-delivery-completion.sh, scripts/manifest.json | in_use | hdr:no | keep | none |
| gates/gate-pr-title.sh | gate | framework | 5: skills/references/engineer-delivery-flow-R4-pr-jira.md, scripts/gates/gate-pr-language-selftest.sh+3 | in_use | hdr:no | keep | none |
| gates/gate-revision-rebase-selftest.sh | selftest | framework | 2: scripts/verify-cross-llm-parity.sh, scripts/manifest.json | in_use | hdr:no | keep | none |
| gates/gate-revision-rebase.sh | gate | framework | 10: hooks/pre-push-quality-gate.sh, skills/references/deterministic-hooks-registry.md+8 | in_use | hdr:no | keep | none |
| gates/gate-template-leaks.sh | gate | framework | 5: hooks/pre-push-quality-gate.sh, scripts/selftests/gate-template-leaks-selftest.sh+3 | in_use | hdr:no | keep | none |
| gates/gate-version-lint.sh | gate | framework | 4: skills/framework-release/SKILL.md, scripts/install-copilot-hooks.sh+2 | in_use | hdr:no | keep | none |
| gates/gate-work-source-selftest.sh | selftest | framework | 1: scripts/manifest.json | in_use | hdr:no | keep | none |
| gates/gate-work-source.sh | gate | framework | 6: skills/references/pr-body-builder.md, skills/references/engineer-delivery-flow-R4-pr-jira.md+4 | in_use | hdr:no | keep | none |

#### Root 1e：scripts/e2e/（per-file，3 entries，含 .ts spec）

> Playwright-based smoke；`.ts` 為 spec/config（非 hot path，列入以維完整性）。

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| e2e/e2e-verify.sh | selftest | framework | 3: scripts/validate-polaris-toolchain-consumers.sh, scripts/manifest.json+1 | in_use | hdr:no | keep | none |
| e2e/e2e-verify.spec.ts | helper | framework | mise run e2e | in_use | hdr:no | keep | none |
| e2e/playwright.config.ts | helper | framework | 4: skills/references/visual-regression-capture-flow.md, skills/references/visual-regression-config.md+2 | in_use | hdr:no | keep | none |

#### Root 1f：scripts/mockoon/（per-file，2 entries）

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| mockoon/mockoon-runner.sh | runner | framework | 7: scripts/polaris-env.sh, scripts/mockoon/package.json+5 | in_use | hdr:no | keep | none |
| mockoon/visual-fixture-review.mjs | analyzer | framework | 2: scripts/selftests/run-visual-snapshot-selftest.sh, scripts/manifest.json | in_use | hdr:no | keep | none |

### Root 2: .claude/skills/**/scripts/（31 entries）

> `path` 省 `.claude/skills/` 前綴；`owner` = skill slug。

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| check-pr-approvals/scripts/check-pr-approval-status.sh | validator | check-pr-approvals | 1: skills/check-pr-approvals/SKILL.md | in_use | hdr:no | keep | none |
| check-pr-approvals/scripts/fetch-pr-review-comments.sh | helper | check-pr-approvals | 1: skills/check-pr-approvals/SKILL.md | in_use | hdr:no | keep | none |
| check-pr-approvals/scripts/fetch-user-open-prs.sh | validator | check-pr-approvals | 4: skills/check-pr-approvals/scripts/rebase-pr-branch.sh, skills/check-pr-approvals/scripts/check-pr-approval-status.sh+2 | in_use | hdr:no | keep | none |
| check-pr-approvals/scripts/rebase-pr-branch.sh | validator | check-pr-approvals | 3: skills/check-pr-approvals/scripts/check-pr-approval-status.sh, skills/check-pr-approvals/SKILL.md+1 | in_use | hdr:no | keep | none |
| exampleco/kibana-logs/scripts/kibana-search.sh | helper | kibana-logs | 2: skills/exampleco/kibana-logs/references/query-templates.md, skills/exampleco/kibana-logs/SKILL.md | in_use | hdr:no | keep | none |
| pr-pickup/scripts/resolve-pr-pickup-input.sh | helper | pr-pickup | 3: skills/pr-pickup/scripts/selftests/resolve-pr-pickup-input-selftest.sh, skills/pr-pickup/SKILL.md+1 | in_use | hdr:no | keep | none |
| pr-pickup/scripts/selftests/resolve-pr-pickup-input-selftest.sh | selftest | pr-pickup | none | orphan | hdr:no | sunset | DP-243 |
| references/scripts/check-feature-pr.sh | validator | references | 2: skills/references/converge-scan-gap-flow.md, skills/references/feature-branch-pr-gate.md | in_use | hdr:no | keep | none |
| references/scripts/polaris-learnings.sh | helper | references | 15: .claude/rules/feedback-and-memory.md, .claude/rules/bash-command-splitting.md+13 | in_use | hdr:no | keep | none |
| references/scripts/polaris-timeline.sh | helper | references | 8: hooks/session-summary-stop.sh, hooks/session-summary-precompact.sh+6 | in_use | hdr:no | keep | none |
| review-inbox/scripts/annotate-review-candidates-selftest.sh | selftest | review-inbox | none | orphan | hdr:no | sunset | DP-243 |
| review-inbox/scripts/annotate-review-candidates.py | helper | review-inbox | 4: skills/references/review-inbox-batch-review-flow.md, skills/references/review-inbox-discovery-flow.md+2 | in_use | hdr:no | keep | none |
| review-inbox/scripts/build-review-prompt-selftest.sh | selftest | review-inbox | none | orphan | hdr:no | sunset | DP-243 |
| review-inbox/scripts/build-review-prompt.sh | composite | review-inbox | 4: skills/references/review-inbox-batch-review-flow.md, skills/review-inbox/scripts/build-review-prompt-selftest.sh+2 | in_use | hdr:no | keep | none |
| review-inbox/scripts/build-review-runtime-plan-selftest.sh | selftest | review-inbox | none | orphan | hdr:no | sunset | DP-243 |
| review-inbox/scripts/build-review-runtime-plan.py | composite | review-inbox | 4: skills/references/review-inbox-batch-review-flow.md, skills/references/context-budget-contract.md+2 | in_use | hdr:no | keep | none |
| review-inbox/scripts/check-my-review-status-selftest.sh | selftest | review-inbox | none | orphan | hdr:no | sunset | DP-243 |
| review-inbox/scripts/check-my-review-status.sh | validator | review-inbox | 4: skills/references/review-inbox-discovery-flow.md, skills/review-inbox/scripts/check-my-review-status-selftest.sh+2 | in_use | hdr:no | keep | none |
| review-inbox/scripts/extract-pr-urls-selftest.sh | selftest | review-inbox | none | orphan | hdr:no | sunset | DP-243 |
| review-inbox/scripts/extract-pr-urls.py | helper | review-inbox | 4: skills/pr-pickup/scripts/resolve-pr-pickup-input.sh, skills/references/review-inbox-discovery-flow.md+2 | in_use | hdr:no | keep | none |
| review-inbox/scripts/fetch-prs-by-url.sh | helper | review-inbox | 2: skills/references/review-inbox-discovery-flow.md, skills/review-inbox/scripts/extract-pr-urls.py | in_use | hdr:yes | keep | none |
| review-inbox/scripts/inspect-pr-section-selftest.sh | selftest | review-inbox | none | orphan | hdr:no | sunset | DP-243 |
| review-inbox/scripts/inspect-pr-section.sh | helper | review-inbox | 4: skills/references/review-inbox-batch-review-flow.md, skills/review-inbox/scripts/build-review-prompt-selftest.sh+2 | in_use | hdr:no | keep | none |
| review-inbox/scripts/measure-review-inbox-session-selftest.sh | selftest | review-inbox | none | orphan | hdr:no | sunset | DP-243 |
| review-inbox/scripts/measure-review-inbox-session.sh | helper | review-inbox | 3: skills/references/review-inbox-batch-review-flow.md, skills/review-inbox/scripts/measure-review-inbox-session-selftest.sh+1 | in_use | hdr:no | keep | none |
| review-inbox/scripts/resolve-handbook-paths-selftest.sh | selftest | review-inbox | none | orphan | hdr:no | sunset | DP-243 |
| review-inbox/scripts/resolve-handbook-paths.sh | helper | review-inbox | 2: skills/review-inbox/scripts/build-review-prompt.sh, skills/review-inbox/scripts/resolve-handbook-paths-selftest.sh | in_use | hdr:no | keep | none |
| review-inbox/scripts/scan-need-review-prs.sh | helper | review-inbox | 3: skills/references/review-inbox-discovery-flow.md, skills/review-inbox/scripts/check-my-review-status.sh+1 | in_use | hdr:no | keep | none |
| review-inbox/scripts/slack-webapi-selftest.sh | selftest | review-inbox | none | orphan | hdr:no | sunset | DP-243 |
| review-inbox/scripts/slack-webapi.sh | helper | review-inbox | 3: skills/references/review-inbox-discovery-flow.md, skills/references/review-inbox-slack-reporting.md+1 | in_use | hdr:no | keep | none |
| review-pr/scripts/fetch-pr-info.sh | helper | review-pr | 1: skills/references/review-pr-entry-fetch-flow.md | in_use | hdr:no | keep | none |

### Root 3: .claude/hooks/（21 entries）

> `path` 省 `.claude/hooks/` 前綴；owner=framework，由 `settings.json` hooks 觸發；`disposition` 反映跨 LLM parity（mirrored=跨 runtime 對等；advisory=claude-code-only 有 fallback；intentional-gap=暫無 parity 計畫）。

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| ci-local-gate.sh | hook | framework | 8: .claude/rules/mechanism-registry.md, skills/references/engineer-delivery-flow-R1-ci-verify.md+6 | in_use | hdr:no | hook-parity-mirrored | DP-245 |
| cross-session-warm-scan.sh | hook | framework | 3: .claude/rules/mechanism-registry.md, skills/references/deterministic-hooks-registry.md+1 | in_use | hdr:no | hook-parity-mirrored | DP-245 |
| feedback-read-logger.sh | hook | framework | 4: .claude/settings.json, .claude/rules/mechanism-registry.md+2 | in_use | hdr:no | hook-parity-mirrored | DP-245 |
| feedback-reflection-stop.sh | hook | framework | 5: .claude/settings.json, .claude/rules/mechanism-registry.md+3 | in_use | hdr:no | hook-parity-mirrored | DP-245 |
| feedback-trigger-advisory.sh | hook | framework | 6: .claude/settings.json, hooks/feedback-read-logger.sh+4 | in_use | hdr:no | hook-parity-mirrored | DP-245 |
| memory-decay-scan.sh | hook | framework | 2: .claude/rules/mechanism-registry.md, skills/references/memory-tiering-contract.md | in_use | hdr:no | hook-parity-mirrored | DP-245 |
| no-direct-evidence-write.sh | hook | framework | 11: .claude/settings.json, .claude/rules/mechanism-registry.md+9 | in_use | hdr:no | hook-parity-mirrored | DP-245 |
| no-manual-work-order-search.sh | hook | framework | 2: .claude/settings.json, .claude/rules/mechanism-registry.md | in_use | hdr:no | hook-parity-mirrored | DP-245 |
| pipeline-artifact-gate.sh | hook | framework | 10: .claude/rules/mechanism-registry.md, skills/references/task-md-schema-common.md+8 | in_use | hdr:no | hook-parity-mirrored | DP-245 |
| post-compact-context-restore.sh | hook | framework | 5: .claude/settings.json, hooks/session-summary-precompact.sh+3 | in_use | hdr:no | hook-parity-mirrored | DP-245 |
| post-memory-index-regenerate.sh | hook | framework | 5: .claude/settings.json, .claude/rules/feedback-and-memory.md+3 | in_use | hdr:no | hook-parity-mirrored | DP-245 |
| pr-base-gate.sh | hook | framework | 7: .claude/rules/mechanism-registry.md, skills/references/task-md-schema-validator.md+5 | in_use | hdr:no | hook-parity-mirrored | DP-245 |
| pre-memory-write.sh | hook | framework | 7: .claude/settings.json, hooks/post-memory-index-regenerate.sh+5 | in_use | hdr:no | hook-parity-mirrored | DP-245 |
| pre-push-quality-gate.sh | hook | framework | 9: .claude/rules/mechanism-registry.md, skills/references/challenger-audit.md+7 | in_use | hdr:no | hook-parity-mirrored | DP-245 |
| pre-write-language-policy.sh | hook | framework | 13: .claude/instructions/runtime/codex.md, .claude/instructions/runtime/claude.md+11 | in_use | hdr:no | hook-parity-advisory | DP-245 |
| session-summary-precompact.sh | hook | framework | 4: .claude/settings.json, hooks/session-summary-stop.sh+2 | in_use | hdr:no | hook-parity-mirrored | DP-245 |
| session-summary-stop.sh | hook | framework | 2: .claude/settings.json, .claude/rules/mechanism-registry.md | in_use | hdr:no | hook-parity-mirrored | DP-245 |
| specs-sidebar-sync.sh | hook | framework | 2: .claude/settings.json, .claude/rules/mechanism-registry.md | in_use | hdr:no | hook-parity-mirrored | DP-245 |
| stop-todo-check.sh | hook | framework | 6: .claude/settings.json, hooks/session-summary-stop.sh+4 | in_use | hdr:no | hook-parity-mirrored | DP-245 |
| version-bump-reminder.sh | hook | framework | 9: .claude/settings.json, .claude/rules/mechanism-registry.md+7 | in_use | hdr:no | hook-parity-mirrored | DP-245 |
| version-docs-lint-gate.sh | hook | framework | 7: hooks/pr-base-gate.sh, .claude/rules/mechanism-registry.md+5 | in_use | hdr:no | hook-parity-mirrored | DP-245 |

## Summary

### Per-extension counts

| Extension | scripts/ | .claude/skills/**/scripts/ | .claude/hooks/ | Total |
|-----------|----------|----------------------------|----------------|-------|
| .sh       | 484 | 28 | 21 | 533 |
| .py       | 22 | 3 | 0 | 25 |
| .mjs      | 12 | 0 | 0 | 12 |
| .ts       | 2 | 0 | 0 | 2 |
| **Total** | 520 | 31 | 21 | **572** |

註：`scripts/e2e/*.ts`（2 支）是 Playwright test infra，**非** framework hot path；其餘 root 無 `.ts`。

### Disposition distribution

> 樣本：scripts/ top-level 269 + skills 31 + hooks 21 = 321 個別 entry。selftest/lib/gates group entry 內檔案見下方註解。

| Disposition | Count | % |
|-------------|-------|---|
| keep | 108 | 33.6% |
| sunset | 192 | 59.8% |
| hook-parity-mirrored | 20 | 6.2% |
| hook-parity-advisory | 1 | 0.3% |
| **Total** | 321 | 100.0% |

註：

- scripts/ top-level `sunset_orphan`（audit 分類）共 **182** 筆，全部 follow-up DP-243（sunset criteria + reviewer signoff）。
- selftests 191 .sh + 5 .mjs 預設 `keep`，未納入此分布。
- 0 `move-to-skill`：DP-244 補。
- 0 `split-and-keep`：DP-243 補檢。

### Compliance summary

| Check | PASS | FAIL | % compliant |
| header_purpose | 17 | 304 | 5.3% |
| categorization | n/a | n/a | (DP-243 follow-up — validator 已存在 `validate-script-categorization.sh`，本 audit 未逐筆呼叫) |
| reuse_dup_none | n/a | n/a | (DP-243 follow-up — 須 callsite duplication scan) |

註：

- header_purpose 嚴格定義：前 20 行須有 `# Purpose:`（.sh/.mjs/.ts）或含 `Purpose` 的 docstring（.py）；其他描述性註解仍列 `no`，DP-243 backfill。
- group entry 內檔案 compliance 未累計；DP-243 擴 audit mode 後補。

## Open Questions for follow-up DP

| Question | Why defer | Expected DP-243 decision |
|----------|-----------|--------------------------|
| 1. unused-orphan 自動刪 vs 人工 review？ | scripts/ 內 `sunset_orphan` 共 182 筆，自動刪可能誤刪低頻 selftest 或被 dynamic invocation 引用的 script | DP-243 refinement 決定 sunset criteria + reviewer signoff 流程 + dynamic-callsite 探測 |
| 2. deprecated 宣告權威？ | 目前無明確 deprecated marker；header 註解 vs manifest field vs separate registry 都可行 | DP-243 決定唯一 source of truth + validator 強制 |
| 3. batch PR 切片粒度？ | 一次 PR 收 ≥10 sunset 可能造成 review fatigue；單 PR 太細又拖時程 | DP-243 決定每 PR 上限（如 ≤5 sunset + ≤3 move-to-skill），含 release-cadence policy |
| 4. multi-language fail-stop pattern 是否各副檔名各 audit？ | `.py` / `.mjs` 與 `.sh` 的 Tool Missing Discipline 行為對齊 vs 分流 | DP-243 決定統一 vs 分流 + 對應 validator pattern |
| 5. group entry vs per-file 邊界？ | 本 audit 把 selftests / lib / gates 做 group entry 控制檔案大小，但會丟失個別 compliance 資料 | DP-243 / DP-246 決定後續 audit 是否拆 per-file 或保持 group entry + 另一份 verbose snapshot |
| 6. .claude/skills/ scripts 是否納入 `script-ownership-audit.sh` scope？ | 目前 audit 僅覆蓋 scripts/ 一層；skills/hooks 多語言檔案靠 grep 補 | DP-244（skills 擴 audit scope） |
| 7. .claude/hooks parity 表如何維護？ | `mechanism-registry.md` Runtime Annotation Registry 已列 21 個 hook 的 runtime / fallback / governance_role，但 audit 與 registry 兩份 source 有 drift 風險 | DP-245 決定唯一 source（hook → audit 自動 derive，或 audit → 讀 registry） |
