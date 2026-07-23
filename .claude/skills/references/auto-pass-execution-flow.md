---
title: "Auto-pass Execution Flow"
description: "auto-pass runner-first execution loop、dispatch envelope、pause / retry cap 與 terminal fixed-point。"
---

# Auto-pass Execution Flow

`auto-pass` 的 execution loop 是 **runner-first**：orchestrator 只讀
`scripts/auto-pass-runner.sh` 輸出的 JSON next-action contract 來決定下一步。runner JSON
是主鏈唯一狀態來源——orchestrator 不再各階段重跑 `auto-pass-probe.sh` 或自行解析 ledger /
filesystem evidence。runner 內部仍 wrap probe + ledger validator + spec source resolver，
但這層 implementation detail 不外露給 orchestrator；orchestrator 只認 runner JSON。

> Runner JSON 也不讀 inner skill final answer 來判斷 PASS：missing / UNKNOWN marker 永遠
> escalate 為 `blocked_by_gate_failure`，即使 spec / refinement / inner skill output prose 含
> 字面 "PASS"。

## Stage Order

1. source resolver gate：唯一 locked/current refinement-owned source（DP-backed 或
   JIRA Epic-backed，由 `spec-source-resolver.md` 解析）。
2. ledger gate：valid source-scoped ledger；pending pause 時 validate resume prerequisite。
   JIRA Epic-backed source 額外檢查 `consent_policy.jira_status_sync` 與 session-scoped marker。
3. breakdown stage：dispatch breakdown，PASS 後鎖定最後一次 task snapshot。
4. engineering stage：依 task DAG dispatch engineering。`task_shape: implementation`
   （含缺欄位 default）要求 non-draft workspace PR opened / ready；`task_shape ∈
   {audit, confirmation}` 的 task 走 no-PR completion path（completion_gate marker
   status=PASS + evidence artifact path），不要求 deliverable PR（見下方 § Required PR
   Set task_shape Carve-out）。
5. verify-AC stage：要求 V work order verification disposition current。
6. terminal fixed-point：required PR set ready + verification current + no higher-priority terminal state。

## Runner JSON Contract

orchestrator 每個 stage transition 只呼叫一次 runner，並把整份 JSON 當作 next-action
authority。runner 不需要 orchestrator 再額外 probe / ledger / filesystem read。

```bash
bash scripts/auto-pass-runner.sh \
  --repo /absolute/path/to/main-checkout \
  --source-id {SOURCE_ID} \
  --stage source|breakdown|engineering|verify-AC \
  [--work-item-id {SOURCE_ID}-T1] \
  [--head-sha <head_sha>] \
  [--ledger /absolute/path/to/ledger.json]
```

JSON 輸出（`schema_version=1`，欄位穩定）：

- `schema_version`
- `source_id`
- `stage`
- `status`：`PASS` | `BLOCKED` | `UNKNOWN` | `ROUTE_BACK_AMEND` | `MANUAL_REQUIRED` | …
- `terminal_status`：`complete` | `loop_cap_reached` | `blocked_by_gate_failure` |
  `paused_for_user_external_write` | `user_aborted` | `null`
- `next_action`：`dispatch` | `terminal` | `blocked` | `resume` | `refinement_amendment`
- `next_skill`：`breakdown` | `engineering` | `verify-AC` | `refinement` | `null`
- `next_work_item_id`：sibling task / V item id 或 source_id；non-applicable 時 `null`
- `evidence_path`：對應 marker 或 resume artifact 的絕對路徑
- `reason`：短字串，供 log / friction 寫入

`status=UNKNOWN` 或 missing marker 永遠 escalate 為 `terminal_status=blocked_by_gate_failure`，
不論 inner skill / spec prose 是否含 "PASS"。

### Internal Probe Wrapping（implementation detail）

runner 內部仍 wrap `auto-pass-probe.sh` 與 `validate-auto-pass-ledger.sh`，分階段對下列
canonical proof markers 做 deterministic lookup。**orchestrator 不直接呼叫**這層；只透過
runner JSON 看結果。

下表 marker path 的 `{work_item_id}` 是 breakdown / engineering / auto-pass 共用的
**canonical task id**（`{source}-T{n}`）。short id、full id、folder-native task path 三種輸入
如何收斂到這一個 id（及其 parent lifecycle anchor `source_id`）見
`pipeline-handoff.md` § Canonical task identity resolution（DP-417 T4）。

| Stage | PASS marker | Blocked / route-back signal | Terminal / next action |
|-------|------------|----------------------------|------------------------|
| breakdown | `.polaris/evidence/task-snapshot/{work_item_id}.json` status PASS | `validation_fail`、`missing_v_task`、`refinement-inbox/` | PASS dispatch engineering；route-back amendment loop；blocked gate failure |
| engineering | `.polaris/evidence/completion-gate/{work_item_id}-{head_sha}.json` status PASS | `blocked_conflict`、`unsupported_mutation`、open PR `needs_code_changes`（actionable review signals） | PASS + 無 actionable signal dispatch verify-AC；`needs_code_changes` `ROUTE_BACK_REVISION` dispatch engineering（revision）；`planning_gap` breakdown；spec issue refinement amendment；blocked gate failure |
| verify-AC | `.polaris/evidence/ac-verification/{work_item_id}-{head_sha}.json` status PASS | `spec_issue`、`MANUAL_REQUIRED`、`BLOCKED_ENV`、`UNCERTAIN`、missing marker | PASS complete；spec issue amendment loop；manual/env pause；unknown blocked |

需要直接 debug 內部 marker 狀態時可以單獨跑 `auto-pass-probe.sh`，但 orchestrator code path
不得以 probe 結果取代 runner JSON。runner ↔ probe 的 stage state parity 由
`scripts/selftests/auto-pass-runner-probe-parity-selftest.sh` enforce。

## Required PR Set task_shape Carve-out（DP-262 T3）

terminal fixed-point 的 **required PR set** 只涵蓋 `task_shape: implementation`（含缺欄位
default）的 task。`task_shape ∈ {audit, confirmation}` 的 task 是 audit / confirmation-only
work order（specs-only 或 empty Allowed Files，無 source diff、無 deliverable PR），因此**排除**
在 required PR set 之外：

- engineering stage 對這類 task 以 `completion_gate` marker（status=PASS）+ marker freshness
  的 evidence artifact path 視為完成，不要求 `deliverable.pr_url` / non-draft PR。enforcement
  落在 `scripts/check-delivery-completion.sh` 的 `task_shape` 分支（同一 task_shape 欄位，無第二套
  classifier）。
- 含 audit / confirmation task 的 source，在其餘 implementation task 的 PR ready、所有
  V work order verification disposition current 時，即可達 terminal `complete`，**不因這類 task
  缺 PR 而阻塞** required PR set。
- carve-out 嚴格綁 `task_shape ∈ {audit, confirmation}`；`implementation`（含缺欄位）的 task
  仍必須有 ready 的 deliverable PR 才算進 required PR set ready，PR gate 不放寬。

## Dispatch Envelope Worktree Resolution

dispatch envelope 描述 orchestrator 把 runner JSON 翻譯成下一段 sub-agent invocation 時必
帶的最小欄位：

- `AUTO_PASS_LEDGER_PATH=/abs/path/to/ledger.json`（breakdown / engineering / verify-AC
  皆必帶；resume 也帶同一個 ledger）。
- `worktree_resolution`：engineering / verify-AC stage 透過
  `scripts/resolve-task-worktree.sh --source-id ... --work-item-id ... --format json`
  解析得到，JSON 形如
  `{"status": "FOUND|NONE", "path": "<abs|null>", "task_key": "<key>", "kind": "implementation|verify_integration|null"}`。
  - `FOUND` + `kind=implementation` → 帶 implementation worktree path，sub-agent 直接以
    該路徑作為 implementation repo / cwd。
  - `FOUND` + `kind=verify_integration` → 僅限 source-level V work order；resolver 已依
    predecessor deliverable head 或 V task `Base branch` 建立 / 找到
    `verify-integration-{source}-{Vn}` throwaway worktree。orchestrator 必須把此 path 原樣
    dispatch 給 verify-AC，verify-AC 必須在該 path 執行，不得 fall back 到 main checkout。
  - `NONE` 且 stage 為 engineering first-cut（runner JSON 為 `next_action=dispatch`，
    `next_skill=engineering`，且 `evidence_path` 尚無 completion-gate marker）→ 正常初始
    狀態，orchestrator 仍 dispatch `engineering`，由 `engineering-branch-setup.sh` 建 fresh
    branch / worktree。
  - `NONE` 但 stage 為 verify-AC 或 engineering resume（runner JSON 不是 first-cut path）→
    terminal `blocked_by_missing_worktree`；orchestrator 不得在 verify-AC 階段 fallback 到 main
    checkout 或隱式建立 implementation worktree。
  - `AMBIGUOUS` → resolver 自身 fail-stop（stderr），orchestrator 升 terminal
    `blocked_by_gate_failure` 並把 resolver stderr 寫入 ledger friction。

dispatch envelope 也必須帶 worktree path map 給 sub-agent（gitignored framework artifact
讀寫一律使用主 checkout 絕對路徑），canonical contract 在
`.claude/skills/references/worktree-dispatch-paths.md`。

## Loop Caps

Planning loop counters live in ledger:

- `loop_counters.engineering_to_breakdown`
- `loop_counters.breakdown_to_refinement_inbox`

任一 counter 達 3，terminal `loop_cap_reached`。此 cap 只涵蓋 planning backward transition。

Review-revision loop counter（DP-313）：

- `loop_counters.engineering_revision_rounds`

engineering stage 偵測到 open PR 的 actionable review signals（classifier 回
`needs_code_changes`）後 dispatch `engineering`（revision mode）；每輪 dispatch 以
`auto-pass-increment-counter.sh` 對此 counter +=1。比照 `engineering_to_breakdown` 模式，
`count > 3` 時 terminal `loop_cap_reached` 並產出 report（schema、shape、cap、consent 明文以
`.claude/skills/references/auto-pass-ledger.md` § engineering_revision_rounds counter 為準）。

Implementation drift retry 另存在 `drift_retry`，以 V item 為 key。單一 V item 達 3 次仍 FAIL,
terminal `blocked_by_gate_failure`。

### Counter Increment Contract (DP-246)

`scripts/auto-pass-increment-counter.sh` 是 transition writer 專用 helper：

```bash
scripts/auto-pass-increment-counter.sh "$AUTO_PASS_LEDGER_PATH" \
  --transition <engineering_to_breakdown|breakdown_to_refinement_inbox|verify_ac_to_engineering> \
  --evidence-id "<source_id>:<from_stage>-><to_stage>:<seq>" \
  --stage <stage>
```

`--evidence-id` 是必填參數（DP-246 AC-NEG2）；建議使用穩定的轉換鍵，例如
`"DP-246:engineering->breakdown:1"`。重複 evidence_id 會 silent exit 0（冪等 no-op），確保同一
retry 不會重複計數。Counter 1→2 transition 會自動 append `inner_skill_halt_bypass` friction；
orchestrator 仍是 transition 寫入的唯一 caller，但不再需要分別呼叫 counter writer 與 friction helper。

### Counter Race-Recovery (DP-246)

當 `auto-pass` 以 `terminal_status=loop_cap_reached` 收尾，但有證據顯示計數器因競爭條件（重複
orchestration session 在沒有 idempotency guard 的情況下寫入同一 transition）被過度累加時，可使用
canonical 外科手術恢復路徑：

```bash
bash scripts/auto-pass-counter-race-recovery.sh \
  --source-id {SOURCE_ID} \
  --prior-ledger /absolute/path/to/prior-ledger.json \
  [--repo /absolute/path/to/repo-root]
```

**此 helper 是 terminal-only**。**禁止在主動 orchestration loop 中呼叫**；否則會繞過 cap
enforcement，導致 runaway retry。

Helper 驗證三條 precondition，任一失敗即 exit 1 + stderr `POLARIS_COUNTER_RECOVERY_PRECONDITION_FAILED`：

| Precondition | 說明 |
|-------------|------|
| (a) | 前 ledger `terminal_status == loop_cap_reached` |
| (b) | `friction_log[]` 含至少一筆 `inner_skill_halt_bypass` / `stage_retry` 條目 |
| (c) | `stage_events` 計算的 actual back-edge 次數 < cap（3） |

成功時：

- 建立新 ledger，`loop_counters` 從 actual back-edge 數重算；舊 `evidence_ids[]` 搬過來作為已認帳（不重複計）。
- `terminal_status` 清為 `null`（讓 orchestrator 可重新 dispatch）。
- `stage_events` 寫入 `COUNTER_RACE_RECOVERY` audit 條目，包含 prior ledger path 與新舊計數。
- 同 source 24h 內只能執行一次（stamp 儲存在 `{source_container}/.polaris/counter-race-recovery-last.json`）。

Recovery 完成後，以新 ledger 路徑繼續 `auto-pass {SOURCE_ID} resume`；orchestrator 會沿用原 ledger
的 snapshot 與 drift_retry，不會重置 loop state。

## Review-Revision Loop (DP-313)

engineering stage 的 completion-gate marker PASS 後，runner 追加一條 review-state branch：
若 work item 有 open PR 且 shared classifier（`pr-state-snapshot.sh` /
`pr-action-classifier.sh`，vocabulary 以 `pr-state-contract.md` 為 authority）回
`needs_code_changes`（actionable review signals），runner emit `ROUTE_BACK_REVISION`：
`next_action=dispatch`、`next_skill=engineering`（revision mode）。

- **Trigger 範圍**：只認 actionable signals，與 `engineering-revision-flow.md` R2 同一組定義
  （unresolved non-outdated root inline comments、reviewer newer follow-up、completed failed
  CI、codecov fail）。`review_required` / `awaiting_re_review` / `wait_ci`（queued / pending
  CI）/ 已 resolved threads 不是 trigger——runner 此時維持既有行為 dispatch verify-AC，輸出與
  現行 byte-parity。
- **`needs_disposition` conversation comments（DP-413）**：classifier 對「approval 已足夠、
  但仍有未 disposition 的實質真人 conversation comment」回 `action_class=needs_disposition`，
  並映射 `readiness_state=needs_code_changes`——因此走與其他 actionable signal 相同的
  `ROUTE_BACK_REVISION`（`next_action=dispatch`、`next_skill=engineering` revision mode），
  不 terminal-halt、不寫 `pause.kind` 也不 `paused_for_user_external_write`。revision agent
  對每則 comment 做 disposition：`reply_only`（回覆澄清、無 code delta）、`code_fix`（改 code
  再 revision）、或 `escalate`（只有 user-only business 決策才回使用者）。已 disposition 的
  comment（`fixed` / `reply_only` / `not_actionable`）不再觸發 needs_disposition；只有 bot
  comment 時 classifier 見到空的 human comment 集合，維持既有 approved-path 輸出。
- **Escalation 分流**：classifier 回 `planning_gap` → `next_skill=breakdown`；spec issue →
  `next_action=refinement_amendment`。不在 revision 內就地擴 scope。
- **Head rebind**：revision dispatch 完成後 orchestrator 以新 head sha 重跑 engineering
  probe；completion-gate marker 由 engineering R5 在新 head 重寫，verify-AC 走既有 stale
  refresh path（不重跑 breakdown）。舊 head 的 marker 不得被當成 current verification。
- **Counter / cap**：每輪 revision dispatch 對 `loop_counters.engineering_revision_rounds`
  +=1（見上方 § Loop Caps）；超 cap=3 → terminal `loop_cap_reached`。
- **fail-closed**：`gh` / PR state 不可得時 review-state 檢查 fail-closed
  （`POLARIS_TOOL_MISSING`），不得 fail-open 假裝沒有 review 而宣告 complete。
- **terminal `complete` 語義不變**：不等 reviewer approval、不 merge（forbidden actions
  不動）。本 loop 只把「已存在的 actionable review feedback」收進 deterministic loop。
- **Source parity**：DP-backed 與 JIRA Epic-backed source 對稱適用，無 DP-only branch。

## No Executable Flow Route-back

engineering stage 跑 behavior contract 時，若 task.md 的
`verification.behavior_contract.applies=true` 卻沒有可執行的 flow（缺 `flow_script`、或
`fixture_policy: static_only` 沒有 runnable script），`scripts/run-behavior-contract.sh` 會
emit evidence-level `status=NOT_COVERED` 的 behavior marker 並以 **exit 2** route-back，而
**不是**靜默當作 covered（見 `behavior-contract.md` § No Executable Flow → NOT_COVERED
Route-back）。

runner 把這視為 stop-at-owning-producer 條件：completion gate 要求 `status=PASS`，因此
`NOT_COVERED` marker 不會讓 engineering stage 判成 PASS。orchestrator **不得**在本地自行
修補（不補寫 flow_script、不改 marker），必須停在 owning producer——回 breakdown 補上可執行
的 flow_script，或回 refinement 重新評估該 task 是否應 `applies`。

## Pause Rules

## Non-Stop Rule

Inner skill `HALT`、final answer 沒有 PASS 字樣、或 session handoff 建議，都不是
auto-pass 的正確停止理由。若 deterministic sidecar 已 PASS（task validators、proof marker、
completion marker、verification marker），orchestrator 必須繼續 dispatch 下一個 owning
skill。只有真正的 context pressure / runtime pressure 可寫 `pause.kind=session_handoff`，
並同時 emit resume artifact 供 `/auto-pass {KEY} resume` 驗證後續跑。

`paused_for_refinement`（non-terminal `pause.kind`）：

- breakdown 判斷需要 refinement。
- verify-AC 回報 spec issue。
- resume 必須有 `pause.inbox_consumed_at` 與 current LOCK evidence。

`paused_for_user_external_write`：

- stage 需要 consent 外 external write。
- verify-AC 回報 `MANUAL_REQUIRED` 或 `BLOCKED_ENV`。
- resume 必須有 `pause.external_write_acknowledged_at`。

## Automatic Pause-Release Sequence

當 runner JSON emit `next_action=resume`（代表 ledger 內有 active `session_handoff` pause，
runner 因此 short-circuit 不算 per-stage verdict）時，orchestrator **必須** 走下列
deterministic chain 釋放 pause，不得用其他方式：

1. **Validate**：`scripts/validate-auto-pass-resume.sh --ledger <ledger> --resume-artifact <artifact> [--source-id <id>]`
   — 對照 ledger pause 驗證 resume artifact（resume prerequisite、source 對齊、artifact
   freshness）。validate fail 時 fail-stop，不得跳過直接清 pause。
2. **Consume**：`scripts/auto-pass-consume-resume.sh --ledger <ledger> --resume-artifact <artifact> [--source-id <id>]`
   — 這是消費 `session_handoff` pause 的 **唯一 sanctioned writer**：清 `pause=null` + 蓋上
   `resumed_at`，byte-preserving 既有 `loop_counters` / `task_snapshot` / `drift_retry`，
   寫入後再以 `scripts/validate-auto-pass-ledger.sh` re-validate ledger 一致性。
3. **Re-probe**：`scripts/auto-pass-runner.sh --stage ...` — pause 已清，runner 不再
   short-circuit 到 `resume`，改回傳該 stage 的真實 per-stage verdict，orchestrator 依此
   verdict 繼續主鏈。

**禁止手動改 ledger 清 pause**：消費 `session_handoff` pause 的唯一 sanctioned writer 是
`scripts/auto-pass-consume-resume.sh`。直接 hand-edit ledger 把 `pause` 改成 null、或補寫
`resumed_at`，都違反 single-writer 契約（會 silently 漏掉 byte-preserve 與 re-validate），
一律禁止。

## Terminal Priority

```text
user_aborted > blocked_by_gate_failure > loop_cap_reached >
paused_for_user_external_write > complete
```

`complete` 只能在 required PR set ready、verification disposition current，且沒有 unresolved
blocker / pause / retry cap 時成立。required PR set 依 § Required PR Set task_shape Carve-out
排除 `task_shape ∈ {audit, confirmation}` 的 task；這類 task 以 completion_gate marker 視為完成，
不計入 required PR set。

## Terminal Complete Sequence

### Runner 端 V task canonical terminal gate（DP-311 T1）

`scripts/auto-pass-runner.sh` 在輸出 `terminal_status=complete` **之前**（fresh verify-AC
PASS path 與 resume-complete rerun path 都經同一個 `map_next_action` hook）執行：

1. **推進**：對每個 required V work item，若其 `ac_verification` frontmatter 為
   `status: PASS` 且 `human_disposition: passed`，呼叫既有 canonical task-level writer
   `scripts/mark-spec-implemented.sh {key} --no-auto-archive`（move → `tasks/pr-release/` +
   status `IMPLEMENTED`）。不新增第二套判定 / writer path（AC-NEG3）。
2. **fail-closed 確認**：重讀 canonical V task file state，確認全部 required V 已達
   canonical terminal contract——位於 `pr-release/` + status `IMPLEMENTED` +
   `ac_verification` PASS（與 `close-parent-spec-if-complete.sh` 同一契約；單看
   ac-verification marker 不算數，AC2）。任一未達 → runner 改輸出
   `terminal_status=blocked_by_gate_failure`，不宣告 complete。
3. **不推進**：`FAIL` / `MANUAL_REQUIRED` / `UNCERTAIN` / `BLOCKED_ENV` 或缺
   `human_disposition=passed` 的 V item 一律不動（AC-NEG1）；`ABANDONED` V 沿用
   close-parent carve-out（留在原位、不阻塞）；T（implementation）task 不在本 gate
   範圍（AC-NEG2）。

此 gate 是 DP-237「runner read-only」契約的唯一 declared exception：runner 只透過既有
canonical writer 推進，selftest（`auto-pass-runner-selftest.sh` AC-NEG2 declared-exception
check）保證該 writer 引用只存在單一 assignment site。Hermetic 覆蓋見
`scripts/selftests/auto-pass-terminal-v-advance-selftest.sh`。

### Closeout chain

terminal complete 後 closeout chain 不需要使用者另戳 archive；complete report 只有在 parent
source 已完成 lifecycle closeout 後才合法。

1. 透過 `scripts/write-producer-owned-artifact.sh --producer-token auto-pass:report` 寫 durable
   auto-pass report。canonical writer 呼叫
   `validate-auto-pass-report.sh --lifecycle-phase prearchive`：除了 parent lifecycle
   postcondition 外，schema、ledger、PR、V evidence 與 follow-up authority checks 全部必須
   PASS；其他錯誤仍 rollback。
2. 對 terminal parent 呼叫 `scripts/mark-spec-implemented.sh {SOURCE_ID} --auto-archive`。
3. **Ledger finalize（DP-311 T2）**：`mark-spec-implemented.sh` 的 parent / bare-DP 分支在翻
   `IMPLEMENTED` **之前**（source 仍 LOCKED）呼叫 `scripts/auto-pass-finalize-ledger.sh`，把
   本次 closeout 的 ledger（`{container}/artifacts/auto-pass/` 最新一份，或 caller 以
   `--ledger` 指定）`terminal_status` 推進成 `complete`。這是 deterministic sanctioned
   writer，不是 LLM prose 步驟（AC-NF1）；fresh-complete 與 paused→resume→complete 共用
   同一 entry。守則：
   - non-complete terminal（`loop_cap_reached` / `blocked_by_gate_failure` / `user_aborted` /
     `paused_for_user_external_write`）與未解除 pause 一律 NOOP，不得改寫成 `complete`
     （AC-NEG4）。
   - 已 `IMPLEMENTED` / archived 的 source 重跑為 idempotent NOOP；不對 archived container
     做 LOCKED-required 寫入，不 migrate frozen archived legacy ledger（AC-NEG5）。
   - task-level mark-spec-implemented 呼叫（推進單一 task，parent 仍 LOCKED）不觸發
     finalize（EC7）。
   - finalize fail-closed（exit 2 + `POLARIS_LEDGER_FINALIZE_*` marker）時 parent 不得翻
     `IMPLEMENTED`。`validate-auto-pass-ledger.sh` 的 LOCKED precondition 維持嚴格，
     不新增 relaxation。
4. `mark-spec-implemented.sh` 標記 parent `IMPLEMENTED` 後呼叫 `archive-spec.sh`。
5. 若 terminal path 來自 framework release closeout，`framework-release-closeout.sh` 透過
   `close-parent-spec-if-complete.sh --archive-terminal-parent` 進入同一 archive chain。
6. archive 後以預設 terminal phase 執行 `scripts/validate-auto-pass-report.sh`。它會對
   `terminal_status=complete` 反查 source parent；
   若仍在 active namespace 且 status 不是 `IMPLEMENTED`，輸出
   `POLARIS_AUTO_PASS_TERMINAL_PARENT_NOT_ARCHIVED` 並 fail-stop。Report summary 不得把這種
   active `LOCKED` parent 降級成 advisory。

### Report / archive gate applicability matrix（DP-417 T5）

上述三步 closeout 具備**固定 enforcement order**：`complete report write`（步驟 1，
canonical writer 做 prearchive validation）→ `archive`（步驟 2，由
`mark-spec-implemented.sh --auto-archive` 這條唯一 canonical writer 執行）→ `report full
validation`（步驟 6，`validate-auto-pass-report.sh` 預設 terminal phase）。
report-validation 反查 parent lifecycle 的行為**編碼**了這個 order：在 archive 之前對 active
parent 跑 report validation 一律 fail-closed，因此 validation 不可能先於 archive 通過。各 cell
的正確 gate 行為（`terminal_status=complete` 專屬；非 complete terminal 不套用本 gate）：

| Report gate × parent 狀態 | Gate 行為 |
|---------------------------|-----------|
| active namespace + status ≠ `IMPLEMENTED`（archive 前 / LOCKED / DISCUSSION） | fail-closed `POLARIS_AUTO_PASS_TERMINAL_PARENT_NOT_ARCHIVED`（order violation / archive-state misjudgment，AC-NEG2） |
| active namespace + status `IMPLEMENTED`（status 已翻、尚未 move） | PASS（gate 認 status，不只認 namespace） |
| archive namespace（continue-after-archive） | PASS（已 archive 的 source 不得被 re-fail） |
| 非 `complete` terminal（如 `blocked_by_gate_failure`）+ active parent | 不套用本 gate（AC-N1 no-false-positive） |

deterministic 覆蓋：`scripts/selftests/report-archive-validation-order-selftest.sh` 以 real
scripts（report validation gate + real `mark-spec-implemented.sh --auto-archive` archive
producer）驅動上述 fixed order 與 matrix 各 cell，不重寫 order 邏輯。

## Recovery State Machine（deterministic recovery / fail-closed cross-check，DP-417 T3）

recovery 狀態的 ledger / report 轉移必須是 **deterministic**（同一輸入 → 同一 next_action /
gate verdict），且 active source 缺 route-back / ledger / delivery-evidence marker 時 report /
complete gate 一律 **fail-closed**（AC-NEG2），不得從 prose 合成 correctness。各狀態的 canonical
enforcer：

| Recovery 狀態 | 判定來源 | Deterministic enforcer |
|---------------|----------|------------------------|
| `blocked_by_gate_failure` | ledger terminal / report terminal | `validate-auto-pass-ledger.sh`（terminal enum）；`validate-auto-pass-report.sh`（terminal ∈ TERMINAL，非 `complete` 且有 issues/blockers 時強制 `follow_up_dp_seed`，缺則 exit 1） |
| `resume`（session_handoff） | ledger `pause.kind=session_handoff` | `validate-auto-pass-ledger.sh`（terminal=null + resume_artifact + next_work_item_id）；`validate-auto-pass-resume.sh`（artifact↔ledger 對齊）；`auto-pass-runner.sh --stage source`（emit `next_action=resume`）；`auto-pass-consume-resume.sh`（唯一 sanctioned writer 清 pause + stamp resumed_at） |
| `continue`（forward / complete-eligible） | ledger terminal=null + pause=null | `validate-auto-pass-ledger.sh`；report terminal cross-check（complete 需 ledger complete 或 complete-eligible，否則 `POLARIS_AUTO_PASS_REPORT_LEDGER_TERMINAL_MISMATCH` exit 2；ledger 不可讀 → `..._LEDGER_UNREADABLE`） |
| `revision`（engineering_revision_rounds） | ledger loop_counters | `validate-auto-pass-ledger.sh`（count>cap 需 terminal `loop_cap_reached`，否則 exit 1） |
| `head-rebind` | report `verification.head_sha` ↔ required T task canonical `deliverable.head_sha`；V verdict ↔ V task `ac_verification.status` | `validate-auto-pass-report.sh`（V/T authority 分工：先驗 parsed task kind / identity，再要求 V `ac_verification.status=PASS` + 至少一筆 canonical T deliverable head 綁定；report row head 不可自我證明；stale head / 非 PASS → `..._VERIFICATION_MARKER_MISMATCH`；無 resolvable task.md / deliverable → `..._VERIFICATION_MARKER_MISSING`） |

AC6（review 後 revision / head-rebind 在宣告 `complete` 前，必須先滿足 PR-visible delivery
evidence publication ownership）由 `validate-auto-pass-report.sh` 的 `required_prs[]` ownership
gate 強制：對每個帶 ownership 欄位（`isDraft` / `publisher` / `engineering_completion_marker` /
`base_freshness` 等）的 row 呼叫唯一 canonical gate `scripts/auto-pass-pr-ownership-gate.sh`。
draft PR → `POLARIS_AUTO_PASS_PR_DRAFT_BLOCKED`；publisher / completion / freshness 未滿足 →
`POLARIS_AUTO_PASS_PR_OWNERSHIP_BLOCKED`（皆 exit 2）。**caller 走 gate 的 `--state-file` 模式**
（gate 的 `--stdin` 模式因 python heredoc 佔用 stdin 而 unreachable，會讓所有 ownership row 誤
判成 `input is not readable JSON`；DP-417 T3 修正此 fail-closed gap，使已發布的合法 owned PR 能
PASS、draft PR 能正確回報 `PR_DRAFT_BLOCKED`）。

DP-417 T6 在同一 `required_prs[]` 迴圈補上 **head-rebind evidence publication freshness**：
凡 row 帶 `revised_head_sha`（review 後 revision / head rebind 後 PR 綁定的新 head），在
`terminal=complete` 時其 PR-visible evidence publication marker 必須 current 於該 revised head——
`evidence_publication_head_sha`（或 nested `evidence_publication.head_sha`）以 canonical
`head_bound()`（不新增第二個 comparator）比對 revised head。stale（綁舊 head）或 missing（revision
改了 head 卻沒重新發佈 evidence）一律 fail-closed `POLARIS_AUTO_PASS_PR_EVIDENCE_PUBLICATION_STALE`
（exit 2），不得 silent PASS；未帶 `revised_head_sha` 的 first-cut delivery row 不受此 gate 影響，
`terminal!=complete`（route back 給 owner）為 AC6 逃生門、不套用此檢查。deterministic 覆蓋：
`scripts/selftests/revision-head-rebind-evidence-publication-ownership-selftest.sh`（AC6 current-head
pass / AC-NEG2 stale + missing fail-closed / route-back not gated / first-cut no-false-positive）。

上述五狀態的 determinism（run-twice 同 verdict）與 AC-NEG2 fail-closed（含 draft PR AC6）由單一
consolidated selftest `scripts/selftests/auto-pass-ledger-report-recovery-state-machine-selftest.sh`
以 real validator 覆蓋（AC-N1），不重寫任何 gate 邏輯。
