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
3. 那張單的 context，特別是 `verify-ac` 把一條量測登錄成 `visual-regression` 的 VR assertion 當 oracle 跑時。

若無法判斷，詢問使用者要對哪個 domain 跑 VR。讀 config 時遵守
`workspace-config.yaml`。

## 頁面從哪裡來

兩種情況，來源不同：

| 情況 | 頁面與 viewport | 其餘設定 |
|---|---|---|
| 為一張單跑（`verify-ac` 執行那張單的 VR assertion） | 那條 assertion 寫出的頁面與 viewport。只跑這些，不跑全域清單 | company config 的 domain：server、masks、locales、fixtures |
| 沒有單，使用者直接叫 | company config 的 `pages[]` | 同上 |

assertion 指名的頁面不在 `pages[]` 裡，照樣跑；`name` 用路徑推一個，`wait_for` 與
`scroll_before_capture` 沿用 domain 的設定，沒有就照 Hard Rules 等 deterministic selector。
assertion 寫了「哪一塊會變」時，那一塊加進這一次的 masks，其餘必須前後相同；另外不加
mask 再比一次，確認那一塊真的變了。mask 會畫進截圖，所以 before 也要遮與不遮各拍一份。
不加 mask 的那一次沒有差，先確認 after 真的是新版本，再看 `threshold`：預設的 per-pixel
容忍度分不出兩個相近的深色。

結果寫回那張單：頁面、viewport、比對結果、HTML report 路徑。位置見 `vr-artifact-location.md`。

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

`.claude/skills/visual-regression/scripts/polaris-env.sh start <company> --vr`

這個入口負責 production-equivalent proxy、fixtures、dev server、health checks。若 Docker
layer 失敗，停止；若 dev server 失敗，停止並指向 log path。

記錄 cleanup command，後續無論結果如何都要呼叫 stop。

## API Contract Guard

Fixtures active 時，在 screenshot 前依 `api-contract-guard.md` 跑 contract check。Breaking
drift 需展示 report，讓使用者選擇先更新 fixture 或帶 warning 繼續。環境不可達時 warn and
continue。
