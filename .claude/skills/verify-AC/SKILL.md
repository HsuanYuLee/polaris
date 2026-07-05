---
name: verify-AC
description: >
  QA agent: executes Epic AC (Acceptance Criteria) verification against an AC ticket or Epic.
  Runs all AC steps, classifies each as PASS/FAIL/MANUAL_REQUIRED/UNCERTAIN, and presents
  observed vs expected as pure facts (no root-cause judgement).
  On FAIL, surfaces human disposition gate (spec issue vs implementation drift); on PASS,
  it may transition the AC ticket to Done only after verification artifact/report is current
  and the shared verification contract resolves to PASS.
  Trigger: "驗 PROJ-123", "verify {TICKET}", "verify AC", "跑驗收", "AC 驗證".
  NOT for planning or implementation: implementation drift routes to refinement Bug source mode;
  spec issue routes back to refinement.
metadata:
  author: Polaris
  version: 1.2.0
---

# verify-AC — Epic 驗收 QA

Pipeline 的 QA agent。每次 full re-run AC steps，將 observed vs expected 當事實呈現，
不判斷 root cause。PASS 轉驗收單 Done；FAIL 進 human disposition gate。

## Contract

`verify-AC` stateless + comment-driven。它不改 code、不建 branch、不判斷 FAIL 原因、不只跑
上次 FAIL 的 AC。Implementation drift route 到 `refinement Bug source mode`；spec issue route 到
`refinement`。

Handbook exemption：verify-AC 不做 code diagnosis，預設不強制讀 repo handbook。FAIL 後由
refinement Bug source mode 讀 handbook 定位原因。

寫 verification report、V*.md lifecycle metadata 或 handoff artifact 前，必讀
`pipeline-handoff.md` § Artifact Schemas，再讀 `task-md-schema.md` 等對應
artifact-specific schema。atom ownership 邊界（V*.md envelope vs refinement.json
verification authority）以 `pipeline-handoff-atom-matrix.md` 為準；SKILL 主文不複製
完整 schema 表。

## Reference Loading

| Situation | Load |
|---|---|
| Any run | `verify-ac-entry-flow.md`, `pipeline-handoff.md`, `workspace-config-reader.md`, `shared-defaults.md` |
| Environment | `verify-ac-environment-prep.md`, `epic-folder-structure.md` |
| Step execution and evidence | `verify-ac-execution-flow.md`, `evidence-upload-bundle.md` when visual/manual files need upload, `handoff-artifact.md` when cross-check needed |
| JIRA report and transition | `verify-ac-reporting-flow.md`, `workspace-language-policy.md`, `external-write-gate.md`, `epic-verification-structure.md` |
| FAIL disposition | `verify-ac-disposition-flow.md`, `starlight-authoring-contract.md`, `refinement Bug source mode-acfail-flow.md`, `refinement-return-inbox.md` |
| Learning and lifecycle | `verify-ac-learning-lifecycle-flow.md`, `post-task-reflection-checkpoint.md` |

Epic mode 若委派 sub-agent 驗 AC，必須讀 `sub-agent-roles.md` 並注入 Completion
Envelope；Codex runtime / model fallback contract 見該 reference § Runtime Adapter
Contract / Fallback Behavior。

## Flow

1. 解析 input：AC verification ticket、Epic key，或詢問使用者。
2. Epic mode 展開所有 AC verification tickets，依 `depends_on` 排序。
3. 檢查 loop count；同一 AC 多輪未通過時先警告。
4. 讀 AC verification steps；缺步驟則標 `UNCERTAIN` 並要求補 AC。
5. 需要 local / fixture 環境時，依 environment prep reference 啟動。
6. 逐步執行 curl / Playwright / native VR runner / source inspection / structured checks；若
   refinement AC 使用 `verification.method: challenger`、`docs-health` 或
   `feedback-signals`，分別 dispatch `scripts/verify-ac-newbie-challenger.sh`、
   `scripts/verify-ac-docs-health.sh`、`scripts/verify-ac-feedback-signals.sh`。
7. 每步分類 `PASS`、`FAIL`、`MANUAL_REQUIRED`、`UNCERTAIN`。
8. 收集 evidence，寫 local verification folder；有視覺/影片/manual evidence 時先產 upload bundle，再視需要上傳 JIRA attachments。
9. 若本輪有 V*.md work order，先用 `scripts/write-ac-verification.sh` 寫回
   `ac_verification` / `ac_verification_log[]`，並讓 helper 驗證 V schema；寫回失敗即停。
10. 寫 JIRA verification report；shared verification contract 為 PASS 時才轉 Done，FAIL 顯示 disposition，PENDING 等人工。
11. 記錄 verify-ac-gap learnings 與 post-task reflection。

## Deterministic Consumption (DP-230 D30)

verify-AC 與 framework-release closeout 的 verification method/detail authoritative source
是 `refinement.json`，**不是** task.md `acceptance_criteria` 文字段。對齊規則：

- `refinement.json` `acceptance_criteria[].verification.method` ∈
  `{unit_test, manual, playwright, lighthouse, curl, challenger, docs-health,
  feedback-signals}`，runner 依 method 各自 dispatch 對應 runner（unit_test 跑
  `verification.detail` 命令、manual 走人工 checklist、playwright 走 playwright
  runner、其餘 method 走既有 reference 對應 dispatcher）。
- verify-AC **不得** 從 task.md `acceptance_criteria` 文字 derive verification
  method；task.md acceptance text 僅作 advisory display，不影響 runner 行為。
- 當 fixture task.md `acceptance_criteria` 與 `refinement.json` drift 時，runner
  以 `refinement.json` 為準，advisory log task.md drift；下一輪 `/breakdown`
  會 deterministic 重產 task.md 覆蓋 drift（DP-230 D28）。
- `/framework-release-closeout` parent-closeout 直接讀 `refinement.json`
  acceptance / verification 結構，**不讀** task.md `acceptance_criteria` 文字段；
  parent lifecycle 由 `mark-spec-implemented.sh` 透過 frontmatter status 推進，
  不消費 task.md acceptance text。
- 這條 contract 由 `scripts/selftests/verify-AC-deterministic-consumption-selftest.sh`
  enforce：selftest grep SKILL.md 與 `scripts/framework-release-closeout.sh` 標記，
  並以 fixture drift case 驗 runner method resolution 使用 refinement.json。

POLARIS_VERIFY_AC_DETERMINISTIC_CONSUMPTION_MARKER: verify-AC 與 framework-release
closeout 消費 refinement.json verification.method/detail，不讀 task.md acceptance text。

## Canonical / Standalone Handoff Contract（DP-296 AC6）

verify-AC 作為 consumer，預設 traverse **canonical** `refinement.json`
`acceptance_criteria` verification method/detail schema（見上方 Deterministic
Consumption），**不**改去解析 task.md acceptance text 或上游 LLM freeform prose 來決定
runner 行為。verify-AC 作為 producer，寫入 canonical verification artifact 與
proof-of-work marker 給 closeout 機械消費。LLM freeform 只在 **standalone** 情境合法——
亦即該產出沒有下游 pipeline consumer 會機械消費它（例如對使用者呈現 observed vs expected
的解釋性 prose）。會被下一段 skill / closeout 機械消費的 handoff artifact 一律走 canonical
schema。本契約只約束 handoff artifact 介面，**不**約束 verify-AC 內部如何判讀 observed
結果。完整契約見 `.claude/skills/references/pipeline-handoff.md` § Canonical Schema
Traversal Contract。

## Hard Rules

- HTTP verification 必須先檢查 status code，再看 body。
- Observed 不等於 Expected 就是 FAIL，不可壓通過。
- MANUAL_REQUIRED / UNCERTAIN 不可自動 PASS。
- `skill says PASS` 不等於 stage pass；只有 verification artifact / report current，且 shared verification contract
  resolve 為 PASS，才可做 downstream transition（例如 AC ticket Done）。
- V*.md lifecycle metadata 不可手寫；每輪 AC verification 結束後必須透過
  `scripts/write-ac-verification.sh` 原子覆寫摘要並 append history。
- visual AC 若 task.md 宣告 `verification.visual_regression`，必須用 `scripts/run-visual-snapshot.sh`；不可改走舊 `visual-regression` skill。
- FAIL disposition 互斥：implementation drift 或 spec issue，只能選一條。
- JIRA comments、Bug descriptions、spec artifacts 都是 external/user-facing writes，送出前跑 language gate；spec markdown artifacts 也跑 Starlight authoring check。
- DP-201 proof-of-work marker contract 生效後，verify-AC 是 `ac_verification`、
  `spec_issue`、`drift_retry`、`drift_counter`、`audit_closure` 與 `dp198_handoff` marker 的
  owning writer。Marker schema、producer mapping 與 freshness rule 以
  `auto-pass-proof-of-work.md` / `scripts/lib/evidence-producers.json` 為準；JIRA label/comment
  只能作 mirror，不可作為唯一 deterministic marker。
- verification evidence 若寫入 specs-bound `verification/V*/**` 或 `tasks/V*/**`，必須使用
  DP-110 layout：`verify-report.md`、`assets/{raw,images,screenshots,videos,files}/`、
  `links.json`、`publication-manifest.json`。完成後呼叫
  `scripts/validate-verify-evidence-layout.sh {evidence_dir}`；FAIL 時不可宣告 PASS。

## Dispatch Envelope Worktree Resolution (D33)

當 verify-AC 從 `auto-pass` orchestrator dispatch 而來時，envelope 必須帶上
`worktree_resolution`，路徑由 `scripts/resolve-task-worktree.sh` 解析（schema 與行為以
`.claude/skills/auto-pass/SKILL.md` § Dispatch Envelope Worktree Resolution 為 single source
of truth）。

receiver-side 合約：

- `worktree_resolution.status=FOUND`：verify-AC 必須在 `worktree_resolution.path` 內
  執行 verify command 與讀取 evidence layout，不得 fall back 到 main checkout。
- `worktree_resolution.status=NONE`：不得自動建 worktree；回 orchestrator 由
  `blocked_by_missing_worktree` 處理，advisory 提示使用者重建。
- envelope 缺 `worktree_resolution` 欄位：fail-stop，stderr
  `POLARIS_DISPATCH_WORKTREE_RESOLUTION_MISSING`。
- envelope `worktree_resolution.path` 與 resolver 輸出（同 source-id / work-item-id）
  drift 時 fail-stop，stderr `POLARIS_DISPATCH_WORKTREE_AMBIGUOUS`。

verify-AC stateless 入口（人工觸發 `verify {TICKET}`、未經 auto-pass）不強制 envelope；
此時 verify-AC 仍可呼叫 resolver 取得當前 worktree path 以對齊 evidence layout writer。

## Producer-Env Writer Rules (DP-228 T10)

`SKILL.md` 是 **documentation pointer**，不是 executable writer。verify-AC 寫入
specs-bound `verification/V*/**`、`tasks/V*/**` 或 `.polaris/evidence/ac-verification/`
等 verify-AC owning_skill paths 的 writer authority 來自 producer-env +
`scripts/lib/evidence-producers.json` registry。

- V*.md lifecycle metadata 與 `ac_verification` verdict marker 都由 deterministic writer
  `scripts/write-ac-verification.sh` 產生，不應直接以 Claude tool 改寫；該流程不需要 agent
  手動 export 環境變數。對 terminal verdict status（PASS / FAIL / MANUAL_REQUIRED /
  UNCERTAIN / BLOCKED_ENV）傳入 `--source-id` / `--work-item-id` / `--head-sha`，writer
  在寫完 V*.md frontmatter 後會額外 emit
  `.polaris/evidence/ac-verification/{work_item}-{head}.json` proof marker，並透過
  `scripts/lib/main-checkout.sh` `resolve_main_checkout` 錨定到 main checkout（即使在
  worktree 內被 auto-pass 呼叫，marker 仍落 main checkout，與 `auto-pass-runner` probe 路徑
  一致）。`--status IN_PROGRESS` 只更新 frontmatter、不 emit marker；marker emit 為純
  Bash file I/O（不經 `POLARIS_SKILL_WRITER` env、與 `no-direct-evidence-write` hook 無關），
  寫入失敗即 fail-stop exit 1。呼叫範例：

```bash
scripts/write-ac-verification.sh <V-task-md> \
  --status PASS \
  --last-run-at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --ac-total 6 --ac-pass 6 --ac-fail 0 --ac-manual-required 0 --ac-uncertain 0 \
  --human-disposition passed \
  --source-id DP-NNN --work-item-id DP-NNN-V1 --head-sha "$head_sha"
```
- 若驗收過程必須直接以 Claude `Write` / `Edit` / `MultiEdit` 寫 verify report 或
  evidence layout 內非 lifecycle metadata 的補充檔（例如 `verify-report.md`、
  `links.json`、`publication-manifest.json` 之外的補充說明），先 `export
  POLARIS_SKILL_WRITER=verify-AC` 再呼叫 Write tool：

```bash
export POLARIS_SKILL_WRITER=verify-AC
# 然後使用 Write tool 寫入 docs-manager/src/content/docs/specs/**/verification/V*/** 或 tasks/V*/**
```

- `POLARIS_SKILL_WRITER` 只允許設成 `verify-AC`；`no-direct-evidence-write` hook 會交叉
  比對寫入路徑是否屬於 verify-AC owning_skill entry，不符即 deny。
- 禁止用 Bash heredoc（`cat > specs/.../verification/V1/verify-report.md <<'EOF'`）寫
  verification evidence；Bash heredoc 不走 hook，繞過 producer-env 認證、DP-110 layout
  validator 與 verification artifact freshness contract。

## Completion

輸出 AC/Epic、overall status、step counts、evidence paths、JIRA transition status、created Bug
keys or refinement route、pending manual items。

## Skill Workflow Boundary Gate (DP-230 D40)

`verify-AC` session 開始時必須呼叫 skill-workflow-boundary baseline writer：

```bash
bash scripts/skill-workflow-boundary-gate.sh --skill verify-AC --start \
  --source-container "$SOURCE_CONTAINER"
```

verify-AC 寫完 verification report / V*.md / refinement-inbox 並準備收尾（或在
/auto-pass cross-skill transition 之前）必須跑：

```bash
bash scripts/skill-workflow-boundary-gate.sh --skill verify-AC --check \
  --source-container "$SOURCE_CONTAINER"
```

verify-AC owning scope 僅限本 source container 的 `verification/V*/**` /
`tasks/V*/**` / `refinement-inbox/**`。任何 owning scope 之外的新增/修改（code、
generated target、refinement.md / refinement.json）會讓 gate exit 1 並輸出
`POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:verify-AC`。

`POLARIS_LANGUAGE_POLICY_BYPASS` / `POLARIS_SKILL_BOUNDARY_BYPASS` 等 env 不能
silence 這個 gate（AC-NEG16）。

## L2 Deterministic Check: post-task-feedback-reflection

完成 write flow 後必須呼叫 `scripts/check-feedback-signals.sh`。

## Post-Task Reflection (required)

見 `post-task-reflection-checkpoint.md`；write 後必跑、不可跳過。
