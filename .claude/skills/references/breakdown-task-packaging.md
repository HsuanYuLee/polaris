---
title: "Breakdown Task Packaging"
description: "breakdown branch DAG、task.md / V*.md work order 產出、dependency validation 與 engineering handoff。"
---

# Task Packaging

## Branch Creation

依 `branch-creation.md` 建 branch。使用 topological order 處理 `depends_on` DAG；非線性
DAG 或循環依賴要 fail-stop，回到 planning 調整。

原則：

- 不使用 `git checkout` / `git checkout -b` / `git pull origin develop`。
- 用 `git branch <name> <start>` 與 push 建 branch。
- 無 depends_on 的 task 從 feature/base branch 切。
- 有 depends_on 的 task 從 upstream task branch 切。
- `Branch chain` 從真正 start point 開始；外部 dependency branch 不假裝是本 Epic chain。
- 不新增 `PR base` 欄位；engineering Resolve 層會動態判斷 PR base。

## Task.md Output

每張 implementation task 產 `tasks/T{n}.md`，schema 以 `task-md-schema.md`
Implementation Schema 為準。必備內容：

- frontmatter title / description / status / depends_on。
- Operational Context。
- Verification Handoff。
- Goal / scope / allowed files。
- Acceptance / test plan。
- Test Command。
- Test Environment。
- Gate Closure Matrix。
- Verify Command。

不放入 task.md：

- full Epic description。
- refinement artifact 全文。
- 技術方案比較。
- repo handbook 全文。

References to load 要只列 engineering 真正需要讀的 references，例如
`branch-creation.md`、`task-md-schema.md`、project handbook pointer、relevant refinement
artifact pointer。

## Verification Task Output

需要 V*.md 時，依 `task-md-schema.md` Verification Schema。V task 與 T task 共用 deps
validator，不另造平行 schema。

過渡期若 consumer 仍要求 `{V-KEY}.md` 命名，producer 保持相容；DP-039 atomic cutover
後才切 V{n}.md。

## Validators

每個 task 寫完立即跑：

```bash
scripts/validate-task-md.sh {task_path}
scripts/validate-task-md-deps.sh {tasks_dir}
scripts/validate-breakdown-ready.sh {task_path_or_tasks_dir}
```

Language / Starlight gates 也要針對新寫入 specs Markdown 執行：

```bash
bash scripts/validate-language-policy.sh --blocking --mode artifact {paths}
bash scripts/validate-starlight-authoring.sh check {paths}
```

任何 validator fail：修 artifact，不 handoff engineering。

## Handoff

完成後輸出下一步：

- JIRA task：`做 {TASK_KEY}`。
- DP task：`做 DP-NNN-T1`。

不要額外指定 engineering 的 `next_engineering_task`；engineering resolver 會依
depends_on 與 READY 狀態處理。
