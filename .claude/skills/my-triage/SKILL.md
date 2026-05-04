---
name: my-triage
description: 個人工作盤點與 zero-input next router；列出 assigned Epics/Bugs/Tasks，整合 cross-session resume signals，協助決定下一步。
metadata:
  author: Polaris
  version: 1.3.0
---

# My Triage

`my-triage` 是個人工作 dashboard 與 zero-input router，用於「下一步 / 繼續 / 手上有什麼」
這類沒有明確 ticket/topic 的情境。

## Contract

`my-triage` 只讀取並排序個人工作，不施工、不估點、不改 JIRA status。若使用者說「繼續
DP-015」或「繼續 PROJ-123」這類帶明確 topic 的句子，不攔截；交給 active skill /
cross-session continuity 解析。

## Reference Loading

| Situation | Load |
|---|---|
| Any run | `my-triage-resume-flow.md`, `workspace-config-reader.md`, `shared-defaults.md`, `jira-story-points.md` |
| Dashboard scan | `my-triage-dashboard-flow.md`, `stale-approval-detection.md` |
| State write / standup handoff | `my-triage-state-flow.md`, `session-timeline.md` |
| Large GitHub scan | `sub-agent-roles.md` Completion Envelope |

## Flow

1. Resolve workspace config and current git context.
2. Run resume scan first: branch-ticket, Hot memory, recent checkpoints, WIP branches.
3. Fetch assigned active Epics, Bugs, and orphan Tasks/Stories.
4. Verify status category and remove completed/status-mismatched items.
5. Add GitHub progress for In Development items.
6. 排成 resume candidates、Bugs、In Development、priority-based todo groups。
7. Render dashboard and write compact `.daily-triage.json` in the same pass.
8. Recommend next routes: `engineering`, `breakdown`, `check-pr-approvals`,
   `sprint-planning`, or explicit topic resume.

## Hard Rules

- Cross-session resume candidates appear before current-day work.
- Bug group appears before normal Epic/Task work, except resume candidates.
- If today's triage state already exists, ask before rescanning.
- Do not scan child Tasks/Stories already covered by an Epic.
- Do not repeat Session Start Fast Check file lists; cite them briefly.
- Do not auto-modify JIRA or GitHub.
- 大型 GitHub scans 可使用 sub-agents，但必須 read-only，並回傳 Completion Envelope。

## Completion

Return active counts, excluded status-mismatch items, ranked dashboard, suggested next action,
triage state write status, and any blocked data sources.

## Post-Task Reflection (required)

Execute `post-task-reflection-checkpoint.md` before reporting completion.
