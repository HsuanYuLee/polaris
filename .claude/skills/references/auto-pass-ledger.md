---
title: "Auto-pass Ledger Contract"
description: "auto-pass source-scoped ledger schema、consent model、terminal enum 與 resume 欄位。"
---

# Auto-pass Ledger Contract

ledger 是 `auto-pass` 的 source-scoped durable state。它記錄本輪 source、consent、stage
events、task snapshot、loop counters、drift retry counters、pause state 與 terminal state。

ledger 必須放在主 checkout 的 DP source container 底下，使用絕對路徑傳給下游：

```text
{source_container}/artifacts/auto-pass/YYYYMMDD-HHMMSS-ledger.json
```

## Minimal Shape

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

`source.id` 使用 canonical `{PREFIX}-NNN` work item key。DP-backed source 的
`source.type` 是 `dp`；JIRA-backed Epic / Bug source 後續統一用 `jira` / `bug`。
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

## Terminal Status Enum

`terminal_status` 可在進行中 ledger 為 `null`。一旦填入，值只能是：

- `complete`
- `paused_for_refinement`
- `paused_for_user_external_write`
- `loop_cap_reached`
- `blocked_by_gate_failure`
- `user_aborted`

多個 terminal condition 同時存在時，priority 固定為：

```text
user_aborted > blocked_by_gate_failure > loop_cap_reached >
paused_for_user_external_write > paused_for_refinement > complete
```

## Resume Fields

`paused_for_refinement` 的 `pause` object 至少需要：

- `kind: "paused_for_refinement"`
- `reason`
- `created_at`
- `inbox_path`
- resume 時追加 `inbox_consumed_at`

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
| breakdown | `refinement-inbox/` presence | `ROUTE_BACK` / `paused_for_refinement` |
| engineering | `completion_gate` PASS + PR freshness | `PASS`，dispatch verify-AC |
| engineering | `blocked_conflict` / `unsupported_mutation` | `BLOCKED` / `blocked_by_gate_failure` |
| verify-AC | `ac_verification` PASS | `PASS` / `complete` when PR set ready |
| verify-AC | `spec_issue` | `ROUTE_BACK` / `paused_for_refinement` |
| verify-AC | `MANUAL_REQUIRED` / `BLOCKED_ENV` | `paused_for_user_external_write` |
| verify-AC | `UNCERTAIN` / missing marker / unknown marker | `blocked_by_gate_failure` |

## Validator

使用：

```bash
scripts/validate-auto-pass-ledger.sh /absolute/path/to/ledger.json \
  --source-container /absolute/path/to/DP-NNN-topic \
  --source-id DP-NNN
```

breakdown 在寫 task 前若消費 auto-pass ledger consent，必須加上 write timestamp：

```bash
scripts/validate-auto-pass-ledger.sh "$AUTO_PASS_LEDGER_PATH" \
  --source-container /absolute/path/to/DP-NNN-topic \
  --source-id DP-NNN \
  --task-write-at 2026-05-19T10:05:00+08:00
```

validator fail 時，下游 skill 不得寫 task.md 或宣稱 consent 已取得。

session handoff resume gate：

```bash
scripts/validate-auto-pass-resume.sh \
  --ledger /absolute/path/to/ledger.json \
  --resume-artifact /absolute/path/to/session-handoff.json \
  --source-id DP-NNN
```
