---
title: "Polaris Tool Token Contract"
description: "Polaris root toolchain 與 delivery gate 使用的缺工具 / 認證失敗 token contract。"
---

# Polaris Tool Token Contract

本 reference 是 DP-202 吸收 DP-194 後的 stable contract anchor。Framework scripts、gates、
doctor、release preflight、engineering dependency install helper 若要回報 root toolchain 或
delivery tool readiness failure，必須使用本檔定義的 token shape。

## Scope

適用於 Polaris-owned root execution surface：

- framework root CLI / runtime binary readiness。
- delivery dependency readiness，例如 `gh` binary 與 GitHub auth。
- ticket-scoped tool handoff 被 engineering dependency installer 消費後的 fail-fast 訊息。

不適用於產品 repo 自身 dependency install error、業務 API error、外部服務回應內容，或測試 runner
自己的原生錯誤；這些 surface 可以引用原錯誤，但若轉成 Polaris readiness failure，必須套用下列
token。

## Tokens

### `POLARIS_TOOL_MISSING`

用於工具 binary、runtime、或必要 runtime asset 無法解析時。

```text
[POLARIS_TOOL_MISSING] tool=<name> profile=<core|runtime|delivery> remediation="<command-or-action>"
```

必要欄位：

- `tool`：缺失的工具名稱，例如 `node`、`pnpm`、`gh`、`rg`、`uv`。
- `profile`：缺失發生的 runtime profile，只能是 `core`、`runtime`、`delivery`。
- `remediation`：可執行或可交給人的修復動作。若必須由使用者手動安裝，使用明確 install command 或
  文件入口；不可只寫 `install it`。

範例：

```text
[POLARIS_TOOL_MISSING] tool=gh profile=delivery remediation="devbox run doctor --profile delivery"
```

### `POLARIS_TOOL_AUTH_FAILED`

用於 tool binary 已存在，但外部 auth readiness 不足時。

```text
[POLARIS_TOOL_AUTH_FAILED] tool=<name> profile=<delivery> hint="<command-or-action>"
```

必要欄位：

- `tool`：auth 失敗的工具名稱，目前主要是 `gh`。
- `profile`：必須是 `delivery`。
- `hint`：可執行或可交給人的登入 / 授權修復動作，例如 `gh auth login` 或 root runner 的
  delivery doctor task。

範例：

```text
[POLARIS_TOOL_AUTH_FAILED] tool=gh profile=delivery hint="gh auth login"
```

## Producer Rules

- token 必須出現在 stderr 或 gate failure summary 中，讓 script / agent 可以 deterministic parse。
- 同一個 readiness failure 只輸出一個 primary token；補充文字可以跟在下一行。
- `remediation` / `hint` 不得包含 secret、token、完整 auth config、shell startup transcript。
- 不可 silent fallback 到 GitHub connector、VS Code extension bundled binary、Homebrew path 或使用者
  shell rc；fallback 若被設計為合法 bridge，仍必須有 doctor / resolver evidence。
- 新增 token 或欄位前，必須在同一個 DP-backed task 更新本 reference、producer script selftest 與
  consumer parser。

### Delivery readiness probe carve-out

`command -v gh` 可作為 delivery readiness probe 的穩態 carve-out，但只限下列情境：

- probe 用來判斷 `gh` 是否存在、是否可 fail-open skip、或是否要 fail-closed；不得把
  `command -v` 的結果當成 invocation source of truth。
- 後續 invocation 必須走 `scripts/lib/github-rest.sh` helper、`GH_BIN` indirection、或既有
  delivery wrapper；不得散落 hardcoded binary path。
- fail-closed surface 必須在 stderr 輸出 `POLARIS_TOOL_MISSING` 或
  `POLARIS_TOOL_AUTH_FAILED`。
- 保留裸 `command -v gh` 的站點必須有 inline `D7 readiness-probe carve-out` 註記，讓 direct-call
  audit 能分辨 readiness probe 與 unmanaged invocation。

## Consumer Rules

- engineering / verify / release lane 可以把這兩個 token 分類為 environment readiness failure。
- 若 task-owned tool 有 `Required Tools` 且缺少可執行 install command，engineering 應回報
  `BLOCKED_ENV`，並保留原始 token。
- Consumer 不得用 substring 猜測替代本檔 token；若 producer 沒有 token，視為 producer bug 或
  未治理 surface。
