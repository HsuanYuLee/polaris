# task.md Schema Index

This thin index is the stable entrypoint for task.md schema consumers. DP-188 split the prior monolithic reference into artifact-sized sub-references so producers only load the section they need.

## Which File To Load

| Need | Reference |
|------|-----------|
| Common identity, frontmatter, dependency, deliverable, and DP-backed conventions | `task-md-schema-common.md` |
| T task implementation schema, required sections, runtime/test/verify contract, examples | `task-md-schema-task.md` |
| V task verification schema, AC execution shape, report/write-back contract, examples | `task-md-schema-verification.md` |
| Cross-section invariants and dependency binding rules | `task-md-schema-invariants.md` |
| Validator mapping, migration notes, and appendix | `task-md-schema-validator.md` |

## Consumer Contract

- `breakdown` loads `task-md-schema-common.md` plus `task-md-schema-task.md` or `task-md-schema-verification.md` before writing a work order.
- `engineering` loads T task sections and invariant sections when consuming implementation tasks.
- `verify-AC` loads V task sections and invariant sections when consuming verification tasks.
- Validators remain authoritative; if this index and validator behavior conflict, fix the reference or script in the same DP-backed task.

## Verification

```bash
bash scripts/validate-task-md.sh <task.md>
bash scripts/validate-task-md-deps.sh <tasks-dir>
bash scripts/validate-breakdown-ready.sh <task.md-or-dir>
```
