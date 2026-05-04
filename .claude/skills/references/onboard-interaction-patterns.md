---
title: "Onboard Interaction Patterns"
description: "onboard 的 smartSelect、AI repo detection、audit trail 與 sub-agent completion envelope 規則。"
---

# Interaction Pattern Contract

這份 reference 定義 `onboard` 共用互動規則。

## smartSelect

可 discovery 的 sections 使用 detect -> present -> confirm：

1. 透過 CLI、MCP tools、static defaults，或 bounded repo analysis 偵測。
2. 用 table 顯示 pre-selected recommendations，並保留來源脈絡。
3. 詢問 Confirm、Adjust、Skip。

Adjust 代表使用者可 toggle row 或修改值，然後重新顯示 table。Skip 會讓該 section
保持空值；但 hard contract 例外，例如需要 dev server 的 project runtime config。

使用 smartSelect 的 sections：

| Section | Detection |
|---|---|
| JIRA projects | Atlassian visible projects MCP |
| Confluence page IDs | targeted CQL search |
| Projects | local repo scan, GitHub repo list, AI analysis |
| Scrum settings | static defaults |

GitHub org、Confluence enablement、Slack、Kibana、infra 預設使用 simple prompt；只有
偵測到多個合理選項時才改用 selection table。

## AI Repo Detection

Project repos 選定後，分析每個 repo 以產生 routing metadata。派 parallel sub-agents
時必須注入 `sub-agent-roles.md` 的 Completion Envelope；detail 寫到 temp artifact，
回傳只保留 summary fields。

每個 repo 的 detection sources：

| Source | Extract |
|---|---|
| `package.json` | framework、key dependencies、description |
| `src/`, `pages/`, `app/` | page names、feature areas、route patterns |
| Dockerfile / compose files | service role |
| repo name | tag candidates |
| README first section | purpose 與 domain keywords |

若 local clone 不存在，可 fallback 到 GitHub API content reads。若分析失敗，回傳空
`tags` / `keywords`，在 row 上標示 uncertain，並請使用者手動補值。

Tags 是短的 lowercase routing labels，通常一到兩個詞。Keywords 是給 fuzzy matching
用的人類可讀 phrases。

## Audit Trail

每個 decision append 一行 JSON 到 `{company}/.onboard-audit.jsonl`。

Required fields：

| Field | Meaning |
|---|---|
| `ts` | ISO 8601 timestamp |
| `step` | onboard step number or decimal extension |
| `section` | config section name |
| `action` | `auto-detect`, `ai-detect`, `mcp-detect`, `confirm`, `adjust`, `skip`, `write`, `check`, or `complete` |
| `value` | detected or confirmed value |
| `source` | `cli`, `mcp`, `ai`, `user`, `default`, `config`, or `system` |

Audit 是 append-only。重跑 `onboard` 時，先 append restart marker，再寫入新 entries；
不可覆寫舊 audit lines。
