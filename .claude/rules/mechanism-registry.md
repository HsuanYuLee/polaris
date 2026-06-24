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
| post-memory-index-regenerate | .claude/hooks/post-memory-index-regenerate.sh | hook | portable | N/A | governance |
| post-runtime-instruction-manifest-regenerate | .claude/hooks/post-runtime-instruction-manifest-regenerate.sh | hook | claude-code-only | scripts/compile-runtime-instructions.sh | governance |
| pre-memory-write | .claude/hooks/pre-memory-write.sh | hook | portable | N/A | governance |
| pre-write-language-policy | .claude/hooks/pre-write-language-policy.sh | hook | claude-code-only | scripts/validate-language-policy.sh | governance |
| pr-base-gate | .claude/hooks/pr-base-gate.sh | hook | portable | N/A | governance |
| pre-push-quality-gate | .claude/hooks/pre-push-quality-gate.sh | hook | portable | N/A | governance |
| session-summary-precompact | .claude/hooks/session-summary-precompact.sh | hook | portable | N/A | observability |
| session-summary-stop | .claude/hooks/session-summary-stop.sh | hook | portable | N/A | observability |
| specs-sidebar-sync | .claude/hooks/specs-sidebar-sync.sh | hook | portable | N/A | governance |
| stop-todo-check | .claude/hooks/stop-todo-check.sh | hook | portable | N/A | governance |
| version-bump-reminder | .claude/hooks/version-bump-reminder.sh | hook | portable | N/A | governance |
| version-docs-lint-gate | .claude/hooks/version-docs-lint-gate.sh | hook | portable | N/A | governance |
| session-start-thread-anchor | .claude/hooks/session-start-thread-anchor.sh | hook | claude-code-only | scripts/update-active-thread.sh | governance |
| stop-active-thread-reminder | .claude/hooks/stop-active-thread-reminder.sh | hook | portable | N/A | governance |
| session-pressure-tick | .claude/hooks/session-pressure-tick.sh | hook | claude-code-only | N/A | ux_enhancement_only |
| session-switch-eval | .claude/hooks/session-switch-eval.sh | hook | claude-code-only | N/A | ux_enhancement_only |
| framework-pr-gate | scripts/check-framework-pr-gate.sh | script | portable | N/A | governance |
| mechanism-runtime-annotations | scripts/validate-mechanism-runtime-annotations.sh | script | portable | N/A | governance |
| mechanism-graduation-audit | scripts/audit-mechanism-graduation.sh | script | portable | N/A | governance |
| reference-line-count-lint | scripts/lint-reference-line-count.sh | script | portable | N/A | governance |
| quarantine-duplication-check | scripts/check-quarantine-duplication.sh | script | portable | N/A | governance |
| learning-seed-contract | scripts/validate-learning-seed-contract.sh | script | portable | N/A | governance |
| agents-mirror-portable-smoke | scripts/verify-agents-mirror-portable.sh | script | portable | N/A | governance |
| specs-collection-shape-write-gate | .claude/hooks/no-direct-evidence-write.sh | hook | claude-code-only | scripts/validate-specs-bound-write-contract.sh | governance |
| closeout-chain-auto-archive | scripts/mark-spec-implemented.sh | script | portable | scripts/selftests/closeout-chain-archive-selftest.sh | governance |
| baseline-snapshot-refresh-after-intake | scripts/refresh-baseline-snapshot.sh | script | portable | scripts/selftests/refresh-baseline-snapshot-selftest.sh | governance |
| auto-pass-friction-helper | scripts/append-auto-pass-friction.sh | script | portable | scripts/selftests/auto-pass-auto-friction-selftest.sh | governance |
| auto-pass-friction-counter | scripts/auto-pass-increment-counter.sh | script | portable | scripts/selftests/auto-pass-auto-friction-selftest.sh | governance |
| auto-pass-friction-probe | scripts/auto-pass-probe.sh | script | portable | scripts/selftests/auto-pass-auto-friction-selftest.sh | governance |
| auto-pass-friction-gate-adapter | scripts/gate-hook-adapter.sh | script | portable | scripts/selftests/auto-pass-auto-friction-selftest.sh | governance |
| counter-idempotency | scripts/auto-pass-increment-counter.sh | script | portable | scripts/selftests/auto-pass-increment-counter-idempotency-selftest.sh | governance |
| counter-race-recovery | scripts/auto-pass-counter-race-recovery.sh | script | portable | scripts/selftests/auto-pass-counter-race-recovery-selftest.sh | governance |
| skill-size-policy | scripts/lint-skill-size.sh | script | portable | scripts/selftests/lint-skill-size-selftest.sh | governance |
| bash-var-utf8-boundary-lint | scripts/lint-bash-variable-utf8-boundary.sh | script | portable | scripts/selftests/lint-bash-variable-utf8-boundary-selftest.sh | governance |
| naive-section-parse-lint | scripts/lint-naive-section-parse.sh | script | portable | scripts/selftests/lint-naive-section-parse-selftest.sh | governance |
| slugify-ascii | scripts/derive-task-md-from-refinement-json.sh | script | portable | scripts/selftests/branch-slug-producer-parity-selftest.sh | governance |
| branch-name-validator | scripts/validate-branch-name-ascii.sh | script | portable | scripts/selftests/validate-branch-name-ascii-selftest.sh | governance |
| pre-push-branch-name-gate | .claude/hooks/pre-push-quality-gate.sh | hook | portable | scripts/selftests/pre-push-branch-name-ascii-selftest.sh | governance |
| skill-routing-subject-aware | scripts/selftests/skill-routing-subject-aware-selftest.sh | script | portable | scripts/selftests/skill-routing-subject-aware-selftest.sh | governance |
| mise-dependency-change | scripts/validate-mise-dependency-change.sh | script | portable | scripts/selftests/validate-mise-dependency-change-selftest.sh | governance |
| script-header-comment | scripts/validate-script-header-comment.sh | script | portable | scripts/selftests/validate-script-header-comment-selftest.sh | governance |
| script-categorization | scripts/validate-script-categorization.sh | script | portable | scripts/selftests/validate-script-categorization-selftest.sh | governance |
| python-union-annotation-py39-portability | scripts/selftests/python-union-annotation-py39-portability-selftest.sh | script | portable | scripts/selftests/python-union-annotation-py39-portability-selftest.sh | governance |
| derive-task-md-stacked-base-branch | scripts/selftests/derive-task-md-stacked-base-branch-selftest.sh | script | portable | N/A | governance |
| derive-task-shape-propagation | scripts/derive-task-md-from-refinement-json.sh | script | portable | scripts/selftests/derive-task-md-from-refinement-json-selftest.sh | governance |
| audit-confirmation-task-kind-carve-out | scripts/validate-breakdown-ready.sh | script | portable | scripts/selftests/validate-breakdown-ready-task-shape-selftest.sh | governance |
| research-dispatch-unit-gate | scripts/validate-breakdown-ready.sh | script | portable | scripts/selftests/validate-breakdown-ready-research-dispatch-unit-selftest.sh | governance |
| framework-release-closeout-bundle-task-closeout | scripts/selftests/framework-release-closeout-bundle-task-closeout-selftest.sh | script | portable | scripts/selftests/framework-release-closeout-bundle-task-closeout-selftest.sh | governance |
| closeout-no-refinement-session-boundary | scripts/selftests/closeout-no-refinement-session-boundary-selftest.sh | script | portable | scripts/selftests/closeout-no-refinement-session-boundary-selftest.sh | governance |
| update-active-thread | scripts/update-active-thread.sh | script | portable | scripts/selftests/update-active-thread-selftest.sh | governance |
| refinement-consumer-schema-binding | scripts/validate-refinement-consumer-schema-binding.sh | script | portable | scripts/selftests/validate-refinement-consumer-schema-binding-selftest.sh | governance |
| closeout-drift-detector | scripts/detect-closeout-drift.sh | script | portable | scripts/selftests/detect-closeout-drift-selftest.sh | governance |
| closeout-drift-bundle-aware-completion | scripts/selftests/check-local-extension-completion-bundle-aware-selftest.sh | script | portable | scripts/selftests/check-local-extension-completion-bundle-aware-selftest.sh | governance |
| framework-release-closeout-pr-close | scripts/framework-release-closeout.sh | script | portable | scripts/selftests/framework-release-closeout-pr-close-selftest.sh | governance |
| scan-template-leaks-gitignore-aware | scripts/scan-template-leaks.sh | script | portable | scripts/selftests/scan-template-leaks-gitignore-aware-selftest.sh | governance |
| install-copilot-hooks-pre-push-carve-out | scripts/install-copilot-hooks.sh | script | portable | scripts/selftests/install-copilot-hooks-pre-push-carve-out-selftest.sh | governance |
| release-cleanup-sweep | scripts/release-cleanup-sweep.sh | script | portable | scripts/selftests/release-cleanup-sweep-selftest.sh | governance |
| auto-pass-terminal-v-advance | scripts/auto-pass-runner.sh | script | portable | scripts/selftests/auto-pass-terminal-v-advance-selftest.sh | governance |
| auto-pass-ledger-finalize | scripts/auto-pass-finalize-ledger.sh | script | portable | scripts/selftests/auto-pass-finalize-ledger-selftest.sh | governance |
| approval-staleness-helper | scripts/lib/approval-staleness.sh | script | portable | scripts/selftests/approval-staleness-selftest.sh | governance |
| task-snapshot-refinement-hash | scripts/breakdown-emit-task-snapshot.sh | script | portable | scripts/selftests/task-snapshot-refinement-hash-selftest.sh | governance |
| selftest-env-hermeticity-lint | scripts/lint-selftest-env-hermeticity.sh | script | portable | scripts/selftests/lint-selftest-env-hermeticity-selftest.sh | governance |
| aggregate-selftest-runner | scripts/run-aggregate-selftests.sh | script | portable | scripts/selftests/run-aggregate-selftests-selftest.sh | governance |
| selftest-enrollment-gate | scripts/validate-selftest-enrollment.sh | script | portable | scripts/selftests/run-aggregate-selftests-selftest.sh | governance |
| breakdown-marker-supersede | scripts/breakdown-emit-task-snapshot.sh | script | portable | scripts/selftests/breakdown-marker-supersede-selftest.sh | governance |
| consumer-reads-authoritative-field | scripts/derive-task-md-from-refinement-json.sh | script | portable | scripts/selftests/derive-task-md-action-from-field-selftest.sh | governance |
| marker-artifact-resolvable | scripts/validate-marker-artifact-resolvable.sh | script | portable | scripts/selftests/validate-marker-artifact-resolvable-selftest.sh | governance |
| marker-source-artifact-move-resilience | scripts/check-delivery-completion.sh | script | portable | scripts/selftests/marker-source-artifact-move-resilience-selftest.sh | governance |
| branch-identity-gate | scripts/validate-breakdown-ready.sh | script | portable | scripts/selftests/validate-breakdown-ready-branch-identity-selftest.sh | governance |
| release-stage-pr-release-exemption | scripts/gates/gate-changeset.sh | script | portable | scripts/selftests/release-stage-pr-release-gate-selftest.sh | governance |
| release-stage-bundle-precondition | scripts/engineering-branch-setup.sh | script | portable | scripts/selftests/release-stage-pr-release-gate-selftest.sh | governance |

## Mechanism Canary Entries

| mechanism | disposition | canary signal | expected deterministic evidence |
|-----------|-------------|---------------|---------------------------------|
| gate-fail-self-correct-disposition | contract_pointer | gate exit 2 後 agent 只用口頭說明「已修正」，沒有逐筆處理 gate failure ledger | `scripts/gate-hook-adapter.sh` 寫入 `.polaris/evidence/gate-failures/{task_id}.jsonl`；post-task reflection 產出 `self_correct_disposition[]`，每筆標 `fixed` / `accepted-workaround` / `escalated` |
| tier-a-direct-call-governance | contract_pointer | 新增 script 直接呼叫 `node` / `pnpm` / `jq` / `rg` / `gh`，或把 ticket-scoped tool 誤加進 root mise，而未經 resolver / disposition | `scripts/validate-script-dependencies.sh` 讀取 `scripts/tool-direct-call-inventory-disposition.txt`，新增違規輸出 `POLARIS_TOOL_DIRECT_CALL` / `POLARIS_TICKET_SCOPED_TOOL_DIRECT_CALL` |
| auto-pass-orchestrator-premature-stop | contract_pointer | inner skill HALT 或 session pressure 建議後，auto-pass 直接停下交回 user，而 deterministic sidecar 已可繼續 | `pause.kind=session_handoff` + `scripts/validate-auto-pass-resume.sh`；若 sidecar PASS 則不得 pause |
| closeout-chain-archive-not-deterministic | contract_pointer | terminal complete 後 parent spec 留在 active 區，還需要使用者另跑 archive | `scripts/selftests/closeout-chain-archive-selftest.sh` 覆蓋 mark-spec / auto-pass docs / framework-release closeout callsite |
| closeout-drift-delivered-but-not-archived | contract_pointer | LOCKED DP 已交付（全 task marker + merged PR / CHANGELOG）卻從未 archive，或 LOCKED 後過期無交付證據（stranded），需靠人工巡查才會發現 | `mise run closeout-drift`（`scripts/detect-closeout-drift.sh --dry-run --json`）以 marker + CHANGELOG + merged-PR 三來源分類 `delivered-drift-high` / `delivered-drift-low` / `stranded`；`delivered-drift-high` 經既有 `scripts/mark-spec-implemented.sh` 單一 writer 自動收編，其餘 report-only。`gh` 缺席時 merged-PR 來源 fail-open（D7），report 標 PR 證據未檢。my-triage / standup 盤點併入此清單。selftest：`scripts/selftests/detect-closeout-drift-selftest.sh`。DP-360 note：交付 head 的 canonical authority 為 task.md `deliverable.head_sha`（+ override），completion-gate marker filename head 來源正在退役；本 detector 的「marker」交付證據來源 relocation 到 task.md delivery block 由 DP-360-T7 交付 |
| baseline-snapshot-stale-after-intake | contract_pointer | breakdown route=task_update 合法改動 planner-owned task.md 後，engineering/finalize 仍讀到舊 baseline snapshot | `scripts/refresh-baseline-snapshot.sh` 重新產生 current head snapshot，舊 snapshot rename `*.superseded` |
| audit-confirmation-task-kind-carve-out | contract_pointer | implementation task 被誤標 `task_shape: audit` / `confirmation` 來逃避 specs-only / non-PR gate，或 carve-out 外溢到 implementation（含缺欄位）task | `scripts/validate-breakdown-ready.sh` 對 `task_shape ∈ {audit, confirmation}` 放寬 specs-only/empty Allowed Files，implementation 維持原 exit 1；`scripts/check-delivery-completion.sh` 對同集合走 completion-gate marker(status=PASS)+evidence path，implementation 維持原 non-draft PR gate（DP-262 T2/T3 selftest）。DP-360 note：交付 head / delivery evidence 的 canonical authority 改為 task.md `deliverable.head_sha`（+ override），completion-gate marker 來源正在退役；此 carve-out 的 completion-gate marker reader relocation 到 task.md delivery block 由 DP-360-T7 交付 |
| refinement-lock-preflight | contract_pointer | LOCK 時把 planned implementation task 宣告成 specs-only deliverable，要到 breakdown 階段才被 `validate-breakdown-ready` 擋下 | `scripts/validate-refinement-lock-preflight.sh` 讀 `refinement.json planned_tasks[]`、合成 placeholder task.md 跑 `validate-breakdown-ready` 本體（不重寫 specs-prefix 判斷），違規 exit 2 + 指名失敗 planned task；refinement Step 7 LOCK gate 串接為 fail-stop（DP-262 T4 selftest） |
| research-dispatch-unit-gate | contract_pointer | 研究單（全 audit task、無 implementation task）或轉發/theme 單（無 implementation task、僅 confirmation/dispatch）被當成獨立 delivery unit 走 breakdown / LOCK，繞過 D1 completion-standard contract | `scripts/validate-breakdown-ready.sh` 在 directory target 對 source 跑 delivery-unit shape gate，banks on 既有 task_shape classifier（無第二套）：研究單 exit 2 + `POLARIS_RESEARCH_UNIT_NO_IMPLEMENTATION`，轉發/theme 單 exit 2 + `POLARIS_DISPATCH_THEME_UNIT_NO_IMPLEMENTATION`；含 ≥1 implementation task 的 mixed-task DP（DP-262 carve-out）PASS。`scripts/validate-refinement-lock-preflight.sh` 委派同判定，LOCK 時就擋（DP-274 T2 selftest） |
| prose-vs-gate-admission | semantic_only | 新增行為原則時跳過 `contract-design.md` § prose-vs-gate 准入標準：A 類 gateable invariant 只寫 prose 不做 fail-closed gate、或 B 類純態度/生成行為（如 reflexive-cave：被質疑就反射性翻盤、討好使用者、過度道歉）新增 prose 規則想規範態度——兩者都讓 prose 治 prose 通膨。reflexive-cave 是 B 類典型：無 tool-call 邊界，框架給不出 commit-time 保證 | 本身屬 B 類，**無** deterministic gate（無 tool-call 觀察點可攔）；唯一證據是 post-task reflection 事後人讀偵測「本輪是否出現 reflexive-cave / A 類行為原則被 prose-only 落地」，發現時寫 feedback memory（帶本 mechanism ID）。不得偽裝成 `contract_pointer`；A 類行為原則的可 gate 部分另由各自 owning validator 攔（worked example：`scripts/review-inbox-discovery-probe.sh` fail-closed） |
| active-thread-writer-trigger-gap | contract_pointer | parking / session switch 發生時 anchor 寫入端（`scripts/update-active-thread.sh`）未被觸發：唯一 trigger `stop-active-thread-reminder.sh` 為 advisory-only（永遠 exit 0、never blocks），無 skill callsite 把 parking 綁到 anchor write，導致 parked work 逃逸到 ad-hoc `/tmp`（DP-300 incident：本 session anchor 仍停在前一條 `/auto-pass DP-298`）。A 類 gateable invariant，不得退回 advisory prose。DP-314 補強並行 session 偽陽：另一 session 在本 session block 後寫入更新 baseline 不得讓本 session 永遠 block，且過期 baseline 不得無限期觸發 | `.claude/hooks/stop-active-thread-reminder.sh` 升為 fail-closed Stop gate（DP-300 T2）：incomplete-work 訊號 AND 本 session 未刷新 anchor 兩者皆成立才 block，提示刷新指令；無 parked work / 明確 bypass 時 exit 0 不誤擋。DP-314 T1 加：(D1) block 時寫 per-session block-state（`$RUNTIME_DIR/stop-gate-block-state/<session_id>.json` 記 `blocked_at_epoch`），同 session anchor 在該時間戳之後刷新即放行（即使並行 session 已寫更新 baseline），但 anchor 未刷新時 block-state 不是無條件通行證仍 block；(D2) baseline mtime 超過 freshness window（預設 7 天，`POLARIS_STOP_GATE_BASELINE_WINDOW_DAYS` 覆寫）不算 incomplete-work 訊號；缺 session_id / 壞 payload / 缺 runtime dir / 損毀 block-state JSON 一律 fail-open exit 0。`scripts/selftests/stop-active-thread-reminder-selftest.sh`（AC1 race / AC2 window / AC4 fail-open / AC-NEG1 block / AC-NEG2 bypass+gate / AC-NEG3 block-state-not-pass / loop guard 全態） |
| auto-pass-terminal-v-not-canonical-terminal | contract_pointer | auto-pass 宣告 terminal=complete 後，PASS + human_disposition=passed 的 required V task 仍留在 `tasks/` 原位（未 move 到 `pr-release/`、status 非 `IMPLEMENTED`），需靠人工巡查 / closeout-drift 才發現；或 runner 對 FAIL / MANUAL_REQUIRED / UNCERTAIN / BLOCKED_ENV 的 V task 誤推進 | `scripts/auto-pass-runner.sh` Terminal Complete Sequence gate（DP-311 T1）：宣告 complete 前經唯一 canonical writer `scripts/mark-spec-implemented.sh` 推進 eligible V，再 fail-closed 重讀 canonical V task file state（pr-release/ + IMPLEMENTED + ac_verification PASS，與 `close-parent-spec-if-complete.sh` 同契約），任一未達降 `blocked_by_gate_failure`；resume-complete path 同 hook。selftest：`scripts/selftests/auto-pass-terminal-v-advance-selftest.sh`；runner read-only declared exception 由 `auto-pass-runner-selftest.sh` AC-NEG2 declared-exception check 守住單一 writer assignment site |
| auto-pass-terminal-t-not-canonical-terminal | contract_pointer | auto-pass 宣告 terminal=complete 後，completion_gate marker PASS at head 的 required implementation（task_shape=implementation，含缺欄位 default）T task 仍留在 `tasks/` 原位（未 move 到 `pr-release/`、status 非 `IMPLEMENTED`），需靠人工巡查 / closeout-drift 才發現；或 runner 對缺 marker / 非 PASS marker 的 implementation T task 誤推進，或誤擋 / 誤推進 audit/confirmation carve-out 與 ABANDONED T task | `scripts/auto-pass-runner.sh` Terminal Complete Sequence gate（DP-317 T1，對稱 DP-311 V gate）：宣告 complete 前對 completion_gate marker status=PASS 的 eligible implementation T 經唯一 canonical writer `scripts/mark-spec-implemented.sh`（與 V advance 共用同一 assignment site）推進，再 fail-closed 重讀 canonical T task file state（pr-release/ + IMPLEMENTED，與 `close-parent-spec-if-complete.sh` 同契約，無第二 classifier），任一未達降 `blocked_by_gate_failure`；task_shape ∈ {audit, confirmation} 走 DP-262 no-PR carve-out、ABANDONED 留原位；fresh 與 resume-complete path 同 hook。selftest：`scripts/selftests/auto-pass-terminal-v-advance-selftest.sh`（case11-16 涵蓋 advance / block / audit-confirmation / ABANDONED / V 迴歸）；runner read-only declared exception 由 `auto-pass-runner-selftest.sh` AC-NEG2 單一 writer assignment site check 守住。DP-360 note：交付 head 的 canonical authority 改為 task.md `deliverable.head_sha`（+ override），completion_gate marker filename head 來源正在退役；本 gate 的 completion_gate marker PASS-at-head reader relocation 到 task.md delivery block 由 DP-360-T7 交付 |
| auto-pass-ledger-finalize-locked-stage | contract_pointer | terminal=complete 收尾後 ledger terminal_status 仍停留 null（要靠 orchestrator prose 補寫或人工巡查），或 closeout chain 把 non-complete terminal（loop_cap_reached / blocked_by_gate_failure / user_aborted / 未解除 pause）改寫成 complete、對 archived container / frozen archived legacy ledger 做 LOCKED-required 寫入 | `scripts/auto-pass-finalize-ledger.sh`（DP-311 T2）是 ledger terminal finalize 的唯一 sanctioned deterministic writer：`scripts/mark-spec-implemented.sh` parent / bare-DP 分支在翻 IMPLEMENTED 之前（仍 LOCKED）呼叫；task-level path 不觸發（EC7）；non-complete terminal / 未解除 pause NOOP（AC-NEG4）；IMPLEMENTED / archived idempotent NOOP、不碰 frozen archived legacy ledger（AC-NEG5）；fail-closed 時 parent 不翻面（AC-NF1 順序）。selftest：`scripts/selftests/auto-pass-finalize-ledger-selftest.sh`；wiring 由 `scripts/selftests/closeout-chain-archive-selftest.sh` Layer 4 守住 |
| active-thread-single-thread-overwrite | contract_pointer | anchor 是單檔 overwrite，無法同時承載兩條以上並行 parked thread（DP-300 incident：DP-298 auto-pass + review-inbox）。寫第二條會 clobber 第一條或被迫逃逸到 ad-hoc 儲存；reader 也只列第一條。A 類 gateable invariant | `scripts/update-active-thread.sh` 改 per-thread-key upsert（DP-300 T3）：寫第二條 key 不 clobber 第一條，同 key 重寫 byte-idempotent，`--done/--remove` 清 key；`.claude/hooks/session-start-thread-anchor.sh` reader 全列 active threads。`scripts/selftests/update-active-thread-selftest.sh` + `scripts/selftests/session-start-thread-anchor-selftest.sh`（兩 key 並存 + idempotent + 全列 + 單 thread 回歸） |
| branch-name-non-ascii-escapes-gate | contract_pointer | branch slug producer（derive python / engineering bash / resolve bash）對含 CJK title 產出 durable 非 ASCII branch 名，或 task.md「Task branch」欄位 / content-bearing push 的非 ASCII branch 名繞過 derive-time + breakdown-readiness + pre-push 兩層 enforcement（DP-307 incident：CJK branch 開 PR 後 GitHub 不 retarget 直接 CLOSED） | `scripts/derive-task-md-from-refinement-json.sh` slugify ASCII-only + `scripts/validate-branch-name-ascii.sh` byte-level fail-closed（`POLARIS_BRANCH_NAME_NON_ASCII`，不 delegate `git check-ref-format`），wire 進 `scripts/validate-breakdown-ready.sh` derive-time 與 `.claude/hooks/pre-push-quality-gate.sh` / `scripts/install-copilot-hooks.sh` $PRE_PUSH_HOOK 兩層；delete-only/tags-only push 保留 DP-305-T3 carve-out。selftests：`scripts/selftests/branch-slug-producer-parity-selftest.sh`、`scripts/selftests/validate-branch-name-ascii-selftest.sh`、`scripts/selftests/pre-push-branch-name-ascii-selftest.sh` |
| utf8-boundary-lint-refspec-construction | contract_pointer | `bash-var-utf8-boundary-lint` 偵測範圍未涵蓋 branch-setup / pr-create 的 push refspec 構造：以 task-title-derived shell var 內插 refspec 時對 legacy 非 ASCII branch 發生 UTF-8 byte-boundary 損壞（DP-272 實證 workaround） | `scripts/lint-bash-variable-utf8-boundary.sh`（DP-307 T4 擴張）對 branch-setup / pr-create 的 refspec var 內插 pattern fail-closed、對 `git symbolic-ref --short HEAD` 構造 pass；`scripts/engineering-branch-setup.sh` / `scripts/polaris-pr-create.sh` 的 refspec 構造改用 symbolic-ref。selftest：`scripts/selftests/lint-bash-variable-utf8-boundary-selftest.sh`（refspec var 內插 fixture fail + marker、symbolic-ref 構造 fixture pass、兩 script 真實內容過 lint） |
| task-snapshot-refinement-hash-stale | contract_pointer | re-LOCK 後 refinement.json 變更，但以舊 hash 衍生的 stale task.md（task_snapshot）未被攔截就進 engineering/verify，需靠人工巡查才會發現；或新增第二套 refinement_hash 實作而非複用 `--print-refinement-hash`（DP-301 FD1 incident：DP-298 dogfood 中 source refinement 變更未綁 task_snapshot freshness） | `scripts/breakdown-emit-task-snapshot.sh` 在 marker 加 `freshness.source_refinement_hash`（值取自 `scripts/validate-auto-pass-ledger.sh --print-refinement-hash`，不寫第二套 hash），`--check` mode 比對 recorded hash ≠ 當前 refinement hash 時 fail-closed exit 2 + `POLARIS_TASK_SNAPSHOT_STALE`；缺欄位舊 marker additive no-op。selftest：`scripts/selftests/task-snapshot-refinement-hash-selftest.sh`（emit→改 refinement.json→stale 攔截、back-compat no-op、additive omit） |
| selftest-env-leak-hermeticity | contract_pointer | selftest spawn fixture-anchored Polaris child（`bash "$0" --scan-root ...`）卻未 unset `POLARIS_WORKSPACE_ROOT` / `POLARIS_SPECS_ROOT`，使 child short-circuit 到 live workspace；帶 env 與不帶 env 結果不一致，靠人工巡查才會發現（DP-301 release-block incident：`resolve-task-md-selftest` 在 `POLARIS_WORKSPACE_ROOT` 已 export 時 FAIL）。A 類 gateable invariant，不得退回 prose-only（對齊 DP-299） | `scripts/lint-selftest-env-hermeticity.sh` 靜態掃所有 selftest：line 同時 spawn Polaris child + 帶 `--scan-root` + 無 explicit `--specs-source` + 無 `env -u POLARIS_WORKSPACE_ROOT` + 無 inline fixture export 時 fail-closed exit 2 + `POLARIS_SELFTEST_ENV_LEAK`（含空 target / 不可讀 allowlist 等 missing-input fail-closed）；deliberately env-dependent leak-guard selftest 走 embedded allowlist。`scripts/resolve-task-md.sh` run_selftest 的 fixture child 已對齊 AC5 T6 `env -u` hermetic-unset pattern，解除 DP-301 block。selftest：`scripts/selftests/lint-selftest-env-hermeticity-selftest.sh`（positive leak + env-unset/specs-source/inline-export/comment/scan-dir negative + allowlist 抑制 + 兩 fail-closed + real-tree pass） |
| selftest-corpus-not-exhaustively-run | contract_pointer | framework PR gate / release lane 只跑 38 支 governed selftest，filesystem 上其餘 ~250 支 selftest 從未被機械執行，紅燈長期潛伏（DP-301 dogfood：release Step 1 假性綠燈、latent red 靠人工巡查才現形）；或新增 selftest 檔未被任何 runner 收編 | `scripts/run-aggregate-selftests.sh` filesystem-enumerate 全部 `scripts/selftests/*-selftest.sh` + `scripts/*-selftest.sh` 並執行，任一非 quarantine 紅燈 → exit 1 + `POLARIS_AGGREGATE_SELFTEST_RED`，quarantine 清單必 log（embedded list，AC-NF2）；`scripts/validate-selftest-enrollment.sh` filesystem-vs-runner 比對，未收編 selftest → exit 2 + `POLARIS_SELFTEST_ENROLLMENT_GAP`。兩者 wire 進 `scripts/check-framework-pr-gate.sh`（W13/W14）與 `scripts/framework-release-pr-lane.sh`（release gate，非-framework repo 無 corpus 時 skip-with-log）。selftest：`scripts/selftests/run-aggregate-selftests-selftest.sh`（一紅一綠 fixture → exit 1 + 紅燈 log、quarantine 跳過但必 log、enrollment gap fail-closed、missing-input fail-closed、--list） |
| breakdown-marker-supersede-stale-blocker | contract_pointer | breakdown 重新 re-package 成功並 emit PASS task_snapshot，但同 work-item 早先 failed run 留下的 `validation-fail/{id}.json` / `missing-v-task/{id}.json` blocker marker 沒被清掉；`auto-pass-probe.sh` stage breakdown 先讀 blocker subdir 再讀 task_snapshot，因此已修好的 work item 仍被 stale blocker 卡在 `blocked_by_gate_failure`，需靠人工刪 marker 才放行（DP-325 B incident） | `scripts/breakdown-emit-task-snapshot.sh` 在 PASS emit 後 writer-side supersede 同 work_item_id 的 `validation-fail` / `missing-v-task` blocker marker（reader 不改），scope 限同 work-item、限 `status=PASS`（非 PASS emit 不清），印 `SUPERSEDED:` 行。selftest：`scripts/selftests/breakdown-marker-supersede-selftest.sh`（pre-emit 被 stale blocker 卡 → PASS emit supersede → probe 放行；他 work-item blocker 保留；非 PASS emit 不清） |
| auto-pass-probe-latent-engineering-blocker-guard | semantic_only | `auto-pass-probe.sh` stage engineering 讀 `blocked-conflict/{id}-{sha}.json` 與 `unsupported-mutation/{id}-{sha}.json` 兩個 reader guard，但 workspace 內目前無任何 writer 會產生這兩個 marker（B2 latent，DP-325 EC3）。這是防呆 reader，不是現役 bug；風險在於未來有人 (a) 新增 writer 卻沒對齊 marker schema / path（`{id}-{sha}` naming），或 (b) 誤把這兩個 guard 當作「已驗證的 enforcement」而不知其無 writer。決策：保留 reader guard（移除等於放棄未來 conflict / unsupported-mutation 偵測的接點），不假裝是現役 bug，以本 canary 事後追蹤 | 無 commit-time gate（latent：無 writer 即無可觀察的 evidence trail）。post-task reflection 偵測：若本輪新增 `blocked-conflict` / `unsupported-mutation` marker writer，須同時驗 marker path = `.polaris/evidence/{blocked-conflict,unsupported-mutation}/{work_item_id}-{head_sha}.json`、`status` 欄位存在，並補對應 selftest；若發現有人移除 reader guard，須確認沒有同時放棄合法偵測接點 |
| consumer-reads-path-heuristic-not-authoritative-field | semantic_only | consumer 用 path / filename heuristic（`path.startswith(...)`、`"selftest" in name`、`name.startswith((...))`）推導本應由 authoritative field 決定的分類 / action，而同源已有權威欄位可讀（refinement.json `modules[].action`、`scripts/manifest.json` `kind` / `owner_surface`）。DP-325 dogfood incident：derive-task-md 的 task.md Action 用兩條互相不一致的 path heuristic（L407 `"selftest" in path` 與 L412 `"selftests/" in path`）、script-ownership-audit 用 `name.startswith(("validate-","check-",...))` 與 dead `scripts/gates/` path-prefix 分支，使 live framework 基礎設施（PR gate）被誤標 sunset_orphan | **B 類，無單一 commit-time gate**（區分「合法 path routing」與「path heuristic 取代欄位」需要語意判斷，機械掃描會大量誤報合法的 `scripts/gates/` / `.claude/skills/` routing）。可 gate 的部分由 worked-example selftest 守：`scripts/selftests/derive-task-md-action-from-field-selftest.sh`（同 path 在 `modules[].action`=create vs modify 下 Action 隨欄位；audit 分類在 manifest kind / owner_surface 與檔名衝突 fixture 下跟欄位）。殘餘 B 類缺口由 post-task reflection 事後人讀偵測「新 consumer 是否以 path heuristic 取代既有權威欄位」，發現時寫 feedback memory（帶本 mechanism ID）；不得偽裝成 `contract_pointer` |
| marker-source-artifact-path-stale | contract_pointer | D 類 reader（`check-delivery-completion.sh` completion_gate/ac_verification、`lib/evidence-classifier.sh` marker-pass）existence-only 卡 frozen `freshness.source_artifact` path：task.md 搬到 `pr-release/` 或 container archive 後 frozen path 不解析，reader 誤判 evidence missing 而 fail-closed，需人工巡查才發現（DP-301 D 類 3 instance：D1 write-completion-gate-marker、D2 breakdown-emit-task-snapshot、D3 write-ac-verification） | reader frozen path 不解析時改用 work_item_id canonical resolver（`scripts/resolve-task-md.sh --scan-root <repo> --include-archive`，不寫第二套 resolver）重定位 + 驗 marker 既存 `freshness.task_artifact_sha256`，moved task.md 放行、path-only-and-stale fail-closed；writer 不改（已持久化 sha256+work_item_id）。全表面 detector `scripts/validate-marker-artifact-resolvable.sh` 掃所有 completion_gate/ac_verification/task_snapshot marker，path-only 不可解析者 exit 2 + `POLARIS_MARKER_ARTIFACT_UNRESOLVABLE:<marker>`。selftests：`scripts/selftests/marker-source-artifact-move-resilience-selftest.sh`（reader move 後放行 + path-only fail-closed）、`scripts/selftests/validate-marker-artifact-resolvable-selftest.sh`（frozen-resolves / re-resolvable / path-only-stale / sha-mismatch）。DP-360 note：交付 head / delivery evidence 的 canonical authority 改為 task.md `deliverable.head_sha`（+ override），completion_gate marker 來源正在退役；本 reader 對 completion_gate marker 的 source-artifact resolution relocation 到 task.md delivery block 由 DP-360-T7 交付 |
| evidence-before-invention | semantic_only | agent 提任何新結構（DP / 方法 / governance / option 清單）前，未先回答「哪條既有 canonical contract 管這件事」並窮盡它就直接提新增；或把自己剛生成的 framing（draft assertion）當權威往下推；或 mid-task 發現 framework gap 時未辨「真實 gap vs 框架正確擋下（WAD）」、未附佐證（既有契約條文 / command 輸出 / source URL）就開 DP。亦涵蓋：任何驅動決策的 constraint 句（「X 需要 Y」「Z 不能做」「卡住因為…」）說出口時無 evidence 或既有契約支撐，卻被當作下一步地基而非 missing input 先驗證。對齊 bootstrap.md § Evidence-Before-Invention（DP-329 T1）與 `self-authored-prose-is-not-contract.md`、Decision Priority Principle。本條屬 B 類 reasoning-posture 原則：無 tool-call 邊界可攔（決策推理不在任一 deterministic 觀察點留下足跡），框架對它給不出 commit-time 保證 | 本身屬 B 類，**無** commit-time gate（無 deterministic 觀察點可攔 reasoning posture）；唯一證據是 post-task reflection 事後人讀偵測「本輪是否在未窮盡既有契約 / 未附佐證 / 把 self-generated framing 當權威的情況下提了新結構或開了 DP」，發現時寫 feedback memory（帶本 mechanism ID）。不得偽裝成 `contract_pointer`（對齊 DP-299 prose-vs-gate B 類判定，與 `prose-vs-gate-admission` canary 同 posture）；本原則的可 gate 部分（若未來辨識出 tool-call 觀察點）才另由 owning validator 攔 |
| producer-identity-parity-at-earliest-gate | contract_pointer | producer 的 product-identity 輸出（task.md「Task branch」欄位、PR title、changeset 名等）在最早 deterministic gate 未對 resolver invariant 做 parity，導致違規 identity 洩漏到下游才被攔（DP-328 incident：JIRA-Epic task branch 帶內部 composite `{Epic}-T{n}`，違反 `resolve-task-branch.sh` validate_branch 的 `task/{delivery_ticket_key}-` 契約，卻拖到 engineering-branch-setup 才 exit 1，卡死所有 JIRA-Epic implementation task）；或新增第二套 branch-identity 判斷而非複用 `resolve-task-branch.sh` validate_branch | `scripts/validate-breakdown-ready.sh` branch-identity gate（DP-328 T2）：對每個 task.md「Task branch」欄位複用唯一 canonical rule `scripts/resolve-task-branch.sh` validate_branch（禁止第二套 prefix/leak 實作），validate_branch exit 1（composite-Tn leak 或 wrong delivery-key prefix）時 exit 2 + `POLARIS_TASK_BRANCH_IDENTITY_LEAK`；validate_branch exit 2（無 identity / parse 失敗）由 schema gate 自有；無 Task branch 欄位 / DP-backed atom-collapse（delivery_ticket_key == work_item_id）不誤擋。producer 端 parity 由 `scripts/derive-task-md-from-refinement-json.sh` 用 `task_identity`（jira_key present 時=jira_key）derive branch（DP-328 T1）。selftests：`scripts/selftests/validate-breakdown-ready-branch-identity-selftest.sh`（dp-backed→pass / jira-key→pass / composite-Tn leak→exit 2 + marker / 不相關 readiness fail 仍 exit 1 / AC5 複用靜態斷言）、`scripts/selftests/branch-slug-producer-parity-selftest.sh`（DP-backed 與 JIRA-Epic-backed 雙 source derive-branch parity） |
| claimed-gap-not-verified-against-pinned-contract | semantic_only | agent 宣稱「framework gap」時雖已附上 `contract_evidence[]`，但 evidence 指到的 pinned contract surface 其實不能證明該 gap；例如引用到一般流程 prose、自己剛寫的 report、或無法對應到 validator / hook / task contract 的行，導致「有 evidence」但不是有效 contract binding | 本身屬 B 類語意判斷，**無** deterministic gate 能判定 evidence 是否真的證成 gap；deterministic 層只強制 gap assertion 必須附 `path:line`（DP-318 T1/T2）。post-task reflection 需抽查 framework gap claim 是否真的對照 pinned contract surface；漂移時寫 feedback memory（帶本 mechanism ID），不得把這筆升格成 `contract_pointer` |
| runtime-instruction-manifest-stale-after-source-edit | contract_pointer | rules/*.md / bootstrap.md / runtime overlay / manifest.yaml 被 Write/Edit/MultiEdit 改動後，generated runtime targets 與 rules-manifest snapshot 未重生，導致 `compile-runtime-instructions.sh --check` stale，需靠 pre-push gate（T1）或人工巡查才現形；或 hook 對非 source 檔誤觸發 regen 製造 noise，或自帶第二套 checksum 而非委派單一 writer | `.claude/hooks/post-runtime-instruction-manifest-regenerate.sh`（DP-320 T2）：命中 manifest source（rules/*.md maxdepth 1 / bootstrap.md / runtime/{claude,codex,copilot}.md / manifest.yaml）的 Write/Edit/MultiEdit 後委派唯一 canonical writer `scripts/compile-runtime-instructions.sh` 重生（hook 自身不含 checksum），使隨後 compile --check PASS；命中非 source 檔 no-op。runtime=claude-code-only（PostToolUse hook 僅 Claude Code 觸發），fallback_script=`scripts/compile-runtime-instructions.sh`（Codex / Copilot / raw bash edit 由 T1 portable pre-push gate 兜底）。selftest：`scripts/selftests/post-runtime-instruction-manifest-regenerate-selftest.sh` |
| release-stage-pr-release-exemption | contract_pointer | framework-release bundle 的 member task.md 全部 finalize 進 `*/tasks/pr-release/*` 後，impl-bearing（behavioral）bundle delta 仍被 gate-changeset 的 per-task changeset 契約或 gate-pr-title 的 `[KEY-Tn]` 契約擋下，使 bundle 被「torn apart」（DP-315 incident）；或實作偷用 container archive 狀態 / branch-name heuristic / 新增 `POLARIS_SKIP_*` env bypass 來達成 exemption，而非以 pr-release task lifecycle 位置觸發；或 multi-match bundle 用 `head -n 1` 取到某 pr-release member 就授予 release-stage，忽略仍在 `tasks/Tn/` 的 sibling | `scripts/gates/gate-changeset.sh` / `scripts/gates/gate-pr-title.sh` 在 resolve task 後、per-task contract（changeset check / evidence-classifier / ticket-summary derive）前插入 `is_release_stage_exempt`：iterate 全部 resolved member（branch multi-match 走 `--scan-root $REPO_ROOT` 取全集），EVERY member 在 `*/tasks/pr-release/*` 才 exit 0（all-members rule），任一在 `tasks/Tn/` 即 fall through 維持 per-task；exemption 先於 evidence-classifier 故 behavioral bundle 不被誤擋；gate-pr-title 僅豁免 `[KEY-Tn]`、仍以 bundle_title_regex 強制 language-safe 標題。selftest：`scripts/selftests/release-stage-pr-release-gate-selftest.sh`（AC1 all-pr-release behavioral→exit 0、AC2 chore release 標題→exit 0、AC3 active→per-task 維持、AC5 mixed→all-members 擋下、AC-NEG1 無新 bypass env、AC-NEG2 release_bump 回歸、AC-NEG3 無 archive/branch-name heuristic） |
| release-stage-bundle-precondition-not-finalized | contract_pointer | `engineering-branch-setup.sh --aggregate-release` 在任一 `--task-md` 仍在 active `tasks/Tn/`（未經 `finalize-engineering-delivery.sh` move-first closeout 進 `tasks/pr-release/`）時仍組裝 bundle branch，使 release-stage bundling 被「torn apart」——部分 member 還在開發階段就被收進 release bundle（DP-315 incident）；或以 container archive 狀態 / branch 命名 heuristic 取代 pr-release lifecycle 位置作判斷依據 | `scripts/engineering-branch-setup.sh` `run_aggregate_release` 在收集 `--task-md` 的 loop 內對每個 path 用 `is_pr_release_task`（pr-release lifecycle 位置，非 archive-state / branch-name heuristic，AC-NEG3）斷言位於 `tasks/pr-release/`，all-members rule：任一不符即 exit 2 + `POLARIS_RELEASE_STAGE_TASK_NOT_FINALIZED`、訊息指回 `finalize-engineering-delivery.sh`，且 fail-closed 發生在任何 branch / worktree 建立之前；全部在 `tasks/pr-release/` 時正常建 bundle branch（DP-319 T2 / AC4）。selftest：`scripts/selftests/release-stage-pr-release-gate-selftest.sh`（active member fail-closed + marker、mixed-member fail-closed、全 pr-release 正常建 branch） |

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
| skill-size-policy | script_candidate | M2 | Polaris | scripts/lint-skill-size.sh |

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
