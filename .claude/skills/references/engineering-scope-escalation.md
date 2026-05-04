---
title: "Engineering Scope Escalation"
description: "engineering scope escalation：gate failure requiring planner-owned field changes, sidecar schema, validation, and halt rules。"
---

# Scope Escalation

## Trigger

三條同時成立才進 scope escalation：

1. mandatory mechanical gate failed（ci-local、type baseline、verify command、coverage）。
2. failure files / required fix 落在 task Allowed Files 之外。
3. 修法需要改 planner-owned 欄位：Allowed Files、estimate、Test Command、Verify
   Command、Test Environment、depends_on。

少任一條，走一般 scope addition / code fix；但仍不得自行改 planner-owned 欄位。

## Halt

一旦進入本流程，立即停止所有 source Edit / Write。不得 push、不得 PR、不得 lifecycle
write-back，直到 breakdown intake 決策。

## Gate Closure Diagnosis

sidecar 必須以 gate closure 為單位，不只列第一個 out-of-scope file：

- Gate to close。
- Pass condition。
- Current measurement：baseline、actual、exit code、evidence file。
- Explained delta：把可歸因 delta 拆成因果群。
- Candidate fixes：每個因果群的修法、是否在 Allowed Files、是否要 planner decision。
- Residual blockers。
- Closure forecast：只批准部分修法時 gate 是否仍 fail。
- Required planner decisions：讓 gate 可能 pass 的最小完整決策集合。

## Lineage Cap

計算同 lineage sidecars：

```bash
ls "{company_specs_dir}/{EPIC}/escalations/T{n}-"*.md 2>/dev/null | wc -l
```

新 count > 2 時不要寫 sidecar；回報 lineage cap，請使用者先跑 `breakdown {EPIC}`，
由 breakdown 建 refinement inbox。

## Sidecar

依 `escalation-flavor-guide.md` 初判 primary flavor：

- `plan-defect`
- `scope-drift`
- `env-drift`

Raw evidence 先用 `scripts/snapshot-scrub.py` scrub。Sidecar path：

```text
{company_specs_dir}/{EPIC}/escalations/T{n}-{count}.md
```

Frontmatter required：

- `skill: engineering`
- `ticket`
- `epic`
- `flavor`
- `escalation_count`
- `timestamp`
- `truncated`
- `scrubbed`

Body required：

- `## Summary`
- `## Gate Closure`
- `## Current Measurement`
- `## Explained Delta`
- `## Proposed Fixes`
- `## Residual Blockers`
- `## Closure Forecast`
- `## Required Planner Decisions`
- `## Raw Evidence`

## Validator

```bash
bash "${POLARIS_ROOT}/scripts/validate-escalation-sidecar.sh" "{sidecar_path}"
```

exit != 0 時修 sidecar 到 pass。未 pass 不得結束 session。

## Report

回報使用者：

- sidecar absolute path。
- proposed flavor。
- closure forecast。
- next step：`breakdown {EPIC}`。

不要繼續實作。
