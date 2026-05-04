# Escalation Flavor Guide

Engineering 的 first-pass classification cheat-sheet for scope escalation sidecars
(see `specs/design-plans/DP-044-engineering-scope-escalation-handoff/plan.md` D4).

When `engineering` halts on a mechanical-gate failure, it must diagnose the
whole gate closure condition, not only the first file outside `Allowed Files`.
The sidecar still carries one primary `flavor`, but mixed causes are expected
and must be described in the gate-closure sections. The tag is a **hint** —
`breakdown` re-classifies if evidence contradicts (D4).

## Decision Tree

先以 gate closure 為單位診斷，再分類檔案：

0. **這個 gate 要怎麼才會過？**
   先寫清楚 pass condition、baseline / actual、explained delta、candidate fixes、
   residual blockers、closure forecast。不要從第一個 out-of-scope file 直接跳到 sidecar。

1. **這個檔案是因為 baseline / external dep / sibling task 的漂移而漏掉的嗎？**
   外部世界往前推了一格，本 task 的 snapshot 沒跟上 → `env-drift`
2. **這個檔案是 task.md 應該包含但 breakdown 沒包進來的嗎？**
   原本就在本 task 的語意責任範圍內（同一功能的另一支 helper、forgotten unit test、應該一起改的 sibling component）→ `plan-defect`
3. **這個檔案是真正的新工作，應該獨立成另一張 task 嗎？**
   涉及全新模組、全新測試計畫、或語意上明顯是另一個交付單位 → `scope-drift`

如果一張 escalation 同時涉及多個 flavor，挑「最能代表 gate closure 決策」的 flavor
當 primary，其他 component 必須寫在 `## Explained Delta`、`## Proposed Fixes`、
`## Residual Blockers`、`## Required Planner Decisions`。不要只在 Summary 裡補一句。

## Gate-Closure Minimum

Every sidecar must answer:

| Question | Why it matters |
|----------|----------------|
| What gate failed? | Avoid planning around a symptom instead of the blocking gate |
| What is the pass condition? | Makes the target measurable |
| What delta is explained? | Separates direct task drift from residual environment/baseline drift |
| What fixes are candidates? | Gives breakdown planner-owned decisions to choose from |
| Will the proposed fix close the gate? | Prevents necessary-but-insufficient scope expansion |
| What residual blockers remain? | Forces one-pass planning instead of ping-pong |

If a proposed fix is necessary but insufficient, the sidecar must say so plainly:

```text
Closure Forecast: NO — approving only {fix A} reduces actual from X to Y, but
gate still fails because Y > baseline Z. Required decisions: {fix A} + {decision B}.
```

## Flavor Glossary

| Flavor | 主訴 | Breakdown 的典型回應 |
|--------|------|----------------------|
| `env-drift` | 外部 baseline / dep / sibling 還沒就緒；本 task 沒做錯，只是 starting point 過時 | Approval to bump `.lint-baseline.txt` / 等 sibling task merge / 升 dep；多半不重切 task |
| `plan-defect` | task.md 自己漏估或範圍寫錯 | 改 task.md（補 Allowed Files / 補 Test Command / 補 Verify Command / 改 estimate） |
| `scope-drift` | 出現原本沒人預期的新工作 | 拆新 task，掛 `depends_on: [<原 task>]`；原 task 等新 task 落地 |

## Worked Examples

### Example 1 — mixed `plan-defect` + `env-drift`（EPIC-478 T3a）

**Scenario**: T3a 把 `dayjs` plugin 串好。`ci-local.sh --repo` 的 type baseline gate
fails: baseline `3149`, actual `3163`.

Gate math:

- `+2` storage helper typing errors are small mechanical unblock candidates.
- Fixing those only reduces actual `3163 → 3161`.
- Baseline is still `3149`, so gate still fails with residual `+12`.

**Why mixed**:

- `plan-defect`: storage helper typing may be folded into T3a if planner agrees.
- `env-drift`: residual baseline mismatch remains even after the mechanical fix.

**Correct sidecar**: Must not ask only for storage helper Allowed Files. It must
tell breakdown that storage is necessary but insufficient and ask for both the
storage scope decision and the residual baseline/env decision in one intake.

### Example 2 — `plan-defect`（漏估的 unit test）

**Scenario**: task.md `Allowed Files` 只列了 `Composables/usePricing.ts`，但 lint
gate 抓到 `Composables/__tests__/usePricing.spec.ts` 也需要更新（既有 spec 引用了
被改的 type）。

**Why plan-defect**: 本來就是同一個 composable 的測試，breakdown 在拆單時應該把這
支 spec 一起放進 Allowed Files。語意上屬於本 task。

**Resolution**: breakdown 直接把 spec 加進 task.md 的 Allowed Files，可能順手把
estimate 從 2pt 調成 3pt；不另開 task。

### Example 3 — `scope-drift`（碰到全新模組）

**Scenario**: task.md 的目的是「統一商品頁日期格式」。實作中發現 server middleware
的 cache key 也得改成包含 locale，否則跨語系商品頁互相覆蓋。原 task.md 完全沒提到
cache layer。

**Why scope-drift**: cache 改動在語意上是另一個交付單位（不同模組、不同測試計畫、
不同部署風險）；硬塞進本 task 會讓 PR review 失焦。

**Resolution**: breakdown 拆一張新 task（可能是 1-2pt），掛 `depends_on:
[<原 task>]`；原 task 等新 task merge 後再 rebase 一次。

## When to Skip the Sidecar

不是每個 gate fail 都該升級成 escalation：

- 失敗檔案落在 `Allowed Files` 內 → 直接修，不寫 sidecar
- 失敗只是 lint warning / formatter 自動修 → 修完繼續，不寫 sidecar
- 失敗是 transient（網路、port 占用、Mockoon 沒起來） → 重試或修環境，不寫 sidecar

Sidecar 只在「失敗的修法會踩到 planner-owned 欄位（Allowed Files / estimate /
Test Command / Verify Command / Test Environment / depends_on）」時才該寫。

## Counter-Audit (Breakdown's Re-Classification Hint)

Breakdown 在 intake path（見 breakdown SKILL.md § Scope-Escalation Intake Path）
讀 sidecar 時會逐項對照：

- **Engineering 標 `env-drift` 但檔案明顯在本 task 語意內** → 多半是 `plan-defect`
- **Engineering 標 `plan-defect` 但檔案是全新模組** → 多半是 `scope-drift`
- **Engineering 標 `scope-drift` 但只是 baseline 漂移** → 多半是 `env-drift`

re-classify 時 breakdown 必須在自己的回應中明寫 “accepted flavor: X” 或
“re-classified to Y because Z”，這樣下次 retro 才能反推 engineering 的判斷準度
（D4 mitigation for Blind Spot #5）。
