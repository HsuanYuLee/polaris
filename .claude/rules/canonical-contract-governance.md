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

## Delivery Unit Completion Standard

delivery unit 的結案標準本身就是一種 canonical contract surface：哪些東西可以成為獨立
delivery unit、研究單與轉發/theme 單為何不算 delivery unit，以及它們的正確收編路徑，由
`.claude/skills/references/delivery-unit-completion-standard.md` 定義（D1 completion-standard
contract、D2 研究單、D3 轉發/theme 單）。

- **D1**：delivery unit 必須具備 runtime-verifiable 結案標準；form / format proxy 不算結案
  （對齊本檔 Strong constraints first / Fail closed on missing inputs）。
- **D2**：研究單（全 audit task、無 implementation task、無 verifiable AC）是 refinement-phase
  activity，收編進 implementation DP 的 refinement，不獨立成 delivery unit。
- **D3**：轉發 / theme 單（無自身 verifiable AC、deliverable 僅 dispatch）改寫成 north-star
  artifact，禁止成為 delivery DP。

規劃 / LOCK refinement-owned source 時必須對齊上述 reference；D4 deterministic gate
（`validate-breakdown-ready.sh` / `validate-refinement-lock-preflight.sh`）負責機械 enforce。

## Derived Artifact Read Boundary

`refinement.md` 是由 `refinement.json` render 出來的 **derived view**（producer：
`scripts/render-refinement-md.sh`），不是 authoritative source。authoritative source 是
`refinement.json`。任何 **business gate**——亦即用 read 結果驅動 lifecycle / scope /
correctness 判斷（exit 2 / fail-closed / branch decision）的 validator、hook、release
gate——**不得**讀 derived `refinement.md` body 做 business 判斷。business judgment 一律從
authoritative `refinement.json` 取得。

對 `refinement.md` 唯一允許的 gate 是 **idempotency / parity `--check`**：確認 derived
view 與 `refinement.json` 一致（例如 `render-refinement-md.sh --check`、
`validate-refinement-artifact-parity.sh` 比對 json AC ids ↔ md AC ids）。這類 reader 把
`refinement.md` 當 render target 做一致性檢查，而非 source of business truth。

合法（非 business-read）的 `refinement.md` 互動：

- **idempotency / parity**：`--check` 模式比對 derived view 與 `refinement.json` 一致性。
- **shape / existence**：`[[ -f .../refinement.md ]]` 存在性探測、primary-doc basename 檢查、
  resolver candidate path 列舉。

違反（business-read）的 `refinement.md` 互動：

- 用 `git show <ref>:.../refinement.md` 取出 body、再 diff `## Scope` / `## Goal` 等 heading
  section 來判定 LOCKED scope violation 或其他 lifecycle gate。
- `cat` / `grep` / heading-parse `refinement.md` body，把結果當 scope / status / AC 的
  authority 來源。

此條對齊本檔 **Strong constraints first / Canonical shape first / Fail closed on missing
inputs**：authoritative source 只有一個（`refinement.json`），derived view 不得成為第二條
business authority path。deterministic enforcement 由
`scripts/lint-no-business-gate-reads-derived-md.sh` 提供：以 allowlist 區分 idempotency /
parity / shape / existence reader（legitimate）與 business-read（violation），新增的
business-read gate 會被偵測 fail，既有 legitimate reader 不被誤判。

## Closeout Delivered-Head Authority

framework-release closeout 在決定一張 task 的「交付 head sha」時，唯一允許的權威來源是
**immutable evidence**，不得讀 mutable `task/*` branch ref。task branch head 會隨後續
push / rebase / 其他 session 的 WIP 漂移，把它當 authority 會讓 closeout 綁到 stale 或
無關的 head（DP-319 incident：closeout 透過 branch ref 取到舊 task-PR head 7b7474b，而
verify marker 已在 feat HEAD f6d9198，導致 `local_extension_completion_failed`）。

closeout 取交付 head 的 resolution 順序（三者皆 immutable）：

1. **明確 `--task-head-sha {work_item_id}={sha}` override**：caller 指定的 head map，
   最高優先。
2. **completion-gate marker filename head**：讀
   `.polaris/evidence/completion-gate/{work_item_id}-{head}.json` 的 filename head；
   marker 由 evidence-producing skill 在交付當下寫入、檔名綁交付 head，是 immutable
   delivered-head 的 canonical record。
3. **task.md `deliverable.head_sha` delivery block**：persisted 在 task.md frontmatter
   的交付 head。

三者皆無法解析時 **fail-closed**（die），不得 fall back 到 branch ref，也不得 silent
pass。aggregate / bundle task（`bundle_branch_alias` present）必須由 caller 明確帶
`--task-head-sha`，不得從 branch 推斷。

此條對齊本檔 **No special writer paths / Fail closed on missing inputs**：交付 head 只有
一條 immutable authority path（marker filename + delivery block + explicit override），
mutable branch ref 不得成為第二條 silent authority。deterministic enforcement 由
`scripts/framework-release-closeout.sh` 的 head-resolution 順序與
`scripts/selftests/framework-release-closeout-head-authority-selftest.sh` 提供：污染
`task/*` ref 時 head 仍取自 marker、缺所有 immutable source 時 fail-closed、V-task 走
parent-closeout、aggregate 缺 `--task-head-sha` 時 fail-closed。

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
