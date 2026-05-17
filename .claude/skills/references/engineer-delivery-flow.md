# Engineer Delivery Flow Index

This thin index is the stable entrypoint for `engineering` delivery. DP-188 split the former monolithic flow into phase-sized references while keeping the same backbone and gate order.

## Phase References

| Phase | Reference | Scope |
|-------|-----------|-------|
| Context | `engineer-delivery-flow-index-context.md` | delivery contract, role matrix, design principles |
| R0 | `engineer-delivery-flow-R0-preflight.md` | simplify, self-review, scope gate, rebase |
| R1 | `engineer-delivery-flow-R1-ci-verify.md` | local CI mirror and behavioral verify |
| R2 | `engineer-delivery-flow-R2-flow-vr.md` | flow gap audit and visual regression |
| R3 | `engineer-delivery-flow-R3-base-commit.md` | base freshness, commit, changeset |
| R4 | `engineer-delivery-flow-R4-pr-jira.md` | PR create / local extension handoff / JIRA transition |
| R5 | `engineer-delivery-flow-R5-completion-cleanup.md` | completion gate, cleanup, halting conditions, evidence model |

## Consumer Contract

- `engineering-first-cut-flow.md` uses this index, then loads only the phases needed for the current role and gate.
- Developer and Local Extension roles share the same phase order; local extension policy may add tail checks but cannot remove evidence gates.
- When changing delivery semantics, update the relevant phase reference and deterministic scripts in the same task.

## Backbone

The complete order remains:

```text
scope -> rebase -> ci-local -> verify -> flow-gap -> VR if triggered -> base freshness -> commit -> PR/local extension -> completion gate -> cleanup
```
