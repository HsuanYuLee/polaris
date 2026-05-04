---
name: bug-triage
description: >
  Bug diagnostic skill: root cause analysis and RD confirmation for Bug tickets.
  Use when the user wants to triage, analyze, or diagnose a Bug ticket — before planning starts.
  Trigger: '修 bug', 'fix bug', '分析 bug', 'triage bug', 'bug 分析', '修這張 bug',
  'help me fix', '幫我修正', '開始修正', '修正這張', 'fix this ticket' (when issue type is Bug),
  'debug', '找 bug', '為什麼壞了', 'why is this failing', 'investigate', '查問題',
  '這個怎麼回事', 'root cause', '根因', '排查'.
  NOT for: PR review fixes (use engineering revision mode), already-diagnosed bugs with root cause confirmed (use breakdown → engineering).
  This skill handles DIAGNOSIS only — estimation, test plan, QA challenge, and design doc are delegated to breakdown.
metadata:
  author: Polaris
  version: 2.3.0
---

# Bug Triage — 診斷層

Bug ticket 的診斷入口：讀票、定位 project、找 root cause、讓 RD 確認，最後把已確認分析寫回
JIRA，交給 `breakdown` 派工。

## Contract

`bug-triage` 只做 diagnosis。不估點、不拆 task、不寫 Design Doc、不建 branch、不修 code、
不開 PR。這些分別屬於 `breakdown` 與 `engineering`。

若 ticket 不是 Bug，停止並路由：Story/Task 走 `breakdown` 或 `engineering`，Epic 走
`refinement` 再 `breakdown`。若 JIRA 已有 `[ROOT_CAUSE]`，詢問要重新分析或直接派工。

## Reference Loading

| Situation | Load |
|---|---|
| Any bug | `bug-triage-entry-flow.md`, `project-mapping.md`, `workspace-config-reader.md` |
| AC verification failure bug | `bug-triage-acfail-flow.md`, `pipeline-handoff.md`, `handoff-artifact.md`, `worktree-dispatch-paths.md` |
| Root cause analysis | `bug-triage-root-cause-flow.md`, `explore-pattern.md`, `repo-handbook.md`, `planning-worktree-isolation.md` as needed |
| Confirmation and JIRA write | `bug-triage-confirm-handoff-flow.md`, `workspace-language-policy.md`, `external-write-gate.md` |

Explorer sub-agent dispatch 必須注入 `sub-agent-roles.md` 的 Completion Envelope。Full path 與
AC-FAIL path 的 raw evidence 寫入 handoff artifact，供 downstream engineering on-demand 讀取。

## Flow

1. Parse ticket key，讀 JIRA ticket，確認 issue type。
2. 依 `project-mapping.md` 找 project 與 handbook。
3. 若 ticket 來自 verify-AC `[VERIFICATION_FAIL]`，走 AC-FAIL scoped path。
4. 否則判斷 fast path；明顯單檔小修可 inline analysis，其他走 Explorer full path。
5. 產出 Root Cause / Impact / Proposed Fix。
6. 向 RD 呈現分析並 hard stop；使用者確認前不得寫 JIRA 或 handoff。
7. 使用者修正時，最多 re-analyze 兩輪；仍不清楚則升級為人工 code confirmation。
8. 確認後，將 `[ROOT_CAUSE]` / `[IMPACT]` / `[PROPOSED_FIX]` 寫成 JIRA comment。
9. 處理 handbook observations。
10. 回報 `breakdown {TICKET}` 或 `做 {TICKET}` 下一步。

## Write Rules

- JIRA diagnostic comment 是 external write，送出前必須通過 `workspace-language-policy.md`
  或 external write gate。
- Handbook gap/stale updates 依 `explore-pattern.md`，只寫 workspace-owned handbook source。
- Bug-triage 不使用 blame 或 author attribution 決定誰修；assignee 是運維層，不是診斷輸入。

## Completion

輸出 ticket、root cause confirmed status、JIRA comment status、proposed fix scope、
evidence artifact path（fast path 可為 none）、next command。

## Post-Task Reflection (required)

Execute `post-task-reflection-checkpoint.md` before reporting completion.
