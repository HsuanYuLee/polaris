# Spec Source Resolver

Shared source resolution contract for JIRA-backed and ticketless Polaris pipeline work.

## Goal

`refinement`, `breakdown`, `engineering`, and `verify-AC` must not each invent their own way to parse work sources. This reference defines the common source model used when a user provides a JIRA key, a design-plan ID, a direct artifact path, or a new ticketless topic.

The core rule is:

```text
source resolver decides where the work lives
pipeline stage decides what to do with it
JIRA sync is optional decoration
```

## Path Variables

```text
{workspace_root}     Polaris workspace root
{company}            active company key resolved from workspace config / JIRA project mapping
{company_specs_dir}  {workspace_root}/specs/companies/{company}
```

## Active And Archive Namespaces

Default source resolution is active-only. Skills that start or continue work must scan these active containers:

```text
{workspace_root}/specs/design-plans/DP-NNN-{slug}/
{workspace_root}/specs/companies/{company}/{TICKET}/
```

Completed or abandoned containers may be moved to archive:

```text
{workspace_root}/specs/design-plans/archive/DP-NNN-{slug}/
{workspace_root}/specs/companies/{company}/archive/{TICKET}/
```

Rules:

- active lookup must prune `archive/` so historical tasks do not resolve as current work
- direct archived artifact paths are allowed for read-only audit
- broad historical lookup requires an explicit mode such as `--include-archive`
- the same DP or ticket container must not exist in both active and archive namespaces
- docs-manager reads the physical `specs/` tree directly, so archived content is browsed under Starlight routes for `specs/design-plans/archive/...` or `specs/companies/{company}/archive/...`

## Source Types

| Type | Input examples | Canonical container | Primary owner |
|------|----------------|---------------------|---------------|
| `jira` | `GT-478`, `KB2CW-3711` | `{company_specs_dir}/{TICKET}/` plus JIRA issue | `refinement` / `breakdown` |
| `dp` | `DP-045`, `specs/design-plans/DP-045-*/plan.md` | `{workspace_root}/specs/design-plans/DP-NNN-{slug}/` | `refinement` |
| `topic` | `討論 CI local blocker`, `refinement "想重構 skill routing"` | newly allocated DP folder | `refinement` |
| `artifact_path` | direct `refinement.json`, `refinement.md`, `tasks/T1.md` path | nearest containing specs folder | stage-specific consumer |

## DP Locator

When input contains `DP-NNN`, locate exactly one folder:

```text
{workspace_root}/specs/design-plans/DP-NNN-*/
```

Rules:

- zero matches: fail loud; do not silently create a replacement DP with the same number
- multiple matches: fail loud; user or maintainer must resolve the duplicate
- one match: canonical DP root is that folder
- `plan.md` is required for `refinement DP-NNN` and `breakdown DP-NNN`
- `tasks/T{n}.md` is optional until `breakdown` produces work orders

The canonical plan path is:

```text
{workspace_root}/specs/design-plans/DP-NNN-{slug}/plan.md
```

## Topic To DP Creation

When input is a ticketless topic instead of an existing `DP-NNN`:

1. scan `{workspace_root}/specs/design-plans/DP-*`
2. allocate max existing N + 1
3. create `{workspace_root}/specs/design-plans/DP-NNN-{topic-slug}/plan.md`
4. set frontmatter `status: DISCUSSION`
5. route into `refinement` ticketless mode

The topic slug is kebab-case and describes the durable subject, not the current implementation step.

## Artifact Paths

For JIRA-backed work:

```text
{company_specs_dir}/{TICKET}/refinement.md
{company_specs_dir}/{TICKET}/refinement.json
{company_specs_dir}/{TICKET}/tasks/T{n}.md
```

For DP-backed ticketless work:

```text
{workspace_root}/specs/design-plans/DP-NNN-{slug}/plan.md
{workspace_root}/specs/design-plans/DP-NNN-{slug}/refinement.md
{workspace_root}/specs/design-plans/DP-NNN-{slug}/refinement.json
{workspace_root}/specs/design-plans/DP-NNN-{slug}/tasks/T{n}.md
```

`refinement.json` is the machine-readable artifact. `plan.md` is the durable decision record. They may share information, but consumers should prefer `refinement.json` when they need structured fields.

## Status Rules

| Status | Meaning | Allowed next stage |
|--------|---------|--------------------|
| `SEEDED` | DP shell exists, usually from learning handoff | `refinement` only |
| `DISCUSSION` | requirements / decisions are still changing | `refinement` only |
| `LOCKED` | source is stable enough for breakdown | `breakdown` |
| `IMPLEMENTED` | work is complete | read-only / audit |
| `ABANDONED` | decision was not to proceed | read-only unless revived by user |

`breakdown DP-NNN` must require `LOCKED` unless the user explicitly asks for advisory review. If source is still `DISCUSSION`, route back to `refinement DP-NNN`.

## Archive Sweep

Terminal specs can be archived one-by-one or by sweep:

```bash
scripts/archive-spec.sh DP-NNN
scripts/archive-spec.sh TICKET-123
scripts/archive-spec.sh --sweep --dry-run
scripts/archive-spec.sh --sweep --apply
```

Sweep uses the same namespace rules as source resolution:

- DP container status comes from `plan.md`
- JIRA/company container status comes from `refinement.md`, falling back to `plan.md`
- only `IMPLEMENTED` and `ABANDONED` are archive candidates
- non-terminal or missing status containers stay active and are reported as `skip`
- destination conflicts fail before any apply move

After sweep apply, docs-manager reads the moved canonical specs directly. For live review or static/search verification:

```bash
scripts/polaris-viewer.sh --mode dev
scripts/verify-docs-manager-runtime.sh --preview
```

## Section Ownership

This section ownership rule prevents `refinement` and `breakdown` from competing over the same DP content.

| Section | Owner | Notes |
|---------|-------|-------|
| frontmatter `topic`, `created`, `status`, `locked_at` | `refinement` | `breakdown` reads; it does not lock a plan |
| `## Goal` | `refinement` | requirement intent |
| `## Background` | `refinement` | context and current state |
| `## Decisions` | `refinement` | selected direction and rationale |
| `## Blind Spots` | `refinement` | risks and mitigations |
| `## Acceptance Criteria` | `refinement` | ticketless AC for future `verify-AC` |
| `## Technical Approach` / `## 技術方案` | `refinement` | implementation direction, not task slicing |
| `## Implementation Checklist` | `breakdown` after LOCKED | may map items to `tasks/T{n}.md`; before LOCKED, `refinement` may draft candidates |
| `## Work Orders` / `## Task Mapping` | `breakdown` | records generated task files and dependencies |
| `## Implementation Notes` | stage-specific | only append facts from the current stage |

If `breakdown` finds a technical decision wrong or incomplete, it must route back to `refinement`; it must not rewrite `Decisions` or `Technical Approach` silently.

## Stage Routing

| Input | Stage command | Behavior |
|-------|---------------|----------|
| `refinement DP-NNN` | refinement | locate DP, continue discussion / produce artifact |
| `refinement "topic"` | refinement | allocate DP, start ticketless refinement |
| `breakdown DP-NNN` | breakdown | require LOCKED DP, consume artifact / plan, create tasks |
| `engineering DP-NNN-Tn` | engineering | resolve to DP-backed task.md via DP-047 bridge |
| `verify-AC DP-NNN` | verify-AC | future ticketless verification mode |

## Compatibility

Legacy `design-plan` triggers such as `想討論`, `怎麼設計`, `ADR`, `design plan`, and `/design-plan DP-NNN` are aliases for `refinement` ticketless mode. The `design-plan` skill has been removed; no separate shim pipeline remains.
