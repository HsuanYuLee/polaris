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

Bundle 只是人工上傳來源；verify-AC 的 PASS/FAIL/MANUAL_REQUIRED/UNCERTAIN 分類仍以實際
observed evidence 與 AC expected 比對為準。

圖片嵌入 JIRA report 時使用 wiki markup attachment syntax。Standalone local paths 也要列入 final
summary，供人工檢視。
