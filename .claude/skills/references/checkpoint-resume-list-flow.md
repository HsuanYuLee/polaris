---
title: "Checkpoint Resume List Flow"
description: "checkpoint resume/list mode 的 timeline query、checkpoint selection、branch verification、context restore 與 output table 格式。"
---

# Checkpoint Resume/List Contract

這份 reference 負責 checkpoint resume 與 list modes。

## Resume Query

讀最近 checkpoints：

```bash
POLARIS_WORKSPACE_ROOT={workspace_root} \
  {base_dir}/scripts/polaris-timeline.sh checkpoints --last 5
```

若使用者指定 timestamp 或 index，使用指定 checkpoint；否則使用最新 checkpoint。

## Restore Context

從 checkpoint note 解析：

- branch
- ticket
- phase
- next action

有 ticket 時讀取目前 JIRA status；讀不到時標 `unknown`，不阻塞 resume。

## Branch Verification

確認 checkpoint branch 仍存在：

```bash
git branch --list "{branch}"
```

再讀 current branch：

```bash
git branch --show-current
```

若 current branch 不同，只詢問是否切換；不要自動切換。

## Resume Output

回報：

- checkpoint timestamp
- branch
- ticket
- JIRA status when available
- next action

結尾提示使用者可說 `next` 或描述下一步。

## List Query

列出最近 checkpoints：

```bash
POLARIS_WORKSPACE_ROOT={workspace_root} \
  {base_dir}/scripts/polaris-timeline.sh checkpoints --last 10
```

輸出欄位：

- index
- time
- branch
- ticket
- note
