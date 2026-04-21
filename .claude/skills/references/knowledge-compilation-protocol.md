# Knowledge Compilation Protocol (Framework)

Canonical policy for framework-level knowledge compilation semantics in Polaris.

Use this reference whenever a document discusses:
- source of truth
- compiled/derived outputs
- parallel documentation generation and naming

## Scope

Applies to framework docs/processes in this workspace (`rules/`, `skills/`, `specs/design-plans/`).

Does not redefine:
- product repo handbook lifecycle
- JIRA wiki markup conventions
- code compilation/build artifacts

## Core Contract

### 1) Atom vs Derived

- **Atom layer**: authoritative, human-reviewed decision content.
  - Examples: `rules/*.md`, `skills/references/*.md`, active `specs/design-plans/*/plan.md`.
- **Derived layer**: generated/transformed outputs built from atom content.
  - Examples: generated sidebar/navigation files, summary/translation docs, sync artifacts.

Rule:
- Normative changes must land in Atom layer first.
- Derived layer updates must reflect Atom changes, not invent new policy.

### 2) Backwrite When Deviating

If urgent operations require editing a derived artifact first:
1. Record the reason.
2. Backwrite the same decision into the corresponding atom file in the same task/session.
3. Re-sync/re-generate derived outputs.

A task is incomplete if it leaves policy only in derived files.

## Parallel Naming Lock Protocol

For parallel documentation/reference generation:

1. **Coordinator locks slots before fan-out**
   - Pre-define target filenames/slugs and owner per slot.
2. **Workers fill assigned slots only**
   - Workers do not rename files or mint new slugs unilaterally.
3. **Collisions are escalation events**
   - If content doesn't fit an assigned slot, return BLOCKED/PARTIAL and request coordinator decision.

This avoids same-concept multi-filename drift (e.g., `foo-protocol.md` vs `foo-workflow.md` for one concept).

## Framework Layer Mapping

Use the mapping below when ambiguity exists:

| Layer | In Polaris |
|------|------------|
| Atom | `.claude/rules/*.md`, `.claude/skills/references/*.md`, `specs/design-plans/*/plan.md` |
| Derived | generated viewers/index/sidebar files, mirrored/synced outputs, translation/summarization outputs |

Note:
- `.agents/skills/references/*` mirrors `.claude/skills/references/*` in this workspace workflow.
- If mirror and source conflict, resolve in canonical source first, then sync mirror.

## Compliance Checks (Behavioral)

Related mechanism IDs:
- `knowledge-source-of-truth-boundary`
- `parallel-doc-naming-lock`

See `rules/mechanism-registry.md` for canary signals and drift levels.
