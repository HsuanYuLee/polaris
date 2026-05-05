---
title: "Converge Scan Gap Flow"
description: "converge 的 workspace config loading、assigned work scan、Epic child expansion、GitHub PR/feature branch scan、gap classification 與排序規則。"
---

# Converge Scan Gap Contract

這份 reference 負責 converge 的掃描、gap 分類、排序。

## Workspace Config

讀取 `workspace-config-reader.md`。需要：

- `jira.instance`
- `jira.projects`
- `github.org`
- `teams`

缺 config 時使用 `shared-defaults.md` fallback。

## Assigned Work Scan

Global mode 查詢 current user 的 active work：

- Epic
- Bug
- 無 parent / Epic Link 的 Story 或 Task
- status 不在 Done、Closed、Launched、完成
- project 在 configured JIRA projects

Fields 至少包含 summary、status、priority、created、duedate、story points、fixVersions、
issuetype、parent。Story points field 依 `jira-story-points.md` dynamic detection。

Epic-only mode 只掃指定 Epic 與其 child tickets。

## Epic Child Expansion

每個 Epic 展開 assigned child tickets，保留 child summary、status、issuetype、priority、
story points。Child 超過 10 張時，可委派 read-only sub-agent 並行查詢 JIRA / GitHub。

## GitHub State Scan

對 In Development / Code Review ticket，以及 Epic feature branch，讀 PR 狀態：

- CI status
- valid approvals
- changes requested
- unresolved comments
- mergeable
- feature PR existence/state

For PRs with review state, feed PR metadata plus review threads into:

```bash
bash scripts/pr-review-state-classifier.sh \
  --pr-json <gh-pr-view.json> \
  --threads-json <review-threads.json> \
  --disposition <optional-review-thread-disposition.json>
```

Do not route `reviewDecision=CHANGES_REQUESTED` by label alone. The classifier's
`classification` is the source of truth for whether the next action is code
fix, wait, or reviewer handoff.

優先使用 reference scripts：

- `references/scripts/get-pr-status.sh`
- `references/scripts/check-feature-pr.sh`

找不到 PR 時，用 ticket key 搜尋 all-state PR。

## Gap Classification

| Gap Type | Condition | Route |
|---|---|---|
| `NO_ESTIMATE` | SP empty and not Bug | `breakdown` |
| `NO_BREAKDOWN` | Epic has no child tickets | `breakdown` |
| `NOT_STARTED` | todo/open with estimate | `engineering` |
| `CODE_NO_PR` | In Development without open PR | `engineering` |
| `CI_RED` | PR checks failed | `engineering` |
| `CI_PENDING` | PR checks pending | wait / report |
| `CHANGES_REQUESTED` | Classifier says changes requested still has code action | `engineering` |
| `HAS_UNRESOLVED_COMMENTS` | Classifier says active unresolved actionable threads remain | `engineering` |
| `AWAITING_RE_REVIEW` | Classifier says CI green and no active unresolved actionable threads remain, but reviewDecision is still CHANGES_REQUESTED | `check-pr-approvals` |
| `REVIEW_STUCK` | PR open over two days with no valid approval | `check-pr-approvals` |
| `STALE_APPROVAL` | approval predates latest push | `check-pr-approvals` |
| `VERIFICATION_PENDING` | implementation done but verification sub-task not done | `engineering` |
| `NO_FEATURE_PR` | all task PRs merged but feature PR missing | `feature-branch-pr-gate.md` |
| `MERGE_CONFLICT` | PR has merge conflict | report only |
| `WAITING_QA` | waiting for QA | skip |
| `WAITING_RELEASE` | waiting for release / stage | skip |
| `READY` | no convergence gap | no action |

A ticket may have multiple gaps; preserve all evidence.

## Sorting

Sort by convergence distance:

1. Quick wins: `CI_RED`, `CHANGES_REQUESTED`, `HAS_UNRESOLVED_COMMENTS`,
   `CODE_NO_PR`, `NO_FEATURE_PR`
2. Reviewer handoff: `AWAITING_RE_REVIEW`, `REVIEW_STUCK`, `STALE_APPROVAL`
3. Implementation: `NOT_STARTED`, `VERIFICATION_PENDING`
4. Planning: `NO_ESTIMATE`, `NO_BREAKDOWN`
5. Waiting / skipped: `CI_PENDING`, `WAITING_QA`, `WAITING_RELEASE`, `MERGE_CONFLICT`

同組內優先選擇離 review 步數較少、且 RD 可自行推進的 items。
