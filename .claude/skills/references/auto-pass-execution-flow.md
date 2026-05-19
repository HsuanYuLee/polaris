---
title: "Auto-pass Execution Flow"
description: "auto-pass execution loop、DP-201 proof marker probe matrix、pause / retry cap 與 terminal fixed-point。"
---

# Auto-pass Execution Flow

`auto-pass` 的 execution loop 只讀 deterministic filesystem proof、task frontmatter 與
validated ledger。它不讀 inner skill final answer 來判斷 PASS。

## Stage Order

1. source resolver gate：唯一 locked/current DP-backed source。
2. ledger gate：valid source-scoped ledger；pending pause 時 validate resume prerequisite。
3. breakdown stage：dispatch breakdown，PASS 後鎖定最後一次 task snapshot。
4. engineering stage：依 task DAG dispatch engineering，要求 non-draft workspace PR opened / ready。
5. verify-AC stage：要求 V work order verification disposition current。
6. terminal fixed-point：required PR set ready + verification current + no higher-priority terminal state。

## Probe Matrix

| Stage | PASS probe | Blocked / route-back probe | Terminal / next action |
|-------|------------|----------------------------|------------------------|
| breakdown | `.polaris/evidence/task-snapshot/{work_item_id}.json` status PASS | `validation_fail`、`missing_v_task`、`refinement-inbox/` | PASS dispatch engineering；route-back pause refinement；blocked gate failure |
| engineering | `.polaris/evidence/completion-gate/{work_item_id}-{head_sha}.json` status PASS | `blocked_conflict`、`unsupported_mutation` | PASS dispatch verify-AC；blocked gate failure |
| verify-AC | `.polaris/evidence/ac-verification/{work_item_id}-{head_sha}.json` status PASS | `spec_issue`、`MANUAL_REQUIRED`、`BLOCKED_ENV`、`UNCERTAIN`、missing marker | PASS complete；spec issue pause refinement；manual/env pause；unknown blocked |

Probe helper:

```bash
bash scripts/auto-pass-probe.sh \
  --repo /absolute/path/to/main-checkout \
  --stage verify-AC \
  --source-id DP-NNN \
  --work-item-id DP-NNN-V1 \
  --head-sha <head_sha> \
  --ledger /absolute/path/to/ledger.json
```

JSON output fields:

- `schema_version`
- `stage`
- `source_id`
- `work_item_id`
- `status`
- `terminal_status`
- `next_action`
- `evidence_path`
- `reason`

`status=UNKNOWN` 或 missing marker 不得 PASS，terminal 固定為 `blocked_by_gate_failure`。

## Loop Caps

Planning loop counters live in ledger:

- `loop_counters.engineering_to_breakdown`
- `loop_counters.breakdown_to_refinement_inbox`

任一 counter 達 3，terminal `loop_cap_reached`。此 cap 只涵蓋 planning backward transition。

Implementation drift retry 另存在 `drift_retry`，以 V item 為 key。單一 V item 達 3 次仍 FAIL，
terminal `blocked_by_gate_failure`。

## Pause Rules

`paused_for_refinement`：

- breakdown 判斷需要 refinement。
- verify-AC 回報 spec issue。
- resume 必須有 `pause.inbox_consumed_at` 與 current LOCK evidence。

`paused_for_user_external_write`：

- stage 需要 consent 外 external write。
- verify-AC 回報 `MANUAL_REQUIRED` 或 `BLOCKED_ENV`。
- resume 必須有 `pause.external_write_acknowledged_at`。

## Terminal Priority

```text
user_aborted > blocked_by_gate_failure > loop_cap_reached >
paused_for_user_external_write > paused_for_refinement > complete
```

`complete` 只能在 required PR set ready、verification disposition current，且沒有 unresolved
blocker / pause / retry cap 時成立。
