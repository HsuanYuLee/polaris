---
title: "Onboard Runtime Setup Flow"
description: "onboard Step 9a 的 dev environment runtime contract 偵測、dependency resolution 與 validation 規則。"
---

# Runtime Contract Setup

這份 reference 設定 `projects[].dev_environment`。它不是參考資訊，而是可被
`scripts/polaris-env.sh` 與 engineering runtime verification 消費的 executable contract。

## Detection

每個 selected project 派 bounded sub-agent，並注入 `sub-agent-roles.md` 的 Completion
Envelope。Sub-agent 掃描：

| Source | Purpose |
|---|---|
| compose files | Docker start command 與 exposed HTTP entry |
| `package.json` | `dev`, `start`, `serve` scripts 與 package manager |
| Makefile | common local targets |
| README setup section | required services 與 run order |

若 repo 是 monorepo，偵測 workspaces，列出有 dev scripts 的 apps 或 packages。不要猜
哪個 app 是 main target；必須詢問使用者。

## Cross-repo Dependencies

Individual scans 後比對 projects 的 runtime dependencies：

- Compose volume mounts 指向 sibling repos。
- Env examples 或 docs reference sibling service names、ports、paths。
- README 出現 "requires X to be running" 類型描述。
- nginx 或 Docker stack proxy 到 app servers。

寫入前先展示 dependencies。若某 repo 是另一個 repo 的 HTTP entry point，把它放到
`requires`。

若 start command reference `.env.local` 等 env file，但 repo 沒有 template 或 example
file，必須警告使用者。

## Required Fields

每個 runtime project 的 `dev_environment` 必須包含：

| Field | Rule |
|---|---|
| `install_command` | recommended；standard install 可由 fallback detector 推導 |
| `start_command` | runtime projects required |
| `ready_signal` | required |
| `base_url` | project 直接提供 HTTP 時 required |
| `health_check` | readiness verification URL |
| `requires` | required array，沒有 dependency 時為 empty array |
| `env` | present object，未使用時為 empty object |

真正 static-only 的 project 可 skip runtime setup。Web frontends、API servers、HTTP entry
point repos 不可 skip。

## Template Alignment

`_template/workspace-config.yaml` 的 `projects[].dev_environment` 範例必須維持與本
reference 一致，至少包含：

```yaml
dev_environment:
  install_command: "npm install"
  start_command: "npm run dev"
  ready_signal: "ready"
  base_url: "http://localhost:3000"
  health_check: "http://localhost:3000/health"
  requires: []
  env: {}
```

若新增或移除 required field，必須同步更新：

- `_template/workspace-config.yaml`
- `scripts/onboard-doctor.sh`
- `scripts/onboard-doctor-selftest.sh`
- 本 reference 的 Required Fields 表格

## Presentation

每個 project 顯示 start command、ready signal、base URL、health check、prerequisites。
寫入前允許使用者調整 row values。

常見調整包含 base URL、ready signal、env keys、install command、dependency order。

## Validation

`onboard` 進入下一步前，確認 runtime entries 可被下列入口消費：

`scripts/polaris-env.sh start <company> --project <repo>`

若 runtime project 缺 required fields、health check 不是 URL，或 dependencies 與偵測圖
矛盾，該 onboard section 視為未完成。Detected values、dependency warnings、
env-template warnings、final confirmed values 都要 audit。
