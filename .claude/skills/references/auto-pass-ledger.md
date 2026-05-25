---
title: "Auto-pass Ledger Contract"
description: "auto-pass source-scoped ledger schema、consent model、terminal enum 與 resume 欄位。"
---

# Auto-pass Ledger Contract

ledger 是 `auto-pass` 的 source-scoped durable state。它記錄本輪 source、consent、stage
events、task snapshot、loop counters、drift retry counters、pause state 與 terminal state。

ledger 必須放在主 checkout 的 source container 底下（DP-backed 或 JIRA Epic-backed），
使用絕對路徑傳給下游：

```text
{source_container}/artifacts/auto-pass/YYYYMMDD-HHMMSS-ledger.json
```

DP-backed source 的 container 為 `design-plans/DP-NNN-*/`；JIRA Epic-backed source 為
`companies/{company}/{EPIC}/`。兩種 container 共用同一條 ledger writer path，受
`scripts/lib/evidence-producers.json` parity 保護。

## Minimal Shape (DP-backed)

```json
{
  "schema_version": "1",
  "source": {
    "type": "dp",
    "id": "DP-NNN",
    "container": "/abs/path/docs-manager/src/content/docs/specs/design-plans/DP-NNN-topic",
    "refinement_hash": "sha256:..."
  },
  "started_at": "2026-05-19T10:00:00+08:00",
  "resumed_at": null,
  "terminal_status": null,
  "consent_policy": {
    "auto_reestimate": true,
    "auto_resplit": true,
    "auto_task_repair": true
  },
  "consent_excludes": [
    "base_branch_force_push",
    "force_push_without_lease",
    "history_rewrite",
    "merge",
    "release",
    "deploy",
    "production_write",
    "jira_child_write",
    "jira_comment_write",
    "jira_worklog_write",
    "task_scope_outside_mutation"
  ],
  "task_snapshot": [],
  "stage_events": [
    {
      "stage": "breakdown",
      "status": "PASS",
      "work_item_id": "DP-NNN-T1",
      "evidence_path": ".polaris/evidence/task-snapshot/DP-NNN.json",
      "ts": "2026-05-19T10:01:00+08:00"
    }
  ],
  "loop_counters": {
    "engineering_to_breakdown": 0,
    "breakdown_to_refinement_inbox": 0
  },
  "drift_retry": {},
  "pre_dispatch_stash": null,
  "post_dispatch_restore": null,
  "pause": null
}
```

## Minimal Shape (JIRA Epic-backed)

```json
{
  "schema_version": "1",
  "source": {
    "type": "jira",
    "id": "GT-NNN",
    "container": "/abs/path/docs-manager/src/content/docs/specs/companies/exampleco/GT-NNN",
    "refinement_hash": "sha256:..."
  },
  "started_at": "2026-05-22T10:00:00+08:00",
  "resumed_at": null,
  "terminal_status": null,
  "consent_policy": {
    "auto_reestimate": true,
    "auto_resplit": true,
    "auto_task_repair": true,
    "jira_status_sync": true
  },
  "consent_excludes": [
    "base_branch_force_push",
    "force_push_without_lease",
    "history_rewrite",
    "merge",
    "release",
    "deploy",
    "production_write",
    "jira_child_write",
    "jira_comment_write",
    "jira_worklog_write",
    "task_scope_outside_mutation"
  ],
  "task_snapshot": [],
  "stage_events": [],
  "loop_counters": {
    "engineering_to_breakdown": 0,
    "breakdown_to_refinement_inbox": 0
  },
  "drift_retry": {},
  "pre_dispatch_stash": null,
  "post_dispatch_restore": null,
  "pause": null
}
```

`source.id` 使用 canonical `{PREFIX}-NNN` work item key。DP-backed source 的
`source.type` 是 `dp`；JIRA Epic-backed source 用 `jira`（Bug source 後續用 `bug`）。
`source.refinement_hash` 是 `refinement.md` 與 `refinement.json` bytes 的 sha256 digest，
格式固定為 `sha256:<hex>`。當任一 refinement artifact 改變，既有 ledger 會被判定 stale，
必須先回 owning skill 重新確認 source state。

## Consent Contract

`consent_policy` 三個欄位都必須是 `true`：

- `auto_reestimate`
- `auto_resplit`
- `auto_task_repair`

`consent_excludes` 必須與 minimal shape 完全一致，不可省略任何值。這些 action 一律不在
auto-pass v1 consent 內：

- `base_branch_force_push`
- `force_push_without_lease`
- `history_rewrite`
- `merge`
- `release`
- `deploy`
- `production_write`
- `jira_child_write`
- `jira_comment_write`
- `jira_worklog_write`
- `task_scope_outside_mutation`

## JIRA Status Consent

JIRA Epic-backed source 額外帶 `consent_policy.jira_status_sync` boolean，代表使用者同意
`auto-pass` 在 stage transition 時同步 JIRA Epic 與子單 status（例：`In Development` /
`子任務開發完畢` / `完成`）。schema：

- `consent_policy.jira_status_sync` (boolean, required for `source.type=jira`)：`true` 才能寫
  JIRA transition。DP-backed source 此欄位省略或設為 `false`，validator 不會強制要求。
- session-scoped marker（同 session 不重複 prompt）：

  ```text
  .polaris/runtime/auto-pass-jira-consent-{session_id}-{JIRA_KEY}
  ```

  marker payload：

  ```json
  {
    "schema_version": "1",
    "source_id": "GT-NNN",
    "session_id": "<runtime session id>",
    "granted_at": "2026-05-22T10:00:00+08:00"
  }
  ```

- session_id 缺失時用 short-TTL fallback（30 分鐘 mtime check），marker 命名為
  `.polaris/runtime/auto-pass-jira-consent-fallback-{JIRA_KEY}`。

行為：

- 第一次 dispatch 時若 marker 不存在 → orchestrator prompt 使用者；同意後寫 marker +
  `consent_policy.jira_status_sync=true`，否決則 terminal `user_aborted`。
- 同 session 第 N 次 dispatch（marker 存在且未過期）→ 不重 prompt，直接沿用 ledger 內
  consent。
- ledger validator 在 `source.type=jira` 時要求 `consent_policy.jira_status_sync` 是 boolean；
  缺欄位視為 schema violation。
- DP-backed source 不寫此欄位、不建立 marker，因為 DP container 沒有外部 JIRA status surface。

## Terminal Status Enum

`terminal_status` 可在進行中 ledger 為 `null`。一旦填入，值只能是：

- `complete`
- `paused_for_user_external_write`
- `loop_cap_reached`
- `blocked_by_gate_failure`
- `user_aborted`

> **DP-212 migration**：`paused_for_refinement` 已從 terminal enum 移除，改為
> non-terminal `pause.kind`。Legacy ledger 若仍帶 `terminal_status=paused_for_refinement`，
> validator 會 fail 並指向 `PAUSED_FOR_REFINEMENT_LEGACY_TERMINAL`，請依現況改為非 terminal
> pause 或以 current terminal status 收尾，不嘗試 silent upgrade。

多個 terminal condition 同時存在時，priority 固定為：

```text
user_aborted > blocked_by_gate_failure > loop_cap_reached >
paused_for_user_external_write > complete
```

## Resume Fields

`paused_for_refinement` 是 **non-terminal** pause (DP-212)：refinement-inbox 出現後，
auto-pass 在主鏈內自動 dispatch `refinement` 進入 amendment mode，消費 inbox 後 loop
回 breakdown。`terminal_status` 必須保持 `null`，由 `loop_counters.breakdown_to_refinement_inbox`
+ counter cap=3 決定是否升為 terminal `loop_cap_reached`。

`pause` object 至少需要：

- `kind: "paused_for_refinement"`
- `reason`
- `created_at`
- `inbox_path`
- amendment 完成後追加 `inbox_consumed_at`、`amendment_commit_sha`、`amendment_round`

`paused_for_user_external_write` 的 `pause` object 至少需要：

- `kind: "paused_for_user_external_write"`
- `reason`
- `created_at`
- resume 時追加 `external_write_acknowledged_at`

`session_handoff` 是 non-terminal pause，只能在 context pressure / runtime pressure 使本
session 無法繼續但沒有 user decision blocker 時使用。ledger 必須保持
`terminal_status: null`，且 `pause` object 至少需要：

- `kind: "session_handoff"`
- `reason`
- `created_at`
- `resume_artifact`
- `next_work_item_id`

resume artifact 由 `scripts/validate-auto-pass-resume.sh` 驗證，必須包含 matching
`source_id`、`ledger_path`、`pause_kind: "session_handoff"`、`next_work_item_id`、
`resume_command`、`summary` 與 `created_at`。

resume 必須沿用原 ledger 的 `loop_counters`、`task_snapshot` 與 `drift_retry`，不得建立新
ledger 來重置 counter。

## Friction Log (DP-214)

`friction_log[]` 是 append-only array，紀錄本輪 `/auto-pass` 流程（含
`framework-release` tail）的繞道、手動補位、deterministic gap。它是 post-task
reflection 與 follow-up DP refinement 的權威 signal source；只能透過
`scripts/append-auto-pass-friction.sh` 寫入，不得手改。

本節定義 ledger schema；emit-side contract（stage / kind enum、writer path、
deterministic trigger map、release-tail capture）以
`.claude/skills/references/friction-capture-contract.md` 為 canonical reference。

每筆 entry 至少包含：

```json
{
  "ts": "2026-05-21T11:00:00+08:00",
  "stage": "engineering",
  "friction_kind": "manual_artifact_patch",
  "summary": "engineering 階段 V-task 缺 implementation_tasks 欄位，手動補欄位後 validator 才 PASS"
}
```

- `ts`：ISO8601。
- `stage`：`source` / `breakdown` / `engineering` / `verify-AC` / `framework-release` /
  `post-task` 之一。
- `friction_kind`：enum
  - `inner_skill_halt_bypass`：inner skill HALT 但 deterministic marker 已 PASS，
    orchestrator 必須繼續 dispatch。
  - `manual_artifact_patch`：手動修補 artifact 才能 PASS gate。
  - `deterministic_gap`：缺 deterministic gate / validator / helper，目前靠人類判斷。
  - `env_bypass`：必須 set 環境變數才能跑通流程。
  - `validator_contract_conflict`：validator 與 contract / hook 出現邏輯衝突。
  - `missing_helper_script`：缺 helper script 必須手寫指令補位。
  - `language_drift_repair`：產出語言違反 workspace language policy，需手動回拉。
  - `other`：上述以外的繞道；summary 必須具體說明。
- `summary`：zh-TW（或 workspace language）短語句，soft limit 280 chars；
  validator 不會截斷，只會印 stderr WARNING。

寫入請呼叫：

```bash
scripts/append-auto-pass-friction.sh /absolute/path/to/ledger.json \
  --stage engineering \
  --kind manual_artifact_patch \
  --summary "..."
```

helper 保證 atomic write、enum 驗證與 soft-limit warning；validator 在
ledger validation 中會 surface 過長 summary 的 WARNING，但不變更 exit code。

## Dispatch Stash Fields

`engineering-branch-setup.sh --auto-stash` 若在 dispatch 前暫存 main checkout unrelated dirty
files，必須寫入 `pre_dispatch_stash` object，至少包含 `stash_ref`、`work_item_id`、
`created_at`。後續 restore 成功後寫入 `post_dispatch_restore` object。Allowed Files 內的
overlap dirty file 不得 auto-stash，必須 fail-stop。

## Stage Events And Snapshots

`stage_events[]` 是 append-only event log。每筆 event 至少包含：

- `stage`: `breakdown` / `engineering` / `verify-AC`
- `status`: DP-201 proof marker status 或 probe status
- `work_item_id`
- `evidence_path` 或 `reason`
- `ts`

`task_snapshot[]` 只能在 breakdown validators 全部 PASS 且 `task_snapshot` marker 可判讀後更新。
auto-pass ledger 內的 snapshot 是 cached view；breakdown marker 仍是 owning source。

## Probe Mapping

`scripts/auto-pass-probe.sh` 將 DP-201 proof marker 映射到 terminal state：

| Stage | Marker / signal | Auto-pass status |
|-------|-----------------|------------------|
| breakdown | `task_snapshot` PASS | `PASS`，dispatch engineering |
| breakdown | `validation_fail` / `missing_v_task` | `BLOCKED` / `blocked_by_gate_failure` |
| breakdown | `refinement-inbox/` presence | `ROUTE_BACK_AMEND` / non-terminal `pause.kind=paused_for_refinement` (DP-212 amendment loop) |
| engineering | `completion_gate` PASS + PR freshness | `PASS`，dispatch verify-AC |
| engineering | `blocked_conflict` / `unsupported_mutation` | `BLOCKED` / `blocked_by_gate_failure` |
| verify-AC | `ac_verification` PASS | `PASS` / `complete` when PR set ready |
| verify-AC | `spec_issue` | `ROUTE_BACK_AMEND` / non-terminal `pause.kind=paused_for_refinement` (DP-212 amendment loop) |
| verify-AC | `MANUAL_REQUIRED` / `BLOCKED_ENV` | `paused_for_user_external_write` |
| verify-AC | `UNCERTAIN` / missing marker / unknown marker | `blocked_by_gate_failure` |

## Validator

使用：

```bash
scripts/validate-auto-pass-ledger.sh /absolute/path/to/ledger.json \
  --source-container /absolute/path/to/{source_container} \
  --source-id {SOURCE_ID}
```

`{SOURCE_ID}` 可為 `DP-NNN` 或 JIRA Epic key；`{source_container}` 對應 DP-backed
`design-plans/DP-NNN-*/` 或 JIRA Epic-backed `companies/{company}/{EPIC}/`。

breakdown 在寫 task 前若消費 auto-pass ledger consent，必須加上 write timestamp：

```bash
scripts/validate-auto-pass-ledger.sh "$AUTO_PASS_LEDGER_PATH" \
  --source-container /absolute/path/to/{source_container} \
  --source-id {SOURCE_ID} \
  --task-write-at 2026-05-22T10:05:00+08:00
```

validator fail 時，下游 skill 不得寫 task.md 或宣稱 consent 已取得。

session handoff resume gate：

```bash
scripts/validate-auto-pass-resume.sh \
  --ledger /absolute/path/to/ledger.json \
  --resume-artifact /absolute/path/to/session-handoff.json \
  --source-id {SOURCE_ID}
```
