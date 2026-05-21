# Refinement Return Inbox Contract

`breakdown` 是 execution-side escalation evidence 與 `refinement` 之間的轉譯層；
`refinement` 不得直接讀取 engineering escalation sidecar。

## Purpose

當 `breakdown` 判斷 scope escalation 無法透過 task-md 修正、新 work order、等待或 baseline
approval 解決時，就要寫一份 refinement-facing inbox record。record 內容是 planner 決策
與需要重新打開的 architecture / spec 問題，**不包含** raw gate output。

這條 boundary 讓 ownership 保持乾淨：

| Producer | Artifact | Consumer |
|----------|----------|----------|
| `engineering` | `escalations/T{n}-{count}.md` raw sidecar | 僅 `breakdown` |
| `breakdown` | `refinement-inbox/{id}.md` decision record | 僅 `refinement` |
| `refinement` | `refinement.md` + `refinement.json` | `breakdown` |

writer-side sidecar schema 與 JSON / Markdown 責任由 `engineering-scope-escalation.md`
擁有；本檔案只負責 refinement-facing inbox reader / decision record 契約。

## Location

JIRA-backed specs:

```text
{company_specs_dir}/{EPIC}/refinement-inbox/{TASK_ID}-{COUNT}-{timestamp}.md
```

Example:

```text
docs-manager/src/content/docs/specs/companies/exampleco/EPIC-478/refinement-inbox/T3a-2-20260429T093000Z.md
```

Ticketless / DP specs:

```text
{workspace_root}/docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/refinement-inbox/{TASK_ID}-{COUNT}-{timestamp}.md
```

## Schema

```markdown
---
skill: breakdown
target_skill: refinement
source: scope-escalation
route: refinement
epic: EPIC-478             # JIRA Epic key, or DP-NNN for ticketless / DP-backed work
source_task: T3a
source_ticket: TASK-3711
source_sidecar: docs-manager/src/content/docs/specs/companies/exampleco/EPIC-478/escalations/T3a-2.md
escalation_count: 2
created_at: 2026-04-29T09:30:00Z
consumed: false
---

## Decision

re-classified to refinement: the failed gate cannot be closed by task.md
repair because the selected technical approach / AC boundary must be re-decided.

## Refinement Context

- Gate summary: ci-local type baseline remains over threshold after approved
  task-level scope fixes.
- Current planning gap: AC does not define whether vendor chunk budget is a
  hard requirement or diagnostic target.
- Breakdown disposition: stop task-md loop; reopen refinement.

## Decisions Needed

1. Decide whether the AC budget remains mandatory.
2. Decide whether the current technical approach should change.
3. Decide which downstream tasks must be regenerated after the decision.

## Amendment Consumption (DP-212)

當 inbox 被 `/auto-pass` driven amendment 消費後，refinement 寫回下列欄位以標記
amendment 來源與通過 / 拒絕狀態。`source_sidecar` 維持 audit-only，不被 amendment 修改。

```yaml
consumed: true
consumed_at: 2026-05-21T10:30:00+08:00
consumed_by_amendment:
  amender: auto-pass
  amendment_commit_sha: abc1234
  amendment_round: 1
rejected_by_scope_guard: false        # true 表示 amendment 命中 LOCKED scope guard
scope_violation_detail: null          # 若 rejected_by_scope_guard=true，記錄違反哪些 section
```

`amendment_round` 對應 ledger `loop_counters.breakdown_to_refinement_inbox` 當下值；counter
cap=3 後不再 amendment，由 auto-pass orchestrator 升 terminal `loop_cap_reached`。違反
LOCKED scope（Goal / Background / Decisions / Scope / AC）時，
`scripts/validate-refinement-locked-scope.sh` exit 2，refinement 不得 silent commit；
inbox 寫 `rejected_by_scope_guard=true` + `scope_violation_detail`，auto-pass 升
terminal `blocked_by_gate_failure` 並產 follow-up DP seed。

## Source Audit

- Source sidecar path is kept for audit only.
- Refinement must not open `source_sidecar`; ask breakdown for a revised inbox
  record if the context is insufficient.
```

## Hard Rules

- `refinement` reads `refinement-inbox/*.md`, never
  `escalations/T{n}-{count}.md`.
- 直接把 sidecar path 丟給 `refinement` 屬於 routing 錯誤，必須先 route 到
  `breakdown` scope-escalation intake。
- `source_sidecar` is an audit pointer only. It is not a permission for
  `refinement` to read raw evidence.
- The inbox body must not include `## Raw Evidence` or full command logs.
  `breakdown` should summarize gate facts into planning language.
- `breakdown` may mark the source sidecar `processed: true` only after the
  inbox record is written and passes validation.
- `refinement` 只有在更新完 `refinement.md` / `refinement.json`，或明確拒絕該決策並要求
  `breakdown` 重寫 inbox record 之後，才可以把 `consumed: true` 寫入。

## Validator

```bash
scripts/validate-refinement-inbox-record.sh \
  {company_specs_dir}/{EPIC}/refinement-inbox/{record}.md
```

The validator blocks:

- producer other than `skill: breakdown`
- target other than `target_skill: refinement`
- `route` other than `refinement`
- missing source id in `epic`（JIRA Epic key or DP-NNN）
- missing required sections
- `## Raw Evidence` sections
- records over the 8 KB body cap
