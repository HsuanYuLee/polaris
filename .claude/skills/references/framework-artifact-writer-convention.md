---
title: "Framework Artifact Writer Convention"
description: "Polaris framework artifact writer 必須把 durable artifact 寫到 main checkout，而非 caller worktree CWD 的共用契約。"
---

# Framework Artifact Writer Convention

> 受眾：新增或調整 framework artifact writer（proof-of-work marker、evidence
> 檔、lock、snapshot）的 maintainer。skill 作者不需要從頭讀完。

## 為什麼需要這條契約

Polaris 重度使用 `git worktree add`，包含 `engineering` task worktree、
sub-agent worktree（`.claude/worktrees/agent-{hash}/`）、ad hoc 驗證
worktree，以及 framework workspace 自身的 checkout。每個 worktree 都有
自己的 working directory，但**多數 framework artifact 必須留在 main checkout
的 `.polaris/` 樹**，後續 session、deterministic gate 與 auto-pass
orchestrator 才能跨 worktree 讀到同一份證據。

若 writer 把 caller 的 CWD 當 artifact root，會把 evidence 拆成兩半：一半
落在 `<main>/.polaris/`，另一半落在 `<worktree>/.polaris/`；只掃其中一個
root 的 gate 就會漏看另一個 root 的 marker。DP-226 P5 就是這個 bug：
`engineering` proof-of-work marker 留在 sub-agent worktree 裡找不到。

DP-230 D18 把 **main-checkout resolution** 收斂成一條共用 deterministic
contract，不再依賴每支 script 自己的習慣。

## Contract 條款

1. **Source 共用 helper。** 每支寫 durable framework artifact 的 writer 都
   必須 `source "$(dirname "${BASH_SOURCE[0]}")/lib/main-checkout.sh"`，並
   呼叫 `resolve_main_checkout` 算出 artifact root。
2. **預設輸出 anchor 在 main checkout。** caller 沒指定 `--out` 時，writer
   要把 `resolve_main_checkout` 與該 artifact 的 canonical sub-path（例如
   `.polaris/evidence/completion-gate/`）組合起來；worktree CWD 不是合法的
   artifact root。
3. **顯式 `--out` 優先。** caller 給的絕對 `--out` 路徑保持原樣 — main-checkout
   resolution 只是預設，不是強制重新導向。這條讓 selftest fixture 與 ad hoc
   一次性寫入仍可正常運作。
4. **只有沒有 git context 時才 fallback 到 CWD。** 若 `resolve_main_checkout`
   回空（例如 writer 在非 git scratch dir 跑 selftest），可使用 CWD-relative
   預設；不可在 git context 存在時靜默 downgrade。

## Producer registry 對齊

`scripts/lib/evidence-producers.json` 治理的 marker（`pr_freshness`、
`completion_gate`、`blocked_conflict`、`unsupported_mutation`、`ci_local`、
`verify`）共用同一條 durability 需求。Producer registry 的 path glob
（`.polaris/evidence/<kind>/*.json`）解讀**相對 main checkout**；
`no-direct-evidence-write` hook 與 auto-pass freshness scanner 都假設這個
anchor。

## 目前的 callsite

下列 script 已遵守（或在 AC14 要求下必須遵守）此 convention：

- `scripts/finalize-engineering-delivery.sh` — engineering producer，
  owning writer，把交付 head + verification PASS 寫進 task.md `deliverable` block
  （DP-360 T7 退役 head-sha-keyed `completion_gate` marker 後的單一交付證據 writer）。
- `scripts/run-verify-command.sh` — Layer B `verify` marker writer
  （`<main>/.polaris/evidence/verify/polaris-verified-*.json`），已 source
  `lib/main-checkout.sh`。
- `scripts/check-delivery-completion.sh` — delivery completion evidence 的
  讀寫兩端，已 source `lib/main-checkout.sh`，read / write root 對齊
  engineering producer。
- `scripts/verification-evidence-gate.sh` — 消費
  `.polaris/evidence/verify/*.json` 的 gate，必須解析到 producer 寫入時的
  同一個 root。

非窮舉的 cross-reference 也保留在 `scripts/lib/evidence-producers.json`
（producer path glob）與描述 runtime contract 的
`engineer-delivery-flow*` reference。

## 驗證

- `scripts/selftests/framework-artifact-writer-cwd-selftest.sh` 以 worktree
  fixture 覆蓋示範 writer（`run-verify-command.sh`），assert
  marker 的絕對路徑開頭是 main checkout，不是 worktree。
- `scripts/check-script-manifest.sh` 維持「每支 writer 都登記 owning
  selftest」的契約；新 writer 若遵守本 convention，manifest entry 的
  `selftest` 欄位應指向此 selftest 或等價的 worktree case。

## 非目標

- 本 convention **不**治理 session-scoped scratch artifact（`/tmp/`、
  `${TMPDIR}/`、transient stdout）或 caller 用顯式 `--out` 主動指定的寫入。
- 本 convention 不重新定義 producer registry；只保證 producer 的 path glob
  解析到正確的 root。
