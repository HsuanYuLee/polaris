# Workspace Self-Development Routing

> 這是一條薄 routing rule。當 agent 維護 Polaris framework 本身（meta-development）時，
> 必須載入 `.claude/rules/handbook/framework/` 作為 self-development handbook SoT；
> 維護 product repo / company 流程時改走 `{company}/polaris-config/{project}/handbook/`，
> 兩種 handbook 不可混用。

## Trigger（何時載入 framework self-development handbook）

當本輪 task / PR / changed files / user request 涉及下列任一 Polaris-owned path 時，必須
載入 `.claude/rules/handbook/framework/index.md`，再由 index 按需 pull 對應 topic 子檔：

- `.claude/**`（rules、skills、hooks、references、instructions、所有 Polaris-tracked 設定）
- `.agents/**`、`.codex/**`、`.github/copilot-instructions.md`（跨 LLM runtime mirror surface）
- `scripts/**`（framework-shared shell / python / mjs / ts scripts、含 selftest / fixture）
- `mise.toml`、`workspace-config.yaml`、`.claude/instructions/manifest.yaml`
  （framework-owned configuration surface，與 `mise.toml` 同層治理；詳見
  `framework/configuration-surface.md`）
- root runtime instruction generated targets：`CLAUDE.md`、`AGENTS.md`、`.codex/AGENTS.md`、
  `.github/copilot-instructions.md`（generated artifacts；source 在 `.claude/instructions/**`）
- `docs-manager/src/content/docs/specs/design-plans/DP-*`（framework workspace 的
  refinement-owned source；JIRA Epic-backed source 走 product handbook）

判定方式以 changed files 與 task scope 為準；無法 deterministic 判定時，由
`scripts/validate-framework-handbook-routing.sh` 在 framework PR gate 標示路由命中。

## Boundary（product handbook 邊界）

下列 path 屬於 product-repo / company / template scaffolding，**不**在 framework
self-development handbook scope 內，仍由 product handbook 接手：

- `{company}/polaris-config/{project}/handbook/**`（product repo 自己的 handbook SoT）
- `{company}/polaris-config/{project}/generated-scripts/**`（local-only 產物）
- `_template/**`、`_template/rule-examples/**`（template scaffolding，never auto-loaded）
- 任何位於 product repo（非 framework workspace）的 source / config

混合命中（同一 PR / task 同時涉及 framework-owned 與 product-repo path）時，**兩種
handbook 都要 route**，不擇一覆蓋；validator 不允許用 framework handbook 規則去管 product
repo handbook path（反之亦然）。

## Handbook Loading Order

當命中 framework self-development trigger 時，建議的載入順序：

1. `.claude/rules/handbook/framework/index.md`（routing pointer + 目錄；先看本輪要載哪些 topic）
2. 視 task 性質 on-demand pull 對應子檔：
   - cross-LLM artifact / generated target → `cross-llm-parity.md`
   - 新 / 改 script → `script-governance.md`
   - 開發紀律、Reference Hierarchy、Shell / Python standards → `development-standards.md`
   - `mise.toml` / framework configuration surface 異動 → `dependency-management.md`、
     `configuration-surface.md`
   - 新 skill / rule / contract 設計 → `contract-design.md`
3. 同時遵守憲法層（`bootstrap.md` 發行的 Skill-First Routing / Markdown Authoring Contract /
   Tool Missing Discipline）；handbook 不重複定義憲法已治理的條文。

詳細條文與對應 deterministic validator 由
[`.claude/rules/handbook/framework/index.md`](handbook/framework/index.md) 收斂；本檔只
負責 routing。

## Verification

- 路由命中與否由 `scripts/validate-framework-handbook-routing.sh` 在 framework PR gate
  判斷；fixture 涵蓋 `.claude/**`、`scripts/**`、`docs-manager/src/content/docs/specs/
  design-plans/DP-*`、product repo path、與混合命中 case。
- 本檔本身屬 framework workspace `.claude/rules/` 範圍，受 framework PR gate 與
  `scripts/verify-cross-llm-parity.sh` aggregate 監管。
