# Canonical Contract Governance

## Core Rule

Polaris governance prefers hard constraints over advisory prose.

When a workflow, artifact, metadata surface, or lifecycle contract can be made
deterministic, Polaris should converge it into one canonical shape, one
canonical writer path, and one deterministic enforcement path.

## Rules

- **Strong constraints first**: if a contract can be enforced by script, hook,
  validator, or generated artifact, do that instead of relying on agent memory
  or maintainer habit.
- **Canonical shape first**: if two workflows or runtimes describe the same
  kind of artifact or authority surface, they should share the same shape unless
  a documented boundary proves they are fundamentally different.
- **No special writer paths**: the same lifecycle, metadata field, or status
  surface must not have multiple silent producer paths. Migration shims are
  allowed only when they are explicit, temporary, and governed by removal
  criteria.
- **Fail closed on missing inputs**: if required authority inputs are missing,
  Polaris must stop rather than synthesize correctness from prose, conversation
  history, or best-effort inference.

## Applicability

Apply this rule whenever changing or designing:

- bootstrap/runtime instructions
- shared rules or skills
- specs and task artifact contracts
- status / lifecycle / metadata writers
- validators, hooks, or release gates
- public maintainer-facing workflow docs

## Required Outcomes

- One canonical source of truth per shared contract surface
- One declared writer path for each authoritative state transition
- One deterministic check for contract violations where enforcement is possible
- No runtime-specific governance wording that changes shared semantics

## Allowed Exceptions

Only temporary compatibility mechanisms may diverge from the target contract,
and only when all of the following are explicit in the owning design plan:

- owner
- removal criteria
- verification method
- follow-up task

Compatibility is a delivery tool, not a steady-state design.
