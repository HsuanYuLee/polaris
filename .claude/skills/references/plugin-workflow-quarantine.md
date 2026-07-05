---
title: "Plugin Workflow Quarantine"
description: "Polaris workflow authority 與 OpenAI-curated / marketplace plugin adapter 的邊界。"
---

# Plugin Workflow Quarantine

OpenAI-curated and marketplace plugin-contributed skills are adapter surfaces, not Polaris workflow authority. When a user intent is covered by a workspace-owned Polaris skill and a plugin skill, the Polaris skill wins.

## Authority Rules

1. Product repo PR revision、review-comment fixes、stack convergence、merge readiness 由 `engineering` 管；GitHub plugin helpers 只能輔助 metadata / review-thread / check reads。
2. JIRA-backed implementation 與 DP-backed framework implementation 必須先由 workspace skills route：`refinement Bug source mode`、`refinement`、`breakdown`、`engineering`、`verify-AC`。
3. Framework release 只能在 engineering workspace PR ready / merged 且 verification current 後，由 `framework-release` 作 terminal tail。
4. Slack / GitHub / Figma plugin tools 可以當資料存取或外部寫入 adapter，但不能覆寫 owning Polaris skill 的 gates、readiness vocabulary 或 side effects。

## GitHub Plugin Boundary

`github:gh-address-comments` 可以支援 `engineering` R2 thread-aware reads；它不能把 generic write-safety flow 匯入 `engineering` R6。Revision mode 的 unresolved review-thread reply、outdated-thread disposition、readiness vocabulary 都以 `.claude/skills/references/engineering-revision-flow.md` 和 shared PR state scripts 為準。

## Conflict Handling

若 plugin workflow 與 Polaris flow 衝突，plugin workflow 只作 advisory context。繼續執行 Polaris flow，不因 generic plugin skill 會要求額外確認就加 gate，也不得用 plugin publisher 取代 Polaris framework release PR path。

Plugin / generic GitHub publisher 產生的 PR 不能滿足 auto-pass PR ownership gate。當
`auto-pass` 或 report validator 消費 PR ownership payload 時，PR 必須有
`polaris-pr-create.sh` provenance、`isDraft=false`、engineering completion marker PASS 與
base freshness current；plugin workflow 只能提供 metadata context，不能後補這些 ownership
事實。
