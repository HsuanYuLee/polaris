---
title: "Auto-pass Report Contract"
description: "auto-pass terminal report schema、follow-up DP seed threshold、overlap disposition 與 framework-release tail trigger。"
---

# Auto-pass Report Contract

`auto-pass` 每次 terminal 都要寫 durable report，不論結果是 complete、pause 或 blocked。

建議路徑：

```text
{source_container}/artifacts/auto-pass/YYYYMMDD-HHMMSS-report.json
```

## Minimal Shape

```json
{
  "schema_version": 1,
  "source_id": "DP-NNN",
  "terminal_status": "complete",
  "created_at": "2026-05-19T10:30:00+08:00",
  "ledger_path": "/absolute/path/to/ledger.json",
  "required_prs": [
    {"task_id": "DP-NNN-T1", "pr_url": "https://github.com/org/repo/pull/1", "head_sha": "abc"}
  ],
  "verification": {"status": "PASS", "work_item_id": "DP-NNN-V1"},
  "issues": [],
  "blockers": [],
  "manual_items": [],
  "follow_ups": [],
  "overlap_disposition": [
    {"candidate": "converge", "disposition": "keep", "reason": "batch active-work convergence"}
  ],
  "follow_up_dp_seed": null,
  "framework_release_tail": {
    "trigger": "framework-release DP-NNN",
    "allowed": true,
    "reason": "workspace PR ready and verification current"
  }
}
```

## Terminal Status

`terminal_status` 必須是：

- `complete`
- `paused_for_refinement`
- `paused_for_user_external_write`
- `loop_cap_reached`
- `blocked_by_gate_failure`
- `user_aborted`

priority 仍以 ledger / execution flow 為準：

```text
user_aborted > blocked_by_gate_failure > loop_cap_reached >
paused_for_user_external_write > paused_for_refinement > complete
```

## DP Seed Threshold

只有 report 包含下列任一訊號時，才需要 `follow_up_dp_seed`：

- `terminal_status` 不是 `complete`
- `issues[]` 非空
- `blockers[]` 非空
- `manual_items[]` 非空
- `follow_ups[]` 非空
- `overlap_disposition[]` 內有 `follow-up-sunset`

`follow_up_dp_seed` 至少包含：

```json
{
  "path": "docs-manager/src/content/docs/specs/design-plans/DP-NNN-follow-up/index.md",
  "reason": "blocked_by_gate_failure",
  "source_report": "/absolute/path/to/report.json",
  "framework_gap": false
}
```

`framework_gap`（DP-330 T2）是必填 boolean，宣告這個 follow-up seed 是否主張一個 framework
gap：

- `framework_gap: true` → 必須附 `contract_evidence`（至少一筆 workspace-root-bound
  `repo/path:line` 字串，指向實際存在且行號在檔案範圍內的 source）。這把「我主張框架有
  gap」綁定到可機械驗證的證據，writer-side fail-closed。

  ```json
  {
    "path": "docs-manager/src/content/docs/specs/design-plans/DP-NNN-follow-up/index.md",
    "reason": "blocked_by_gate_failure",
    "source_report": "/absolute/path/to/report.json",
    "framework_gap": true,
    "contract_evidence": ["scripts/validate-auto-pass-report.sh:140"]
  }
  ```

- `framework_gap: false` → `contract_evidence` 不要求（非 framework-gap 的一般 follow-up
  seed）。

`framework_gap` 缺漏或非 boolean → fail。`framework_gap: true` 而 `contract_evidence`
缺漏 / 空陣列 / 路徑越界 workspace root / 檔案不存在 / 行號越界 → fail。seed_needed 觸發條件
與 `path` / `reason` / `source_report` 必填不變。

complete 且沒有 issue threshold 時，`follow_up_dp_seed` 必須是 `null`。

## Overlap Disposition

允許值只有：

- `keep`
- `narrow`
- `deprecate-note`
- `follow-up-sunset`

`follow-up-sunset` 只可建立 follow-up DP seed；同一 PR 不得刪除 skill、刪除 routing row 或做
行為性 deprecation。

## Friction Log Summary (DP-214)

`friction_log_summary` 是從 ledger `friction_log[]` 聚合而來的計算欄位。報告 writer 可
選擇是否寫入 snapshot；若寫入，validator 必須與 ledger 聚合結果完全一致，否則 fail。

```json
{
  "friction_log_summary": {
    "total": 3,
    "by_stage": {"breakdown": 1, "engineering": 2},
    "by_kind": {"manual_artifact_patch": 2, "deterministic_gap": 1}
  }
}
```

聚合規則：

- `total`：ledger.friction_log[] 的條目數。
- `by_stage`：以 `stage` 欄位聚合。
- `by_kind`：以 `friction_kind` 欄位聚合。

`friction_log_summary` 不為空時，report 必須在 `follow_ups[]` 或 `follow_up_dp_seed`
標出對應的後續 DP / backlog item；不可只回 `complete` 就結束。

## Framework-release Tail

`auto-pass` report 可以輸出 framework release 下一步 trigger：

```json
{
  "trigger": "framework-release DP-NNN",
  "allowed": true,
  "reason": "workspace PR ready and verification current"
}
```

report 不得把 framework merge、sync-to-polaris、tag 或 GitHub release 記為 auto-pass 已執行。
