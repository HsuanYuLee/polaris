# Pipeline Handoff Artifact

定義 skill handoff 點寫下的 **evidence artifact**，讓 pipeline 下一個 skill 可在需要時驗證 raw
findings，而不必重新探索。

本 reference 在 `pipeline-handoff.md`（角色邊界與 task.md schema）之上補上 evidence layer。
來源：DP-024 P4。

## Why

Skill pipeline（`refinement → breakdown → engineering → verify-AC`）目前主要 handoff
**結論文件**（refinement.md、task.md、JIRA comments）。Raw tool return，例如 grep matches、
error traces、endpoint responses、commit hashes，會在 producing skill session 結束後流失。

結果是下一個 skill 只能 (a) 盲信結論，或 (b) 重新 grep / rerun 來驗證；(b) 會浪費 context，
也提高 drift 風險。

Handoff artifact 是 supporting evidence 的精簡、scrubbed snapshot，寫在 handoff 點。預設行為是：
下一個 skill 的 sub-agent 信任結論並跳過 artifact；只有結論含糊、互相矛盾或需要驗證時才打開。

## File Location and Naming

Handoff artifacts 寫到 sub-agent Completion Envelope Detail files 已使用的同一個
`specs/{EPIC_OR_TICKET}/artifacts/` folder（見 `sub-agent-roles.md` § Summary vs Detail
Separation）。這刻意收斂兩個概念：

- **Detail file**（Completion Envelope）：由 sub-agent 寫入，由目前 skill 的 dispatching Strategist 讀取
- **Handoff artifact**（本文件）：由 skill 結束時寫入，由下一個 skill 的 sub-agent 讀取

兩者位於同一 folder 並使用相同格式；差異在 **consumer**，不是檔案本身。

**Filename**: `{skill}-{scope}-{ticket_key}-{timestamp}.md`

| Part | Format | Example |
|------|--------|---------|
| skill | skill name slug | `refinement Bug source mode`, `engineering`, `verify-ac` |
| scope | optional scope qualifier, omit if not meaningful | `root-cause`, `ac-fail`, `verify-fail` |
| ticket_key | primary JIRA key being worked on | `TASK-3847`, `EPIC-521` |
| timestamp | UTC, seconds-precision, `Z` suffix | `2026-04-22T153000Z` |

完整範例：`specs/EPIC-521/artifacts/refinement-root-cause-TASK-3847-2026-04-22T153000Z.md`

不需要 `scope` 時省略該 segment：`engineering-TASK-3847-2026-04-22T154500Z.md`。

## Artifact Format

```markdown
---
skill: refinement Bug source mode
ticket: TASK-3847
scope: root-cause
timestamp: 2026-04-22T15:30:00Z
truncated: false
scrubbed: true
---

## Summary

≤ 500 字 conclusion in the conversation's language (Traditional Chinese or English).
Routing decisions for the consumer can be made from this section alone.

Structure suggestion:
- 1–2 sentences of the headline finding
- Key file paths / line numbers
- Next-step direction

## Raw Evidence

Supporting tool return — grep matches, error traces, endpoint responses, git diff
excerpts, test output. Capped at 20KB after secret scrubbing. Truncation (if applied)
inserts a single `[truncated, N bytes omitted]` marker between kept head and tail.
```

### Required Frontmatter Fields

| Field | Type | Description |
|-------|------|-------------|
| `skill` | string | Producing skill slug |
| `ticket` | string | Primary JIRA key |
| `scope` | string | Optional — qualifies multi-mode skills (e.g., `root-cause` vs `ac-fail`) |
| `timestamp` | string (ISO 8601) | UTC, with `Z` suffix |
| `truncated` | bool | `true` when 20KB cap forced truncation |
| `scrubbed` | bool | `true` when `snapshot-scrub.py` was applied |

### Size Cap (Hard Limit 20KB)

Scrub 後的內容必須 ≤ 20KB。若 raw evidence 超過上限：

1. Keep head (first **13000 bytes**)
2. Insert marker `\n\n[truncated, N bytes omitted]\n\n` (where N = total raw bytes − kept bytes)
3. Keep tail (last **6000 bytes**)

Head + marker + tail ≤ 19100 bytes，低於上限。Frontmatter 與 `## Summary` 不納入 cap 計算；
cap 只套用在 `## Raw Evidence` 內容。

### Secret Scrubbing

所有 artifacts 寫入前都必須通過 `scripts/snapshot-scrub.py`。此 script 會把下列 patterns
替換成 `[REDACTED:kind]` markers：

| Pattern family | Kind marker |
|----------------|-------------|
| GitHub PAT / OAuth / server tokens | `github-*` |
| OpenAI / Anthropic API keys | `openai-like`, `anthropic` |
| Slack bot/user/app tokens | `slack-*` |
| AWS access keys (standard + temporary) | `aws-*` |
| Bearer tokens in HTTP headers | `bearer` |
| Basic auth in URLs | `basic-auth` |
| Atlassian / generic `api_token`-labelled strings | `api-token` |
| Generic `password|secret|token|api_key = ...` | `secret` |

若跳過 scrubbing（非常少見，只適用於必須保留精確 token value 的 evidence，例如 security review），
必須設定 `scrubbed: false`，並在 JIRA handoff comment 標示，讓 reader 知道需要謹慎處理。

## Per-Skill Write Policy (「結論不自明」判定 — per-skill, not shared heuristic)

每個 producing skill 決定自己的 write rules。規則必須具體：哪個 **scope** 會產生 artifact，
以及哪些 **content** 會進 Raw Evidence。

### refinement Bug source mode

| Path | Artifact? | Scope | Raw Evidence content |
|------|-----------|-------|----------------------|
| Full Path (Step 3, Explorer dispatched) | **Write** | `root-cause` | File paths + grep matches; line ranges of suspect code; commit hashes referenced; PR diff excerpts; stack traces / error output from ticket |
| AC-FAIL Path (Step 2-AF.2, Explorer dispatched) | **Write** | `ac-fail` | Same as root-cause plus `[VERIFICATION_FAIL]` block from Bug description; mapping of AC# → suspect code location |
| Fast Path (Step 2, inline, ≤ 3 files) | **Skip** | — | Conclusion is self-evident from ticket + trivial file read; no evidence to preserve |

### engineering

| Path | Artifact? | Scope | Raw Evidence content |
|------|-----------|-------|----------------------|
| First-cut delivery (PR opened, transitioning to QA) | **Write** | — (scope omitted) | Final commit SHAs on the branch; test command + full output (pass/fail counts, timing); quality-gate results (lint, typecheck, coverage); Layer B behavioral verify output (curl output, screenshots paths, dev-server logs); evidence-file JSON contents; task.md items marked PASS/FAIL/SKIP |
| Revision mode (fix on existing PR) | **Write** | `revision` | Delta commit SHAs; re-test output; Layer B re-verify output; responses to review comments; any regression catches |
| Batch mode (parallel sub-agents) | **Write per ticket** | — | Same as first-cut, one artifact per ticket |

Filename examples:
- `engineering-TASK-3847-2026-04-22T154500Z.md` (first-cut)
- `engineering-revision-TASK-3847-2026-04-22T170000Z.md` (revision)

為何無條件寫入：engineering 的工作本身就是 delivered change。verify-AC 需要 Layer B evidence
trail，才能理解本機已測試什麼、接下來要 re-verify 什麼。這同時也是 dispatching Strategist
的 Completion Envelope Detail file；同一檔案，雙 consumer（見下方 § Interaction with Existing
Mechanisms）。

### verify-AC

| Path | Artifact? | Scope | Raw Evidence content |
|------|-----------|-------|----------------------|
| PASS (all AC pass) | **Skip** | — | Comment + JIRA transition are sufficient; no downstream handoff |
| FAIL → 實作偏差 disposition (per-AC Bug created) | **Write per Bug** | `verify-fail` | AC# + expected vs observed (including HTTP status when applicable); failing step transcript (curl output / playwright trace / evidence paths); env snapshot (dev server URL, fixture path, commit SHA under test); AC ticket description excerpt; links to evidence attachments |
| FAIL → 規格問題 disposition | **Skip** | — | Routes back to refinement (a planning skill), not through the artifact consumer chain |
| PENDING (MANUAL_REQUIRED / UNCERTAIN) | **Skip** | — | Human judgement pending; artifact premature |

Filename: `verify-ac-verify-fail-{BUG_KEY}-{timestamp}.md` (one per Bug created for 實作偏差)

原因：refinement Bug source mode 的 AC-FAIL path（Bug description 內的 `[VERIFICATION_FAIL]`
block detection）以 Bug description 作為 primary work order。Artifact 補上 verify-AC 收集的 raw
observed/expected evidence，讓 refinement Bug source mode 的 Explorer 不必重跑 AC 就能定位疑似
壞掉的 code。

## On-Demand Read — Dispatch Prompt Template

Consumer skills **不得**盲目讀 artifact。預設是信任 conclusion document（task.md、JIRA comment）。
只有需要時才讀 artifact。

Injection point in the consumer sub-agent dispatch prompt:

```text
## Evidence Artifact (on-demand)

Upstream skills may have dropped a handoff artifact with raw supporting evidence.
Do not read by default. Open only when:

- The work order (task.md / JIRA comment) is ambiguous or missing detail
- You need to verify a claim (e.g., a file path, an error message, a response shape)
- You suspect the conclusion is stale or inconsistent with the current codebase

Location: `specs/{EPIC_OR_TICKET}/artifacts/{skill}-*.md`
Format: `## Summary` (≤500 字 decision digest) + `## Raw Evidence` (capped raw output)
Read the Summary first; only scan Raw Evidence when Summary does not answer your question.
```

將此 block 放在 work-order reading instruction **之後**，讓 sub-agent 仍把 task.md / JIRA comment
視為 primary input。

## Interaction with Existing Mechanisms

| Existing | Relationship |
|----------|--------------|
| Completion Envelope Detail (`sub-agent-roles.md`) | Same folder, same format. The producing skill's Detail file IS the handoff artifact — no separate write |
| `pipeline-handoff.md` task.md schema | task.md is still the primary contract. Artifact is supplementary |
| `epic-folder-structure.md` | `artifacts/` folder is already canonical; this reference pins the content format |
| `safety-gate.sh` | Different scope — gate blocks dangerous commands; scrub filters secret strings. Patterns are mostly disjoint |

## Script

- **Writer-side scrub + cap**: `scripts/snapshot-scrub.py` (stdin → stdout, or `--file path` in place)
- **Typical invocation** (inside a sub-agent Bash step):
  ```bash
  python3 scripts/snapshot-scrub.py --file specs/EPIC-521/artifacts/refinement-root-cause-TASK-3847-2026-04-22T153000Z.md
  ```
  此 script 讀取檔案、scrub `## Raw Evidence` 內的 secrets、套用 20KB cap、更新 frontmatter
  `scrubbed` / `truncated` booleans，並原地重寫檔案。

## Source

- Design plan: `specs/design-plans/DP-024-memory-system-enhancement/plan.md` § D3 + D5
- Pilot handoff: refinement Bug source mode → engineering (2026-04-22 confirmed)
- Follow-up expansion: engineering → verify-AC, verify-AC FAIL → refinement Bug source mode
