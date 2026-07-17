# Workspace Self-Development Routing

> 這是一條薄 routing rule。當 agent 維護 Polaris framework 本身（meta-development）時，
> 必須透過 `scripts/resolve-handbook.sh --project polaris-framework` 載入 repo-scoped
> self-development handbook SoT；
> 維護 product repo / company 流程時改走 `{company}/polaris-config/{project}/handbook/`，
> 兩種 handbook 不可混用。

## Trigger（何時載入 framework self-development handbook）

當本輪 task / PR / changed files / user request 涉及下列任一 Polaris-owned path 時，必須
呼叫 canonical resolver，並把回傳的 `narrative_paths` 視為本輪完整 handbook payload：

- `.claude/**`（rules、skills、hooks、references、instructions、所有 Polaris-tracked 設定）
- `.agents/**`、`.codex/**`、`.github/copilot-instructions.md`（跨 LLM runtime mirror surface）
- `scripts/**`（framework-shared shell / python / mjs / ts scripts、含 selftest / fixture）
- `mise.toml`、`workspace-config.yaml`、`.claude/instructions/manifest.yaml`
  （framework-owned configuration surface，與 `mise.toml` 同層治理）
- root runtime instruction generated targets：`CLAUDE.md`、`AGENTS.md`、`.codex/AGENTS.md`、
  `.github/copilot-instructions.md`（generated artifacts；source 在 `.claude/instructions/**`）
- `docs-manager/src/content/docs/specs/design-plans/DP-*`（framework workspace 的
  refinement-owned source；JIRA Epic-backed source 走 product handbook）

判定方式以 repo identity、changed files 與 task scope 為準；tracked-file 首次變更前由
`validate-handbook-load-gate.sh` 經同一 resolver surface handbook 並建立 session marker。

## Boundary（product handbook 邊界）

下列 path 屬於 product-repo / company / template scaffolding，**不**在 framework
self-development handbook scope 內，仍由 product handbook 接手：

- `{company}/polaris-config/{project}/handbook/**`（product repo 自己的 handbook SoT）
- `{company}/polaris-config/{project}/generated-scripts/**`（local-only 產物）
- `_template/**`、`_template/rule-examples/**`（template scaffolding，never auto-loaded）
- 任何位於 product repo（非 framework workspace）的 source / config

混合命中（同一 PR / task 同時涉及 framework-owned 與 product-repo path）時，依各 repo 的
project mapping 分別解析；不得以 framework handbook 覆蓋 product handbook（反之亦然）。

## Handbook Loading Order

當命中 framework self-development trigger 時，載入順序只有一條：

1. 執行 `scripts/resolve-handbook.sh --project polaris-framework`。
2. 驗證 resolver payload 後，依 `narrative_paths` 的 deterministic 順序載入 index 與全部 topic；
   不再由第二套 framework-special path classifier 推測要載哪些子檔。
3. 同時遵守憲法層（`bootstrap.md` 發行的 Skill-First Routing / Markdown Authoring Contract /
   Tool Missing Discipline）；handbook 不重複定義憲法已治理的條文。

詳細條文由 resolver 回傳的 canonical `index_path` 與 `narrative_paths` 收斂；本檔只負責
repo identity routing。

## Verification

- canonical path 與 framework/product 對稱解析由 `scripts/selftests/resolve-handbook-selftest.sh`
  驗證；首次變更前的 fail-closed marker 行為由
  `scripts/selftests/handbook-load-gate-selftest.sh` 驗證。
- 本檔本身屬 framework workspace `.claude/rules/` 範圍，受 framework PR gate 與
  `scripts/verify-cross-llm-parity.sh` aggregate 監管。
