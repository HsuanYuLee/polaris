---
name: onboard
description: "Use when the user wants to onboard a company workspace from scratch, add a company, or rerun workspace setup. Primary trigger: 'onboard'. Deprecated aliases: 'init', '/init', 'initialize', 'setup workspace', '初始化'."
metadata:
  author: Polaris
  version: 4.0.0
---

# Onboard — Workspace Setup Wizard

互動式 wizard，負責建立或更新 company workspace config，並把 company route 登記到
root `workspace-config.yaml`。

`init` / `/init` / `re-init` 是 deprecated aliases，只作相容入口；新的 skill source、
reference loading 與文件語言都以 `onboard` 為主。

## Contract

`onboard` 只負責 setup orchestration：

- 從 `_template/workspace-config.yaml` 建立或編輯 `{company}/workspace-config.yaml`。
- 在 root `workspace-config.yaml` 登記 company routing。
- 從 `_template/rule-examples/` scaffold company-scoped L2 rules。
- 探測 optional integrations，但 optional 系統不可阻塞 onboard 完成。
- 所有偵測值都必須先顯示給使用者確認，再寫入。

不要猜缺漏值。Auto-detection 只能提供 suggestion，必須經使用者確認。每個 optional
section 都可 skip；skip 後欄位保持空值，下游 skills graceful degrade。

## Reference Loading

依使用者選到的路徑只讀需要的 references：

| Situation | Load |
|---|---|
| Any `onboard` run | `onboard-interaction-patterns.md`, `onboard-core-workflow.md`, `workspace-config-reader.md`, `workspace-language-policy.md` |
| Existing company / upgrade rerun | `onboard-core-workflow.md` rerun section |
| `onboard repair` / readiness check | `onboard-core-workflow.md`, `onboard-post-setup-flow.md`, `workspace-config-reader.md` |
| Project repo detection | `onboard-interaction-patterns.md`, `sub-agent-roles.md` |
| Dev environment setup | `onboard-runtime-setup-flow.md`, `dependency-consent.md` |
| Visual regression setup | `onboard-visual-regression-setup.md`, `visual-regression-config.md` |
| Daily learning scanner | `learning-setup-flow.md`, `daily-learning-scan-spec.md` |
| Runtime toolchain / Codex bootstrap / handbook | `onboard-post-setup-flow.md`, `repo-handbook.md` as needed |

Repo analysis 或 dev environment detection 派 sub-agent 時，必須注入
`sub-agent-roles.md` 的 Completion Envelope。

## Flow

1. 解析 workspace root，讀取 root config。
2. 判斷 full onboard、edit existing company、rerun missing sections，或 cancel。
3. 確認 root language preference 存在，後續 prompt 全部使用該語言。
4. 依 loaded references 收集 company basics、GitHub、JIRA、Confluence、Slack、
   Kibana、projects、scrum、infra、runtime、visual regression 設定。
5. 寫入前顯示完整 YAML；`default_company` 只能在 root config，不可進 company config。
6. 寫入 company config、更新 root company routing、append audit entries。
7. 執行 optional post-setup：clone missing repos、genericize maps、MCP health check、
   daily learning scanner、required toolchain install、Codex bootstrap、handbook generation。
8. 執行 `scripts/onboard-doctor.sh`，回報 `ready` / `partial` / `blocked`、deferred empty
   fields、Codex bootstrap status 與建議的第一個指令。

## Write Rules

- Config writes 只寫 local，且必須 idempotent。
- Root config 只 append 或 update 目標 company。
- 不可因新增 company 移除或重寫既有 companies。
- Rerun 只 merge 新收集 sections，不破壞既有 user-provided fields。
- Repair mode 必須先顯示 doctor summary，再依 action class 決定是否可自動修復。
- Config 不可存 secrets，即使 company config 是 gitignored。
- Setup extensions 若觸及 Slack、JIRA、Confluence、GitHub external write surface，
  發送 user-visible text 前必須通過 `workspace-language-policy.md` language gate。

## Output Rules

產出的 company config 遵守 `_template/workspace-config.yaml`：

- YAML 使用 two-space indentation。
- Template 原本有 inline comments 的欄位保留 comments。
- Skipped optional scalar fields 使用 empty strings。
- Template 預期為 arrays 的欄位保持 arrays。

每個 user decision 與 auto-detection result 都 append 到
`{company}/.onboard-audit.jsonl`；re-run 時 append restart marker。

## Completion

回報完成前：

1. 掃描產出的 company config，列出 empty string deferred fields 與補值方式。
2. 若曾提供 Codex bootstrap，顯示 bootstrap status。
3. 執行 `post-task-reflection-checkpoint.md` checklist。

## Post-Task Reflection (required)

Final response 前執行 shared reflection checkpoint。
