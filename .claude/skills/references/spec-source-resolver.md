---
title: "Shared Spec Source Resolver"
description: "JIRA、DP、topic 與 artifact path 的共用 source resolution 與 folder-native write contract。"
---

# Spec Source Resolver

JIRA-backed 與 ticketless Polaris pipeline 共用的 source resolution contract。

## Goal

`refinement`、`breakdown`、`engineering`、`verify-AC` 不應各自發明 work source 解析方式。本 reference 定義共用 source model，涵蓋使用者提供 JIRA key、design-plan ID、直接 artifact path，或新的 ticketless topic。

核心規則：

```text
source resolver 決定 work 住在哪裡
pipeline stage 決定要做什麼
JIRA sync 只是 optional side effect
```

## Path Variables

```text
{workspace_root}     Polaris workspace root
{company}            從 workspace config / JIRA project mapping 解析出的 active company key
{specs_root}         {workspace_root}/docs-manager/src/content/docs/specs
{company_specs_dir}  {specs_root}/companies/{company}
```

## Active And Archive Namespaces

預設 source resolution 只看 active namespace。開始或續做 work 的 skills 必須掃描這些 active containers：

```text
{specs_root}/design-plans/DP-NNN-{slug}/
{specs_root}/companies/{company}/{TICKET}/
```

完成或放棄的 containers 可以移到 archive：

```text
{specs_root}/design-plans/archive/DP-NNN-{slug}/
{specs_root}/companies/{company}/archive/{TICKET}/
```

規則：

- active lookup 必須 prune `archive/`，避免歷史 tasks 被解析成目前 work
- 直接給 archived artifact path 時，可以做 read-only audit
- 大範圍 historical lookup 必須使用明確模式，例如 `--include-archive`
- 同一個 DP 或 ticket container 不可同時存在於 active 與 archive namespaces
- docs-manager 直接讀 physical `docs-manager/src/content/docs/specs` tree，因此 archived content 仍從 Starlight routes `specs/design-plans/archive/...` 或 `specs/companies/{company}/archive/...` 瀏覽

## Source Types

| Type | Input examples | Canonical container | Primary owner |
|------|----------------|---------------------|---------------|
| `jira` | `EPIC-478`, `TASK-3711` | `{company_specs_dir}/{TICKET}/` 加上 JIRA issue | `refinement` / `breakdown` |
| `dp` | `DP-045`, `docs-manager/src/content/docs/specs/design-plans/DP-045-*/index.md`, legacy `plan.md` | `{specs_root}/design-plans/DP-NNN-{slug}/` | `refinement` |
| `topic` | `討論 CI local blocker`, `refinement "想重構 skill routing"` | 新分配的 DP folder | `refinement` |
| `artifact_path` | direct `refinement.json`, `refinement.md`, `tasks/T1.md`, `tasks/T1/index.md` path | 最近的 containing specs folder | stage-specific consumer |

## DP Locator

當 input 包含 `DP-NNN` 時，必須定位到唯一 folder：

```text
{specs_root}/design-plans/DP-NNN-*/
```

規則：

- zero matches：fail loud，不可默默建立同號 replacement DP
- multiple matches：fail loud，由使用者或 maintainer 解 duplicate
- one match：該 folder 就是 canonical DP root
- `refinement DP-NNN` 與 `breakdown DP-NNN` 必須有 primary DP document：`index.md` 優先，legacy `plan.md` fallback
- `tasks/T{n}.md` / `tasks/T{n}/index.md` 在 `breakdown` 產出 work orders 前是 optional

Canonical DP primary document path：

```text
{specs_root}/design-plans/DP-NNN-{slug}/index.md
```

Legacy DP containers may still use:

```text
{specs_root}/design-plans/DP-NNN-{slug}/plan.md
```

## Topic To DP Creation

當 input 是 ticketless topic 而不是既有 `DP-NNN`：

1. 呼叫 `scripts/create-design-plan.sh "<topic>"`。
2. command 掃描 active + archive parent `index.md` 與 legacy `plan.md`，分配全域最大 N + 1。
3. command 建立 `{specs_root}/design-plans/DP-NNN-{topic-slug}/index.md`。
4. command 寫入完整 metadata：`title`、`description`、`topic`、`created`、`status`、`priority`、`sidebar`。
5. command 跑 Starlight / language / route-safe authoring gates，通過後 route 到 `refinement` ticketless mode。

topic slug 採 kebab-case，描述 durable subject，不描述當下 implementation step。

因為 docs-manager 使用 Starlight `docsLoader()` + `docsSchema()` 直接讀取
`{specs_root}`，所有 specs markdown 都必須有 `title` frontmatter。新 producer
建立 `plan.md`、`refinement.md` 或 task work order 時，必須在 source file 寫入
stable title；不可依賴額外 loader 或 generated mirror 補齊 metadata。

DP number allocation 永遠包含 active + archive namespaces，且同時看 `index.md` 與 legacy
`plan.md`。任何 producer 不可只掃描 active `design-plans/DP-*`，也不可在 validator 回報
duplicate 時建立同號 replacement DP。

## Artifact Paths

JIRA-backed work：

```text
{company_specs_dir}/{TICKET}/refinement.md
{company_specs_dir}/{TICKET}/refinement.json
{company_specs_dir}/{TICKET}/tasks/T{n}.md
{company_specs_dir}/{TICKET}/tasks/T{n}/index.md
```

DP-backed ticketless work：

```text
{specs_root}/design-plans/DP-NNN-{slug}/index.md
{specs_root}/design-plans/DP-NNN-{slug}/plan.md
{specs_root}/design-plans/DP-NNN-{slug}/refinement.md
{specs_root}/design-plans/DP-NNN-{slug}/refinement.json
{specs_root}/design-plans/DP-NNN-{slug}/tasks/T{n}.md
{specs_root}/design-plans/DP-NNN-{slug}/tasks/T{n}/index.md
```

`refinement.json` 是 machine-readable artifact。`index.md` 是 folder-native durable decision record，
legacy DP 可能仍使用 `plan.md`。兩者可以共享資訊，但 consumer 需要 structured fields 時應優先讀
`refinement.json`。

## Folder-Native Task Lookup

過渡期 reader 必須 dual-read legacy 與 folder-native task source。給定 task key `T1` / `V1` 時，lookup order 是：

```text
tasks/{key}.md
tasks/{key}/index.md
tasks/pr-release/{key}.md
tasks/pr-release/{key}/index.md
```

規則：

- active lookup 預設 prune `archive/`，除非使用者明確 `--include-archive`
- 同一 key 若同時存在 legacy 與 folder-native source，必須 fail loud
- 同一 key 若同時存在 active 與 `pr-release/`，必須 fail loud
- `pr-release/` 是 completed task fallback，不是 archive namespace；reader 可讀，validator 不重驗其 schema
- `index.md` 的 task kind 由 parent folder basename 判斷，例如 `tasks/V1/index.md` 是 V mode

## Status Rules

| Status | Meaning | Allowed next stage |
|--------|---------|--------------------|
| `SEEDED` | DP shell 已存在，通常來自 learning handoff | 只能進 `refinement` |
| `DISCUSSION` | requirements / decisions 仍在變動 | 只能進 `refinement` |
| `LOCKED` | source 已穩定到可以 breakdown | `breakdown` |
| `IMPLEMENTED` | work 已完成 | read-only / audit |
| `ABANDONED` | 決策是不繼續 | read-only，除非使用者明確 revive |

`breakdown DP-NNN` 必須要求 `LOCKED`，除非使用者明確要求 advisory review。若 source 仍是 `DISCUSSION`，route 回 `refinement DP-NNN`。

## Archive Sweep

Terminal specs 可以逐一 archive，也可以 sweep：

```bash
scripts/archive-spec.sh DP-NNN
scripts/archive-spec.sh TICKET-123
scripts/archive-spec.sh --sweep --dry-run
scripts/archive-spec.sh --sweep --apply
```

Sweep 使用與 source resolution 相同的 namespace rules：

- DP container status 來自 `plan.md`
- JIRA/company container status 來自 `refinement.md`，fallback 到 `plan.md`
- 只有 `IMPLEMENTED` 與 `ABANDONED` 是 archive candidates
- non-terminal 或 missing status containers 留在 active，並回報為 `skip`
- destination conflict 必須在任何 apply move 前 fail

Sweep apply 後，docs-manager 會直接讀 moved canonical specs。Live review 或 static/search verification：

```bash
scripts/polaris-toolchain.sh run docs.viewer.dev
scripts/polaris-toolchain.sh run docs.viewer.doctor
```

## Folder-Native Migration

Legacy specs 轉 folder-native layout 必須使用 deterministic migration helper，不可手動批次搬檔：

```bash
bash scripts/migrate-spec-container-layout.sh --dry-run
bash scripts/migrate-spec-container-layout.sh --apply
```

預設只處理 active namespace；archive 需要明確 opt-in：

```bash
bash scripts/migrate-spec-container-layout.sh --apply --include-archive
```

Migration rules：

- DP `plan.md` 轉為 `index.md`。
- company spec `refinement.md` 轉為 `index.md`。
- task work order `tasks/Tn.md` / `tasks/Vn.md` 轉為 `tasks/Tn/index.md` / `tasks/Vn/index.md`。
- `tasks/pr-release/Tn.md` 同樣可轉為 folder-native completed task。
- 任何 legacy 與 folder-native target collision 必須 blocked，不可覆寫。
- task file 移入子資料夾時，relative Markdown links 需改寫到新的相對層級。
- `--cleanup-legacy-bundles` 只有在 bundle 已有 `assets/`、`links.json`、`publication-manifest.json`
  與 `verify-report.md` 時可移除 legacy copied files；缺任一條件必須 blocked。

## Section Ownership

這個 section ownership rule 防止 `refinement` 與 `breakdown` 競爭同一份 DP content。

| Section | Owner | Notes |
|---------|-------|-------|
| frontmatter `title`, `topic`, `created`, `status`, `locked_at` | `refinement` | `breakdown` 只讀，不負責 lock primary DP document |
| `## Goal` | `refinement` | requirement intent |
| `## Background` | `refinement` | context 與 current state |
| `## Decisions` | `refinement` | selected direction 與 rationale |
| `## Blind Spots` | `refinement` | risks 與 mitigations |
| `## Acceptance Criteria` | `refinement` | 未來 `verify-AC` 使用的 ticketless AC |
| `## Technical Approach` / `## 技術方案` | `refinement` | implementation direction，不是 task slicing |
| `## Implementation Checklist` | `breakdown` after LOCKED | 可 map 到 `tasks/T{n}.md`；LOCKED 前 `refinement` 可先 draft candidates |
| `## Work Orders` / `## Task Mapping` | `breakdown` | 記錄 generated task files 與 dependencies |
| `## Implementation Notes` | stage-specific | 只 append current stage 的 facts |

如果 `breakdown` 發現 technical decision 錯誤或不完整，必須 route 回 `refinement`；不可默默 rewrite `Decisions` 或 `Technical Approach`。

## Stage Routing

| Input | Stage command | Behavior |
|-------|---------------|----------|
| `refinement DP-NNN` | refinement | locate DP，繼續 discussion / produce artifact |
| `refinement "topic"` | refinement | allocate DP，開始 ticketless refinement |
| `breakdown DP-NNN` | breakdown | 要求 LOCKED DP，consume artifact / plan，create tasks |
| `engineering DP-NNN-Tn` | engineering | 透過 DP-047 bridge resolve 到 DP-backed task.md |
| `verify-AC DP-NNN` | verify-AC | 未來 ticketless verification mode |

## Compatibility

Legacy `design-plan` triggers，例如 `想討論`、`怎麼設計`、`ADR`、`design plan`、`/design-plan DP-NNN`，都是 `refinement` ticketless mode 的 aliases。`design-plan` skill 已移除，不再保留 separate shim pipeline。

Legacy top-level `{workspace_root}/specs` 已由 DP-066 sunset。Runtime 與 lifecycle scripts 必須使用 `scripts/resolve-specs-root.sh` 或 `scripts/lib/specs-root.sh`，不可 hard-code 任一 root。
