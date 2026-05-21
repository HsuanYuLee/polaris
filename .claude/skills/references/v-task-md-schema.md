# V Task task.md Schema — Quick Reference

> **DP-217 pointer reference.** V (verification) task.md 的完整 schema 落在
> [`task-md-schema-verification.md`](./task-md-schema-verification.md)；本檔
> 是 `breakdown` / `verify-AC` 在寫 V task 前的 quick lookup，並列出與 T
> (implementation) task 的關鍵差異，避免 producer 把 T schema 套到 V task。
>
> Filename 是 type 訊號：`V{n}[suffix].md` (e.g. `V1.md`, `V2a.md`)，
> 對應 folder-native `tasks/Vn/index.md` 或 `tasks/pr-release/Vn/index.md`。
> Frontmatter **不**含 `type` 欄位（DP-033 D2）。

## V vs T at a Glance

| 面向 | T (implementation) | V (verification) |
|------|--------------------|------------------|
| 必要章節 (V-only) | — | `## 驗收項目`, `## 驗收計畫（AC level）`, `## 驗收步驟`（Level≠static 時） |
| 必要章節 (T-only) | `## 改動範圍`, `## Allowed Files`, `## Test Command`, `## Verify Command` | — |
| Operational Context cells (T-only) | `Test sub-tasks`, `AC 驗收單`, `Task branch` | — |
| Operational Context cells (V-only) | — | `Implementation tasks`, `AC 範圍`, 驗收 target host |
| frontmatter lifecycle 欄位 | `jira_transition_log[]`, `deliverable`, `extension_deliverable` | `jira_transition_log[]`, `ac_verification`, `ac_verification_log[]` |
| status enum | `PLANNED|IN_PROGRESS|BLOCKED|IMPLEMENTED|ABANDONED` (同 T) | `PLANNED|IN_PROGRESS|BLOCKED|IMPLEMENTED|ABANDONED` (同 T) |
| Verify Command 形態 | deterministic shell（`bash …` + `echo "PASS: …"`） | verify-AC LLM driver entry + 逐 AC 步驟描述（fenced code block） |
| 對稱原則 | parse-task-md / mark-spec-implemented / pipeline-artifact-gate / `tasks/pr-release/` / D7 atomic write contract / `jira_transition_log[]` 全部 T/V 共用 | 同左 |

## V Task Skeleton

`tasks/V{n}/index.md`（或 `tasks/pr-release/V{n}/index.md`）：

```markdown
---
title: "DP-NNN V1: <一句中文驗收主題> (X pt)"
description: "<一句中文描述驗收覆蓋的 AC 範圍>"
status: PLANNED
ac_verification:
  disposition: pending      # pending | pass | fail | drift_retry
  last_run: null
  evidence: null
ac_verification_log: []
jira_transition_log: []
depends_on:
  - DP-NNN-T1
---

# V1: <一句中文驗收主題> (X pt)

> Source: DP-NNN | Task: DP-NNN-V1 | JIRA: N/A | Repo: <repo>

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-NNN |
| Task ID | DP-NNN-V1 |
| JIRA key | N/A |
| Implementation tasks | DP-NNN-T1 |
| AC 範圍 | AC1, AC2, AC-NEG1, AC-NF1, AC-NF2 |
| Base branch | main |
| Branch chain | main -> task/DP-NNN-V1-... |
| Task branch | task/DP-NNN-V1-... |
| Depends on | DP-NNN-T1 |
| References to load | <links to plan / refinement / T task index.md> |

## Verification Handoff

驗收將由 verify-AC 觸發，產出寫回本檔 `ac_verification` + `ac_verification_log[]`。

## 目標

<一段中文，描述本 V 對哪幾條 AC 做最終確認，為什麼這次驗收必要。>

## 驗收項目

| AC | 描述 | Verification method |
|----|------|---------------------|
| AC1 | <... > | manual | code-inspection | selftest | runtime |
| AC2 | <... > | ... |
| AC-NEG1 | <... > | ... |
| AC-NF1 | <... > | ... |

## 估點理由

X pt - 對應 T1 已 ship 的 deterministic 化，驗收涵蓋 AC1~AC-NF2，主要由本人逐項
inspection + 跑 T1 selftest 套件 + 跑語言 / runtime annotation gate。

## 驗收計畫（AC level）

- 逐項對照 DP-NNN refinement.json `acceptance_criteria[].verification.detail`。
- T1 selftest 全綠 → AC1 ~ AC-N PASS evidence base。
- 跑 `validate-mechanism-runtime-annotations` → AC-NF1 PASS。
- 跑 `pre-write-language-policy-selftest` 並讀 timing → AC-NF2 PASS。

## Test Environment

- **Level**: static | runtime
- **Dev env config**: N/A 或具體 host / fixture
- **Fixtures**: <fixture path or N/A>
- **Runtime verify target**: <host or N/A>
- **Env bootstrap command**: <bash 命令或 N/A>

## 驗收步驟

```bash
set -euo pipefail
bash scripts/selftests/<T1 套件>-selftest.sh
bash scripts/validate-mechanism-runtime-annotations.sh
bash scripts/validate-language-policy.sh --blocking --mode artifact <doc>
echo "PASS: DP-NNN-V1"
```

預期輸出：`PASS: DP-NNN-V1`
```

## 常見 producer 錯誤（DP-217 驅動）

DP-212 V1 在沒有清楚 V schema reference 時誤把 T-only 章節 (`## Verify Command`、
`## Allowed Files`) 套到 V task，造成 verify-AC consumer 讀不到 `## 驗收步驟`。
踩到的點：

1. **把 `## Verify Command` 寫進 V task** — V 沒有這個章節；改寫 `## 驗收步驟`，
   裡面放 fenced code block。
2. **加 `## Allowed Files`** — V 不寫 code，沒有 Scope Check；移除。
3. **加 `## 改動範圍`** — 用 `## 驗收項目` 取代，內容是 AC 表，不是檔案表。
4. **缺 `ac_verification` / `ac_verification_log[]` frontmatter** — verify-AC 寫
   回時找不到 anchor 會 fail-stop；先在 breakdown 階段就把這兩個欄位放好。
5. **status 跳過 IMPLEMENTING** — V task 跟 T task 一樣走 PLANNED → IMPLEMENTED；
   verify-AC PASS 觸發 status 寫回。

## Validator 引用

- `bash scripts/validate-task-md.sh <task.md>` — filename `V*.md` 觸發 V mode。
- `bash scripts/validate-task-md-deps.sh <tasks-dir>` — V task 的 `depends_on`
  通常指向同 DP 的 T task；cross-file invariant 由此檢查。
- `bash scripts/validate-breakdown-ready.sh <task.md-or-dir>` — V task 在 breakdown
  handoff 前必須通過 ready check。

## 完整 schema 參照

V task 完整 schema、所有 cell 規則、`ac_verification` lifecycle、§ 4 全章節
contract 一律以 [`task-md-schema-verification.md`](./task-md-schema-verification.md)
為準。本檔是 quick lookup，遇到衝突以完整 schema 為準。
