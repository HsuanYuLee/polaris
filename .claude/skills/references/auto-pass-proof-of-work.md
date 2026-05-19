---
title: "Auto-pass Proof-of-Work Artifact Contract"
description: "DP-201 定義的 strict pipeline proof marker schema、producer ownership 與 deterministic validation contract。"
---

## Proof Marker Contract

本 reference 是 DP-201 的 proof-of-work marker contract。它讓 DP-198 auto-pass 只能讀取
durable filesystem evidence 或 canonical task frontmatter，不依賴 LLM final answer、raw prose、
JIRA-only state 或 `/tmp` only artifact。

## Core Rules

- Durable marker root 是 `.polaris/evidence/`；`/tmp` 只能作 runtime cache。
- Owning skill 寫自己的 marker：`breakdown`、`engineering`、`verify-AC` 各自負責。
- `auto-pass` 只讀 marker，不是 marker writer。
- 每個 JSON marker 必須有 `schema_version`、`marker_kind`、`writer`、`owning_skill`、
  `source_id`、`work_item_id`、`status`、`freshness`。
- `freshness` 不能只有 timestamp；PR 類 marker 必須能對齊 `head_sha`，verification 類 marker
  必須能對齊 V task 或 source artifact。

## Marker Kinds

| Marker kind | Owning skill | Durable path |
|-------------|--------------|--------------|
| `task_snapshot` | breakdown | `.polaris/evidence/task-snapshot/{work_item_id}.json` |
| `validation_fail` | breakdown | `.polaris/evidence/validation-fail/{work_item_id}.json` |
| `missing_v_task` | breakdown | `.polaris/evidence/missing-v-task/{work_item_id}.json` |
| `route_back_refinement_inbox` | breakdown | canonical signal: `refinement-inbox/` folder presence |
| `pr_freshness` | engineering | task frontmatter `deliverable.head_sha` plus PR `headRefOid` |
| `completion_gate` | engineering | `.polaris/evidence/completion-gate/{work_item_id}-{head_sha}.json` |
| `blocked_conflict` | engineering | `.polaris/evidence/blocked-conflict/{work_item_id}-{head_sha}.json` |
| `unsupported_mutation` | engineering | `.polaris/evidence/unsupported-mutation/{work_item_id}-{head_sha}.json` |
| `ci_local` | engineering | `.polaris/evidence/ci-local/{work_item_id}-{head_sha}.json` |
| `verify` | engineering | `.polaris/evidence/verify/polaris-verified-{work_item_id}-{head_sha}.json` |
| `ac_verification` | verify-AC | `.polaris/evidence/ac-verification/{work_item_id}-{head_sha}.json` |
| `spec_issue` | verify-AC | `.polaris/evidence/ac-verification/spec-issue-{work_item_id}-{head_sha}.json` |
| `drift_retry` | verify-AC | `.polaris/evidence/ac-verification/drift-retry-{work_item_id}-{head_sha}.json` |
| `drift_counter` | verify-AC | `.polaris/evidence/ac-verification/drift-counter-{work_item_id}.json` |
| `audit_closure` | verify-AC | `.polaris/evidence/auto-pass/audit/audit-closure-DP-201-{head_sha}.json` |
| `dp198_handoff` | verify-AC | `.polaris/evidence/ac-verification/DP-201-V1-{head_sha}.json` |

`route_back_refinement_inbox` 與 `pr_freshness` 是 canonicalized existing signal，不要求新增
duplicate JSON marker。若 consumer 需要 JSON proof，可把 existing signal 摘要放進
`completion_gate` 或 `audit_closure` marker。

## JSON Schema

最低 JSON schema：

```json
{
  "schema_version": 1,
  "marker_kind": "completion_gate",
  "writer": "engineering",
  "owning_skill": "engineering",
  "source_id": "DP-201",
  "work_item_id": "DP-201-T1",
  "status": "PASS",
  "freshness": {
    "head_sha": "abc1234",
    "source_artifact": "docs-manager/src/content/docs/specs/design-plans/DP-201-.../tasks/T1/index.md"
  }
}
```

Valid `status` values are `PASS`, `FAIL`, `BLOCKED`, `ROUTE_BACK`, `MANUAL_REQUIRED`,
`UNCERTAIN`, `BLOCKED_ENV`, and `IN_PROGRESS`.

## Producer SoT

`scripts/lib/evidence-producers.json` 是 producer-to-path canonical SoT。Reference docs 可
呈現摘要，但不可用 markdown table 取代 JSON mapping。

```json
{
  "schema_version": 1,
  "producers": [
    {"owning_skill": "breakdown", "writer": "breakdown", "marker_kinds": ["task_snapshot", "validation_fail", "missing_v_task"], "path_globs": [".polaris/evidence/task-snapshot/*.json", ".polaris/evidence/validation-fail/*.json", ".polaris/evidence/missing-v-task/*.json"]},
    {"owning_skill": "engineering", "writer": "engineering", "marker_kinds": ["pr_freshness", "completion_gate", "blocked_conflict", "unsupported_mutation", "ci_local"], "path_globs": [".polaris/evidence/completion-gate/*.json", ".polaris/evidence/blocked-conflict/*.json", ".polaris/evidence/unsupported-mutation/*.json", ".polaris/evidence/ci-local/*.json"]},
    {"owning_skill": "engineering", "writer": "run-verify-command.sh", "marker_kinds": ["verify"], "path_globs": [".polaris/evidence/verify/*.json"]},
    {"owning_skill": "verify-AC", "writer": "verify-AC", "marker_kinds": ["ac_verification", "spec_issue", "drift_retry", "drift_counter", "audit_closure", "dp198_handoff"], "path_globs": [".polaris/evidence/ac-verification/*.json", ".polaris/evidence/auto-pass/audit/*.json"]}
  ]
}
```

## Audit Closure

`audit_closure` marker 必須列出 DP-198 contract gap audit 的 12 個 PARTIAL / MISSING marker
disposition rows。每列至少包含：

- `audit_marker`
- `disposition`: `implemented`、`canonicalized_existing` 或 `blocked_follow_up`
- `marker_kind`
- `evidence_path` 或 canonical signal description

## DP-198 Handoff

`dp198_handoff` marker 必須包含：

- `status: PASS`
- `dp_198_t3_unblocked: true`
- `evidence_paths[]`
- `audit_closure_summary`
- `freshness.head_sha`
- `freshness.source_artifact`

DP-198 T3 只能在此 marker current 且 validator PASS 後接線 probe matrix。
