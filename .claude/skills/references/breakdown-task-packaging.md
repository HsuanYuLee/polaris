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
- 若 `stacked-delivery-sibling-epic-policy.md` 判定某 lane 已拆 sibling Epic，該 lane 的第一張
  task 必須在 Operational Context 標示 `Feat branch owner | yes`，後續 task 標示
  `Feat branch owner | no - merges into <TXa>`。

## Task.md Output

產生 task skeleton 前先讀 `authoring-preflight.md`。task.md / V*.md 是 downstream-facing
artifact，所有 planner-authored prose 必須直接使用 workspace policy language 起稿。

每張新 implementation task 預設產 `tasks/T{n}/index.md`，schema 以
`task-md-schema.md` Implementation Schema 為準。Legacy `tasks/T{n}.md` 只作為既有
work order 讀取 fallback，不再作為新產物預設。必備內容：

- frontmatter title / description / status / depends_on。
- Operational Context。
- stacked delivery lane 的 aggregation / feat branch ownership decision。
- Verification Handoff。
- Goal / scope / allowed files。
- Scope Trace Matrix。
- Acceptance / test plan。
- Behavior contract。
- Required Tools（只有 refinement / ticket 明確宣告工單級工具需求時才寫；沒有就省略）。
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

DP-backed implementation task 的 packaging 仍沿用 Epic 正規鏈：

- `breakdown` 只負責產生 engineering 可施工的 releaseable tracked work order。
- Initial-create task.md 的 `## Allowed Files` 由 deterministic derive 從 matched
  `tasks[].modules` task intent 產生；`refinement.json tasks[]` 仍不得攜帶
  `allowed_files` / `estimate_points` 這類 per-task packaging 欄位。
- Re-derive / repair 若帶 `--preserve-from` existing task.md，已 authored 的
  `## Allowed Files` 與 points 優先，必須 byte-identical preserve，不被 task module intent
  覆寫。
- `engineering` 依 task.md 施工、驗證、開 workspace PR。
- 若 local policy 宣告 `framework-release`，它只能作為 engineering PR 之後的 release tail。
- local sample/spec-only recut 不得包成 implementation task；那不是 `engineering` lane。

## Required Tools

若 refinement artifact 有 `tool_requirements[]`，每個會影響 Test Command / Verify Command /
runtime bootstrap 的 entry 都要映射到 task.md `## Required Tools` table。table 是給
engineering setup 的可執行 handoff：`check_command` 用來確認工具是否已存在；
`install_command` 只在有明確且被授權的安裝方式時填入，否則填 `N/A` 並在
`handoff_hint` 說明需要使用者安裝或授權。

`owner=ticket` 或 `runtime_profile=ticket` 的工具一律 `goes_to_mise=false`。這類需求是
單張工單的執行前置條件，不是 framework root runtime contract；除非另有 framework-level
DP 決策，不得把它包進 root `mise.toml`。

## Scope Trace Matrix

每張 implementation task 都要把可觀測目標 trace 到 owning files、使用者或系統邊界、
以及測試。這不是敘述用章節；`validate-breakdown-ready.sh` 會在 handoff 前檢查。

最低格式：

```markdown
## Scope Trace Matrix

| Goal / AC | Owning files | Surface / boundary | Tests |
|-----------|--------------|--------------------|-------|
| release closeout records task metadata | `scripts/framework-release-closeout.sh`, `scripts/check-release-completed.sh` | framework release completion gate | `bash scripts/framework-release-closeout-selftest.sh` |
```

規則：

- 每個 row 對應一個 goal / AC，不可把整張 task 混成單一 vague row。
- `Owning files` 必須是 machine-matchable repo-root path / glob，且必須被
  `## Allowed Files` 覆蓋。
- UI / dashboard / API-visible work 必須列出 render/API boundary；只列 presenter、
  helper、data generator 不夠。
- data → presenter → render 的任務，必須列出實際會動到的層；若任一層不在 scope，
  要在 `Surface / boundary` 說明 boundary。
- target surface 無法判斷時不可填 unknown；回 refinement 補規格或拆成 discovery task。

## Behavior Contract

每張 implementation task 都要讓 engineering 看得出「行為驗證意圖」。寫在
frontmatter `verification.behavior_contract`：

- 使用者可見 UI / runtime 行為不適用：填 `applies: false` 與 `reason`。
- 替換元件、migration、refactor、移除 legacy dependency：預設 `mode: parity`；
  若允許少量刻意差異，改 `mode: hybrid` 並列出 `allowed_differences`。
- Figma 驅動的畫面變更：使用 `mode: visual_target`，source_of_truth 通常為 `figma`。
- PM 提供操作 flow 且沒有要求前後畫面 parity：使用 `mode: pm_flow`，
  source_of_truth 通常為 `pm_flow`。
- 需要既有行為維持，但同時有設計或規格允許差異：使用 `mode: hybrid`，不可留空
  `allowed_differences`。

`applies: true` 時至少填：

```yaml
verification:
  behavior_contract:
    applies: true
    mode: parity
    source_of_truth: existing_behavior
    fixture_policy: mockoon_required
    baseline_ref: develop
    target_url: "/zh-tw/product/12156"
    viewport: mobile
    flow: "open media lightbox, swipe next, close"
    assertions:
      - "modal visible"
    allowed_differences: []
```

若 source ticket / refinement artifact 沒有足夠資訊判斷 mode，不建立 READY task；
回到 refinement 補決策。不得填 `unknown`，也不得把判斷責任留給 engineering。

Active work order backfill 產生的 decision queue 由 breakdown / refinement 消費。處理時只
能做三種決策：

- 補 `applies: false` 與具體 reason。
- 補 `applies: true` 與完整 mode / source_of_truth / fixture_policy / flow / assertions。
- route refinement，要求 PM / RD 補 source of truth。

不得把 queue item 關成 `unknown`，也不得在沒有判斷依據時填假的 parity contract。

## Verification Task Output

需要 V task 時，依 `task-md-schema.md` Verification Schema。新產物預設
`tasks/V{n}/index.md`；legacy `{V-KEY}.md` 仍可讀，但不作為新寫入預設。V task 與 T
task 共用 deps validator，不另造平行 schema。

V*.md producer checklist：

- 先讀 `task-md-schema.md` § 4 Verification Schema。
- frontmatter 不寫 root-level `type`；filename `V{n}` 是唯一 dispatch 訊號。
- `Operational Context` 必須列 Task JIRA key / Parent Epic / Implementation tasks /
  Base branch / References to load。
- `驗收項目` 必須 trace 到對應 T task。
- `驗收步驟` 是 verify-AC driver entry；若 `Level=static` 仍需列出可執行 static checks。
- lifecycle metadata 只能由 `scripts/write-ac-verification.sh` 寫入，不可手寫
  `ac_verification` / `ac_verification_log[]`。

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
