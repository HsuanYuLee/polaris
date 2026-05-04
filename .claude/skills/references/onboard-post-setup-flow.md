---
title: "Onboard Post Setup Flow"
description: "onboard 的 repo clone、genericize mapping、MCP health、daily learning、toolchain、Codex bootstrap 與 handbook generation 流程。"
---

# Post Setup Contract

這份 reference 負責 company config ready 之後的 optional 與 final `onboard` actions。

## Clone Missing Repos

比對 selected projects 與 company base directory 下的 directories。提供 clone all、select
repos、skip 三種選項。透過 GitHub CLI sequential clone，避免 rate limits，並逐 repo 顯示
progress。Cloned 與 skipped repos 都要 audit。

## Genericize Mapping Files

從收集到的 config 產出 `{company}/genericize-map.sed` 與 `{company}/genericize-jira.sed`：

- 複製 `_template/genericize-map.sed` 與 `_template/genericize-jira.sed`。
- 有值時填入 domain、GitHub org、repo、project、company name、path、ticket key、
  Confluence、Slack channel、team-name replacements。
- Repo names replacements 先排長字串，再排短字串，避免 partial match。

輸出提醒使用者檢查 internal URLs、teammate names，以及 `onboard` 無法推導的其他 values。

## MCP Health Check

檢查已設定的 MCP connectors，但不可阻塞 wizard：

| Server | Required when |
|---|---|
| Atlassian | JIRA or Confluence configured |
| Slack | Slack configured |
| Google Calendar | optional |
| Figma | optional |

Report connected、not configured、skipped、failed。Required connector 失敗時，提醒相依
skills 在 MCP setup 修好前不可用。每個 server status 都要 audit。

Shell doctor 不直接呼叫 Slack、JIRA、Confluence MCP，也不宣稱 external write 成功。
`scripts/onboard-doctor.sh` 只輸出 connector 需要 runtime check 的 fact；active agent
runtime 取得 user confirmation 後，才可做外部讀取或後續登入檢查。

## Daily Learning Scanner

詢問是否設定 daily learning scanner。若接受，從 `learning-setup-flow.md` 的 preference
collection 開始，因為 `onboard` 已確定這是 setup run。若拒絕，記錄 disabled state，並告知
之後可用 learning setup commands 啟用。

## Required Runtime Toolchain

透過 root toolchain runner install 並 verify Polaris required tools：

- install required tools
- doctor required tools

若任一步失敗，保留 partial state，並提供 `scripts/polaris-toolchain.sh` repair command。
不可隱藏 partially healthy toolchain。Status Dashboard 與 Quick Start 需持續顯示 failure
直到修復。Install 與 doctor status 都要 audit。

## Codex Bootstrap

詢問使用者是否也在此 workspace 使用 Codex。若是，執行 cross-runtime bootstrap：

- sync skills to agents with links
- sync Codex MCP baseline
- transpile rules for Codex
- verify Claude/Codex parity
- run Codex compatibility doctor

若 Codex CLI 不存在或 bootstrap 任一步失敗，warn and continue。Audit 是否 linked skills、
synced MCP，以及 doctor passed。

## Deferred Fields And Next Steps

掃描 generated company config 的 empty string values。只有存在 empty fields 時才顯示
deferred fields table，包含 section、field、日後補值方式。

若 Codex bootstrap 曾被 offered，永遠顯示 bootstrap status。

接著提供第一個可試的 commands，例如 JIRA work command 與 standup generation。

## Completion Dashboard Contract

onboard 完成前必須輸出 completion dashboard。Dashboard 不取代 doctor；它是 doctor
結果、人類決策與下一步的合併摘要。

最小欄位：

| Field | Required | Meaning |
|---|---|---|
| `doctor_status` | yes | `ready`、`partial` 或 `blocked` |
| `blocking_checks` | yes | `blocked` 時列 required local config 缺失；沒有則 empty |
| `manual_followups` | yes | `partial` 時列 global CLI、external read、toolchain 等需確認項 |
| `deferred_fields` | yes | generated config 中仍為 empty string 的欄位；沒有則 empty |
| `codex_bootstrap` | yes if offered | `ready`、`partial`、`skipped` 或 `not_offered` |
| `next_command` | yes | 下一個可直接貼給 agent 的 prompt 或 repair command |

狀態輸出規則：

| Doctor status | Dashboard behavior |
|---|---|
| `ready` | 顯示 first useful prompt；不列 repair action |
| `partial` | 顯示可用功能、deferred 欄位、manual follow-up、`onboard repair` 下一步 |
| `blocked` | 顯示 required local config 缺口；next command 必須是 repair 或手動補 config 路徑 |

若 Codex bootstrap 被跳過，不可把 Codex 顯示為 ready；必須標示 `skipped` 或
`not_offered`。若 `deferred_fields` 非空，dashboard 必須保留欄位路徑，避免只輸出
「稍後補設定」。

## Onboard Doctor And Repair Boundary

onboard 完成或 `onboard repair` 時，必須執行：

```bash
bash scripts/onboard-doctor.sh --workspace <workspace-root>
```

Doctor 輸出三種狀態：

| Status | Meaning | Next action |
|---|---|---|
| `ready` | required local setup complete | 顯示第一個可執行 agent prompt |
| `partial` | setup 可用，但有 optional/manual follow-up | 顯示 repair summary 與 deferred fields |
| `blocked` | required config 缺失或不可讀 | 先修 required local config |

Repair mode 的 action class：

| Action class | Examples | Auto-fix policy |
|---|---|---|
| local config | root `workspace-config.yaml`、company config、`projects[].dev_environment` | 顯示 summary 後可自動修 |
| generated parity | `.agents/skills` symlink、Codex generated runtime target | 顯示 summary 後可自動修 |
| global CLI | Codex MCP、global Codex config、required toolchain install | 必須二次確認 |
| external read | Slack / JIRA / Confluence connector login 或 discovery | 只做連線檢查，不寫外部資料 |
| external write | Slack / JIRA / Confluence 寫入 | repair mode 禁止自動執行 |

Completion dashboard 必須包含 doctor status、每個 failing check、action class、可自動修復
與需手動確認的分流，以及下一個可執行指令。不可只說「請看 README」。

## Handbook Generation

Onboard 完成後，詢問是否產生 repo handbooks。若接受，configured repos sequential processing：

1. 依 `repo-handbook.md` 偵測 repo type。
2. Draft handbook。
3. 請使用者 confirm 或 correct。
4. 寫入 `{company}/polaris-config/{project}/handbook/index.md`。

已存在 handbook 的 repos 直接 skip。若使用者拒絕，engineering 第一次使用 repo 時可再產生。
