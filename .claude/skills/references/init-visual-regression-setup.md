---
title: "Init Visual Regression Setup"
description: "/init Step 9b 的 visual regression domain、pages、SIT URL、locale 與 Playwright tooling 生成流程。"
---

# Visual Regression Setup Contract

這份 reference 只在 selected projects 包含 web-facing frontend 時設定 visual regression。

## Eligibility

當 project tags 或 repo analysis 顯示 web frontend 時，提供 visual regression setup。例如
Nuxt、Next、Vue、React、`web`、`frontend`，或 product route directories。

若使用者拒絕，`visual_regression.domains` 保持 empty。

## Domain Mapping

將 web projects 映射到 production domains。永遠請使用者 confirm 或輸入 domain。Code
可以從 README、app config、package metadata 提供 suggestion，但 `.env` values 不可靠，
不可自動套用為 production domain。

只提供 Docker 或 nginx 的 infrastructure repos 應標示為 providers，不是 end-user domains。

## Key Pages

每個 domain 從 route files、router config、sitemap references 建議 pages。Dynamic routes
需要使用者提供 concrete examples；只有 route pattern 不可測。偵測到 redirect-only pages
時要 skip。

若 app 有 i18n，從 app config 讀 exact locale codes。Primary locale 預設測；再詢問是否
加入 additional locales。

## SIT Or Local Baseline

永遠詢問 SIT 或 staging URL。不可從 `.env` 推導，因為 local development URLs 與 staging
URLs 常常不同。

若沒有 stable SIT URL，visual regression 使用 local before/after mode 與 git stash。

## Server Config Resolution

Visual regression `server` block 描述 screenshot 如何連到 domain，可能不同於 app 自己的
dev command。

Resolution：

1. 若 Step 9a 找到作為 HTTP entry point 的 infrastructure dependency，使用該 dependency
   的 start command 與 base URL。
2. 若 app 是 standalone HTTP server，使用 app 自己的 runtime contract。
3. 兩條路徑都合理時，列出選項請使用者選。

Resulting config populates `visual_regression.domains[]`：

| Field | Source |
|---|---|
| `name` | confirmed production domain |
| `server.start_command` | runtime entry or infra entry |
| `server.ready_signal` | runtime entry |
| `server.base_url` | local dev screenshot URL |
| `server.sit_url` | user-provided staging URL, optional |
| `locales` | primary plus selected extras |
| `locale_strategy` | detected or user-confirmed |
| `pages[]` | confirmed page list with viewports and source project |

## Test File Generation

Config 寫入後，產生 domain tooling 到 `polaris-config/{company}/visual-regression/`：

- shared `package.json` with `@playwright/test` when absent
- `{domain}/playwright.config.ts`
- `{domain}/pages.spec.ts`

使用既有 example domain templates 作為 implementation reference。Domain mappings、page
counts、SIT availability、locales、generated files 都要 audit。
