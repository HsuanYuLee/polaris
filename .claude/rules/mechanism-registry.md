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

## Mechanism Tables（已搬出）

Runtime Annotation Registry 與 Cross-LLM Hook Parity Registry 兩張表是**腳本讀的資料**，
沒有一列需要 agent 在推理時記得，已搬到 `scripts/lib/mechanism-tables.md`。
Consumer 與欄位契約寫在該檔檔頭。

## Mechanism Canary Entries

需要判斷的條目留在這裡；`contract_pointer`（已由 script / hook 強制）只留索引。
完整 canary signal 與 deterministic evidence 見
`.claude/skills/references/mechanism-canary-entries.md`（需要時才載入）。

### 需要 agent 判斷（semantic_only / script_candidate）

| mechanism | disposition | canary signal | expected deterministic evidence |
|-----------|-------------|---------------|---------------------------------|
| prose-vs-gate-admission | semantic_only | 新增行為原則時跳過 `contract-design.md` § prose-vs-gate 准入標準：A 類 gateable invariant 只寫 prose 不做 fail-closed gate、或 B 類純態度/生成行為（如 reflexive-cave：被質疑就反射性翻盤、討好使用者、過度道歉）新增 prose 規則想規範態度——兩者都讓 prose 治 prose 通膨。reflexive-cave 是 B 類典型：無 tool-call 邊界，框架給不出 commit-time 保證 | 本身屬 B 類，**無** deterministic gate（無 tool-call 觀察點可攔）；唯一證據是 post-task reflection 事後人讀偵測「本輪是否出現 reflexive-cave / A 類行為原則被 prose-only 落地」，發現時寫 feedback memory（帶本 mechanism ID）。不得偽裝成 `contract_pointer`；A 類行為原則的可 gate 部分另由各自 owning validator 攔（worked example：`scripts/review-inbox-discovery-probe.sh` fail-closed） |
| auto-pass-probe-latent-engineering-blocker-guard | semantic_only | `auto-pass-probe.sh` stage engineering 讀 `blocked-conflict/{id}-{sha}.json` 與 `unsupported-mutation/{id}-{sha}.json` 兩個 reader guard，但 workspace 內目前無任何 writer 會產生這兩個 marker（B2 latent，DP-325 EC3）。這是防呆 reader，不是現役 bug；風險在於未來有人 (a) 新增 writer 卻沒對齊 marker schema / path（`{id}-{sha}` naming），或 (b) 誤把這兩個 guard 當作「已驗證的 enforcement」而不知其無 writer。決策：保留 reader guard（移除等於放棄未來 conflict / unsupported-mutation 偵測的接點），不假裝是現役 bug，以本 canary 事後追蹤 | 無 commit-time gate（latent：無 writer 即無可觀察的 evidence trail）。post-task reflection 偵測：若本輪新增 `blocked-conflict` / `unsupported-mutation` marker writer，須同時驗 marker path = `.polaris/evidence/{blocked-conflict,unsupported-mutation}/{work_item_id}-{head_sha}.json`、`status` 欄位存在，並補對應 selftest；若發現有人移除 reader guard，須確認沒有同時放棄合法偵測接點 |
| consumer-reads-path-heuristic-not-authoritative-field | semantic_only | consumer 用 path / filename heuristic（`path.startswith(...)`、`"selftest" in name`、`name.startswith((...))`）推導本應由 authoritative field 決定的分類 / action，而同源已有權威欄位可讀（refinement.json `modules[].action`、`scripts/manifest.json` `kind` / `owner_surface`）。DP-325 dogfood incident：derive-task-md 的 task.md Action 用兩條互相不一致的 path heuristic（L407 `"selftest" in path` 與 L412 `"selftests/" in path`）、script-ownership-audit 用 `name.startswith(("validate-","check-",...))` 與 dead `scripts/gates/` path-prefix 分支，使 live framework 基礎設施（PR gate）被誤標 sunset_orphan | **B 類，無單一 commit-time gate**（區分「合法 path routing」與「path heuristic 取代欄位」需要語意判斷，機械掃描會大量誤報合法的 `scripts/gates/` / `.claude/skills/` routing）。可 gate 的部分由 worked-example selftest 守：`scripts/selftests/derive-task-md-action-from-field-selftest.sh`（同 path 在 `modules[].action`=create vs modify 下 Action 隨欄位；audit 分類在 manifest kind / owner_surface 與檔名衝突 fixture 下跟欄位）。殘餘 B 類缺口由 post-task reflection 事後人讀偵測「新 consumer 是否以 path heuristic 取代既有權威欄位」，發現時寫 feedback memory（帶本 mechanism ID）；不得偽裝成 `contract_pointer` |
| evidence-before-invention | semantic_only | agent 提任何新結構（DP / 方法 / governance / option 清單）前，未先回答「哪條既有 canonical contract 管這件事」並窮盡它就直接提新增；或把自己剛生成的 framing（draft assertion）當權威往下推；或 mid-task 發現 framework gap 時未辨「真實 gap vs 框架正確擋下（WAD）」、未附佐證（既有契約條文 / command 輸出 / source URL）就開 DP。亦涵蓋：任何驅動決策的 constraint 句（「X 需要 Y」「Z 不能做」「卡住因為…」）說出口時無 evidence 或既有契約支撐，卻被當作下一步地基而非 missing input 先驗證。對齊 bootstrap.md § Evidence-Before-Invention（DP-329 T1）與 `self-authored-prose-is-not-contract.md`、Decision Priority Principle。本條屬 B 類 reasoning-posture 原則：無 tool-call 邊界可攔（決策推理不在任一 deterministic 觀察點留下足跡），框架對它給不出 commit-time 保證 | 本身屬 B 類，**無** commit-time gate（無 deterministic 觀察點可攔 reasoning posture）；唯一證據是 post-task reflection 事後人讀偵測「本輪是否在未窮盡既有契約 / 未附佐證 / 把 self-generated framing 當權威的情況下提了新結構或開了 DP」，發現時寫 feedback memory（帶本 mechanism ID）。不得偽裝成 `contract_pointer`（對齊 DP-299 prose-vs-gate B 類判定，與 `prose-vs-gate-admission` canary 同 posture）；本原則的可 gate 部分（若未來辨識出 tool-call 觀察點）才另由 owning validator 攔 |
| in-session-decision-slip | semantic_only | in-session（非跨-session）orchestration 中，agent 把自己剛生成的 framing（draft assertion）當權威，推翻其實正確的 sub-agent 結論、或把「框架正確擋下（WAD）」誤判成 framework bug，而未先 resolve 既有 canonical contract + 取得正確 shape 證據就往下推（對齊 `self-authored-prose-is-not-contract.md` 的 in-session handoff 範圍與 `evidence-before-invention`）。本條屬 B 類 reasoning-posture slip：違規發生在 agent 的判斷推理，不在任一 deterministic 觀察點（tool-call argument / changed-file glob / artifact schema / exit code）留下足跡，框架對它給不出 commit-time 保證 | 本身屬 B 類，**無** commit-time gate（無 tool-call 觀察點可攔 in-session reasoning slip）；唯一證據是 post-task reflection 事後人讀偵測「本輪是否把 self-generated framing 當權威推翻正確 sub-agent / 誤報 WAD 為 bug 而未先對既有契約 + shape 證據驗證」，發現時寫 feedback memory（帶本 mechanism ID）。不得偽裝成 `contract_pointer`（對齊 DP-299 prose-vs-gate B 類判定，與 `prose-vs-gate-admission` / `evidence-before-invention` canary 同 posture） |
| claimed-gap-not-verified-against-pinned-contract | semantic_only | agent 宣稱「framework gap」時雖已附上 `contract_evidence[]`，但 evidence 指到的 pinned contract surface 其實不能證明該 gap；例如引用到一般流程 prose、自己剛寫的 report、或無法對應到 validator / hook / task contract 的行，導致「有 evidence」但不是有效 contract binding | 本身屬 B 類語意判斷，**無** deterministic gate 能判定 evidence 是否真的證成 gap；deterministic 層只強制 gap assertion 必須附 `path:line`（DP-318 T1/T2）。post-task reflection 需抽查 framework gap claim 是否真的對照 pinned contract surface；漂移時寫 feedback memory（帶本 mechanism ID），不得把這筆升格成 `contract_pointer` |

### 已由 deterministic gate 強制（contract_pointer，索引）

依 § Disposition 圖例，這些只在「工具失敗被忽略、繞過或誤讀」時才需要回頭看。

`gate-fail-self-correct-disposition` · `tier-a-direct-call-governance` · `auto-pass-orchestrator-premature-stop` · `closeout-chain-archive-not-deterministic` · `closeout-drift-delivered-but-not-archived` · `dp-keyed-source-symmetry` · `baseline-snapshot-stale-after-intake` · `audit-confirmation-task-kind-carve-out` · `refinement-lock-preflight` · `research-dispatch-unit-gate` · `evidence-bearing-command-direct-call` · `active-thread-writer-trigger-gap` · `auto-pass-terminal-v-not-canonical-terminal` · `auto-pass-terminal-t-not-canonical-terminal` · `auto-pass-ledger-finalize-locked-stage` · `active-thread-single-thread-overwrite` · `branch-name-non-ascii-escapes-gate` · `utf8-boundary-lint-refspec-construction` · `task-snapshot-refinement-hash-stale` · `selftest-env-leak-hermeticity` · `selftest-corpus-not-exhaustively-run` · `breakdown-marker-supersede-stale-blocker` · `marker-source-artifact-path-stale` · `producer-identity-parity-at-earliest-gate` · `runtime-instruction-manifest-stale-after-source-edit` · `generated-artifact-interface-without-freshness` · `release-stage-pr-release-exemption` · `release-stage-bundle-precondition-not-finalized` · `work-item-id-branch-identity-conflated` · `marker-reader-product-repo-evidence-root` · `ci-local-content-hash-staleness` · `branch-setup-base-context-cwd-independent` · `spec-check-contract-parity` · `worktree-cleanup-stop-worktree-scoped-dev-server` · `delivery-evidence-conformance` · `artifact-contract-conformance` · `self-referential-dp-delivery`

## Script Candidate Graduation Schedule

`script_candidate` 不可只停在 prose audit；每筆都要有 milestone 與 owner。`M-future`
可存在，但比例必須 ≤ 40%，避免把所有 graduation 都推給未來。

| mechanism | disposition | graduation_milestone | owner | deterministic target |
|-----------|-------------|----------------------|-------|----------------------|
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

## Producer／Consumer／Validator Registry

`scripts/lib/producer-consumer-bridges.json` 是 field、producer specs、validator 與 live
anchor 的單一 bridge registry；`scripts/refinement-consumer-registry.json` 是
refinement.json `tasks[]` consumer accessor 的單一 registry。前者缺 producer／validator、
規格矛盾或 stale anchor 均 fail-closed；後者攔截未登錄 consumer 與 out-of-schema read。
兩個 validator 都接入 `check-framework-pr-gate.sh` W12 blocking aggregate，包含
`backfill-refinement-verification-strategy.sh` 的 `task` accessor binding。
兩者以 `--describe-authority` 暴露 machine-readable owner identity，供 DP-422 source
closeout 檢查 owner collision；introspection 不新增 registry，也不重新實作 parity 判定。


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
