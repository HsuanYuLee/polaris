---
title: Quick Start
description: Polaris specs quick start.
---

# Polaris Specs

Polaris Specs 是本機閱讀介面，用來瀏覽 design plans、ticket specs、task work orders 與 archived implementation records。

可以從 sidebar 開始，也可以直接進入代表性 specs：

- [Status Dashboard](/docs-manager/status/)
- [Archived DP inventory sweep: DP-075](/docs-manager/specs/design-plans/archive/dp-075-framework-backlog-convergence/plan/)
- [Active discussion: DP-110](/docs-manager/specs/design-plans/dp-110-verification-report-evidence-dashboard/)
- [Archived design plan: DP-063](/docs-manager/specs/design-plans/archive/dp-063-docs-manager-source-unification/plan/)

## Runtime Toolchain

Polaris 的 docs viewer、Mockoon fixtures 與 Playwright verification 是 required runtime tools。初始化或修復環境時使用 root runner：

```bash
bash scripts/polaris-toolchain.sh install --required
bash scripts/polaris-toolchain.sh doctor --required
```

常用入口也可走 root `pnpm` alias；alias 只代理到 framework scripts，不承擔機制實作：

```bash
pnpm toolchain:doctor
pnpm viewer:status
pnpm scripts:check
pnpm commands:check
```

Status Dashboard 會顯示 required toolchain 缺失與 repair command。新增或移動 specs 後，
framework 只更新 canonical files 與 route metadata；docs viewer 的啟動、停止與重啟由
使用者決定。

```bash
bash scripts/polaris-toolchain.sh run docs.viewer.dev
```

撰寫與檢查內容時使用 dev mode；驗證 production search 行為時使用 preview mode。
