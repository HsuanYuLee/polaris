---
title: "Delivery Unit Completion Standard"
description: "Canonical contract defining delivery-unit completion standard (D1), research-unit handling (D2), and dispatch/theme-unit handling (D3) for Polaris refinement-owned sources."
---

# Delivery Unit Completion Standard

> 本 reference 是 delivery unit 結案標準的 canonical contract。它定義：哪些東西可以成為
> 獨立 delivery unit（DP-backed 或 JIRA Epic-backed source）、研究單與轉發/theme 單為何
> 不算 delivery unit，以及它們各自的正確收編路徑。由
> `.claude/rules/canonical-contract-governance.md` routing pointer 指向；refinement /
> breakdown / engineering 在規劃與 LOCK source 時必須對齊本契約。

## D1 — Delivery Unit Completion-Standard Contract

**一個 delivery unit 必須具備 runtime-verifiable 的結案標準；form / format proxy 不算結案。**

「delivery unit」指任何被當成獨立交付容器、會走 `breakdown -> engineering -> verify-AC`
主鏈並期待 `IMPLEMENTED` / `RELEASED` 終局的 refinement-owned source（DP-backed 或 JIRA
Epic-backed）。要成為合法 delivery unit，必須同時滿足：

1. **結案標準是 runtime-verifiable 的**：至少一條 AC 的驗證方式是可機械執行的觀察
   （`unit_test` / selftest / gate exit code / runtime behavior / curl / dev server），
   不是只靠人讀文件判斷「看起來做完了」。
2. **存在合法 writer / 結案路徑**：交付物落在有 producer registry entry 或 sanctioned
   writer 的路徑；不得交付到「被 `no-direct-evidence-write` 保護但沒有任何 producer」的
   gitignored 路徑——那種路徑寫不進去也結不了案，屬於 hollow completion。
3. **至少一張 implementation task**：source 內必須有真正改變 framework / product 行為的
   implementation task（`task_shape: implementation`），而不是全部都是 audit /
   confirmation。

### Form proxy 不算結案（反面定義）

下列「形式上像完成」的訊號都 **不** 構成 D1 結案標準，單獨出現時視為 hollow completion：

- 只 grep 到 status 字串改成 `IMPLEMENTED` / `SUPERSEDED`，但 container 仍殘留 in-flight
  ledger / task work order / planned_tasks amendment。
- 只產出一份「研究結論」或「audit 報告」prose，沒有任何 deterministic gate / selftest
  把該結論落地成可重複驗證的行為。
- AC 全部是 `manual`「人讀確認」且無任何可機械執行的對照。

### Why

結案標準若只看 form proxy，source 會在「文件寫好了」的假象下被宣告完成，但實際上沒有任何
機制保證它解決了所述問題（功能完整原則）。runtime-verifiable 標準把「做完」綁定到可重複
觀察的事實，符合 canonical-contract-governance 的 **Strong constraints first** 與
**Fail closed on missing inputs**。

## D2 — Research Unit（研究單）

**定義**：研究單是「全部 task 皆 audit / 無任何 implementation task」、且交付物本質是
研究結論 / 盤點 / audit 報告，本身沒有 runtime-verifiable 結案標準的 source。

### 判定訊號（三訊號，須對齊 DP-262 task_shape classifier）

研究單判定 **必須** 命中以下全部條件，避免誤擋合法 implementation DP：

1. **task_shape**：source 內 **全部** task 皆為 `audit`（無任何 `implementation` task）。
   「含部分 audit / confirmation task」的 mixed-task source 不算研究單（見 § Edge Cases）。
2. **AC verifiability**：沒有任何 AC 具備可機械執行的結案標準（全部是 `manual` 人讀）。
3. **production-contract 改動**：交付物不改動任何 framework / product 行為契約
   （無 code / rule / gate / schema 變更，只產出研究文字）。

判定一律 banks on 既有 `validate-breakdown-ready.sh` 的 task_shape 解析，**不另寫第二套
classifier**（避免與 DP-262 判定 drift）。

### 處理方式

研究是 **refinement-phase activity**，不可獨立成 delivery unit：

- 研究單的 scope **收編進** 一個或多個 implementation DP 的 refinement seed（research →
  refinement input），由該 implementation DP 在自己範圍內做 gap 盤點並落地成
  verifiable AC。
- 既有研究單偵測到時，由 D4 deterministic gate 在 LOCK / breakdown 階段 fail-stop（exit 2
  + `POLARIS_*` marker），要求改走「收編進 implementation DP refinement」路徑，而非讓它
  獨立走主鏈。
- 歷史上已 RELEASED 的同類研究 umbrella **不追溯 unlock**；僅記為 precedent，往後由 D4
  gate 擋同類重現。

## D3 — Dispatch / Theme Unit（轉發 / theme 單）

**定義**：轉發 / theme 單是「自己不產 concrete 交付物、無自身 verifiable AC，只 dispatch /
指派到其他 concrete DP」的 source。它承載方向 / 北極星 / 主題 ownership，但不是 delivery
unit。

### 判定訊號

1. **無自身 verifiable AC**：所有 AC 都是描述方向或主題，沒有綁定本 source 自己的
   runtime-verifiable 結案標準。
2. **deliverable 僅 dispatch**：實際交付被指向其他 concrete delivery unit（例如「本 theme
   由 DP-NNN 承載實際 delivery」），本 source 自身不留 concrete diff。

### 處理方式

- 轉發 / theme 單 **改寫成 north-star artifact**（方向 / 主題容器），**禁止**成為 delivery
  DP，也不得期待 `complete` / `IMPLEMENTED` 終局。
- north-star artifact **必須定義 supersede 訊號**，避免無 lifecycle 永久 stale：當被它
  seed / dispatch 的 concrete delivery DP 全部 `IMPLEMENTED` 時，該 north-star artifact
  自然標記為 superseded。
- 既有轉發單偵測到時，由 D4 deterministic gate 在 LOCK / breakdown 階段 fail-stop（exit 2
  + `POLARIS_*` marker），要求改寫成 north-star artifact，而非讓它獨立走 delivery 主鏈。

## Edge Cases

- **合法 implementation DP 含部分 audit / confirmation task（DP-262 carve-out）**：研究單
  判定條件必須是「全部 task 皆 audit 且無 implementation task」才命中；只「含 audit task」
  不算研究單。mixed-task source（implementation + audit）必須 PASS，不得被研究單 gate
  誤擋。
- **north-star artifact 無 lifecycle 易 stale**：透過 D3 supersede 訊號（被 seed 的
  concrete DP 全 IMPLEMENTED 即標 superseded）綁定 lifecycle，不是只刪 delivery 標記。
- **未來 audit 偽裝成 implementation task 規避 D4 gate**：gate 判定嚴格對齊 D2 三訊號
  （task_shape + AC verifiability + production-contract 改動），不是只看 task 標籤字串。

## Enforcement

D1 / D2 / D3 不依賴 prose-only（對齊 contract-design.md § Deterministic-First）：

- **D4 deterministic gate**：`scripts/validate-breakdown-ready.sh` 偵測研究單 / 轉發單，
  fail-stop exit 2 + `POLARIS_*` marker；`scripts/validate-refinement-lock-preflight.sh`
  委派同一判定，在 LOCK 時就擋下。判定 banks on 既有 task_shape classifier，不另寫第二套。
- 本 reference 的條文同時被 D4 gate selftest 機械驗證，避免退化成「只出 rule prose」的
  半研究單。

## Cross-Reference

- `.claude/rules/canonical-contract-governance.md` — 本 reference 的 routing pointer 來源；
  D1 對齊其 Strong constraints first / Fail closed on missing inputs。
- `.claude/rules/handbook/framework/contract-design.md` — Deterministic-First heuristic
  （D4 gate 為何必須機械落地）。
- `scripts/validate-breakdown-ready.sh` / `scripts/validate-refinement-lock-preflight.sh`
  — D4 gate 與 LOCK preflight 委派。
