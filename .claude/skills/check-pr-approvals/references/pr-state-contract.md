---
title: "PR State Contract"
description: "Framework-wide PR state producer and readiness vocabulary contract for Polaris."
---

# PR State Contract

`DP-130` 定義這份文件為 Polaris 所有 PR-related workflows 的單一 authority。
任何 skill、gate、wrapper、reporting surface 若要判斷「能不能改」、「下一步是什麼」、
或「能不能對外說已修好 / 可 review / 可 merge」，都必須 consume 同一套 state model。

## Contract Layers

共有三層，consumer 不得跳過前一層自行推論：

1. `resolve-pr-work-source.sh`
   - 決定 work source、ownership、PR type、authoritative base。
2. `pr-state-snapshot.sh`
   - 產出 machine-readable state snapshot。
3. `pr-action-classifier.sh`
   - 將 snapshot 映射成 action class 與 readiness vocabulary。

## PR Types

| Type | 說明 | Mutable lane |
|---|---|---|
| `direct_task` | task branch 直接基於 `main` / `develop` / `master` 等產品上游 | allowed |
| `stacked_task` | task branch 基於另一條 `task/*`，必須受 `Branch chain` 與 upstream freshness 治理 | allowed |
| `feature` | `feat/*` / feature PR，自成一種可寫 lane，但不可假裝是 task PR | allowed |
| `aggregate_release` | framework 明示 opt-in 的 aggregate release PR；共享 snapshot schema，但 base policy 特例化 | allowed |
| `external_base` | authoritative base 不屬 Polaris 可治理 branch family，或 ownership 不在本 repo | blocked for mutation |
| `no_task_legacy` | mutable lane 缺少 task.md / work order authority | blocked for mutation |

`reviewer-side` 不是 PR type，而是 consumer access mode。read-only reviewer lane 仍必須使用同一套
review semantics 與 readiness vocabulary。

## Source Resolution Fields

`resolve-pr-work-source.sh` 至少要產出以下欄位：

| Field | 說明 |
|---|---|
| `intent` | `mutable` 或 `read-only` |
| `pr_type` | 上表 enum |
| `ownership` | `task_managed` / `feature_branch` / `aggregate_release` / `external_base` / `no_task` |
| `task_md` | authoritative task.md path；沒有就 `null` |
| `source_type` | `jira` / `dp` / `unknown` |
| `source_id` | Epic / DP ID |
| `work_item_id` | `TASK-1234` 或 `DP-130-T1` |
| `task_branch` | task.md 的 task branch |
| `branch_chain` | normalized branch chain array |
| `declared_base` | task.md Base branch 原值 |
| `authoritative_base` | rebase / PR base / freshness 判斷真正要看的 base |
| `mutable_allowed` | mutable consumer 是否可繼續 |
| `unsupported_reason` | `missing_task_authority` / `external_base_authority` / `null` |

## Snapshot Fields

`pr-state-snapshot.sh` 必須建立下列 shared schema：

| Field | Enum / shape | 說明 |
|---|---|---|
| `base_freshness` | `fresh` / `stale_downstream` / `unknown` / `external_base` | branch chain 與 authoritative base 的 freshness |
| `mergeability` | `clean` / `conflict` / `blocked` / `unknown` | GitHub merge state normalized |
| `ci_state` | `GREEN` / `PENDING` / `FAIL` / `UNKNOWN` | checks + statuses normalized |
| `review_decision` | GitHub upper-case enum or `UNKNOWN` | reviewer summary signal |
| `review_threads_loaded` | boolean | threads 是否真的被讀到 |
| `total_unresolved_threads` | integer | 所有 unresolved thread count，包含 outdated |
| `active_unresolved_threads` | integer | unresolved + non-outdated thread count |
| `outdated_unresolved_threads` | integer | unresolved + outdated thread count；closeout 不得忽略 |
| `actionable_unresolved_threads` | integer | 未被 disposition consume 的 active threads |
| `disposed_unresolved_threads` | integer | `fixed` / `reply_only` / `not_actionable` |
| `deferred_threads` | integer | `deferred_with_reason` |
| `conversation_comments_loaded` | boolean | conversation (issue-level) comments 是否真的被讀到 |
| `unaddressed_human_comments` | array | bot-filter 後仍待 agent disposition 的 human conversation comments，每筆帶 `id` / `url` / `author_login` / `author_typename` / `author_association` |
| `evidence_head_sha_match` | `true` / `false` / `null` | current-head evidence / deliverable head 與 PR head 是否一致 |
| `head_branch` | string or `null` | PR head branch |
| `head_sha` | string or `null` | PR head SHA |
| `pr_state` | `OPEN` / `MERGED` / `CLOSED` / `UNKNOWN` | remote PR lifecycle |

### Conversation Comment Bot-Filter Contract

`unaddressed_human_comments` 只承載**需要 agent disposition 的 human comment**。automation-authored
comment 必須在 **snapshot layer**（`pr-state-snapshot.sh`）就被濾掉，classifier 只看到已濾乾淨的
human-only list；不得把 bot-filter 判斷延後到 classifier 或任何下游 consumer。判定為 automation
的三個條件（任一命中即排除）：

- author `__typename` 為 `Bot`（GitHub App / bot account）；
- comment body 帶 Polaris HTML marker（framework 自寫的 evidence / status comment）；
- 已知 automation 樣式（例如 Claude Code Review summary、JIRA ticket-link boilerplate）。

`unaddressed_human_comments` 的 disposition 由 `--disposition` 檔提供，schema 為
`{"comments":[{"comment_id":"<id>","disposition":"<value>"}]}`；`disposition ∈ {fixed, reply_only,
not_actionable}` 視為已消化。所有 unaddressed human comment 都拿到上述 disposition 之一後，該訊號清空。

## Action Classes

`pr-action-classifier.sh` 必須將 snapshot 映射成單一 action class：

| Action class | 說明 |
|---|---|
| `unsupported_mutation` | mutable lane 缺 authority，不可 best-effort 修改 |
| `rebase_required` | upstream / base freshness 阻擋，先處理 lineage |
| `blocked_conflict` | merge conflict 或 equivalent hard block |
| `wait_ci` | checks / mergeability 尚未穩定 |
| `code_fix` | 仍需改 code 或補 current-head evidence / review disposition |
| `needs_disposition` | 有 `unaddressed_human_comments`（bot-filter 後仍待 agent disposition 的 conversation comment）；映射到 `needs_code_changes` readiness |
| `planning_gap` | 規格 / disposition / authority 缺口，不應直接施工 |
| `reviewer_handoff` | code 與 evidence 已齊，下一步是 reviewer |
| `ready_to_merge` | PR 可進 merge lane |

## Readiness Vocabulary

只有 classifier 可以產生 readiness term。skill 對外文字必須映射到這些值，不能自行發明
「有修」、「有處理」、「大概可以 merge」之類語義。

| Readiness | 說明 |
|---|---|
| `unsupported_mutation` | mutable lane 不得繼續 |
| `blocked_conflict` | conflict / stale lineage 阻擋 |
| `wait_ci` | 等 CI / mergeability / API state 穩定 |
| `needs_code_changes` | 仍有 code / evidence / actionable threads 要處理 |
| `planning_gap` | 缺 source-of-truth / deferred decision / authority |
| `review_required` | reviewer 仍未完成本輪看單 |
| `awaiting_re_review` | 變更與 evidence 已齊，等待 reviewer 回頭看 |
| `mergeable_ready` | branch freshness、mergeability、CI、review semantics、head-bound evidence 都過關 |

## Approval Threshold Policy

`pr-action-classifier.sh` 判斷 `review_decision=APPROVED` 的 PR 是否升格為 `ready_to_merge` /
`mergeable_ready` 時，approval threshold 依 **policy-first** 順序解析（第一個命中者勝出）：

1. 明確 `--approval-threshold N` flag override（selftest / explicit caller）；
2. company config `defaults.scrum.approval_threshold`（canonical single place）；
3. 前兩者皆缺時 fallback 到 branch-protection `reviewDecision`（`APPROVED` 已隱含 branch
   protection 滿足，直接視為 threshold 達成）。

threshold 解析出數值時，valid approval 數必須 `>= threshold` 才升格；`valid_approvals < threshold`
（例如 `1 < 2`）維持 `review_required`，不得升 `mergeable_ready`。valid approval 的計數由唯一
canonical counter `scripts/lib/pr-approval-count.sh` 產出（check-pr-approvals 與 classifier 共用
同一支；內部以 `scripts/lib/approval-staleness.sh` 判定 review commit_id == head.sha 的 staleness）。
不得在 classifier 或任何 consumer 內另寫第二套 approval-count / staleness 判斷。

## Source-Type Symmetry

conversation-comment 訊號與 approval-threshold policy 對 DP-backed source 與 JIRA-Epic-backed
source **對稱適用**；classifier 不得對 `source_type`（`dp` / `jira`）開 fast path 或特殊豁免。
兩種 source type 在相同 snapshot + 相同 threshold 下必須產出相同 action class 與 readiness term。

## Fail-Closed Rules

- 沒有 shared snapshot evidence，任何 skill 都不得輸出等價於 `awaiting_re_review` 或
  `mergeable_ready` 的訊息。
- `stacked_task` 只要 `base_freshness=stale_downstream`，就不能升格成 `mergeable_ready`。
- `no_task_legacy` 與 `external_base` 在 mutable lane 一律走 `unsupported_mutation`。
- `evidence_head_sha_match=false` 時，不得說「已重走」「delivery-ready」「comment addressed complete」。
- reviewer-side read-only lane 雖可 advisory，但 `changes_requested`、`active unresolved comments`、
  `awaiting_re_review` 的語義必須與 author-side mutable lane 一致。

## Consumer Duties

| Consumer class | Duty |
|---|---|
| Mutable lane | 必須先 resolve → snapshot → classifier，再決定是否 rebase、push、reply、report |
| Reporting / reminder | 只能 consume shared readiness vocabulary；不得自己拼 API 說 ready |
| Reviewer read-only | 必須使用 shared review semantics；不得重寫 `awaiting_re_review` |
| Gates / completion | 必須把 assignee、task-bound verify report、PR body template/language 等 head-bound metadata 視為同一個 readiness surface |

## Migration Note

過渡期允許舊 consumer 雙軌讀取自己的 metadata，但：

- 不能再新增平行 heuristics
- readiness wording 要先收斂到 shared vocabulary
- mutable lane 的 authority 判斷不可再停留在 skill prose
