---
title: "Polaris Command Catalog"
description: "Polaris 常用 command surface 的 human-facing catalog；machine-readable source 為 scripts/command-catalog.json。"
---

# Polaris Command Catalog

`scripts/command-catalog.json` 是 machine-readable source of truth。本文件提供人讀摘要。

## Viewer

Docs viewer lifecycle 由使用者擁有。Framework command 只提供穩定入口；除非使用者明確下指令，
否則 framework 不會自行啟動、重新載入、重啟或停止 viewer。

| 用途 | 指令 |
|--------|---------|
| 啟動 dev viewer | `pnpm viewer:dev` |
| 啟動 preview viewer | `pnpm viewer:preview` |
| 查詢 viewer 狀態 | `pnpm viewer:status` |
| 停止 viewer | `pnpm viewer:stop` |
| 驗證 preview route/search | `pnpm viewer:verify` |

## Toolchain

| 用途 | 指令 |
|--------|---------|
| 安裝 required framework toolchain | `pnpm toolchain:install` |
| 檢查 required framework toolchain | `pnpm toolchain:doctor` |
| 輸出 required capability manifest | `pnpm toolchain:manifest` |

## Scripts Governance

| 用途 | 指令 |
|--------|---------|
| 檢查 script inventory manifest | `pnpm scripts:check` |
| 檢查 command catalog | `pnpm commands:check` |

## Maintainer-Only

`framework-release`、`framework-docs-health` 這類 local-only maintainer commands 不屬於 portable
template user command surface。它們可以列在 `scripts/command-catalog.json` 的 maintainer 區塊，
但不能暴露成一般 root package scripts。
