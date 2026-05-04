---
title: "Checkpoint Save Flow"
description: "checkpoint save mode 的狀態收集、checkpoint note、timeline checkpoint/session_summary 寫入與使用者確認格式。"
---

# Checkpoint Save Contract

這份 reference 負責 checkpoint save mode。

## Gather State

並行收集：

- git branch：`git branch --show-current`
- git status：`git status --short` 前 20 行
- ticket：從 branch name 或 active todo context 擷取
- todo list：目前 items 與 status
- recent timeline：`polaris-timeline.sh query --last 5`

Workspace root 是目前工作目錄的 git root。Polaris project dir slug 依
`polaris-project-dir.md`。

## Checkpoint Note

建立一行 summary：

```text
branch:{branch} ticket:{ticket} phase:{current_phase} next:{next_action}
```

缺值保留 `unknown`，不要猜。

## Timeline Writes

先 append `checkpoint` event：

```bash
POLARIS_WORKSPACE_ROOT={workspace_root} \
  {base_dir}/scripts/polaris-timeline.sh append \
  --event checkpoint \
  --branch "{branch}" \
  --ticket "{ticket}" \
  --company "{company}" \
  --note "{checkpoint_note}"
```

接著 append matching `session_summary` event，讓下一次 resume scan 可讀 narrative line：

```bash
POLARIS_WORKSPACE_ROOT={workspace_root} \
  {base_dir}/scripts/polaris-timeline.sh append \
  --event session_summary \
  --text "checkpoint: {one-line narrative derived from phase+next_action}" \
  --session-id "{session_id}" \
  --field 'branches=["{branch}"]' \
  --field 'tickets=["{ticket}"]'
```

若 session id unknown，可省略 `--session-id`。

## User Confirmation

回報：

- checkpoint saved
- branch
- ticket
- phase
- next action
- resume phrase：`/checkpoint resume`
