---
title: "Breakdown DP Intake Flow"
description: "breakdown DP-backed intake：消費 locked DP refinement artifact，產出 DP task work orders，不寫 JIRA。"
---

# DP Intake Flow

## Resolve DP Source

依 `spec-source-resolver.md` 定位唯一 DP folder：

```text
docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/index.md
docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/plan.md (legacy)
docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/refinement.json
```

Hard rules：

- `DP-NNN` 必須唯一 match。
- primary DP document 必須存在；`index.md` 優先，legacy `plan.md` fallback。
- primary DP document frontmatter `status` 必須是 `LOCKED`。
- `status: DISCUSSION` 時停止，提示先跑 `refinement DP-NNN`。
- 新 DP 缺 `refinement.json` 時停止並 route back to refinement；legacy DP 只有在使用者
  明確確認後才允許 minimal intake，preview 必須標示 artifact 缺失。

## Read Without Rewriting Decisions

讀 primary DP document 的 Goal / Decisions / Blind Spots / Acceptance Criteria / Technical
Approach，以及 `refinement.json` 的 source / modules / dependencies / edge cases /
acceptance criteria / downstream breakdown hints。

Ownership：

- refinement owns Goal / Background / Decisions / Blind Spots / AC / Technical Approach。
- breakdown owns Implementation Checklist finalization、Work Orders / Task Mapping、
  `tasks/T{n}.md`。

Decisions 或 Technical Approach 不足時，不補寫；route back to refinement。

## Split Work Orders

依 `breakdown-planning-flow.md` 的拆解與 constructability 原則產 preview，但輸出是
DP-backed tasks，不是 JIRA sub-tasks。新產物預設 folder-native：

```text
docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/tasks/T1/index.md
docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/tasks/T2/index.md
```

Task identity 使用 `DP-NNN-T1`；branch 使用 `task/DP-NNN-T1-{slug}`。

Task schema 依 `task-md-schema.md` implementation schema：

- `Task JIRA key` = pseudo-task ID。
- `Parent Epic` = source DP。
- `Test sub-tasks` = `N/A - framework work order`。
- `AC 驗收單` = `N/A - framework work order`。

## Confirmation And Writes

Preview 必須包含 summary / points / allowed files / depends_on chain / source DP path /
artifact gap / route-back issue。使用者確認前不可寫 task.md、不可更新 DP plan。

確認後：

```bash
scripts/validate-task-md.sh {dp_folder}/tasks/T{n}/index.md
scripts/validate-task-md-deps.sh {dp_folder}/tasks/
```

全部 pass 後，更新 primary DP document Implementation Checklist / Work Orders linkage。
Validator fail 時修 artifact，不 handoff engineering。

Handoff 提示：

```text
做 DP-NNN-T1
```
