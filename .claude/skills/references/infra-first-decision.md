# Infra-First Decision Framework

Decides — deterministically, from the refinement artifact — whether an Epic needs **1–2 infra prerequisite subtasks** (Mockoon fixtures, VR baseline recording, stable data seed) inserted **before** feature subtasks. Driven entirely by AC verification requirements, not by config presence or Strategist intuition.

Consumed by **breakdown** (Step 5.5) and mirrored by **refinement** (Step 5 § 子單結構 preview), so the team sees the same subtask plan during refinement as breakdown will actually produce.

## Why

Verify-AC produces real verdicts only when the environment can honestly answer each AC. Some AC need live runtime state (Lighthouse under a specific data shape, Playwright against a stable fixture set, curl against a deterministic response). Others can be fully answered by unit tests. The split is visible in the refinement artifact.

Historically this decision was improvised per Epic, with two failure modes:

- **Over-engineering** — infra subtask inserted because `visual_regression` config exists, even when every AC is `unit_test`. Wastes SP, pushes team to think infra is always needed.
- **Under-engineering** — complex Epic ships without fixtures; verify-AC hits backend API drift and reports false negatives. Team loses trust in verify-AC.

Lifting the decision tree into an explicit reference eliminates both failure modes and makes the plan legible during refinement (before any sub-task is created in JIRA).

## Inputs

Read from `{company_base_dir}/specs/{EPIC_KEY}/refinement.json`:

| Field | Values | Meaning |
|-------|--------|---------|
| `acceptance_criteria[].verification.method` | `lighthouse` / `playwright` / `curl` / `unit_test` / `manual` | How the AC gets verified |
| `modules[].api_change` (optional) | `none` / `additive` / `breaking` | API contract delta signal (defaults to `none` when absent) |

Absence of refinement.json → framework is **skipped** (see § Graceful Degrade), callers fall back to their pre-framework logic.

## Classification — runtime-required methods

| Method | Needs runtime infra? | Rationale |
|--------|---------------------|-----------|
| `lighthouse` | **Yes** | Needs deployed env + stable page state for reproducible scores |
| `playwright` | **Yes** | Needs running server + deterministic responses |
| `curl` | **Yes** | Needs live endpoint; likely hits same fragile APIs |
| `unit_test` | No | Runs in isolation, no env/data dependency |
| `manual` | **No** (default) | User-driven; infra for automated prereq is out of scope |

**Mixed methods in one AC** (e.g., AC says "curl + manual inspection") → treat as runtime-required if ANY listed method is in the "Yes" column.

## Decision tree

### Q1 — Does any AC use `lighthouse` / `playwright` / `curl`?

- **Yes** → output 1–2 infra prerequisite subtasks. Typical shapes:
  - **Mockoon fixtures** — when AC consume backend APIs that are known to drift (check handbook § Key Libraries or `api-contract-guard.md` for fragile endpoints)
  - **VR baseline recording** — when AC includes visual regression assertions
  - **Stable data seed** — when AC depends on a specific page state (e.g., "product with 10 reviews")
- **No** → skip infra; feature subtasks start directly.

### Q2 — Any `modules[].api_change`?

| `api_change` | Ordering rule |
|--------------|---------------|
| `breaking` (or `replace`) | **API change task FIRST, then infra** — sequential. Fixtures must be re-recorded against the new API; recording before the change would produce stale fixtures |
| `additive` (backward-compatible) | **Parallel** — API change and infra can run simultaneously, since existing fixtures still match the old contract |
| `none` | Q1 conclusion unchanged (no ordering constraint introduced) |

### Exceptions (skip framework entirely)

If any of the following applies, output `skipped: true` with the matching reason:

| Exception | Reason |
|-----------|--------|
| Static/config change only | No runtime verification possible |
| i18n / translation-only | Pure text change; infra does not help |
| Docs-only | No runtime deliverable |
| Research / Spike | No deliverable yet; infra premature |
| Epic IS the infra | e.g., "build Mockoon fixture library" — framework would be self-referential |
| Existing infra already covers this Epic's AC | refinement Step 2 / handbook records this |

Exceptions are inferred from:
- Epic summary / description keywords (`refactor`, `i18n`, `docs`, `spike`, `infra`, `fixture`, `VR baseline`)
- `refinement.json.modules[].action` — all `investigate` or empty → likely research
- `refinement.json.tier_signals` — explicit hints like "infra Epic" or "no runtime signals"

When uncertain, **do not skip** — default to Q1/Q2 and let the Strategist override at breakdown confirmation step.

## Output structure

Returned by the framework, consumed by breakdown Step 6 and refinement Step 5:

```jsonc
{
  "infra_subtasks": [
    {
      "summary": "Mockoon fixtures: product page pricing",
      "points": 2,
      "reason": "AC2/AC3 use playwright + lighthouse against product page APIs; fixtures isolate from BE drift"
    }
  ],
  "ordering_rule": "api_first_then_infra",   // "parallel" | "no_api_change" | "api_first_then_infra"
  "skipped": false,
  "skip_reason": null,                        // e.g., "i18n_only", "no_refinement_artifact"
  "decision_trace": [
    "Q1: lighthouse + playwright present → need infra",
    "Q2: modules[].api_change = 'additive' → parallel ordering"
  ]
}
```

`decision_trace` is **required** — it is the audit trail that satisfies the `breakdown-infra-first-applied` canary.

## Graceful degrade

No `refinement.json` (e.g., ad-hoc breakdown, legacy Epic pre-refinement-v2):

```jsonc
{
  "infra_subtasks": [],
  "ordering_rule": "no_api_change",
  "skipped": true,
  "skip_reason": "no_refinement_artifact",
  "decision_trace": ["no refinement.json found; caller should use fallback ordering logic"]
}
```

Callers (breakdown / refinement) must handle `skipped: true` by:
1. Notifying the user — "無 refinement artifact，略過 infra-first 框架，使用傳統排序"
2. Running their pre-framework logic (breakdown: hard-coded API-first + `visual_regression`-bound fixture task)

## Tier Guidance per Skill

| Skill | When to apply |
|-------|--------------|
| **breakdown** (Planning Path) | Always at Step 5.5, unless exceptions match or `refinement.json` absent |
| **refinement** | Step 5 — use to pre-render § 子單結構 preview row, so team sees infra decision during refinement |
| **bug-triage** | N/A — bugs inherit parent Epic's infra state |
| **sasd-review** | N/A — SA/SD predates subtask decomposition |
| **breakdown** (Bug Path) | N/A — bug path does not decompose into infra + feature |

## Canary Signal (self-check)

Before Step 6 in breakdown (or § 子單結構 render in refinement), ask:

> "Did I consult `acceptance_criteria[].verification.method` for this decision, or did I default to the old `visual_regression`-config-bound fallback?"

- **Consulted methods + have `decision_trace`** → proceed.
- **Defaulted without consulting** → stop, re-read refinement.json, re-run Q1/Q2. If refinement.json truly missing, declare `skipped: true` explicitly — do not silently fall back without logging.

Violating canary = drift per `mechanism-registry.md` § `breakdown-infra-first-applied` (Medium).

## Edge cases

| Scenario | Handling |
|----------|----------|
| AC list is empty | `skipped: true`, `skip_reason: "no_acceptance_criteria"` — refinement should have caught this first |
| `verification.method` missing on an AC | Surface warning ("AC{n} has no verification method — treating as `manual`"); user can correct by going back to refinement Step 4 |
| All AC use `manual` | No infra by default; framework respects user-driven verification |
| AC text mentions runtime concept (LCP, rendering, timing) but method is `unit_test` | Mismatch — surface as warning; likely refinement under-classified. Default to Q1 based on method, but flag for review |
| Refinement artifact version < 1.1 | `modules[].api_change` absent → treat all as `"none"`. Q2 has no effect; Q1 alone drives decision |
| Two Epics share infra (e.g., same Mockoon fixtures) | Framework does not deduplicate across Epics. Exception "Existing infra already covers" is the manual override; Strategist applies at breakdown confirm step |

## Relationship to other references

- [planning-worktree-isolation.md](planning-worktree-isolation.md) — structural sibling; both are "shared decision procedures called by multiple planning skills". This file covers infra prereq decisions; that file covers worktree isolation during runtime verification.
- [refinement-artifact.md](refinement-artifact.md) — defines the input schema (`acceptance_criteria[].verification.method`, `modules[].api_change`).
- [pipeline-handoff.md](pipeline-handoff.md) — breakdown → engineering contract; this framework shapes what breakdown puts on the belt.
- [api-contract-guard.md](api-contract-guard.md) — downstream: fixtures created by infra-first subtasks are guarded against live-API drift by this mechanism.
- [estimation-scale.md](estimation-scale.md) — infra subtasks default to 1–2 pt; consumer skills apply scale rules.

## Source

Designed 2026-04-16 after PROJ-123 refinement. The pattern had been applied intuitively across multiple Epics (PROJ-123 VR baseline, PROJ-123 Mockoon, PROJ-123 curl); lifting it into a reference removes the per-Epic improvisation cost and gives refinement / breakdown a shared, auditable decision source.
