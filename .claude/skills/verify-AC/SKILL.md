---
name: verify-AC
description: >
  QA agent: executes Epic AC (Acceptance Criteria) verification against an AC ticket or Epic.
  Runs all AC steps, classifies each as PASS/FAIL/MANUAL_REQUIRED/UNCERTAIN, and presents
  observed vs expected as pure facts (no root-cause judgement).
  On FAIL, surfaces human disposition gate (spec issue vs implementation drift); on PASS,
  transitions the AC ticket to Done.
  Trigger: "驗 PROJ-123", "verify {TICKET}", "verify AC", "跑驗收", "AC 驗證".
  NOT for planning or implementation: implementation drift routes to bug-triage;
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
上次 FAIL 的 AC。Implementation drift route 到 `bug-triage`；spec issue route 到
`refinement`。

Handbook exemption：verify-AC 不做 code diagnosis，預設不強制讀 repo handbook。FAIL 後由
bug-triage 讀 handbook 定位原因。

## Reference Loading

| Situation | Load |
|---|---|
| Any run | `verify-ac-entry-flow.md`, `pipeline-handoff.md`, `workspace-config-reader.md`, `shared-defaults.md` |
| Environment | `verify-ac-environment-prep.md`, `epic-folder-structure.md` |
| Step execution and evidence | `verify-ac-execution-flow.md`, `evidence-upload-bundle.md` when visual/manual files need upload, `handoff-artifact.md` when cross-check needed |
| JIRA report and transition | `verify-ac-reporting-flow.md`, `workspace-language-policy.md`, `external-write-gate.md`, `epic-verification-structure.md` |
| FAIL disposition | `verify-ac-disposition-flow.md`, `starlight-authoring-contract.md`, `bug-triage-acfail-flow.md`, `refinement-return-inbox.md` |
| Learning and lifecycle | `verify-ac-learning-lifecycle-flow.md`, `post-task-reflection-checkpoint.md` |

Epic mode 若委派 sub-agent 驗 AC，必須注入 `sub-agent-roles.md` 的 Completion Envelope。

## Flow

1. 解析 input：AC verification ticket、Epic key，或詢問使用者。
2. Epic mode 展開所有 AC verification tickets，依 `depends_on` 排序。
3. 檢查 loop count；同一 AC 多輪未通過時先警告。
4. 讀 AC verification steps；缺步驟則標 `UNCERTAIN` 並要求補 AC。
5. 需要 local / fixture 環境時，依 environment prep reference 啟動。
6. 逐步執行 curl / Playwright / native VR runner / source inspection / structured checks。
7. 每步分類 `PASS`、`FAIL`、`MANUAL_REQUIRED`、`UNCERTAIN`。
8. 收集 evidence，寫 local verification folder；有視覺/影片/manual evidence 時先產 upload bundle，再視需要上傳 JIRA attachments。
9. 寫 JIRA verification report；PASS 轉 Done，FAIL 顯示 disposition，PENDING 等人工。
10. 記錄 verify-ac-gap learnings 與 post-task reflection。

## Hard Rules

- HTTP verification 必須先檢查 status code，再看 body。
- Observed 不等於 Expected 就是 FAIL，不可壓通過。
- MANUAL_REQUIRED / UNCERTAIN 不可自動 PASS。
- visual AC 若 task.md 宣告 `verification.visual_regression`，必須用 `scripts/run-visual-snapshot.sh`；不可改走舊 `visual-regression` skill。
- FAIL disposition 互斥：implementation drift 或 spec issue，只能選一條。
- JIRA comments、Bug descriptions、spec artifacts 都是 external/user-facing writes，送出前跑 language gate；spec markdown artifacts 也跑 Starlight authoring check。

## Completion

輸出 AC/Epic、overall status、step counts、evidence paths、JIRA transition status、created Bug
keys or refinement route、pending manual items。

## 11. L2 Deterministic Check: post-task-feedback-reflection

完成 write flow 後必須呼叫 `scripts/check-feedback-signals.sh`，再執行 Post-Task Reflection。

## Post-Task Reflection (required)

Execute `post-task-reflection-checkpoint.md` before reporting completion.
