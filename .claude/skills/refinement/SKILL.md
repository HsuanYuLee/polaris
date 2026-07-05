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

- 所有 source 先用 `spec-source-resolver.md` 解析；source-mode 細節（DP container path、
  JIRA-backed container path、LOCKED scope guard）讀 `refinement-source-mode.md`。
- 開始產生 preview、`refinement.md`、`refinement.json`、JIRA comment draft 或任何
  downstream-facing prose 前，先讀 `workspace-config-reader.md`、
  `workspace-language-policy.md` 與 `authoring-preflight.md`；root `language` 是起稿語言，
  不是送出前翻譯步驟。
- 寫 artifact 前必讀 `pipeline-handoff.md` § Artifact Schemas，再讀
  `refinement-artifact.md` / `task-md-schema.md` 等對應 artifact-specific schema。atom
  ownership 邊界以 `pipeline-handoff-atom-matrix.md` 為準；SKILL 主文不複製完整 schema 表。
- Phase 1 / Phase 2 發現 AC、Verify Command、repo script、project handbook 或特定 ticket
  需要 framework root toolchain 之外的 CLI / package / local binary 時，必須寫入
  `refinement.json` 的 `tool_requirements[]`。工單級或 `runtime_profile=ticket` 的工具只做
  downstream handoff，`goes_to_mise=false`，不得建議放進 root `mise.toml`。
- Framework contract change 預設走 DP / ticketless refinement proposal；未經使用者確認
  不直接改 skill / rule / reference / validator。
- LOCK 後若下游需要改 `.claude/**`、`.codex/**`、`scripts/**` 等 framework/control-plane
  source，planned task 的 Allowed Files 必須精確列出這些 path；寫入時會由
  `scripts/validate-framework-source-write.sh` 以 active task.md fail-closed 檢查，不接受
  事後口頭補 scope。
- DP-backed source 沒有特殊施工捷徑；`refinement` 完成後仍必須走與 Epic 相同的正規鏈：
  `breakdown -> engineering -> (verify-AC when verification work order / AC artifact exists)`，
  Polaris-specific `framework-release` 只能作為 engineering 之後的 local extension tail。
- breakdown → refinement 回流只讀 `refinement-inbox/*.md`；禁止直接讀 engineering raw
  sidecar，schema 依 `refinement-return-inbox.md`。
- 所有 sub-agent dispatch 前讀 `sub-agent-roles.md` 並注入 Completion Envelope；Codex
  runtime / model fallback contract 見該 reference § Runtime Adapter Contract /
  Fallback Behavior。
- 多輪 refinement 先寫本地 `refinement.md` 與 docs-manager preview；定版後才一次性產
  `refinement.json`，JIRA-backed source 才同步 JIRA。
- 任何 refinement-owned source（JIRA Epic / Story / Task、Bug、ticketless topic、DP-backed
  source）交給 `breakdown` 前，都必須有 current `refinement.md` + `refinement.json`
  並通過 handoff gate；不得先 LOCK / 提示 breakdown 再回頭補 artifact。Bug source
  走 `refinement-bug-source-mode.md`，由 `source_kind=bug` 觸發 reproduction、RCA、
  source PR identification 與 severity / impact assessment sub-steps。
- 新 ticketless DP source 由 `scripts/create-design-plan.sh` 建立 folder-native
  `index.md` container；legacy `plan.md` 只作為既有 DP fallback，不作為新寫入預設。
- DP frontmatter / section shape 的 template authority 只有 `scripts/create-design-plan.sh`
  產生的 container 與 `refinement-source-mode.md`；不得以搜尋其他 DP 當作預設 template
  來源，也不得靠手動比對 sibling DP 推回 schema。
- 對下游公開前必跑 `mise run docs-health -- {source_container}/refinement.md`、`workspace-language-policy.md` gate、
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
| Bug ticket / Bug source / source_kind=bug | Bug source mode | `refinement-bug-source-mode.md` |
| `DP-NNN` / topic / ADR / design plan | Ticketless DP source | `refinement-source-mode.md` |
| unconsumed refinement inbox | Return inbox intake | `refinement-return-inbox.md` |
| auto-pass amendment dispatch（任何 refinement-owned source LOCKED + refinement-inbox 出現新 message）| Auto-pass driven amendment | `refinement-source-mode.md` § LOCKED Scope Guard |

**Auto-pass driven amendment mode (DP-212)**：當 refinement 由 `/auto-pass` dispatch（envelope
包含 `AUTO_PASS_LEDGER_PATH` + `AUTO_PASS_AMENDMENT=1` 訊號）時，refinement 進入 amendment
mode。Amendment trigger 是「任何 refinement-owned source（DP-backed 或 JIRA Epic-backed）
進入 `LOCKED` 後，`{source_container}/refinement-inbox/` 出現新 message」——DP / Epic
共用同一條 amendment 路徑，不再分流。amendment 必須：只消費
`{source_container}/refinement-inbox/*.md`、不向使用者發問、不重做 Phase 0/1/2 discovery、
不能改 LOCKED scope（Goal / Background / Decisions / Scope / AC），只能更新 `refinement.md` /
`refinement.json` 的 implementation detail。寫回後在 inbox record 補 `consumed_by_amendment`
欄位（`amender=auto-pass`、`amendment_commit_sha`、`amendment_round`）。違反 scope guard
時必須讓 `scripts/validate-refinement-locked-scope.sh` exit 2，並標 inbox
`rejected_by_scope_guard=true`，不得 silently 修改 LOCKED section。

## Producer Env Contract

`refinement` 寫入 specs-bound artifact（`refinement.md` / `refinement.json` /
docs-manager preview / refinement-owned spec Markdown）時，必須在 producer
script 內部設定：

```bash
export POLARIS_SKILL_WRITER=refinement
export POLARIS_PRODUCER=refinement
```

這兩個 env 由 `pre-write-language-policy.sh` 與 `no-direct-evidence-write.sh` hook
辨識，確認本次寫入屬於 refinement 的 deterministic writer，不是 ad-hoc tool 直寫。
producer env 只能透過 deterministic writer script（例如 `write-producer-owned-artifact.sh`、
`create-design-plan.sh`）注入，不得用 Claude tool per-call env 模擬，也不得在 main
session shell 永久 export。違反時 hook fail-closed、不寫檔。

producer-env 規則同時適用 DP-backed 與 JIRA Epic-backed refinement-owned source；
writer path glob 受 `scripts/lib/evidence-producers.json` parity 保護。

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
  breakdown 產出的 authoritative task.md。若本 source 有工單級工具需求，
  `tool_requirements[]` 是 breakdown 產生 `## Required Tools` 的唯一 handoff 來源。
- Handoff 前必須完成 Predecessor Scan、AC Coverage、Adversarial Pass、
  Production↔Selftest parity、Framework Release Surface、Cross-Doc Referrer Cascade
  等 author-time self-check。`refinement.md` 是 derived view；strict
  `refinement.json` 通過後一律用 `scripts/render-refinement-md.sh` 重渲，hand-edit 由
  handoff gate fail-stop。

這是所有 refinement-owned source 的 handoff contract，不只適用 DP。Epic / Story /
Task / Bug / ticketless topic / DP 都必須先完成 artifact，且 handoff / language / authoring
gates 全部通過後，再對使用者提示 `/auto-pass {KEY}`。

### Canonical / Standalone Handoff Contract（DP-296 AC6）

refinement 作為 producer，預設產出 **canonical** schema artifact 給下游消費：
`refinement.json` 的 canonical `tasks[]` 是 breakdown 的唯一 handoff 介面，breakdown
traverse 該 canonical schema 而非 refinement 的 freeform prose。LLM freeform（非
canonical schema 的自由敘述）只在 **standalone** 情境合法——亦即該產出沒有下游 pipeline
consumer 會機械消費它，例如純人讀的 `refinement.md` derived view 或對使用者的解釋性
prose。一旦產出會被下一段 skill 機械消費，就必須走 canonical schema。本契約只約束 handoff
artifact 介面，**不**約束 refinement 內部如何探索 codebase、推導方案或組織 reasoning。
完整契約見 `.claude/skills/references/pipeline-handoff.md` § Canonical Schema Traversal
Contract。

## Per-Task Body Field Population — All Source (DP-302)

Phase 1 / Phase 2 收斂 `refinement.json` 時，**所有 source（不分 `dp` / `jira`）** 都必須為
每筆 `tasks[]` populate 下列 **per-task body 欄位**。這些欄位是
`derive-task-md-from-refinement-json.sh` 產出 task.md body 的 field-driven 輸入；derive 一律
讀欄位、不看 `source.type`，因此 dp / jira 兩種 source 產出的 task.md「結構一模一樣、只有值
不同」（DP-302 Goal）。schema 與 fail-loud 契約見 `references/refinement-artifact.md`
§ `tasks[].verification` per-task body fields。

- **`tasks[].verification.behavior_contract`**：object，required boolean `applies`。
  `applies` 由 task 真實性質判定（見下方判定接線），**不再依賴 derive hardcode**。
  `applies=false` 時必須附非空 `reason`；`applies=true` 可附 `mode`（如 `parity` / `hybrid`）。
  derive 寫入 task.md frontmatter `verification.behavior_contract`。
- **`tasks[].verification.test_environment`**：object，required `level` ∈ `static` /
  `component` / `integration` / `runtime`。derive 寫入 task.md `## Test Environment` 的 Level。
- **`tasks[].verification.verify_command`**：非空字串；derive 寫入 task.md `## Verify
  Command`（**無無條件 framework 尾段**——framework-only 步驟只在此欄位明確要求時才出現）。
- **`tasks[].verification.references`**：字串陣列（每筆非空）；derive 寫入 task.md
  `References to load`。實際 container 路徑（`companies/` vs `design-plans/`）由 resolved
  container 生成，不由本欄位寫死。

### `behavior_contract.applies` 判定接線（不由 derive hardcode — EC2）

判定每筆 task 的 `behavior_contract.applies` 時，接 **`infra-first-decision.md`** 的判斷
surface，依該 task 的 AC verification method 與真實性質判定，而不是讓 derive 套固定
`false` default：

1. **runtime / UI / product task**（AC 用 `lighthouse` / `playwright` / `curl`，或交付物是
   會被使用者觀察的 runtime / 畫面行為）→ `applies=true`；可依需要附 `mode`。
2. **framework infra task**（framework deterministic gate / selftest / helper / validator /
   schema；AC 全為 `unit_test`、無 runtime / UI 行為變更）→ `applies=false`，`reason` 明寫為何
   無行為契約（例：`framework deterministic gate / selftest / helper；無 runtime / UI 行為變更`）。
3. **判定來源**：以 `acceptance_criteria[].verification.method` 與 task 交付物性質為準
   （對齊 `infra-first-decision.md` 的 runtime-required 分類），不靠 Strategist 直覺，也不靠
   derive 的 hardcode false。同一筆判定理由要能回溯到 AC method，便於下游 verify-AC 對齊。

這條對 dp 與 jira source 對稱適用：framework DP 的 infra task 多為 `applies=false`；
JIRA-Epic-backed 的產品 runtime / UI task 多為 `applies=true`。判定本身依 task 性質，不依
source type。

## JIRA-Epic-Backed Source Field Population (DP-269)

當 refinement-owned source 是 **JIRA-Epic-backed**（`source.type=jira`，container 在
`docs-manager/src/content/docs/specs/companies/{company}/{EPIC}/`）時，除了上方所有 source
共用的 per-task body 欄位外，Phase 1 / Phase 2 收斂 `refinement.json` 還必須額外 populate
下列 **jira-only identity 欄位**，讓 breakdown initial-create 的
`derive-task-md-from-refinement-json.sh` 能注入真實 task identity / Repo / Base branch
（schema 定義見 `references/refinement-artifact.md` § Strong-Bound Machine Contract）：

- **`source.repo`**：產品 repo slug。由 company context 解析 ——
  `{company}/polaris-config/{project}/` 的 `{project}` 目錄名即產品 repo slug。
- **`source.base_branch`**：產品 base branch（如 `develop`）。**由
  `{company}/polaris-config/{project}/handbook/config.yaml` 新增的 `base_branch` 欄位
  讀取**（與既有 `runtime` / `test` block 同層；屬 product-repo-local-owned config
  carve-out，不需 framework configuration-surface DP 治理）。
- **`tasks[].jira_key`**：每筆 task 的真實子單 key（string）或 `null`（尚未建子單）。
  derive jira mode 對 `null` fail-closed（要求先 populate，無 N/A fallback）。

### Base Branch Resolution（不得硬猜 — EC3）

解析 `source.base_branch` 時：

1. 讀 `{company}/polaris-config/{project}/handbook/config.yaml` 的 `base_branch` 欄位。
2. **有對應 entry** → 寫入 `source.base_branch`。
3. **無對應 entry / config 缺 `base_branch` 欄位** → **fail-stop**，提示使用者在
   `{company}/polaris-config/{project}/handbook/config.yaml` 補 `base_branch`。**不得**
   硬猜 `develop` / `main`（base branch 是 per-repo 的產品事實，猜測會 silently 注入錯誤
   base branch 到 task.md）。

### V 驗收單與 jira_key（D3a）

JIRA-Epic-backed source 的 V 驗收單 = 在對應子單專案（如 `EXAMPLE` 的子單專案
`EXAMPLESUB`）開一張真實「驗收子單」當 V key，對齊既有 JIRA 可見追蹤慣例。建 JIRA child
屬 external write，由
refinement / breakdown 階段向使用者取得明確 consent 後建立，再 populate `tasks[].jira_key`；
auto-pass 啟動時 task set 已有真實 key，auto-pass 自身不做 `jira_child_write`。

> DP-backed source（`source.type=dp`）**禁止**帶 `source.repo` / `source.base_branch` /
> `tasks[].jira_key`；`validate-refinement-json.sh` 對 dp source 出現任一 jira-only 欄位
> 以 `POLARIS_REFINEMENT_JIRA_ONLY_FIELD` fail-closed（jira-only 鬆綁不外洩到 dp 分支）。

## Step 7 — 定版寫入（一次性）

先完成 `draft_json` → strict `refinement.json` 收斂；draft 不可 LOCK、不可 handoff、
不可 render canonical Markdown。strict JSON 通過後先執行
`scripts/render-refinement-md.sh {source_container}/refinement.json`，再跑下列 gates。

在提示 `/auto-pass {KEY}` 或把 DP status 改為 `LOCKED` 前先跑：

```bash
mise run docs-health -- {source_container}/refinement.md
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

任何 refinement dogfood-evidence 或 specs-bound Markdown 產出，都必須走 specs-bound emit
contract：frontmatter 至少包含 `title`、`description`、`draft: true`、
`sidebar.hidden: true`，producer 對應 `scripts/lib/evidence-producers.json` 的
refinement entry；不得裸寫沒有 Starlight frontmatter 的 `.md` artifact。

Step 7 同時執行 runtime cache residue gate：

```bash
bash scripts/check-runtime-cache-residue.sh --repo . --source-container {source_container}
```

## Framework Contract Change Guard

`refinement` 用於討論 framework contract change（skills、rules、references、validators、
handoff contracts、workflow boundary）時，**proposal 必須落到 DP artifact**，不可只停在
chat：

1. 把 topic resolve 成 ticketless DP source；DP container 不存在時，由
   `scripts/create-design-plan.sh` 建立。
2. 在 `{source_container}/refinement.md` + `refinement.json` 寫入 Goal、Background、
   Decisions、Blind Spots、AC、Implementation Scope（不是只在 chat 列重點）。
3. 跑 `scripts/validate-language-policy.sh --blocking --mode artifact <refinement.md>`。
4. 跑 docs-viewer sidebar sync（`.claude/hooks/specs-sidebar-sync.sh` hook）讓使用者能在 docs-manager preview 讀到。
5. **完成上述後**才向使用者回報 DP path，等指示是否進入 breakdown / engineering。

Why：chat-only proposal 跨 session 容易丟失，且違反「framework contract change 預設走
DP」的 mandatory contract。下游 `breakdown` / engineering 需要 durable plan artifact 才能
建立 task.md、Allowed Files、Verify Command。實例：DP-060（check-pr-approvals token slimming）
原本只在 chat 提案，使用者問「有 dp 嗎」後才補建 container。

## Unsolicited LOCK Prompt Forbidden

Refinement gates 全 PASS、artifact 完成後，**不可**主動：

- 在 chat 提示「DP-NNN 可以 LOCK 並 route 到 breakdown 嗎？」
- 在 AskUserQuestion 提供「LOCK and 進入 breakdown」之類的選項
- 暗示下一步應該做什麼（除非使用者明確問下一步）

正確收尾輸出：陳述狀態（DP container 已建立、artifacts 完成、status 仍 `DISCUSSION`、
gates 全 PASS）+ 已產出 artifact 路徑 → **停下**等使用者下一個明確指示（例如「LOCK」、
「定版」、「開始做」、「breakdown DP-NNN」）。

Why：使用者授權「建立計劃」≠ 授權「跑完 refinement → LOCK → breakdown」。`refinement-
dp-source-mode.md` Step 7 規定的是「使用者說 LOCK 時要跑哪些 gate」，**不是**「gates 跑完
要主動問要不要 LOCK」。AskUserQuestion 只用在「需要使用者拍板 design content 才能繼續寫
artifact」的情境，不用在「artifact 完成後要不要狀態轉換」的情境。

本 rule 適用所有 refinement-owned source（DP / JIRA Epic / Story / Task / ticketless
topic），不只 DP。例外只有 auto-pass amendment mode：amendment 已透過 ledger 取得 consent，
不需要再向使用者發問。

## Skill Workflow Boundary Gate (DP-230 D40)

`refinement` session 開始時必須呼叫 skill-workflow-boundary baseline writer，
讓 refinement-handoff-gate.sh 與 /auto-pass cross-skill transition 能在 handoff 時
deterministic 檢查本 session 是否只動到 refinement-owned scope：

```bash
bash scripts/skill-workflow-boundary-gate.sh --skill refinement --start \
  --source-container "$SOURCE_CONTAINER"
```

`--start` 紀錄 HEAD sha 與 pre-existing dirty files；後續所有 refinement-owned
寫入（`refinement.md`、`refinement.json`、`index.md`、`plan.md`、
`artifacts/**`、`jira-comments/**`、`refinement-inbox/**`）都會在 handoff 時被
`--check` 比對。任何 owning scope 之外的新增/修改（包含 generated targets）會讓
gate exit 1 並輸出 `POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:refinement`。

`POLARIS_LANGUAGE_POLICY_BYPASS` / `POLARIS_SKILL_BOUNDARY_BYPASS` 等 env 不能
silence 這個 gate（AC-NEG16）；違反 boundary 必須改回去或走 scope escalation，
不得用 env 跳過。

## L2 Deterministic Check: post-task-feedback-reflection

完成 write flow 後必須呼叫 `scripts/check-feedback-signals.sh`。

## Post-Task Reflection (required)

見 `post-task-reflection-checkpoint.md`；write 後必跑、不可跳過。
