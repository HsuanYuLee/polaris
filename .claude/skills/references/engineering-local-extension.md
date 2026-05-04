---
title: "Engineering Local Extension"
description: "engineering local delivery extension boundary：合法條件、handoff package、extension completion 與 closeout rules。"
---

# Local Extension

Local delivery extension 是 workspace-local policy，不是 portable shortcut。Product ticket
預設不可用。

## Legal Conditions

三者都成立才可用：

1. authoritative work order 是 local policy 允許的類型。
2. local skill / rule / config 明確宣告 extension id、repo、權限邊界、證據、rollback /
   failure rules。
3. 使用者明確要求，或 DP plan / local policy 明確宣告終態由 extension 接手。

任一不成立，走一般 first-cut / revision。

## Execution Rules

前半段完全同 first-cut：resolver、handbook gate、branch/worktree、TDD、ci-local、verify、
VR、base freshness 都必須執行。Extension 不得降低 gate。

若 local policy 要求 workspace PR，engineering 必須先建立 / 更新真實 PR，並寫回
`deliverable.pr_url`。若 local policy 明確允許不建 PR，不得寫 fake PR URL；extension
必須提供自己的 completion evidence。

## Handoff Package

local gates 全通過後，交給 extension 前整理：

```text
role: local-extension
extension_id: <local extension id>
task_md: <absolute task.md path>
task_id: <identity.work_item_id>
repo: <repo root>
workspace_pr_url: <if required>
task_branch: <current branch>
task_head_sha: <git rev-parse HEAD>
evidence:
  ci_local: <Layer A evidence or N/A>
  verify: <Layer B durable evidence>
  vr: <Layer C evidence or N/A>
delivery_intent:
  endpoint: local_extension
  summary: <human summary>
  changed_files: <intentional files only>
```

## Completion

Completion = engineering evidence gates AND local extension final verification。

Extension 成功後依 local policy 寫 `extension_deliverable` metadata。若 local policy 宣告
closeout helper（例如 framework release），必須呼叫該 helper；不得只手動寫 metadata 後
宣稱完成。

Generic fallback 只有 local policy 沒提供 helper 時可用：

```bash
bash "${POLARIS_ROOT}/scripts/write-extension-deliverable.sh" "<task.md>" ...
bash "${POLARIS_ROOT}/scripts/check-local-extension-completion.sh" --repo "$(git rev-parse --show-toplevel)" --task-md "<task.md>" --task-id "{task_id}" --extension-id "{extension_id}"
```

Extension final verification 後才可 cleanup worktree：

```bash
bash "${POLARIS_ROOT}/scripts/engineering-clean-worktree.sh" --task-md "<task.md>" --repo "$(git rev-parse --show-toplevel)"
```
