---
title: "Visual Regression Principles"
description: "visual-regression 的 domain-level testing 原則、production proxy、CSR readiness、mobile UA、fixture strictness 與 first-run quality gate。"
---

# VR Principle Contract

這份 reference 保存 visual regression 的 hard-won rules。違反這些規則會造成 flaky
screenshots、漏抓 regression，或把錯誤 fixture 誤判成 pass。

## Domain-level Testing

VR 的測試單位是 domain，例如 `www.example.com`，不是 repo。Configured pages 由 URL path
決定；即使某頁由另一個 service 提供，也仍屬於同一個 domain 的視覺面。

Skip 必須有明確原因：

- Domain 未設定 VR config。
- Dependency 被使用者拒絕。
- Local mode 下 working tree clean，沒有可比對變更。
- Smart skip 確認 changed files 不影響任何 configured `source_project`。
- Fixture 尚未建立。
- SSR 已知 hang，需另開修復工作。
- 必要環境依賴缺失。

## Production-equivalent Proxy

VR 必須經過 production-equivalent proxy，例如 nginx 或 Caddy。不可直接打 app dev port。
Proxy 才會把 domain paths route 到正確 upstream services；直接打單一 app port 只測到其中
一個 service，會漏掉 cross-service routing 問題。

若 proxy 壞掉，要修 proxy，不要繞過它。

## CSR Readiness

CSR content 常在 `networkidle` 後才 render，因為 hydration 會再觸發 client-side fetches。
不要用 fixed timeout 猜等待時間。Page spec 應提供 deterministic selector，等到只有資料
render 完才會出現的 DOM element。

## Mobile SSR

使用 UA-based SSR detection 的網站，只設 375px viewport 不夠。Server 還是可能回 desktop
layout。Mobile Playwright project 必須設定 mobile user agent，並確認 app 的 SSR detection
方法。

## Fixture Strictness

Proxy mode 會隱藏 missing fixtures：未 match 的 request 可能 fallback 到 SIT，因此頁面看起來
正常。Replay mode 才會暴露 missing route，例如 CSR 區塊變 skeleton 或 404。

Fixtures active 時，API data 是 deterministic。任何 visual diff 都不是 data variation；
diff 只能是 intentional change 或 regression。

## First-run Quality Gate

Zero-diff 不代表截圖正確。兩次錯的一樣，也會 zero-diff。

第一次 fixture setup 或 fixture change 後，必須 human review screenshots，確認沒有灰色
skeleton、錯誤 mobile layout、空內容、或缺少重要區塊。未確認前不可發布 JIRA report。

## Sequential Execution

Playwright tests 必須 `workers: 1`。Parallel tests 會同時打 shared Mockoon 與 dev server，
造成 timeout、不完整 response、memory pressure，並讓 screenshot 結果不穩。

## JIRA Report Surface

Inline screenshots 必須使用 JIRA REST API v2 wiki markup。MCP markdown comment 無法可靠嵌入
ticket attachments。Report template 見 `vr-jira-report-template.md`。
