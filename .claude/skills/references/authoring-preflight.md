---
title: "Authoring Preflight"
description: "所有 skill 在產生 user-facing / downstream-facing prose、specs markdown、refinement artifact 或 task.md 前的共用 authoring 規格入口。"
---

# Producer Authoring Preflight

本 reference 是 producer-side preflight：在 skill 動筆產生 durable artifact、external write
body、preview 或 handoff 文字之前先讀。Validator 仍是 blocking source of enforcement；本檔
把常見 gate 規則前移，避免最後一刻才被 script 退回重寫。

## 1. Language First

所有 skill 先解析 root `workspace-config.yaml` 的 `language`，再開始撰寫 user-facing 或
downstream-facing prose。這是 authoring default，不是送出前翻譯步驟。

規則：

- 若 root `language` 存在，skill 自己新增的自然語言 prose 必須直接使用該語言起稿。
- `language` 缺失時，不可宣稱已 enforce；需要對人或下游公開的輸出要先 fail closed 或明確
  標示 `language_unset` blocker。
- 原文引用、code、identifier、CLI、path、API name、PR template heading、log/error transcript
  可保留原文；producer 自己的說明 prose 仍依 workspace language。
- 外部寫入與 durable artifacts 送出前仍必須跑 `workspace-language-policy.md` 定義的 gate。

Preflight command：

```bash
bash scripts/validate-language-policy.sh --blocking --mode artifact <artifact-or-body.md>
```

External write 可用 wrapper：

```bash
bash scripts/polaris-external-write-gate.sh \
  --surface <jira-comment|slack-message|confluence-page|github-review|artifact> \
  --body-file <final-body.md>
```

## 2. Specs Markdown Shape

任何寫入 `docs-manager/src/content/docs/specs/**/*.md` 的 producer，在產文前先套用
`starlight-authoring-contract.md`：

- YAML frontmatter 必須有 stable `title` 與 `description`。
- body 第一個 visible heading 不重複 frontmatter `title`。
- fenced code block 標明 language。
- internal links 指向 canonical source path，不指向 `docs-manager/dist`。
- raw evidence 放 appendix 或 artifact path；主文保留摘要、決策與 handoff 資訊。

Preflight / post-write command：

```bash
bash scripts/validate-starlight-authoring.sh check <specs-md-or-container>
```

DP primary document 另跑：

```bash
bash scripts/validate-dp-plan-authoring.sh <source_container>/index.md
```

## 3. Refinement Artifact Shape

`refinement` 產生 `refinement.md` / `refinement.json` 前，先確認：

- `refinement.md` 使用 workspace language，且只放 downstream implementation information。
- AC 保留 `功能 AC`、`非功能 AC`、`負面 AC` 與每條 `驗證方式`；不相關項目明確寫 `N/A`
  或原因。
- `refinement.json` 有 current `source`、`tier`、`modules`、`dependencies`、`edge_cases`、
  `acceptance_criteria[]`、`downstream`。
- `acceptance_criteria[]` 每條都有 `category` 與 `verification.method/detail`。
- DP-backed source 的 `predecessor_audit` 即使沒有 predecessor 也要寫 `[]`。
- external write drafts、research snapshots、manual validation output 要歸檔到 source
  container 或刪除 temporary body file。

Handoff gate：

```bash
bash scripts/refinement-handoff-gate.sh <source_container>/refinement.md
bash scripts/validate-language-policy.sh --blocking --mode artifact <source_container>/refinement.md
bash scripts/validate-starlight-authoring.sh check <source_container>/refinement.md
```

## 4. Task.md Readiness Shape

`breakdown` 產生 `tasks/Tn/index.md` 或 `tasks/Vn/index.md` 前，先確認 task skeleton 已符合
`task-md-schema.md` 與 `breakdown-task-packaging.md`：

- 新 task 預設 folder-native `tasks/Tn/index.md` / `tasks/Vn/index.md`。
- frontmatter 有 `title` / `description`；`depends_on` 最多一個 direct predecessor。
- `Allowed Files` 是 machine-matchable repo-root path / glob，不是自然語言描述。
- `Scope Trace Matrix` 每個 Goal / AC trace 到 owning files、surface/boundary、tests。
- `Scope Trace Matrix` 的 owning files 必須被 `Allowed Files` 覆蓋。
- `Gate Closure Matrix` 至少有 scope / test / verify / ci-local，且每列有 pass condition 與
  owner / decision。
- `Behavior Contract` 必須可判斷 `applies=true/false`；`applies=true` 時不可留
  `unknown/default`，必須決定 `parity` / `visual_target` / `pm_flow` / `hybrid`。
- `Test Environment` 與 `Test Command` 不可互相矛盾；test/build runner 不可標成
  `Level: static` 且 `Env bootstrap command: N/A`。
- package graph / dependency / catalog 改動要納入 lockfile，或明確說明 repo 無 lockfile /
  不觸及 package graph。
- Nuxt / Vitest 類 command 需清掉 known inherited debug env，例如 `env -u DEBUG ...`。
- library migration 的 Verify Command 不可用 broad substring grep 誤掃跨 scope API name、
  文件註解或後續 task 的相容介面。

Readiness gate：

```bash
bash scripts/validate-task-md.sh <task_path>
bash scripts/validate-task-md-deps.sh <tasks_dir>
bash scripts/validate-breakdown-ready.sh <task_path_or_tasks_dir>
bash scripts/validate-language-policy.sh --blocking --mode artifact <task_path>
bash scripts/validate-starlight-authoring.sh check <task_path>
```

## 5. Fail-Stop Rule

Preflight 發現無法判斷的 authoring input 時，不要用 placeholder 繼續產 READY artifact。

常見 route：

- 缺語言設定：回 onboard / workspace config 修正。
- 缺 AC verification method、behavior source of truth、surface boundary：回 refinement 補決策。
- 缺 Allowed Files、test env、verify command、gate owner：breakdown 內先修 skeleton，不 handoff
  engineering。
- validator fail：修 producer/template 輸出後重跑；不可把 gate fail 的文字送到下游或外部系統。
