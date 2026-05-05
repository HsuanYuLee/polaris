---
name: refinement
description: >
  Iteratively enriches incomplete JIRA Epics into estimation-ready, technically-validated specs.
  Five modes: batch readiness scan, RD discovery (Phase 0), PM elaboration (Phase 1),
  technical approach (Phase 2), and multi-round iteration. Phase 1 goes beyond checklist
  filling — it explores the codebase, hardens AC, and produces a structured artifact for
  downstream skills. Trigger: "refinement", "grooming", "討論需求", "需求釐清", "補完 Epic",
  "這張單缺什麼", "brainstorm", "方案討論", "想重構", "tech debt", "batch refinement",
  "sprint prep", or Epic with sparse content needing enrichment.
metadata:
  author: Polaris
  version: 4.1.0
---

# Refinement — Architect

`refinement` 是 Architect：把模糊需求變成經技術驗證、可估點、可拆工的藍圖。它擁有
Goal / Background / Decisions / Blind Spots / AC / Technical Approach；不拆子單、不估點、
不寫 code。下游 `breakdown` 才負責 work orders。

## Mandatory Contracts

- 所有 source 先用 `spec-source-resolver.md` 解析；DP / topic 低頻細節讀
  `refinement-dp-source-mode.md`。
- Framework contract change 預設走 DP / ticketless refinement proposal；未經使用者確認
  不直接改 skill / rule / reference / validator。
- breakdown → refinement 回流只讀 `refinement-inbox/*.md`；禁止直接讀 engineering raw
  sidecar，schema 依 `refinement-return-inbox.md`。
- 所有 sub-agent dispatch 前讀 `sub-agent-roles.md` 並注入 Completion Envelope。
- 多輪 refinement 先寫本地 `refinement.md` 與 docs-manager preview；定版後才一次性產
  `refinement.json`，JIRA-backed source 才同步 JIRA。
- 對下游公開前必跑 `refinement-handoff-gate.sh`、`workspace-language-policy.md` gate、
  `starlight-authoring-contract.md` gate；DP `plan.md` 必須用
  `scripts/validate-dp-plan-authoring.sh` 統一檢查。
- 寫入後最後跑 Post-Task Reflection。

## Mode Routing

| Signal / source | Mode | Reference |
|---|---|---|
| 多張 Epic / sprint prep readiness | Batch readiness scan | `refinement-batch-readiness-flow.md` |
| RD 主動提出 code smell / tech debt / performance issue | Phase 0 discovery | `refinement-phase0-discovery-flow.md` |
| JIRA Epic sparse / PM needs elaboration | Phase 1 elaboration | `refinement-phase1-elaboration-flow.md` |
| 需求已明確但需要方案取捨 | Phase 2 technical approach | `refinement-phase2-decision-flow.md` |
| `DP-NNN` / topic / ADR / design plan | Ticketless DP source | `refinement-dp-source-mode.md` |
| unconsumed refinement inbox | Return inbox intake | `refinement-return-inbox.md` |

## Complexity Tier

Phase 1 預設 Tier 2；只有明確符合 Tier 1 才降級。

| Tier | Condition | Depth |
|---|---|---|
| Tier 1 | <= 2 expected tasks and description nearly complete | checklist + small supplement |
| Tier 2 | default | codebase exploration + historical context + AC hardening + artifact |
| Tier 3 | external URL, new tech/framework, user asks deep | solution research + multi-role analysis |

## Handoff

定版後 source container 必須同時有：

- `refinement.md`：人讀，docs-manager preview。
- `refinement.json`：機器讀，供 breakdown / engineering 消費。

## Step 7 — 定版寫入（一次性）

在提示 `breakdown {SOURCE}` 前先跑：

```bash
bash scripts/refinement-handoff-gate.sh {source_container}/refinement.md
bash scripts/validate-language-policy.sh --blocking --mode artifact {source_container}/refinement.md
bash scripts/validate-starlight-authoring.sh check {source_container}/refinement.md
```

若同 container 有 `plan.md`，language / Starlight gate 一併檢查。
DP-backed source 的 `plan.md` 必須額外跑：

```bash
bash scripts/validate-dp-plan-authoring.sh {source_container}/plan.md
```

## Step 8 — L2 Deterministic Check: post-task-feedback-reflection

完成 write flow 後必須呼叫 `scripts/check-feedback-signals.sh`，再執行 Post-Task Reflection。

## Post-Task Reflection (required)

> Non-optional. Execute before reporting task completion after any write.

Run the checklist in `post-task-reflection-checkpoint.md`.
