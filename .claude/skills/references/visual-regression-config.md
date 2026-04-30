# Visual Regression Config Schema

visual-regression skill 的 config 結構說明。測試對象是 **domain**（使用者看到的網站），不是 repo。

**比對模式：Before/After + Per-Epic Baseline**
- 每次執行抓兩組截圖（before + after），diff 完即刪
- 利用 Playwright `--update-snapshots` 建暫時 baseline，正常 run 比對
- VR baseline 永久存 `specs/{EPIC}/tests/vr/baseline/`（見 `references/epic-folder-structure.md`）
- Mockoon fixtures 存 `specs/{EPIC}/tests/mockoon/`（per-epic 隔離）

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

VR 分為 **tooling（domain-level）** 和 **data（per-epic）** 兩層：

### Tooling（domain-level）
```
ai-config/{company}/visual-regression/
  ├── package.json              # 共用 Playwright 依賴（跨 domain 共享）
  ├── node_modules/             # 共用安裝
  ├── record-fixtures.sh        # VR 錄製工具
  └── {domain}/
      ├── playwright.config.ts  # Playwright 設定（讀 VR_BASE_URL env var）
      ├── pages.spec.ts         # 測試案例（從 config 生成初版，用戶可修改）
      ├── snapshots/            # 暫存：before 截圖（跑完即刪）
      ├── test-results/         # 暫存：diff 圖片（跑完即刪）
      └── playwright-report/    # HTML report（保留供檢視，不 commit）
```

### Data（per-epic，見 `references/epic-folder-structure.md`）
```
specs/{EPIC}/tests/
  ├── mockoon/                  # Mockoon environment JSONs（per-epic 隔離）
  │   ├── dev.example.com.json
  │   └── ...
  └── vr/
      └── baseline/             # VR baseline screenshots（永久，per-epic 快照）
          ├── homepage-zh-tw-1280.png
          └── ...
```

- Tooling 層是 domain-level：所有 Epic 共用同一個 Playwright 和測試設定
- Data 層是 per-epic：每個 Epic 有獨立的 fixtures 和 baseline
- `snapshots/` 和 `test-results/` 是暫時的 — skill 執行完即清除
- 不需要 commit 任何截圖檔案（specs/ 已 gitignore）

### Playwright config 必設項目

`playwright.config.ts` 生成時必須包含以下設定：

| 設定 | 值 | 原因 |
|------|---|------|
| `workers` | `1` | 多 test 並行會打爆 Mockoon + dev server 的 shared port，造成 timeout、記憶體不足、截圖不完整。見 SKILL.md P6 |
| mobile project `userAgent` | iPhone UA string | UA-based SSR detection（如 `@nuxtjs/device`）需要 mobile UA 才會回 mobile layout。只設 viewport 375px 不夠。見 SKILL.md P3 |

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
| `runner` | string | 是（如果有 fixtures block） | Runner 腳本路徑（如 `~/work/scripts/mockoon/mockoon-runner.sh`）。Skill 在 runtime 組合 `{runner} start {company_specs_dir}/{EPIC}/tests/mockoon` 啟動 |
| `stop_command` | string | 是（如果有 fixtures block） | 停止 fixture server 的指令 |
| `health_ports` | number[] | 否 | 健康檢查端口列表 |
| `ready_signal` | string | 是（如果有 fixtures block） | 同 server.ready_signal 邏輯 |
| `shared_config_dir` | string | 否 | 跨 Epic 共用 config 目錄（proxy-config.yaml 等）。見 `references/epic-folder-structure.md` |

整個 fixtures block 是 optional。打 SIT 時通常不需要 fixtures（SIT 有自己的資料）。

**Fixture 路徑解析**：不再使用 `environments_dir` + `active_epic` 拼接。Skill 從 active Epic context 推導 mockoon 路徑：`{company_specs_dir}/{EPIC}/tests/mockoon/`。

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
| `viewports` | number[] | 是 | 截圖寬度列表（px）。**注意：** 375px viewport 不等於 mobile。如果站台使用 UA-based SSR detection（如 `@nuxtjs/device`、`mobile-detect`），Playwright config 必須同時設定 mobile `userAgent`，否則 SSR 仍回 desktop layout。見 SKILL.md P3 |
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

# company: ~/work/acme/workspace-config.yaml
visual_regression:
  domains:
    - name: "www.example.com"
      server:
        start_command: "docker compose -f ~/work/acme/acme-web-docker/docker-compose.yml up -d"
        ready_signal: "ready"
        base_url: "https://dev.example.com"
        sit_url: "https://sit.example.com"
      fixtures:
        type: "mockoon"
        runner: "~/work/scripts/mockoon/mockoon-runner.sh"
        stop_command: "~/work/scripts/mockoon/mockoon-runner.sh stop"
        health_ports: [4001, 4002]
        ready_signal: "Started"
        shared_config_dir: "~/work/acme/mockoon-config"
      global_masks:
        - "[data-testid*='date']"
        - "[data-testid*='price']"
        - ".ad-banner"
      locales: ["zh-TW", "en"]
      locale_strategy: "url_prefix"
      pages:
        - name: "homepage"
          path: "/"
          source_project: "acme-web-app"
          viewports: [1280, 375]
          scroll_before_capture: true
        - name: "product-page"
          path: "/product/2825"
          source_project: "acme-web-app"
          viewports: [1280, 375]
          masks: ["[data-testid='review-count']"]
```
