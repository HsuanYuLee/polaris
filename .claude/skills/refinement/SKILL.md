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
  version: 4.2.0
---

# Refinement — Architect

`refinement` 是 Architect：把模糊需求變成經技術驗證、可估點、可拆工的藍圖。它擁有
Goal / Background / Decisions / Blind Spots / AC / Technical Approach；不拆子單、不估點、
不寫 code。下游 `breakdown` 才負責 work orders。

## Mandatory Contracts

- 所有 source 先用 `spec-source-resolver.md` 解析；DP / topic 低頻細節讀
  `refinement-dp-source-mode.md`。
- 開始產生 preview、`refinement.md`、`refinement.json`、JIRA comment draft 或任何
  downstream-facing prose 前，先讀 `workspace-config-reader.md`、
  `workspace-language-policy.md` 與 `authoring-preflight.md`；root `language` 是起稿語言，
  不是送出前翻譯步驟。
- Framework contract change 預設走 DP / ticketless refinement proposal；未經使用者確認
  不直接改 skill / rule / reference / validator。
- DP-backed source 沒有特殊施工捷徑；`refinement` 完成後仍必須走與 Epic 相同的正規鏈：
  `breakdown -> engineering -> (verify-AC when verification work order / AC artifact exists)`，
  Polaris-specific `framework-release` 只能作為 engineering 之後的 local extension tail。
- breakdown → refinement 回流只讀 `refinement-inbox/*.md`；禁止直接讀 engineering raw
  sidecar，schema 依 `refinement-return-inbox.md`。
- 所有 sub-agent dispatch 前讀 `sub-agent-roles.md` 並注入 Completion Envelope。
- 多輪 refinement 先寫本地 `refinement.md` 與 docs-manager preview；定版後才一次性產
  `refinement.json`，JIRA-backed source 才同步 JIRA。
- 任何 refinement-owned source（JIRA Epic / Story / Task、ticketless topic、DP-backed
  source）交給 `breakdown` 前，都必須有 current `refinement.md` + `refinement.json`
  並通過 handoff gate；不得先 LOCK / 提示 breakdown 再回頭補 artifact。Bug 例外：
  Bug 由 `bug-triage` 產 confirmed RCA handoff，不走 refinement artifact。
- 新 ticketless DP source 由 `scripts/create-design-plan.sh` 建立 folder-native
  `index.md` container；legacy `plan.md` 只作為既有 DP fallback，不作為新寫入預設。
- DP frontmatter / section shape 的 template authority 只有 `scripts/create-design-plan.sh`
  產生的 container 與 `refinement-dp-source-mode.md`；不得以搜尋其他 DP 當作預設 template
  來源，也不得靠手動比對 sibling DP 推回 schema。
- 對下游公開前必跑 `refinement-handoff-gate.sh`、`workspace-language-policy.md` gate、
  `starlight-authoring-contract.md` gate；DP `plan.md` 必須用
  `scripts/validate-dp-plan-authoring.sh` 統一檢查。
- refinement 產生的 external write drafts、JIRA comment body、manual validation output 若要保留，
  必須 close out 到 source container 的 `jira-comments/`、`artifacts/external-writes/`
  或 `artifacts/research/`；temporary transport cache 只能使用
  `.polaris/runtime/external-writes/`，不可作為 durable artifact。`.codex/external-writes/`
  與 `.codex/tmp/` 是 forbidden old / scratch residue，不得寫入或讀取。
- Phase 1 suggested task structure preview 前讀 `infra-first-decision.md`，用 AC 的
  verification method 判斷是否需要 infra prerequisite；不得回到 visual-regression-config
  bound fallback。
- Phase 1 suggested task structure preview 前也必須讀
  `stacked-delivery-sibling-epic-policy.md`，並對 draft task structure 執行
  `scripts/detect-stacked-delivery-lane.mjs` lens；命中長線性 stack 時，preview 必須先呈現
  sibling Epic advisory / required decision，不得把 `TXa~TXn` 直接留在原 umbrella Epic。
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
- `refinement.json`：機器讀，供 breakdown 產生 task.md；engineering 只消費
  breakdown 產出的 authoritative task.md。

這是所有 refinement-owned source 的 handoff contract，不只適用 DP。Epic / Story /
Task / ticketless topic / DP 都必須先完成 artifact，且 handoff / language / authoring
gates 全部通過後，再對使用者提示 `breakdown ...`。
Bug 不屬於 refinement-owned source；Bug 的 planning handoff 由 `bug-triage` 的 confirmed
`[ROOT_CAUSE]` comment 與 local evidence artifact 承擔。

## Step 7 — 定版寫入（一次性）

在提示 `breakdown {SOURCE}` 或把 DP status 改為 `LOCKED` 前先跑：

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

同時檢查本輪產生的 external write drafts 是否已歸檔或刪除：

- durable JIRA comment drafts：`{source_container}/jira-comments/YYYYMMDD-{slug}.md`
- durable raw transport drafts：`{source_container}/artifacts/external-writes/YYYYMMDD-{slug}.md`
- research / validation snapshots：`{source_container}/artifacts/research/YYYY-MM-DD-{slug}.md`
- temporary body files：gate pass 後刪除，不得留下 `.polaris/runtime/external-writes/`、
  `.codex/external-writes/` 或 `.codex/tmp/` residue。

Step 7 同時執行 runtime cache residue gate：

```bash
bash scripts/check-runtime-cache-residue.sh --repo . --source-container {source_container}
```

## L2 Deterministic Check: post-task-feedback-reflection

完成 write flow 後必須呼叫 `scripts/check-feedback-signals.sh`，再執行 Post-Task Reflection。

## Post-Task Reflection (required)

> Non-optional. Execute before reporting task completion after any write.

Run the checklist in `post-task-reflection-checkpoint.md`.
