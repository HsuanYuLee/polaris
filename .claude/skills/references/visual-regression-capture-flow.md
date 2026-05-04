---
title: "Visual Regression Capture Flow"
description: "visual-regression before/after screenshot capture、Local stash flow、Playwright compare 與 temporary artifacts 規則。"
---

# Screenshot Capture Contract

這份 reference 負責 before / after screenshots 與 Playwright compare。

## Before Capture

Before capture 使用 Playwright `--update-snapshots` 建立 temporary baseline。Snapshots
寫在 domain tooling 的 `snapshots/`，執行後會刪除，不 commit。

SIT path：

- `VR_BASE_URL` 設為 `server.sit_url`。
- 使用 domain `playwright.config.ts`。
- 只建立 temporary snapshots，不分析 diff。

Local path：

1. Stash current changes，記錄 stash ref。
2. 等 dev server hot reload；用 health check polling，不用固定 sleep。
3. `VR_BASE_URL` 設為 `server.base_url`，執行 `--update-snapshots`。
4. `stash pop` 還原目前變更。
5. 再次等待 hot reload。

若 hot reload polling 逾時，abort，提示使用者手動重啟 dev server。若 stash pop 失敗，
保留 stash ref 並停止，避免覆蓋工作狀態。

## After Capture And Compare

After capture 一律 against local dev server。使用相同 `playwright.config.ts`，但不帶
`--update-snapshots`，讓 Playwright 自動比對 Step Before 建立的 snapshots。

Playwright outputs：

| Output | Meaning |
|---|---|
| exit code 0 | 所有 screenshots match |
| exit code 1 | 至少一個 screenshot diff |
| `test-results/` | diff images 與 failed test artifacts |
| `playwright-report/` | HTML report，保留給使用者檢視 |

## Page Spec Requirements

Generated Playwright specs 應遵守：

- 每個 page 使用 configured path、locale、viewports。
- `global_masks` 套用到每張 screenshot。
- CSR-heavy pages 使用 deterministic wait selector。
- Mobile project 若 app 使用 UA-based SSR，必須設定 mobile user agent。
- `workers: 1`。

## Temporary Artifact Policy

`snapshots/` 與 `test-results/` 是此次 run 的 temporary artifacts，cleanup 時刪除。
`playwright-report/` 可保留，供使用者透過 toolchain show-report 檢視。

Standalone run 不上傳 artifacts。Ticket verification flow 必須在 cleanup 前收集 after
screenshots 與 diff images。
