# Visual Regression Config Schema

visual-regression skill 的 config 結構說明。測試對象是 **domain**（使用者看到的網站），不是 repo。

**比對模式：Before/After（非 Baseline）**
- 不維護長期 baseline 截圖
- 每次執行抓兩組截圖（before + after），比完即刪
- 利用 Playwright `--update-snapshots` 建暫時 baseline，正常 run 比對

## 兩層繼承

```
框架 defaults（root workspace-config.yaml）
  ↓ 公司未設定時繼承
公司 config（{company}/workspace-config.yaml → visual_regression.domains[]）
```

## 框架層 Defaults

位置：`~/work/workspace-config.yaml`

```yaml
defaults:
  visual_regression:
    fixtures_tool: "mockoon"
    browsers: ["chromium"]
    threshold: 0.02
    full_page: true
    timeouts:
      server_startup: 60000
      fixture_startup: 30000
      screenshot: 30000
  e2e:
    runner: "playwright"
    browsers: ["chromium"]
```

## 公司層 Config（per-domain）

位置：`~/work/{company}/workspace-config.yaml` → `visual_regression.domains[]`

```yaml
visual_regression:
  domains:
    - name: "www.example.com"

      server:
        start_command: "..."       # 啟動 local dev 環境
        ready_signal: "..."        # stdout 出現此字串 = ready
        base_url: "..."            # local dev URL
        sit_url: "..."             # SIT/staging URL（不需要起 server）

      fixtures:                    # optional
        type: "mockoon"
        start_command: "..."
        ready_signal: "..."

      global_masks: [...]
      locales: ["zh-TW"]
      locale_strategy: "url_prefix"

      pages:
        - name: "..."
          path: "/"
          source_project: "..."    # 哪個 repo 實作此頁面（用於 smart skip）
          viewports: [1280, 375]
```

## 目錄結構

```
ai-config/{company}/visual-regression/
  ├── package.json              # 共用 Playwright 依賴（跨 domain 共享）
  ├── node_modules/             # 共用安裝
  └── {domain}/
      ├── playwright.config.ts  # Playwright 設定（讀 VR_BASE_URL env var）
      ├── pages.spec.ts         # 測試案例（從 config 生成初版，用戶可修改）
      ├── snapshots/            # 暫存：before 截圖（跑完即刪）
      ├── test-results/         # 暫存：diff 圖片（跑完即刪）
      └── playwright-report/    # HTML report（保留供檢視，不 commit）
```

- `package.json` 在公司 VR 層（非 domain 層），所有 domain 共用同一個 Playwright
- Polaris 生成初版測試檔，用戶可自由新增或修改
- `snapshots/` 和 `test-results/` 是暫時的 — skill 執行完即清除
- 不需要 commit 任何截圖檔案

## 欄位詳細說明

### `server` — Dev 環境啟動

| 欄位 | 型別 | 必填 | 說明 |
|------|------|------|------|
| `start_command` | string | 否 | 啟動 local dev 環境的 shell 指令。可以是 `docker compose up`（micro-frontend）或 `pnpm dev`（單 repo） |
| `ready_signal` | string | 否 | dev server stdout 出現此字串時視為啟動完成 |
| `base_url` | string | 否 | Local dev 環境的 URL |
| `sit_url` | string | 否 | SIT/staging 環境的 URL。設定此值後可直接打 SIT 測試，不需要起 local server |
| `env` | map | 否 | 啟動 dev server 時注入的環境變數 |

**使用邏輯**：
- 有 `sit_url` 且使用者選擇打 SIT → 直接用 `sit_url`，跳過 server 啟動
- 有 `start_command` → 起 local server，用 `base_url`
- 都沒有 → 報錯

### `fixtures` — 測資 Server

| 欄位 | 型別 | 必填 | 說明 |
|------|------|------|------|
| `type` | string | 否 | 工具標識（mockoon / prism / json-server）。用於 log，不影響行為 |
| `start_command` | string | 是（如果有 fixtures block） | 啟動 fixture server 的指令 |
| `ready_signal` | string | 是（如果有 fixtures block） | 同 server.ready_signal 邏輯 |

整個 fixtures block 是 optional。打 SIT 時通常不需要 fixtures（SIT 有自己的資料）。

**為什麼建議使用 fixture server：** 開發期間後端 API 可能調整（欄位變更、資料異動），導致截圖比對出現假陽性。Fixture server 提供穩定、可控的 API 回應，確保 before/after 差異只來自前端代碼變更。

### `global_masks` — 全域遮蔽

型別：`string[]`（CSS selector 陣列）

截圖前，這些 selector 匹配的元素會被純色方塊遮蓋，不參與像素比對。用途：遮蔽每次渲染都不同的動態內容（價格、日期、廣告）。

### `locales` — 多語系測試

型別：`string[]`

skill 會對每個 page × 每個 locale 分別截圖。

| 欄位 | 型別 | 預設 | 說明 |
|------|------|------|------|
| `locales` | string[] | `[""]`（不切語系） | 語系代碼列表 |
| `locale_strategy` | string | `"url_prefix"` | `"url_prefix"` = `/{locale}/path`、`"query"` = `?lang={locale}`、`"cookie"` = 設定 cookie `lang={locale}` |

### `pages` — 關鍵頁面清單

| 欄位 | 型別 | 必填 | 說明 |
|------|------|------|------|
| `name` | string | 是 | 頁面識別名稱，用於截圖檔名 |
| `path` | string | 是 | URL 路徑，接在 base_url 或 sit_url 後面 |
| `source_project` | string | 否 | 實作此頁面的 repo 名稱。用於 smart skip — 當某 PR 只改了特定 repo，只跑該 repo 負責的頁面 |
| `viewports` | number[] | 是 | 截圖寬度列表（px） |
| `masks` | string[] | 否 | 此頁面專屬的 CSS selector mask，與 global_masks 合併 |
| `wait_for` | string | 否 | 截圖前等待此 CSS selector 出現 |
| `scroll_before_capture` | boolean | 否 | `true` = 截圖前先滾到頁底觸發 lazy-load |

截圖命名規則：`{name}-{locale}-{viewport}.png`

## 完整範例

```yaml
# root: ~/work/workspace-config.yaml
defaults:
  visual_regression:
    fixtures_tool: "mockoon"
    browsers: ["chromium"]
    threshold: 0.02
    full_page: true
    timeouts:
      server_startup: 60000
      fixture_startup: 30000
      screenshot: 30000

# company: ~/work/kkday/workspace-config.yaml
visual_regression:
  domains:
    - name: "www.kkday.com"
      server:
        start_command: "docker compose -f ~/work/kkday/kkday-web-docker/docker-compose.yml up -d"
        ready_signal: "ready"
        base_url: "https://dev.kkday.com"
        sit_url: "https://www.sit.kkday.com"
      global_masks:
        - "[data-testid*='date']"
        - "[data-testid*='price']"
        - ".ad-banner"
      locales: ["zh-TW", "en"]
      locale_strategy: "url_prefix"
      pages:
        - name: "homepage"
          path: "/"
          source_project: "kkday-b2c-web"
          viewports: [1280, 375]
          scroll_before_capture: true
        - name: "product-page"
          path: "/product/2825"
          source_project: "kkday-b2c-web"
          viewports: [1280, 375]
          masks: ["[data-testid='review-count']"]
```
