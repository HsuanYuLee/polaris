# Canonical Contract Governance

## Core Rule

Polaris governance 優先使用 hard constraints，而不是 advisory prose。

當 workflow、artifact、metadata surface 或 lifecycle contract 可以 deterministic 化時，Polaris
應收斂成一種 canonical shape、一條 canonical writer path、以及一條 deterministic enforcement
path。

## Rules

- **Strong constraints first**：若 contract 可由 script、hook、validator 或 generated artifact
  enforce，就採用機械 enforcement，不依賴 agent memory 或 maintainer habit。
- **Canonical shape first**：若兩個 workflows 或 runtimes 描述相同類型的 artifact 或 authority
  surface，除非 documented boundary 證明兩者本質不同，否則必須共享同一種 shape。
- **No special writer paths**：同一個 lifecycle、metadata field 或 status surface 不得有多條
  silent producer paths。Migration shims 只有在明確、temporary、且受 removal criteria 管理時才允許。
- **Fail closed on missing inputs**：缺少 required authority inputs 時，Polaris 必須停止，不得從 prose、
  conversation history 或 best-effort inference 合成 correctness。

## Applicability

變更或設計下列表面時套用本 rule：

- bootstrap/runtime instructions
- shared rules or skills
- specs and task artifact contracts
- status / lifecycle / metadata writers
- validators、hooks 或 release gates
- public maintainer-facing workflow docs

## Required Outcomes

- 每個 shared contract surface 都要有一個 canonical source of truth。
- 每個 authoritative state transition 都要有一條 declared writer path。
- 可 enforcement 的 contract violations 都要有一個 deterministic check。
- 不得用 runtime-specific governance wording 改變 shared semantics。

## Allowed Exceptions

只有 temporary compatibility mechanisms 可以偏離 target contract，而且 owning design plan 必須明確列出：

- owner
- removal criteria
- verification method
- follow-up task

Compatibility 是 delivery tool，不是 steady-state design。

## Source Parity

Polaris 的 refinement-owned source 同時涵蓋兩種 container：

- **DP-backed source**：framework workspace 的 `docs-manager/src/content/docs/specs/design-plans/DP-NNN-*/`。
- **JIRA Epic-backed source**：產品 repo 的 `docs-manager/src/content/docs/specs/companies/{company}/{EPIC}/`。

兩者由 `spec-source-resolver.md` 解析為相同的 `refinement-owned source` 抽象。任何 contract
surface——producer registry、ledger schema、validators、routing rules、hooks、reference
prose——只要描述 source-level lifecycle，就必須對 DP-backed 與 JIRA Epic-backed source
**symmetrically** 適用：

- **No DP-only writer path**：producer registry 內每個指向 `design-plans/DP-*/` 的 path glob
  都必須有對應的 `companies/*/*/` glob（反之亦然），由
  `scripts/validate-spec-source-parity.sh` 在 framework PR gate 強制。
- **No DP-only routing prose**：rules / skills / references / helper scripts 不得在
  source-neutral surface 留下 `only DP-backed source`、`只接受 DP-backed source`、
  `DP-only route`、`DP-only routing` 等措辭；validator 把這類 prose 視為 drift fail-stop。
- **No DP-only validator branch**：lifecycle / ledger / consent validator 不得對 source type
  做特殊豁免；source-type-specific 邏輯（例如 JIRA 才需要 `jira_status_transition` consent）
  必須是「additional」契約，而非「DP-only fast path」。

### Allowed Exceptions（source parity）

唯一可接受的不對稱必須登記在 `scripts/lib/spec-source-parity-allowlist.txt`，分為兩類：

- **`[registry]`**：producer 經由 design 決定只服務單一 source type（例如「DP-only docs page
  metadata」），列出該 path glob 並在 owning DP plan 記錄理由。
- **`[auto-pass-prose]`**：transitional baseline。檔案目前仍含 DP-only routing prose，但已有
  owning migration task 排定移除（entry 格式：`<path>:<token>:<owning-task>`）。

任何超出 allowlist 的不對稱都是 `validate-spec-source-parity.sh` 的 fail-stop 條件。

`framework-release` skill 是已知 carve-out：它只對 framework workspace（DP-backed source）
生效。這條 boundary 由 `framework-release` skill 自身的 precondition 強制，不在 source parity
gate scope 內——`framework-release` 不是 source-level lifecycle contract，而是 framework
workspace 專屬的 release tail。

## Steady-State Carve-Outs

`command -v gh` 的 delivery readiness probe 是 D7 穩態 carve-out，但只在 probe 不作為
invocation source of truth 時成立。允許情境包含：

- gate / hook 在 `gh` 不存在時 fail-open skip，例如只用來查詢 existing PR 狀態的保護 gate。
- gate / hook 在 `gh` 不存在時 fail-closed，且 stderr 輸出 `POLARIS_TOOL_MISSING`。
- auth readiness 失敗時 fail-closed，且 stderr 輸出 `POLARIS_TOOL_AUTH_FAILED`。

保留站點必須加 inline `D7 readiness-probe carve-out` 註記；若 script 後續用該解析結果呼叫工具，
必須改走 shared helper 或 resolver。
