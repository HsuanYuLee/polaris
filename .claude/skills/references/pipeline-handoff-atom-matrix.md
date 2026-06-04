---
title: "Pipeline Handoff Atom Matrix"
description: "refinement -> breakdown -> engineering -> verify-AC handoff atom ownership：每個 atom 的 canonical authority、derived surfaces、consumers、validator 與 drift policy。只做 ownership mapping，不複製欄位 schema。"
---

# Pipeline Handoff Atom Matrix

本檔是 `refinement -> breakdown -> engineering -> verify-AC` pipeline 中每個跨 skill atom 的
**ownership mapping single source of truth**。每個 atom 回答：誰是 canonical writer、誰可
讀作為 authority、哪些 surface 只是 derived copy、哪個 validator / selftest 守住 drift。

> Scope：本檔只列 ownership / consumer / drift policy。**完整欄位 schema** 仍由 canonical
> schema reference 持有（`refinement-artifact.md`、`task-md-schema.md` 與其 task / verification
> 子檔、`auto-pass-ledger.md`、`auto-pass-proof-of-work.md`）。本檔禁止複製完整欄位表；只允許
> 點名欄位 ID 並指回 canonical schema。

## 使用方式

- Skill / reference / script 修改任何 cross-skill atom 前，先在這張表確認 canonical
  writer 與允許的 consumer。
- 若一個 atom 出現新 writer / 新 consumer，先更新本表 + 對應 selftest，再改 code。
- `drift_policy` 是 selftest / validator 對 drift 的處置；不是 prose 提醒。
- Atom 命名規則：`snake_case` 識別 ID，加上反引號（如 \`work_item_id\`），方便 selftest grep。

## Pipeline Atom Ownership

| atom | owner | canonical_source | derived_surfaces | allowed_consumers | validator_or_selftest | llm_role | drift_policy |
|------|-------|------------------|------------------|-------------------|-----------------------|----------|--------------|
| `refinement_artifact` | refinement | `refinement.json`（schema 詳見 `refinement-artifact.md`） | `refinement.md` derived view（`render-refinement-md.sh`） | breakdown（work order derivation）、verify-AC（AC method/detail authority） | `scripts/validate-refinement-json.sh`、`scripts/validate-refinement-artifact-parity.sh` | refinement 產出時做 authoring；下游 skill 不得用 LLM 自行從 prose 補欄位 | `fail_stop_on_missing_field`；derived view 與 JSON drift → render script 重跑，不允許手寫 |
| `t_task_work_order` | breakdown | `tasks/T{n}/index.md`（schema 詳見 `task-md-schema.md` + task subref） | task.md display body、PR description | engineering（唯一施工輸入）、completion gate、scope boundary gate | `scripts/validate-task-md.sh`、`scripts/validate-task-md-deps.sh`、`scripts/validate-breakdown-ready.sh`、`scripts/skill-workflow-boundary-gate.sh` | engineering 只依 task.md scope 施工；不得讀 `refinement.json` 補 scope authority | `fail_stop_on_planner_field_mutation_by_engineering`；planner-owned field 由 scope escalation 改，不就地 patch |
| `v_task_envelope` | breakdown | `tasks/V{n}/index.md`（schema 詳見 `task-md-schema-verification.md`） | V*.md AC summary block | verify-AC（execution envelope / lifecycle）、engineering（verification handoff link） | `scripts/validate-task-md.sh`（V branch）、`scripts/selftests/verify-AC-deterministic-consumption-selftest.sh` | verify-AC 以 `refinement.json.acceptance_criteria[].verification` 為 method/detail authority；V*.md 是 envelope，不是第二份 AC source | `fail_stop_on_v_text_overriding_refinement_method`；drift → 以 refinement.json 為準，並 advisory log |
| `lifecycle_marker` | engineering（除 verify marker 外） | `.polaris/evidence/{producer}/{work_item_id}-{head_sha}.json`（schema 詳見 `auto-pass-proof-of-work.md`） | final answer status、JIRA comment、PR body summary | auto-pass runner / probe、closeout chain、framework-release tail | `scripts/lib/evidence-producers.json`、`.claude/hooks/no-direct-evidence-write.sh`、`scripts/validate-specs-bound-write-contract.sh` | LLM 不得用 prose 補 PASS / terminal；必須讀 durable marker | `fail_stop_on_missing_marker`；prose-only PASS → blocked_by_gate_failure |
| `orchestration_signal` | auto-pass runner | `scripts/auto-pass-runner.sh` JSON（schema 詳見 `auto-pass-execution-flow.md`） | orchestrator user-facing summary | auto-pass orchestrator（唯一 next-action authority）、resume validator | `scripts/selftests/auto-pass-runner-selftest.sh`、`scripts/selftests/auto-pass-runner-probe-parity-selftest.sh` | orchestrator 不讀 inner skill 自然語言 final answer 補判斷 | `fail_stop_on_runner_json_missing_field`；runner schema 變更 → 同步 probe + selftest |
| `work_item_id` | breakdown | `task.md` canonical identity / `refinement.json.tasks[].id` | task DAG node label、auto-pass ledger task_id | task DAG、auto-pass ledger、task-local markers | `scripts/parse-task-md.sh`（canonical identity）、`scripts/selftests/auto-pass-probe-selftest.sh` | LLM 不得把 `work_item_id` 當外部 ticket key | `fail_stop_on_id_leak_into_product_pr_identity`（AC-NEG5） |
| `jira_key` | refinement / breakdown（依 source type） | `task.md` canonical `JIRA key` cell / `refinement.json.source.jira_key` | JIRA comment 連結、external link metadata | JIRA transition、external links、PR JIRA-link evidence | `scripts/validate-task-md.sh`（identity block）、JIRA transition gates | LLM write-only；不讀 JIRA description / status / comment 補施工指令 | `fail_stop_on_missing_or_mismatched_jira_key`（Bug source 必填） |
| `delivery_ticket_key` | parser-derived alias | `scripts/parse-task-md.sh` derivation（Bug source = `jira_key`；DP-backed = `work_item_id`） | product branch prefix、Developer PR title、PR reviewer-visible metadata | `scripts/resolve-task-branch.sh`、`scripts/gates/gate-pr-title.sh`、`scripts/polaris-pr-create.sh` | `scripts/selftests/pipeline-handoff-authority-selftest.sh`（identity split fixture）、`gate-pr-title.sh` self-check | LLM 不得用 legacy `task_jira_key` alias 補判斷；branch / PR title 只用 `delivery_ticket_key` | `fail_stop_on_internal_work_item_id_in_product_pr_identity`（AC-NEG5） |
| `loop_counters` | auto-pass ledger writer | `scripts/auto-pass-increment-counter.sh`（writes `{count, evidence_ids}` dict shape，DP-246 後） | ledger `loop_counters` summary 給 orchestrator 觀察 | `scripts/auto-pass-probe.sh`（**read-only consumer**）、orchestrator terminal classification | `scripts/selftests/auto-pass-runner-probe-parity-selftest.sh`、`scripts/selftests/auto-pass-increment-counter-idempotency-selftest.sh`、本檔對應 selftest case `probe-ledger-atom-declared` | LLM 不得手寫 ledger counter 或繞過 writer | `fail_stop_on_schema_mismatch`（probe / writer dict shape parity；DP-246 cascade gap regression guard） |

## 衍生規則

- **No third schema authority**：本檔禁止複製 `refinement.json` / `task.md` / V*.md /
  ledger 的完整欄位表。`drift_policy` 與 `validator_or_selftest` 是唯一允許的「強制行為」
  描述方式。
- **Pointer 優先**：每個 atom 的 `canonical_source` 必須是檔案路徑或 canonical schema
  reference；不寫 inline schema 段落。
- **Identity split 必守**：`work_item_id` / `jira_key` / `delivery_ticket_key` 的 consumer
  邊界由 parser + gate 強制；不允許 reference / SKILL prose 自行宣告新的 consumer。
- **Compatibility bridge** 必須在 `drift_policy` 註明 owner / removal criteria；本檔不
  接受沒有 sunset plan 的長期 compatibility shim。

## Drift Policy Vocabulary

| Token | 行為 |
|-------|------|
| `fail_stop_on_missing_field` | validator exit 2；不接受 fallback inference |
| `fail_stop_on_missing_marker` | runner / probe escalate 為 `blocked_by_gate_failure` |
| `fail_stop_on_planner_field_mutation_by_engineering` | engineering scope escalation 是唯一改 planner-owned field 的路徑 |
| `fail_stop_on_v_text_overriding_refinement_method` | verify-AC runner 以 `refinement.json.method` 為準；advisory log drift |
| `fail_stop_on_runner_json_missing_field` | orchestrator 不接受 partial runner JSON；missing field → blocked |
| `fail_stop_on_id_leak_into_product_pr_identity` | `gate-pr-title.sh` 擋 internal `work_item_id` 出現在 product PR title / branch |
| `fail_stop_on_internal_work_item_id_in_product_pr_identity` | branch resolver + PR title gate 雙層擋（AC-NEG5） |
| `fail_stop_on_missing_or_mismatched_jira_key` | Bug source 必填 jira_key；mismatch → JIRA transition gate fail |
| `fail_stop_on_schema_mismatch` | counter writer / probe schema parity；DP-246 dict shape 必須兩端齊步走 |

新 drift policy token 新增前，必須同步：

1. 對應 selftest（本檔 selftest 或 owning skill selftest）。
2. 對應 validator script。
3. 本檔 vocabulary section 註記。

## 相關 reference

- [pipeline-handoff.md](pipeline-handoff.md) — pipeline 角色邊界、handoff contract、AC-FAIL
  disposition gate（本檔的上層 narrative）。
- [refinement-artifact.md](refinement-artifact.md) — `refinement.json` 完整 schema。
- [task-md-schema.md](task-md-schema.md) — `task.md` schema 索引（含 task / verification 子檔）。
- [auto-pass-ledger.md](auto-pass-ledger.md) — auto-pass ledger schema（含 `loop_counters`
  dict shape）。
- [auto-pass-proof-of-work.md](auto-pass-proof-of-work.md) — proof marker schema + producer
  whitelist。
- [auto-pass-execution-flow.md](auto-pass-execution-flow.md) — runner JSON `next_action`
  schema。

## 來源

DP-238-T1（2026-05-28）：refinement -> breakdown -> engineering -> verify-AC handoff
contract slimming，建立 ownership atom matrix 作為 single source of truth，避免 schema
authority 分散在四個 SKILL.md 與多份 reference prose。
