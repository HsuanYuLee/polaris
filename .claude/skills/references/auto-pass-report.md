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
  "source_report": "/absolute/path/to/report.json"
}
```

complete 且沒有 issue threshold 時，`follow_up_dp_seed` 必須是 `null`。

## Overlap Disposition

允許值只有：

- `keep`
- `narrow`
- `deprecate-note`
- `follow-up-sunset`

`follow-up-sunset` 只可建立 follow-up DP seed；同一 PR 不得刪除 skill、刪除 routing row 或做
行為性 deprecation。

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
