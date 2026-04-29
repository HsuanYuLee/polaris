---
name: design-plan
description: >
  Deprecated compatibility shim for legacy `design-plan DP-NNN` or `/design-plan`
  handoff prompts. Do not use as the primary entry for new non-ticket design
  discussions; route "想討論", "怎麼設計", "重構", "ADR", and ticketless
  design topics to `refinement` ticketless mode instead. This shim only locates
  or creates the DP container, then hands off to `refinement DP-NNN` or
  `breakdown DP-NNN`.
metadata:
  author: Polaris
  version: 2.0.0
---

# Design Plan — Compatibility Shim

`design-plan` is no longer an independent research → breakdown → engineering
pipeline. It remains only so older prompts, seeded DP folders, and historical
references still have a deterministic route into the unified ticketless
pipeline.

For new work, use:

| Intent | Route |
|--------|-------|
| Start a non-ticket design discussion | `refinement "討論 XXX"` |
| Continue an existing DP discussion | `refinement DP-NNN` |
| Split a locked DP into work orders | `breakdown DP-NNN` |
| Implement a DP-backed task | `engineering DP-NNN-Tn` |

## Authority Boundary

This shim may:

- read `references/spec-source-resolver.md`
- locate exactly one `specs/design-plans/DP-NNN-*/` folder
- create a minimal DP shell only when routing has not already been handled by
  `refinement`
- update Specs Viewer sidebar metadata after creating a shell
- tell the user which successor command to run

This shim must not:

- perform codebase research
- own Goal / Background / Decisions / Blind Spots / Acceptance Criteria /
  Technical Approach
- lock plans as a planning authority
- split implementation checklist into task.md work orders
- edit framework source, scripts, skills, rules, or docs as implementation

Those responsibilities now belong to:

| Responsibility | Owner |
|----------------|-------|
| Ticketless requirement research and decision capture | `refinement` |
| Implementation checklist finalization and DP-backed task.md packing | `breakdown` |
| Source changes | `engineering` |
| Ticketless acceptance verification | `verify-AC` future DP mode |

## Shim Flow

1. Read `references/spec-source-resolver.md`.
2. Resolve the input:
   - `design-plan DP-NNN` → locate the DP folder.
   - `/design-plan DP-NNN` from learning handoff → locate the seeded DP folder.
   - legacy topic prompt → allocate a DP folder only if `refinement` has not
     already done so.
3. Check status:
   - `SEEDED` / `DISCUSSION` → hand off to `refinement DP-NNN`.
   - `LOCKED` → hand off to `breakdown DP-NNN`.
   - `IMPLEMENTED` / `ABANDONED` → read-only audit unless the user explicitly
     asks to open a new DP.
4. Stop after the handoff instruction. Do not continue the successor workflow
   inside this shim.

## Minimal DP Shell

If the shim must create a DP shell for an older client, create only:

```markdown
---
topic: {Human-readable title}
created: YYYY-MM-DD
status: DISCUSSION
---

# {Title} — Design Plan

Plan pending — continue with `refinement DP-NNN`.
```

Do not fill research sections in this skill. `refinement` owns the durable
content.

## Legacy Learning Handoff

Older `/learning` flows may still tell the user to run `/design-plan DP-NNN`
after seeding:

```text
specs/design-plans/DP-NNN-{slug}/artifacts/research-report.md
specs/design-plans/DP-NNN-{slug}/plan.md
```

When that happens, this shim only validates the folder and redirects to:

```text
refinement DP-NNN
```

Future learning copy should point users directly to `refinement DP-NNN`.

## Do / Don't

- Do: keep old `/design-plan DP-NNN` prompts from dead-ending.
- Do: preserve DP folder identity and source-resolver hard rules.
- Do: prefer explicit handoff text over silently continuing as another skill.
- Don't: reintroduce a parallel planning pipeline.
- Don't: treat legacy design-plan triggers as a reason to bypass refinement or
  breakdown.
- Don't: write implementation work orders here; `breakdown` owns that output.

## Post-Task Reflection (required)

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
