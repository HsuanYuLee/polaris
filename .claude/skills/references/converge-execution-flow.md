---
title: "Converge Execution Flow"
description: "converge 的 confirmation gate、downstream skill routing、parallel safety、dirty worktree handling、sub-agent completion envelope 與 blocked handling。"
---

# Converge Execution Contract

這份 reference 負責 converge 在使用者確認後的執行規則。

## Confirmation Gate

Phase 2 必須呈現 plan 並等待使用者確認。允許的調整：

- execute all
- select item numbers
- remove items
- reorder items
- run quick wins only

未確認前不得寫 JIRA、不得發 Slack、不得開 PR、不得執行下游 skill。

## Routing

| Gap Type | Route |
|---|---|
| `NO_BREAKDOWN` | `breakdown` |
| `NO_ESTIMATE` | `breakdown` |
| `NOT_STARTED` | `engineering` |
| `CODE_NO_PR` | `engineering` |
| `CI_RED` | `engineering` |
| `CHANGES_REQUESTED` | `engineering` |
| `HAS_UNRESOLVED_COMMENTS` | `engineering` |
| `AWAITING_RE_REVIEW` | `check-pr-approvals` |
| `REVIEW_STUCK` | `check-pr-approvals` |
| `STALE_APPROVAL` | `check-pr-approvals` |
| `VERIFICATION_PENDING` | `engineering` |
| `NO_FEATURE_PR` | `feature-branch-pr-gate.md` |

`AWAITING_RE_REVIEW` 是 reviewer handoff state，不是 code-fix state。除非後續 classifier
重新把它判回 `CI_RED`、`HAS_UNRESOLVED_COMMENTS`、或 `CHANGES_REQUESTED`，否則不得為此 dispatch
engineering。

下游 skill 必須讀自己的 `SKILL.md` / references，並自行負責 code、JIRA、PR、Slack、
status side effects。

`converge` 的 routing result 只是一張 dispatch plan，不是 mutation warrant。任何：

- JIRA status movement
- verification pass / fail
- PR mergeability / completion
- release eligibility / completion

都仍必須由下游 skill 與 shared deterministic gates 重新判定；不得因 converge plan 已選中某張票，
就把該票視為可直接前進。

## Execution Strategy

預設逐張 sequential execution。只有同時滿足以下條件時，才允許 parallel execution：

- quick-win tier
- not under the same Epic
- not expected to touch the same repo files
- each worker has separate worktree isolation

`NOT_STARTED` tickets run sequentially because implementation scope is unknown.

## Worktree Safety

執行前先檢查 worktree state。若存在 user changes 或 unrelated changes，先回報 dirty scope，
並在 stash、commit、切換 worktree 前取得使用者明確指示。

不得 revert user changes。若既有變更影響目標 ticket，應配合既有變更施工，或停下請使用者指示。

## Sub-Agent Dispatch

Every dispatch must include:

- target ticket and gap evidence
- downstream skill route
- repository / branch context when known
- `sub-agent-roles.md` Completion Envelope
- handbook requirement for code-modifying engineering work
- external write language gate requirement

Sub-agent result artifacts 應保持精簡；需要 raw evidence 時用 link 指向，不內嵌大量內容。

## Blocked Handling

若 sub-agent 回傳 BLOCKED，且 blocker 會影響後續 items，暫停 batch 並回報：

- ticket
- blocker type
- evidence
- downstream owner
- recommended next action
