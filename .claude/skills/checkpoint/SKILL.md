---
name: checkpoint
description: 保存、恢復、列出長 session checkpoint；記錄 branch、ticket、todo、recent activity，方便中斷或 context compression 後接續。
triggers:
  - "checkpoint"
  - "存檔"
  - "save checkpoint"
  - "resume"
  - "恢復"
  - "list checkpoints"
  - "列出存檔"
version: 1.2.0
---

# Checkpoint

`checkpoint` 保存、恢復、列出長 session 的工作狀態，讓 context compression 或換 session
後能接回 branch、ticket、phase、next action。

## Contract

Checkpoint 是 session continuity tool，不是 planning、triage、或 implementation skill。
它只寫 workspace memory / timeline 類的 local state，不替下游 skill 決定 scope，也不自動切
branch。

## Mode Routing

| User says | Mode | Reference |
|---|---|---|
| `checkpoint`, `存檔`, `save checkpoint`, `save state` | save | `checkpoint-save-flow.md` |
| `resume`, `恢復`, `resume checkpoint`, `接回去` | resume | `checkpoint-resume-list-flow.md` |
| `list checkpoints`, `列出存檔`, `show checkpoints` | list | `checkpoint-resume-list-flow.md` |

Ambiguous input defaults to save.

## Reference Loading

| Situation | Load |
|---|---|
| Any run | `polaris-project-dir.md`, `session-timeline.md`, `shared-defaults.md` |
| Save | `checkpoint-save-flow.md`, `checkpoint-carry-forward-flow.md` |
| Resume / list | `checkpoint-resume-list-flow.md` |

## Hard Rules

- Save must capture branch, git status summary, ticket, todo disposition, phase, next action,
  and recent timeline context.
- 回報 checkpoint saved 前，carry-forward validation 必須通過。
- Resume verifies the checkpoint branch exists before suggesting a switch.
- 未取得使用者明確指示前，不切 branch、不 stash、不 rewrite memory。
- 不可默默丟掉 pending items；每項都要標記 done、carry-forward、或 dropped。

## Completion

Save 回傳 branch、ticket、phase、next action、resume phrase。Resume 回傳 checkpoint
timestamp、branch、ticket、可取得時的 current status、next action。List 回傳 recent checkpoint
rows。

## Step 2.5 — L2 Deterministic Check: cross-session-carry-forward

Save mode 的 carry-forward gate 由 `checkpoint-carry-forward-flow.md` 執行；必須呼叫
`scripts/check-carry-forward.sh`，通過後才可回報 checkpoint saved。

## Post-Task Reflection (required)

Execute `post-task-reflection-checkpoint.md` before reporting completion.
