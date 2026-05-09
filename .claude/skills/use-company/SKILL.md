---
name: use-company
description: >
  Sets the active company context or diagnoses company routing.
  Two modes: (1) Set — declare which company to work with, bypassing auto-detection.
  (2) Diagnose — show which company a JIRA ticket or project routes to.
  Trigger keywords: "use company", "switch company", "切換公司", "用這間", "/use-company",
  "set company", "公司切換", "我要做 X 公司的", "which company", "哪間公司", "/which-company".
user-invocable: true
---

# /use-company — Active Company Context Switcher

## Purpose

明確設定目前對話要使用哪個 company context，避免在多公司 workspace 中反覆 auto-detect，
或因 routing 歧義導致用錯設定。

## Workflow

Shared authority: `bash scripts/resolve-company-context.sh`

### Step 1 — Resolve Target Company

**If the user provides a company name:**
1. Run `bash scripts/resolve-company-context.sh --company "<name>" --format json`
2. If `status=ok` → proceed with resolved payload
3. 若 `status=error` → 直接呈現 resolver 的 fail-stop diagnostics；skill 內不得自己重寫 YAML matching

**If no company name provided:**
1. Run `bash scripts/resolve-company-context.sh --format json`
2. If `status=ok` → proceed with resolved payload
3. 若 `error_code=default_company_unset` → 列出已註冊公司，請使用者選擇
4. 其他 resolver error 一律直接回報 fail-stop diagnostics；不得默默猜測

### Step 2 — Load and Validate Company Config

1. 把 resolver output 視為 `base_dir`、`config_path`、`github.org`、`jira.projects` 的單一 authority
2. 若 resolver 回傳 `status=error`，就停止並直接回報該錯誤
3. 對非 blocking 的 `warnings[]` 才能用 warning 呈現；不得把 resolver failure 降格成 advisory prose

### Step 3 — Confirm Context

以簡短摘要回報：

```
✓ Active company: {company_name}
  Base dir:     {base_dir}
  GitHub org:   {github_org}
  JIRA projects: {project_keys}
  Slack:        {configured channels or "not configured"}
```

### Step 4 — Inform Strategist

要明確告知：「在這段對話剩餘流程中，所有工作都應透過 **{company_name}** context routing。
套用 `.claude/rules/{company_name}/` 的 L2 rules，並從 `{base_dir}/workspace-config.yaml`
 解析 config。」

## Notes

- 這只會設定 **目前這段對話** 的 context，不會跨對話持久化
- 若使用者之後提到另一間公司的 ticket，要明確警告 context mismatch

## Diagnostic Mode

當使用者提供 JIRA ticket key 或 project prefix，而且目的是查 routing、不是設定 context 時，
就顯示 routing resolution：

```
🔍 Routing Diagnostic

Ticket:    PROJ-123
Company:   acme
Base dir:  {base_dir}
Config:    {base_dir}/workspace-config.yaml

Resolved via: jira.projects[].key match ("PROJ")
```

若找不到 match，列出所有已註冊公司與其 JIRA project keys。

若存在潛在問題，也要明確標出：例如 config file 缺失、`jira.projects` 未定義、或多間公司宣告相同 project prefix。

Diagnostic mode must also consume the shared resolver:

- `bash scripts/resolve-company-context.sh --ticket PROJ-123 --format json`
- `bash scripts/resolve-company-context.sh --project PROJ --format json`

skill 可以為了可讀性重排 resolver 結果，但不得自創另一個 routing verdict。


## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
