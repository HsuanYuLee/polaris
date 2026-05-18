# Engineer Delivery Flow Index

這份薄索引是 `engineering` delivery 的穩定入口。DP-188 將原本單一大型流程拆成分段 reference，同時保留相同 backbone 與 gate 順序。

## Phase References

| Phase | Reference | Scope |
|-------|-----------|-------|
| Context | `engineer-delivery-flow-index-context.md` | delivery contract、role matrix、design principles |
| R0 | `engineer-delivery-flow-R0-preflight.md` | simplify、self-review、scope gate、rebase |
| R1 | `engineer-delivery-flow-R1-ci-verify.md` | local CI mirror 與 behavioral verify |
| R2 | `engineer-delivery-flow-R2-flow-vr.md` | flow gap audit 與 visual regression |
| R3 | `engineer-delivery-flow-R3-base-commit.md` | base freshness、commit、changeset |
| R4 | `engineer-delivery-flow-R4-pr-jira.md` | PR create / local extension handoff / JIRA transition |
| R5 | `engineer-delivery-flow-R5-completion-cleanup.md` | completion gate、cleanup、halting conditions、evidence model |

## Consumer Contract

- `engineering-first-cut-flow.md` 先讀此索引，再只載入目前 role / gate 需要的 phase。
- Developer 與 Local Extension role 共用相同 phase 順序；local extension policy 可以增加 tail checks，但不能移除 evidence gates。
- 修改 delivery semantics 時，必須在同一張 task 內同步更新相關 phase reference 與 deterministic scripts。

## Backbone

完整順序維持如下：

```text
scope -> rebase -> ci-local -> verify -> flow-gap -> VR if triggered -> base freshness -> commit -> PR/local extension -> completion gate -> cleanup
```

Developer completion gate 也會消費 `engineering-branch-setup.sh` 在 fresh worktree 建立時寫入的 planner-owned baseline snapshot。若 snapshot 缺失，或 `Verify Command`、`depends_on`、`Base branch`、`Allowed Files` 任一欄位與 snapshot 不一致，屬於 scope-escalation blocker；engineering 不得就地修改 task.md，或建立 post-hoc snapshot evidence 來通過 closeout。
