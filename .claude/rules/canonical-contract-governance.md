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

## Steady-State Carve-Outs

`command -v gh` 的 delivery readiness probe 是 D7 穩態 carve-out，但只在 probe 不作為
invocation source of truth 時成立。允許情境包含：

- gate / hook 在 `gh` 不存在時 fail-open skip，例如只用來查詢 existing PR 狀態的保護 gate。
- gate / hook 在 `gh` 不存在時 fail-closed，且 stderr 輸出 `POLARIS_TOOL_MISSING`。
- auth readiness 失敗時 fail-closed，且 stderr 輸出 `POLARIS_TOOL_AUTH_FAILED`。

保留站點必須加 inline `D7 readiness-probe carve-out` 註記；若 script 後續用該解析結果呼叫工具，
必須改走 shared helper 或 resolver。
