# Mechanism Tables（機器讀取的資料，非 agent context）

> 這個檔案是**資料**，不是規則散文。它從 `.claude/rules/mechanism-registry.md` 搬出來，
> 因為 `.claude/rules/**` 每個 session 都會無條件載入，而下面兩張表沒有一列需要
> agent 在推理時記得——它們只被腳本 parse。
>
> Consumer（動表格結構前先看這三處）：
> - `scripts/selftest-affected-runner.sh` — parse Runtime Annotation 的 6 欄，
>   把 changed path 映射到 selftest member。欄序不可變。
> - `scripts/lib/validate_framework_source_write_1.py` — 檢查 framework-source-write
>   兩支 hook 的 parity 列存在。
> - `scripts/compile-runtime-instructions.sh` — 以 heading 名稱擷取
>   `## Cross-LLM Hook Parity Registry` 整段，emit Codex invocation guidance。
>   **heading 文字不可變。**

## Runtime Annotation Registry

DP-188 將 mechanism / hook / script runtime metadata 集中在這張表。
（原本的 PR-time portability gate 已隨 C 桶清除退役；本表現為純文件。）

| mechanism | path | kind | runtime | fallback_script | governance_role |
|-----------|------|------|---------|-----------------|-----------------|
| ci-local-gate | .claude/hooks/ci-local-gate.sh | hook | portable | N/A | governance |
| cross-session-warm-scan | .claude/hooks/cross-session-warm-scan.sh | hook | portable | N/A | governance |
| pre-write-language-policy | .claude/hooks/pre-write-language-policy.sh | hook | claude-code-only | scripts/validate-language-policy.sh | governance |
| session-start-thread-anchor | .claude/hooks/session-start-thread-anchor.sh | hook | claude-code-only | scripts/update-active-thread.sh | governance |
| engineering-self-review-result-writer | scripts/write-engineering-self-review-result.sh | script | portable | scripts/selftests/write-engineering-self-review-result-selftest.sh | governance |
| engineering-self-review-result-validator | scripts/validate-engineering-self-review-result.sh | script | portable | scripts/selftests/validate-engineering-self-review-result-selftest.sh | governance |
| learning-seed-contract | scripts/validate-learning-seed-contract.sh | script | portable | N/A | governance |
| specs-collection-shape-write-gate | .claude/hooks/pre-push-quality-gate.sh | hook | portable | scripts/validate-specs-collection-shape.sh | governance |
| closeout-chain-auto-archive | scripts/mark-spec-implemented.sh | script | portable | scripts/selftests/closeout-chain-archive-selftest.sh | governance |
| baseline-snapshot-refresh-after-intake | scripts/refresh-baseline-snapshot.sh | script | portable | scripts/selftests/refresh-baseline-snapshot-selftest.sh | governance |
| auto-pass-friction-helper | scripts/append-auto-pass-friction.sh | script | portable | scripts/selftests/auto-pass-auto-friction-selftest.sh | governance |
| auto-pass-friction-counter | scripts/auto-pass-increment-counter.sh | script | portable | scripts/selftests/auto-pass-auto-friction-selftest.sh | governance |
| auto-pass-friction-probe | scripts/auto-pass-probe.sh | script | portable | scripts/selftests/auto-pass-auto-friction-selftest.sh | governance |
| auto-pass-friction-gate-adapter | scripts/gate-hook-adapter.sh | script | portable | scripts/selftests/auto-pass-auto-friction-selftest.sh | governance |
| counter-idempotency | scripts/auto-pass-increment-counter.sh | script | portable | scripts/selftests/auto-pass-increment-counter-idempotency-selftest.sh | governance |
| counter-race-recovery | scripts/auto-pass-counter-race-recovery.sh | script | portable | scripts/selftests/auto-pass-counter-race-recovery-selftest.sh | governance |
| bash-var-utf8-boundary-lint | scripts/lint-bash-variable-utf8-boundary.sh | script | portable | scripts/selftests/lint-bash-variable-utf8-boundary-selftest.sh | governance |
| naive-section-parse-lint | scripts/lint-naive-section-parse.sh | script | portable | scripts/selftests/lint-naive-section-parse-selftest.sh | governance |
| dp-keyed-source-symmetry-lint | scripts/lint-dp-keyed-source-symmetry.sh | script | portable | scripts/selftests/lint-dp-keyed-source-symmetry-selftest.sh | governance |
| slugify-ascii | scripts/derive-task-md-from-refinement-json.sh | script | portable | scripts/selftests/branch-slug-producer-parity-selftest.sh | governance |
| branch-name-validator | scripts/validate-branch-name-ascii.sh | script | portable | scripts/selftests/validate-branch-name-ascii-selftest.sh | governance |
| pre-push-branch-name-gate | .claude/hooks/pre-push-quality-gate.sh | hook | portable | scripts/selftests/pre-push-branch-name-ascii-selftest.sh | governance |
| skill-routing-subject-aware | scripts/selftests/skill-routing-subject-aware-selftest.sh | script | portable | scripts/selftests/skill-routing-subject-aware-selftest.sh | governance |
| python-union-annotation-py39-portability | scripts/selftests/python-union-annotation-py39-portability-selftest.sh | script | portable | scripts/selftests/python-union-annotation-py39-portability-selftest.sh | governance |
| derive-task-md-stacked-base-branch | scripts/selftests/derive-task-md-stacked-base-branch-selftest.sh | script | portable | N/A | governance |
| derive-task-shape-propagation | scripts/derive-task-md-from-refinement-json.sh | script | portable | scripts/selftests/derive-task-md-from-refinement-json-selftest.sh | governance |
| audit-confirmation-task-kind-carve-out | scripts/validate-breakdown-ready.sh | script | portable | scripts/selftests/validate-breakdown-ready-task-shape-selftest.sh | governance |
| research-dispatch-unit-gate | scripts/validate-breakdown-ready.sh | script | portable | scripts/selftests/validate-breakdown-ready-research-dispatch-unit-selftest.sh | governance |
| framework-release-closeout-bundle-task-closeout | scripts/selftests/framework-release-closeout-bundle-task-closeout-selftest.sh | script | portable | scripts/selftests/framework-release-closeout-bundle-task-closeout-selftest.sh | governance |
| closeout-no-refinement-session-boundary | scripts/selftests/closeout-no-refinement-session-boundary-selftest.sh | script | portable | scripts/selftests/closeout-no-refinement-session-boundary-selftest.sh | governance |
| update-active-thread | scripts/update-active-thread.sh | script | portable | scripts/selftests/update-active-thread-selftest.sh | governance |
| refinement-consumer-schema-binding | scripts/validate-refinement-consumer-schema-binding.sh | script | portable | scripts/selftests/validate-refinement-consumer-schema-binding-selftest.sh | governance |
| verification-strategy-source-neutral | scripts/validate-verification-strategy.sh | script | portable | scripts/selftests/validate-verification-strategy-selftest.sh | governance |
| closeout-drift-detector | scripts/detect-closeout-drift.sh | script | portable | scripts/selftests/detect-closeout-drift-selftest.sh | governance |
| closeout-drift-bundle-aware-completion | scripts/selftests/check-local-extension-completion-bundle-aware-selftest.sh | script | portable | scripts/selftests/check-local-extension-completion-bundle-aware-selftest.sh | governance |
| framework-release-execute | scripts/framework-release-execute.sh | script | portable | scripts/selftests/framework-release-full-tail-selftest.sh | governance |
| framework-release-closeout-pr-close | scripts/framework-release-closeout.sh | script | portable | scripts/selftests/framework-release-closeout-pr-close-selftest.sh | governance |
| framework-release-closeout-residue-cleanup | scripts/framework-release-closeout.sh | script | portable | scripts/selftests/framework-release-closeout-residue-cleanup-selftest.sh | governance |
| scan-template-leaks-gitignore-aware | scripts/scan-template-leaks.sh | script | portable | scripts/selftests/scan-template-leaks-gitignore-aware-selftest.sh | governance |
| install-git-hooks-pre-push-carve-out | scripts/install-git-hooks.sh | script | portable | scripts/selftests/install-git-hooks-pre-push-carve-out-selftest.sh | governance |
| release-cleanup-sweep | scripts/release-cleanup-sweep.sh | script | portable | scripts/selftests/release-cleanup-sweep-selftest.sh | governance |
| auto-pass-terminal-v-advance | scripts/auto-pass-runner.sh | script | portable | scripts/selftests/auto-pass-terminal-v-advance-selftest.sh | governance |
| auto-pass-ledger-finalize | scripts/auto-pass-finalize-ledger.sh | script | portable | scripts/selftests/auto-pass-finalize-ledger-selftest.sh | governance |
| auto-pass-consume-resume | scripts/auto-pass-consume-resume.sh | script | portable | scripts/selftests/auto-pass-consume-resume-selftest.sh | governance |
| approval-staleness-helper | scripts/lib/approval-staleness.sh | script | portable | scripts/selftests/approval-staleness-selftest.sh | governance |
| task-snapshot-refinement-hash | scripts/breakdown-emit-task-snapshot.sh | script | portable | scripts/selftests/task-snapshot-refinement-hash-selftest.sh | governance |
| selftest-env-hermeticity-lint | scripts/lint-selftest-env-hermeticity.sh | script | portable | scripts/selftests/lint-selftest-env-hermeticity-selftest.sh | governance |
| aggregate-selftest-runner | scripts/run-aggregate-selftests.sh | script | portable | scripts/selftests/run-aggregate-selftests-selftest.sh | governance |
| selftest-enrollment-gate | scripts/validate-selftest-enrollment.sh | script | portable | scripts/selftests/run-aggregate-selftests-selftest.sh | governance |
| breakdown-marker-supersede | scripts/breakdown-emit-task-snapshot.sh | script | portable | scripts/selftests/breakdown-marker-supersede-selftest.sh | governance |
| consumer-reads-authoritative-field | scripts/derive-task-md-from-refinement-json.sh | script | portable | scripts/selftests/derive-task-md-action-from-field-selftest.sh | governance |
| verification-handoff-authoritative-field | scripts/derive-task-md-from-refinement-json.sh | script | portable | scripts/selftests/derive-task-md-verification-handoff-selftest.sh | governance |
| branch-identity-gate | scripts/validate-breakdown-ready.sh | script | portable | scripts/selftests/validate-breakdown-ready-branch-identity-selftest.sh | governance |
| release-stage-pr-release-exemption | scripts/gates/gate-pr-title.sh | script | portable | scripts/selftests/release-stage-pr-release-gate-selftest.sh | governance |
| release-stage-bundle-precondition | scripts/engineering-branch-setup.sh | script | portable | scripts/selftests/release-stage-pr-release-gate-selftest.sh | governance |
| archive-spec-thread-recycle | scripts/archive-spec.sh | script | portable | scripts/selftests/archive-spec-thread-recycle-selftest.sh | governance |
| work-item-id-branch-identity-deconfliction | scripts/derive-task-md-from-refinement-json.sh | script | portable | scripts/selftests/work-item-id-deconfliction-selftest.sh | governance |
| marker-reader-product-repo-evidence-root | scripts/auto-pass-probe.sh | script | portable | scripts/selftests/auto-pass-marker-product-repo-reader-selftest.sh | governance |
| ci-local-content-hash-staleness | scripts/ci-local-generate.sh | script | portable | scripts/selftests/ci-local-content-hash-staleness-selftest.sh | governance |
| branch-setup-base-context-cwd-independent | scripts/engineering-branch-setup.sh | script | portable | scripts/selftests/branch-setup-base-resolution-selftest.sh | governance |
| worktree-cleanup-stop-worktree-scoped-dev-server | scripts/engineering-worktree-cleanup.sh | script | portable | scripts/selftests/worktree-cleanup-stop-dev-server-selftest.sh | governance |
| spec-check-contract-parity | scripts/validate-spec-check-contract-parity.sh | script | portable | scripts/selftests/validate-spec-check-contract-parity-selftest.sh | governance |
| delivery-evidence-conformance | scripts/validate-delivery-evidence-conformance.sh | script | portable | scripts/selftests/validate-delivery-evidence-conformance-selftest.sh | governance |
| artifact-contract-conformance | scripts/validate-artifact-contract-conformance.sh | script | portable | scripts/selftests/validate-artifact-contract-conformance-selftest.sh | governance |
| self-referential-dp-carve-out | scripts/selftests/self-referential-dp-carve-out-selftest.sh | script | portable | scripts/selftests/self-referential-dp-carve-out-selftest.sh | governance |

## Cross-LLM Hook Parity Registry

D43（DP-343）Claude/Codex 雙平台全機制 parity 的 constitutional source。每一支由有效
Claude project hook source（`.claude/settings.json` 與存在時的 `.claude/settings.local.json`，
跨所有 event family 解析）啟用的 active hook，都必須在本表登記：要嘛給出完整 parity
宣告，要嘛帶一個有紀錄的 `parity_exception`。（原以本表為 machine-checkable authority 的 parity gate 已退役；本表現為文件。）

欄位契約：

- `runtime` — `portable` 或 `claude-code-only`。
- `fallback_script` — Codex shell 可直接執行、產出相同 PASS/FAIL 的 runtime-neutral
  validator；active hook script 必須可機器驗證地委派它（callsite-verifiable）。
- `codex_adapter` — `codex_hook` 時為 Codex adapter 檔案；`guarded_wrapper` / `pr_gate`
  時為實際 invoke adapter/fallback 的 callsite script。
- `codex_invocation_point` — 可機器驗證的機制：`codex_hook`（在 `.codex/config.toml`
  active 註冊）、`guarded_wrapper` 或 `pr_gate`。`manual` / `skill_prose` / 空值都不是
  等價機制，一律 fail-stop。
- `adapter_selftest` — 驗證 adapter 的 selftest。
- `payload_contract` / `golden_fixture` — payload normalization 契約與 golden fixture；
  Claude 與 Codex normalize 後的 decision-field digest（tool_name / matcher /
  tool_input.path / changed_paths / session_id / transcript provider / cwd /
  env carve-out token）與 fallback PASS/FAIL 必須完全一致。
- `parity_exception` — `DP-NNN:<reason-anchor>` carve-out；owning DP plan 必須記錄理由。
  有效 carve-out 會 short-circuit 該 hook 其餘 parity 欄位的檢查。

Bootstrap carve-out（DP-343）：下表 active governance hooks 一律帶
`parity_exception=DP-343:dual-platform-parity-bootstrap`。D43 本 task 交付的是 constitutional
gate（`validate-cross-llm-mechanism-parity.sh` + registry authority + compiler-emitted
guidance + PR-gate / release-preflight wiring）；把 runtime-neutral 委派推廣到每一支既有
hook 的 per-hook Codex adapter / golden-fixture infrastructure 由後續 framework-source-write
adapter track 擁有。此 parity carve-out 的理由記錄在 DP-343 的 design plan；容器位置以
`scripts/resolve-spec-source.sh` 解析，不在此硬寫路徑（DP 歸檔後路徑會變）。本 gate 生效後，任何**新增**的 active hook 都必須在此登記完整 parity，或
自帶有紀錄的 `parity_exception`；bootstrap carve-out 不延伸到 DP-343 之後新增的 hook。

| hook | runtime | fallback_script | codex_adapter | codex_invocation_point | adapter_selftest | payload_contract | golden_fixture | parity_exception |
|------|---------|-----------------|---------------|------------------------|------------------|------------------|----------------|------------------|
| no-manual-work-order-search.sh | portable | N/A | N/A | N/A | N/A | N/A | N/A | DP-343:dual-platform-parity-bootstrap |
| post-memory-index-regenerate.sh | portable | N/A | N/A | N/A | N/A | N/A | N/A | DP-343:dual-platform-parity-bootstrap |
| post-runtime-instruction-manifest-regenerate.sh | claude-code-only | scripts/compile-runtime-instructions.sh | N/A | N/A | N/A | N/A | N/A | DP-343:dual-platform-parity-bootstrap |
| pre-memory-write.sh | portable | N/A | N/A | N/A | N/A | N/A | N/A | DP-343:dual-platform-parity-bootstrap |
| pre-write-language-policy.sh | claude-code-only | scripts/validate-language-policy.sh | N/A | N/A | N/A | N/A | N/A | DP-343:dual-platform-parity-bootstrap |
| pre-framework-source-write.sh | portable | scripts/validate-framework-source-write.sh | .codex/hooks/pre-framework-source-write.sh | codex_hook | scripts/selftests/framework-source-mutation-no-bypass-selftest.sh | .codex/hooks/pre-framework-source-write.payload.md | .codex/hooks/pre-framework-source-write.golden.json | N/A |
| post-framework-source-diff-audit.sh | portable | scripts/validate-framework-source-write.sh | .codex/hooks/post-framework-source-diff-audit.sh | codex_hook | scripts/selftests/framework-source-mutation-no-bypass-selftest.sh | .codex/hooks/post-framework-source-diff-audit.payload.md | .codex/hooks/post-framework-source-diff-audit.golden.json | N/A |
| session-start-thread-anchor.sh | claude-code-only | scripts/update-active-thread.sh | N/A | N/A | N/A | N/A | N/A | DP-343:dual-platform-parity-bootstrap |
| stop-active-thread-reminder.sh | portable | N/A | N/A | N/A | N/A | N/A | N/A | DP-343:dual-platform-parity-bootstrap |
