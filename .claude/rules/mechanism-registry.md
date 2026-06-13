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

## Mechanism Canary Entries

| mechanism | disposition | canary signal | expected deterministic evidence |
|-----------|-------------|---------------|---------------------------------|
| gate-fail-self-correct-disposition | contract_pointer | gate exit 2 後 agent 只用口頭說明「已修正」，沒有逐筆處理 gate failure ledger | `scripts/gate-hook-adapter.sh` 寫入 `.polaris/evidence/gate-failures/{task_id}.jsonl`；post-task reflection 產出 `self_correct_disposition[]`，每筆標 `fixed` / `accepted-workaround` / `escalated` |
| tier-a-direct-call-governance | contract_pointer | 新增 script 直接呼叫 `node` / `pnpm` / `jq` / `rg` / `gh`，或把 ticket-scoped tool 誤加進 root mise，而未經 resolver / disposition | `scripts/validate-script-dependencies.sh` 讀取 `scripts/tool-direct-call-inventory-disposition.txt`，新增違規輸出 `POLARIS_TOOL_DIRECT_CALL` / `POLARIS_TICKET_SCOPED_TOOL_DIRECT_CALL` |
| auto-pass-orchestrator-premature-stop | contract_pointer | inner skill HALT 或 session pressure 建議後，auto-pass 直接停下交回 user，而 deterministic sidecar 已可繼續 | `pause.kind=session_handoff` + `scripts/validate-auto-pass-resume.sh`；若 sidecar PASS 則不得 pause |
| closeout-chain-archive-not-deterministic | contract_pointer | terminal complete 後 parent spec 留在 active 區，還需要使用者另跑 archive | `scripts/selftests/closeout-chain-archive-selftest.sh` 覆蓋 mark-spec / auto-pass docs / framework-release closeout callsite |
| closeout-drift-delivered-but-not-archived | contract_pointer | LOCKED DP 已交付（全 task marker + merged PR / CHANGELOG）卻從未 archive，或 LOCKED 後過期無交付證據（stranded），需靠人工巡查才會發現 | `mise run closeout-drift`（`scripts/detect-closeout-drift.sh --dry-run --json`）以 marker + CHANGELOG + merged-PR 三來源分類 `delivered-drift-high` / `delivered-drift-low` / `stranded`；`delivered-drift-high` 經既有 `scripts/mark-spec-implemented.sh` 單一 writer 自動收編，其餘 report-only。`gh` 缺席時 merged-PR 來源 fail-open（D7），report 標 PR 證據未檢。my-triage / standup 盤點併入此清單。selftest：`scripts/selftests/detect-closeout-drift-selftest.sh` |
| baseline-snapshot-stale-after-intake | contract_pointer | breakdown route=task_update 合法改動 planner-owned task.md 後，engineering/finalize 仍讀到舊 baseline snapshot | `scripts/refresh-baseline-snapshot.sh` 重新產生 current head snapshot，舊 snapshot rename `*.superseded` |
| audit-confirmation-task-kind-carve-out | contract_pointer | implementation task 被誤標 `task_shape: audit` / `confirmation` 來逃避 specs-only / non-PR gate，或 carve-out 外溢到 implementation（含缺欄位）task | `scripts/validate-breakdown-ready.sh` 對 `task_shape ∈ {audit, confirmation}` 放寬 specs-only/empty Allowed Files，implementation 維持原 exit 1；`scripts/check-delivery-completion.sh` 對同集合走 completion-gate marker(status=PASS)+evidence path，implementation 維持原 non-draft PR gate（DP-262 T2/T3 selftest） |
| refinement-lock-preflight | contract_pointer | LOCK 時把 planned implementation task 宣告成 specs-only deliverable，要到 breakdown 階段才被 `validate-breakdown-ready` 擋下 | `scripts/validate-refinement-lock-preflight.sh` 讀 `refinement.json planned_tasks[]`、合成 placeholder task.md 跑 `validate-breakdown-ready` 本體（不重寫 specs-prefix 判斷），違規 exit 2 + 指名失敗 planned task；refinement Step 7 LOCK gate 串接為 fail-stop（DP-262 T4 selftest） |
| research-dispatch-unit-gate | contract_pointer | 研究單（全 audit task、無 implementation task）或轉發/theme 單（無 implementation task、僅 confirmation/dispatch）被當成獨立 delivery unit 走 breakdown / LOCK，繞過 D1 completion-standard contract | `scripts/validate-breakdown-ready.sh` 在 directory target 對 source 跑 delivery-unit shape gate，banks on 既有 task_shape classifier（無第二套）：研究單 exit 2 + `POLARIS_RESEARCH_UNIT_NO_IMPLEMENTATION`，轉發/theme 單 exit 2 + `POLARIS_DISPATCH_THEME_UNIT_NO_IMPLEMENTATION`；含 ≥1 implementation task 的 mixed-task DP（DP-262 carve-out）PASS。`scripts/validate-refinement-lock-preflight.sh` 委派同判定，LOCK 時就擋（DP-274 T2 selftest） |
| prose-vs-gate-admission | semantic_only | 新增行為原則時跳過 `contract-design.md` § prose-vs-gate 准入標準：A 類 gateable invariant 只寫 prose 不做 fail-closed gate、或 B 類純態度/生成行為（如 reflexive-cave：被質疑就反射性翻盤、討好使用者、過度道歉）新增 prose 規則想規範態度——兩者都讓 prose 治 prose 通膨。reflexive-cave 是 B 類典型：無 tool-call 邊界，框架給不出 commit-time 保證 | 本身屬 B 類，**無** deterministic gate（無 tool-call 觀察點可攔）；唯一證據是 post-task reflection 事後人讀偵測「本輪是否出現 reflexive-cave / A 類行為原則被 prose-only 落地」，發現時寫 feedback memory（帶本 mechanism ID）。不得偽裝成 `contract_pointer`；A 類行為原則的可 gate 部分另由各自 owning validator 攔（worked example：`scripts/review-inbox-discovery-probe.sh` fail-closed） |
| active-thread-writer-trigger-gap | contract_pointer | parking / session switch 發生時 anchor 寫入端（`scripts/update-active-thread.sh`）未被觸發：唯一 trigger `stop-active-thread-reminder.sh` 為 advisory-only（永遠 exit 0、never blocks），無 skill callsite 把 parking 綁到 anchor write，導致 parked work 逃逸到 ad-hoc `/tmp`（DP-300 incident：本 session anchor 仍停在前一條 `/auto-pass DP-298`）。A 類 gateable invariant，不得退回 advisory prose | `.claude/hooks/stop-active-thread-reminder.sh` 升為 fail-closed Stop gate（DP-300 T2）：incomplete-work 訊號 AND 本 session 未刷新 anchor 兩者皆成立才 block，提示刷新指令；無 parked work / 明確 bypass 時 exit 0 不誤擋。`scripts/selftests/stop-active-thread-reminder-selftest.sh`（block / 不擋 / bypass / false-positive 四態） |
| auto-pass-terminal-v-not-canonical-terminal | contract_pointer | auto-pass 宣告 terminal=complete 後，PASS + human_disposition=passed 的 required V task 仍留在 `tasks/` 原位（未 move 到 `pr-release/`、status 非 `IMPLEMENTED`），需靠人工巡查 / closeout-drift 才發現；或 runner 對 FAIL / MANUAL_REQUIRED / UNCERTAIN / BLOCKED_ENV 的 V task 誤推進 | `scripts/auto-pass-runner.sh` Terminal Complete Sequence gate（DP-311 T1）：宣告 complete 前經唯一 canonical writer `scripts/mark-spec-implemented.sh` 推進 eligible V，再 fail-closed 重讀 canonical V task file state（pr-release/ + IMPLEMENTED + ac_verification PASS，與 `close-parent-spec-if-complete.sh` 同契約），任一未達降 `blocked_by_gate_failure`；resume-complete path 同 hook。selftest：`scripts/selftests/auto-pass-terminal-v-advance-selftest.sh`；runner read-only declared exception 由 `auto-pass-runner-selftest.sh` AC-NEG2 declared-exception check 守住單一 writer assignment site |
| auto-pass-ledger-finalize-locked-stage | contract_pointer | terminal=complete 收尾後 ledger terminal_status 仍停留 null（要靠 orchestrator prose 補寫或人工巡查），或 closeout chain 把 non-complete terminal（loop_cap_reached / blocked_by_gate_failure / user_aborted / 未解除 pause）改寫成 complete、對 archived container / frozen archived legacy ledger 做 LOCKED-required 寫入 | `scripts/auto-pass-finalize-ledger.sh`（DP-311 T2）是 ledger terminal finalize 的唯一 sanctioned deterministic writer：`scripts/mark-spec-implemented.sh` parent / bare-DP 分支在翻 IMPLEMENTED 之前（仍 LOCKED）呼叫；task-level path 不觸發（EC7）；non-complete terminal / 未解除 pause NOOP（AC-NEG4）；IMPLEMENTED / archived idempotent NOOP、不碰 frozen archived legacy ledger（AC-NEG5）；fail-closed 時 parent 不翻面（AC-NF1 順序）。selftest：`scripts/selftests/auto-pass-finalize-ledger-selftest.sh`；wiring 由 `scripts/selftests/closeout-chain-archive-selftest.sh` Layer 4 守住 |
| active-thread-single-thread-overwrite | contract_pointer | anchor 是單檔 overwrite，無法同時承載兩條以上並行 parked thread（DP-300 incident：DP-298 auto-pass + review-inbox）。寫第二條會 clobber 第一條或被迫逃逸到 ad-hoc 儲存；reader 也只列第一條。A 類 gateable invariant | `scripts/update-active-thread.sh` 改 per-thread-key upsert（DP-300 T3）：寫第二條 key 不 clobber 第一條，同 key 重寫 byte-idempotent，`--done/--remove` 清 key；`.claude/hooks/session-start-thread-anchor.sh` reader 全列 active threads。`scripts/selftests/update-active-thread-selftest.sh` + `scripts/selftests/session-start-thread-anchor-selftest.sh`（兩 key 並存 + idempotent + 全列 + 單 thread 回歸） |
| branch-name-non-ascii-escapes-gate | contract_pointer | branch slug producer（derive python / engineering bash / resolve bash）對含 CJK title 產出 durable 非 ASCII branch 名，或 task.md「Task branch」欄位 / content-bearing push 的非 ASCII branch 名繞過 derive-time + breakdown-readiness + pre-push 兩層 enforcement（DP-307 incident：CJK branch 開 PR 後 GitHub 不 retarget 直接 CLOSED） | `scripts/derive-task-md-from-refinement-json.sh` slugify ASCII-only + `scripts/validate-branch-name-ascii.sh` byte-level fail-closed（`POLARIS_BRANCH_NAME_NON_ASCII`，不 delegate `git check-ref-format`），wire 進 `scripts/validate-breakdown-ready.sh` derive-time 與 `.claude/hooks/pre-push-quality-gate.sh` / `scripts/install-copilot-hooks.sh` $PRE_PUSH_HOOK 兩層；delete-only/tags-only push 保留 DP-305-T3 carve-out。selftests：`scripts/selftests/branch-slug-producer-parity-selftest.sh`、`scripts/selftests/validate-branch-name-ascii-selftest.sh`、`scripts/selftests/pre-push-branch-name-ascii-selftest.sh` |
| utf8-boundary-lint-refspec-construction | contract_pointer | `bash-var-utf8-boundary-lint` 偵測範圍未涵蓋 branch-setup / pr-create 的 push refspec 構造：以 task-title-derived shell var 內插 refspec 時對 legacy 非 ASCII branch 發生 UTF-8 byte-boundary 損壞（DP-272 實證 workaround） | `scripts/lint-bash-variable-utf8-boundary.sh`（DP-307 T4 擴張）對 branch-setup / pr-create 的 refspec var 內插 pattern fail-closed、對 `git symbolic-ref --short HEAD` 構造 pass；`scripts/engineering-branch-setup.sh` / `scripts/polaris-pr-create.sh` 的 refspec 構造改用 symbolic-ref。selftest：`scripts/selftests/lint-bash-variable-utf8-boundary-selftest.sh`（refspec var 內插 fixture fail + marker、symbolic-ref 構造 fixture pass、兩 script 真實內容過 lint） |

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
