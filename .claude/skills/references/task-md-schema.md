# task.md Schema Index

這份輕量索引是 task.md schema 消費者的穩定入口。DP-188 把舊的單檔 reference 拆成 artifact 等級的子 reference，讓 producer 只載入它真正需要的章節。

## Which File To Load

| Need | Reference |
|------|-----------|
| Common identity, frontmatter, dependency, deliverable, and DP-backed conventions | `task-md-schema-common.md` |
| T task implementation schema, required sections, runtime/test/verify contract, examples | `task-md-schema-task.md` |
| V task verification schema, AC execution shape, report/write-back contract, examples | `task-md-schema-verification.md` |
| V vs T quick differences + V task skeleton (DP-217 discoverable pointer) | `v-task-md-schema.md` |
| Cross-section invariants and dependency binding rules | `task-md-schema-invariants.md` |
| Validator mapping, migration notes, and appendix | `task-md-schema-validator.md` |

## V vs T Boundary (DP-217)

V (verification) task.md 與 T (implementation) task.md 共用大量基礎設施（parse-task-md / mark-spec-implemented / pipeline-artifact-gate / D7 atomic write contract / `jira_transition_log[]`），但章節集合與 frontmatter lifecycle 欄位不對稱。常見 producer 錯誤是把 T-only 章節（`## Verify Command`, `## Allowed Files`, `## 改動範圍`, `## Test Command`）寫進 V task，造成 verify-AC 找不到 `## 驗收步驟`。改 V task 前一律先讀 [`v-task-md-schema.md`](./v-task-md-schema.md) 的 V/T 對照表。

## Consumer Contract

- `breakdown` 在寫 work order 之前先載入 `task-md-schema-common.md`，再依 T / V 載入 `task-md-schema-task.md` 或 `task-md-schema-verification.md`。寫 V task 時額外載入 `v-task-md-schema.md` 做快速對照。
- `engineering` 處理 implementation task 時載入 T task 章節與 invariant 章節。
- `verify-AC` 處理 verification task 時載入 V task 章節與 invariant 章節。
- Validator 永遠是權威來源；本索引與 validator 行為不一致時，要在同一張 DP-backed task 內修正 reference 或 script。

## Verification

```bash
bash scripts/validate-task-md.sh <task.md>
bash scripts/validate-task-md-deps.sh <tasks-dir>
bash scripts/validate-breakdown-ready.sh <task.md-or-dir>
```
