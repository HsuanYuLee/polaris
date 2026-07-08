---
title: "Verify AC Execution Flow"
description: "verify-AC 的 AC step parsing、environment prep、step execution、PASS/FAIL/MANUAL_REQUIRED/UNCERTAIN classification 與 evidence collection。"
---

# Verify Execution Contract

這份 reference 負責驗證步驟執行與 evidence。

## Step Parsing

從 AC ticket description 讀「驗證步驟」。若缺少可執行步驟，該 AC 標 `UNCERTAIN`，寫 JIRA
comment 要求補充 AC 描述，停止該張。

## Environment

需要 local server、fixtures、Mockoon、或 runtime target 時，讀 `verify-ac-environment-prep.md`。
該 reference 決定 task.md lookup、fixture fallback、start-test-env orchestrator。

`start-test-env.sh` 失敗時標 `UNCERTAIN`。不可自行改 code，也不可把環境失敗判成實作 FAIL。

## Step Execution

每個 step 執行：

1. 操作，例如 curl、Playwright、HTML/source inspection、JSON-LD check。
2. 擷取 observed：HTTP status、response body、screenshot path、DOM evidence、raw output。
3. 對比 expected。
4. 分類。

### Framework DP V Task Regression Scope

Framework DP 的 V 單 / umbrella regression 在 implementation tasks 完成後採分層驗證，不再把
完整 `run-aggregate-selftests.sh` 當成每張 V 單的預設成本。

V 單 verdict 必須先完成 declared direct AC verification；direct AC FAIL /
MANUAL_REQUIRED / UNCERTAIN 時，不得用後續 selftest 結果覆蓋。direct AC PASS 後，verify-AC
必須用 implementation deliverable range 的 changed files 呼叫 `scripts/selftest-affected-runner.sh
--run`，讓既有 affected-selftest closure 決定要跑哪些 framework selftest。這個步驟沿用
affected runner 內建的 filesystem-glob / registry / manifest 規則，不新增第二套
script↔selftest 綁定表。

若 changed-file range 缺失、range 不可信、或 affected runner 回
`POLARIS_AFFECTED_FULL_CORPUS`，V 單必須 fail closed 或升級執行
`scripts/run-aggregate-selftests.sh`。升級後任一非 quarantine selftest 紅燈時，V 單不得標
PASS，必須回報為 FAIL 或依實際 blocker 分類。

release tail / framework PR gate 的 full corpus backstop 不在本節降級；該 backstop 仍作為
release 前全域安全網。本節只把 per-V 預設成本收斂為 direct AC + affected selftests，並在
shared / high-fanout / unknown range 情境保留 full corpus escalation。

### Visual AC native runner

若 task.md 有 `verification.visual_regression`，visual AC 必須使用 native runner：

```bash
bash {polaris_root}/scripts/run-visual-snapshot.sh \
  --task-md {task_md_path} \
  --ticket {AC_TICKET_KEY} \
  --mode baseline \
  --repo {repo_path} \
  --source-container {company_specs_dir}/{EPIC_KEY} \
  --output-dir {company_specs_dir}/{EPIC_KEY}/verification/{run_id}/vr

bash {polaris_root}/scripts/run-visual-snapshot.sh \
  --task-md {task_md_path} \
  --ticket {AC_TICKET_KEY} \
  --mode compare \
  --repo {repo_path} \
  --source-container {company_specs_dir}/{EPIC_KEY} \
  --output-dir {company_specs_dir}/{EPIC_KEY}/verification/{run_id}/vr
```

Runner status mapping：

| Runner status | verify-AC step status |
|---|---|
| `PASS` | `PASS` |
| `BLOCK` | `FAIL` |
| `BLOCKED_ENV` | `UNCERTAIN` |
| `MANUAL_REQUIRED` | `MANUAL_REQUIRED` |
| `SKIP` | `UNCERTAIN` |
| `BASELINE_CAPTURED` without compare | `UNCERTAIN` |

`BLOCK` 只能代表 observed visual output differs from expected visual contract；不要在 verify-AC
內推論 root cause。`BLOCKED_ENV` 是環境或 deterministic fixture 問題，不可判成 implementation FAIL。
在 verify-AC report layer，它可映成 `UNCERTAIN` 供人類閱讀；但在 shared gate / portable schema
layer，若 native artifact 直接提供 `BLOCKED_ENV`，應保留為獨立 blocking outcome，不要壓扁成 pass。

## Classification

| Status | Condition |
|---|---|
| `PASS` | machine-checkable and observed equals expected |
| `FAIL` | machine-checkable and observed differs from expected |
| `MANUAL_REQUIRED` | subjective UX/visual/copy judgment |
| `UNCERTAIN` | ran but assertion semantics are unclear or output nondeterministic |

HTTP endpoint verification 必須先檢查 status code 等於 AC 指定值，預設為 200，再看 body。
只看 body 看起來正確不夠；status 不明時是 `UNCERTAIN` 或 `FAIL`。

## Evidence

Evidence 先存 local verification folder，再視需要 upload JIRA attachments。Evidence 包含：

- screenshots
- curl output
- Playwright trace/report
- VR diff
- response snippets
- environment metadata

若 evidence 含 screenshots、videos、VR diff、trace/report 等需人工檢視或上傳的檔案，必須依
`references/evidence-upload-bundle.md` 產生 Jira upload bundle，並在驗證報告列出 bundle path：

```bash
bash {polaris_root}/scripts/collect-evidence-upload-bundle.sh \
  --repo {repo_path} \
  --ticket {AC_TICKET_KEY} \
  --head-sha {head_sha_under_test} \
  --source-container {company_specs_dir}/{EPIC_KEY} \
  --target jira
```

接著先 dry-run，再依 verify-AC reporting gate 使用 apply 上傳 Jira attachment：

```bash
node {polaris_root}/scripts/publish-jira-evidence.mjs \
  --repo {polaris_root} \
  --manifest {bundle_dir}/publication-manifest.json \
  --links {bundle_dir}/links.json \
  --jira-key {AC_TICKET_KEY} \
  --report {verification_report_md} \
  --dry-run

node {polaris_root}/scripts/publish-jira-evidence.mjs \
  --repo {polaris_root} \
  --manifest {bundle_dir}/publication-manifest.json \
  --links {bundle_dir}/links.json \
  --jira-key {AC_TICKET_KEY} \
  --report {verification_report_md} \
  --apply
```

Bundle / Jira attachment 只是 evidence publication；verify-AC 的 PASS/FAIL/MANUAL_REQUIRED/UNCERTAIN 分類仍以實際
observed evidence 與 AC expected 比對為準。

圖片嵌入 JIRA report 時使用 wiki markup attachment syntax。Standalone local paths 也要列入 final
summary，供人工檢視。
