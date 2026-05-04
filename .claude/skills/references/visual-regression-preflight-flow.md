---
title: "Visual Regression Preflight Flow"
description: "visual-regression 執行前的 domain resolution、config inheritance、smart skip、dependency consent、comparison path 與 environment setup。"
---

# VR Preflight Contract

這份 reference 負責 screenshots 前的所有準備。

## Domain Resolution

從以下來源判斷 active domain：

1. Git branch 或 project context 對應到 company config 的 project，再找
   `visual_regression.domains[]`。
2. 使用者明確提到的 domain。
3. JIRA ticket 或 DP task context，特別是 engineering 觸發時。

若無法判斷，詢問使用者要對哪個 domain 跑 VR。讀 config 時遵守
`workspace-config-reader.md`。

## Config Availability

若 company config 找不到 matching `visual_regression.domains[]` entry，停止並提示使用者
先在 company workspace config 設定該 domain。不可臨時猜 pages、server、或 base URL。

## Smart Skip

若每個 configured page 都有 `source_project`，比較 changed files 與 page source projects。
沒有任何 affected source project 時，skip 並說明此次變更不影響畫面。

若任一 page 缺 `source_project`，不可 safe skip，必須繼續。

Local comparison path 若 working tree clean，skip 並回報 nothing to compare。

## Dependency Consent

讀 root config 的 `dependencies.playwright.status`：

| Status | Action |
|---|---|
| `consented` | Verify installed；missing 時透過 framework toolchain install |
| `declined` | 靜默 skip，並在 output 附註 playwright 未安裝 |
| `pending` / missing | 依 `dependency-consent.md` 詢問 |

Domain config 有 fixtures block 時，也要透過 toolchain verify `fixtures.mockoon` capability。

## Config Inheritance

Effective config 由 root defaults 與 company domain config merge：

- `threshold`
- `full_page`
- `browsers`
- `timeouts.*`
- `server.sit_url`
- `server.base_url`
- `server.start_command`
- `server.ready_signal`
- `fixtures.*`
- `pages[]`
- `global_masks`
- `locales`
- `locale_strategy`

Domain value 優先；空值才 fallback 到 root defaults。

## Comparison Path

SIT path：`server.sit_url` configured 且 health check 可達時，before 使用 SIT/staging URL，
after 使用 local dev server。

Local path：沒有 SIT、SIT 不可達、或使用者指定 local 時，before 使用 stash 前 local dev，
after 使用目前變更。

使用者強制 SIT 但 SIT 不可達時，回報錯誤並詢問是否 fallback Local。

## Environment Setup

先 verify Playwright toolchain，不可安裝到 product repo。接著使用 shared environment entry：

`scripts/polaris-env.sh start <company> --vr`

這個入口負責 production-equivalent proxy、fixtures、dev server、health checks。若 Docker
layer 失敗，停止；若 dev server 失敗，停止並指向 log path。

記錄 cleanup command，後續無論結果如何都要呼叫 stop。

## API Contract Guard

Fixtures active 時，在 screenshot 前依 `api-contract-guard.md` 跑 contract check。Breaking
drift 需展示 report，讓使用者選擇先更新 fixture 或帶 warning 繼續。環境不可達時 warn and
continue。
