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
它屬於 `mixed reader / next-step orchestrator`：workspace config 與 resume signals 只用來
決定 dashboard scope、排序、與 route suggestion。`my-triage` 可以推薦下一步，但推薦不等於
workflow transition、verification result、release readiness、或 author-side completion
authority。

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
7. 盤點單的位置漂移（report-only）：跑
   `bash .claude/skills/verify-ac/scripts/archive-delivered-issues.sh --check`。它比對
   `issues/` 底下每一張單的位置與 `.spine/loop-state.json` 的 `status`，對不上就列出來。
   把結果併入 dashboard，讓使用者看到已收斂卻還擋在活躍區、或還沒收斂卻躺在 archive 的單。
   沒有輪次狀態的目錄不參與判定，但它會把數量印出來——照樣轉述，不要當成已檢查過。
8. Render dashboard and write compact `.daily-triage.json` in the same pass.
9. Recommend next routes：會改變行為的走 `refinement`（不用立案的直接做），另有
   `check-pr-approvals`、`sprint-planning`，或 explicit topic resume。位置漂移**不要在這裡
   動手搬**——搬是 `spine-loop-state.sh record` 的事，這裡只報。想讓一張單離開待辦清單，
   讓它收斂，不要搬它。

## Hard Rules

- Cross-session resume candidates appear before current-day work.
- Bug group appears before normal Epic/Task work, except resume candidates.
- If today's triage state already exists, ask before rescanning.
- Do not scan child Tasks/Stories already covered by an Epic.
- Do not repeat Session Start Fast Check file lists; cite them briefly.
- Do not auto-modify JIRA or GitHub.
- `.daily-triage.json` 是 local planning state，不是 shared workflow state；不得把其中的
  rank / progress 直接包裝成 `mergeable_ready`、`release_eligible`、`release_completed`、
  或其他 deterministic gate 結果。
- 大型 GitHub scans 可使用 sub-agents，但必須 read-only，並回傳 Completion Envelope。

## Completion

Return active counts, excluded status-mismatch items, ranked dashboard, suggested next action,
triage state write status, and any blocked data sources.

## Post-Task Reflection (required)

Execute `post-task-reflection-checkpoint.md` before reporting completion.
