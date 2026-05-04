---
title: "Onboard Core Workflow"
description: "onboard 的核心公司設定流程：precheck、language、company basics、GitHub、JIRA、Confluence、Slack、Kibana、projects、scrum、infra 與 write。"
---

# Core Setup Contract

這份 reference 負責 `onboard` 在 runtime 與 post-setup extensions 之前的公司設定流程。

## Precheck, Rerun, And Repair

若 root `workspace-config.yaml` 存在，先讀取並顯示 existing companies。接著詢問要
add company、edit existing company、rerun missing upgrade sections、repair readiness，
或 cancel。

Rerun 時讀取選定 company config，只執行缺漏 sections：

| Section | Missing when |
|---|---|
| Dev environment | `projects[].dev_environment` absent or incomplete |
| Visual regression | `visual_regression.domains[]` absent |
| Scrum | `scrum` missing or empty |
| Daily learning | `daily_learning_scan` absent |

新收集的 values merge 回 existing config；不可刪除 user fields。

`onboard repair` 先執行：

```bash
bash scripts/onboard-doctor.sh --workspace <workspace-root>
```

Doctor 結果為 `blocked` 時，只處理 required local config 修復，例如 root config、
company routing、company config path。Doctor 結果為 `partial` 時，依 missing checks
補 dev environment、visual regression、daily learning、Codex generated parity 或
toolchain follow-up。Doctor 結果為 `ready` 時，不改 config，只輸出下一個可執行指令。

## Language

檢查 root `language:`。若存在，所有 prompts 使用該語言。若不存在，詢問語言代碼
例如 `zh-TW` 或 `en`，並寫成 root config top-level field，位置在 `companies:` 之前。
此 decision 必須寫入 audit。

## Company Basics

詢問 company name。可 trim whitespace 並 lowercase simple cases。因為此值會成為
directory name，只允許 ASCII lowercase 與 hyphens。若 company 已存在，提供 edit，
不可 overwrite。

建立 company directory，並從 `_template/workspace-config.yaml` 複製起始 config。
從 `_template/rule-examples/` scaffold `.claude/rules/{company}/`，並在每個 copied file
的 H1 後插入 scope header。

## GitHub

透過 GitHub CLI 列出 available orgs。若只有一個 org，prefill 並請使用者確認；若多個
org，顯示 numbered selection；若無法偵測，改問 manual input。Detected orgs 與 final
selection 都要 audit。

## JIRA

詢問 Atlassian instance，並在可用時用 visible-project MCP discovery。Presentation 需包含
project key、name、description、team。Preselect recent activity projects；若數量少則可全選。

Selection 後，一次詢問缺漏 team names。接著確認 selected keys 是否就是使用者平常輸入的
ticket prefixes。`custom_fields` 先留空，日後再設定。

## Confluence

詢問是否使用 Confluence。若使用，優先 reuse Atlassian instance，選 primary space，
再詢問是否有 additional spaces。Common page IDs 透過 targeted CQL 搜尋：

| Field | Search intent |
|---|---|
| `folders.sasd` | SA/SD folder |
| `pages.standup_parent` | standup parent page |
| `pages.release_parent` | release parent page |
| `pages.rd_workflow` | RD workflow |
| `pages.skills_reference` | skill reference |
| `pages.estimation_guide` | estimation guide |

Multiple matches 必須請使用者選。No match 保持空值，除非使用者手動填入。

## Slack, Kibana, Scrum, Infra

Slack：詢問是否使用 Slack；可用時搜尋 channel names，並映射到 `pr_review`、
`ai_notifications`、`worklog_report`。

Kibana：若使用，收集 host、index pattern、environments。

Scrum：顯示 approval threshold、review label、sprint capacity、excluded bots defaults，
並允許調整。

Infra：只有使用者有 deployment 或 ansible repos 時才收集 repo paths。

## Projects

掃描 company base directory 找 local git repos，接著列出 GitHub org repos 並 cross-reference
local status。GitHub listing 沒回傳但本機存在的 local-only repos 也要顯示。若選到
local-only repo，從 origin URL 推導 repo metadata。

Repo selection 後，依 `onboard-interaction-patterns.md` 做 AI repo detection，填入 project
`tags` / `keywords`，再請使用者 confirm 或 adjust。

## Review And Write

寫入前顯示完整 generated YAML。確認 `default_company` 不在 company config；default
company 只屬於 root config。

使用者確認後：

1. 寫入 `{company}/workspace-config.yaml`。
2. 在 root `workspace-config.yaml` add 或 update target company entry，base directory
   必須使用 actual absolute path。
3. 若這是唯一 company，詢問是否設定 top-level `default_company`。
4. Append write audit entries。
