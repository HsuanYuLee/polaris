---
title: "DP-242 audit-hooks：cross-LLM hook parity audit"
description: "對 .claude/hooks/** 逐 hook 列 cross-LLM parity entry，標 Claude / Codex / Copilot runtime 的 mirrored / advisory / intentional-gap disposition，並以 parity matrix 呈現行為等價對映；audit-only，結論流向 DP-245。"
draft: true
sidebar:
  hidden: true
---

# Cross-LLM Hook Parity 盤點（DP-242 T3）

## Parity 語義宣告

本 audit 採用的 parity 語義是**行為等價（behavior parity），不是檔案 1:1 mirror**。Claude Code
透過 `settings.json` 的 `PreToolUse` / `PostToolUse` / `Stop` / `PreCompact` / `PostCompact` /
`UserPromptSubmit` / `SessionStart` 事件掛載 `.claude/hooks/**` shell hook；Codex 與 Copilot 兩個
runtime **沒有對等的 hook 事件機制**（workspace 內不存在 `.codex/hooks/`，Copilot 只有
`.github/copilot-instructions.md` prose adapter）。因此 hook 級 parity **不可能**也**不應該**用
「每個 `.claude/hooks/*.sh` 在 Codex / Copilot 都有一份對應檔案」來衡量。

正確的衡量單位是 **hook 想保護的 behavior / intent**：

- `mirrored`：該 behavior 在目標 runtime 有**對等的機械 enforcement**（例如 Codex 透過
  `scripts/codex-guarded-git-commit.sh` / `scripts/codex-guarded-git-push.sh` wrapper 呼叫
  與 Claude hook 相同的 portable gate 邏輯）。
- `advisory`：該 behavior 在目標 runtime **沒有機械攔截**，但其規範已 render 進該 runtime 的
  instruction surface（`.codex/AGENTS.md` / `.github/copilot-instructions.md`），靠 agent 自律遵守。
- `intentional-gap`：該 behavior 在目標 runtime **既無機械 enforcement 也無對等 runtime 事件**，
  且這個缺口是**刻意接受**的設計取捨（不是遺漏）。每筆 `intentional-gap` 後面必附一句 rationale。

> 本 audit 為 audit-only 盤點，**不**修改任何 production surface（`.claude/hooks/**`、`scripts/**`、
> runtime adapter）。所有需要決策的 design item 一律 defer 給 DP-245（見文末
> `## Open Questions for follow-up DP`）。

## Parity matrix

下表的 row = hook 想保護的 behavior / intent；column = 三個 runtime 的 disposition。這是行為等價
視角的 parity matrix，與下方逐 hook entry 互為對照。

| Behavior / hook intent | Claude | Codex | Copilot |
|------------------------|--------|-------|---------|
| commit 前 CI mirror / 品質 gate | mirrored（`ci-local-gate` PreToolUse） | mirrored（`codex-guarded-git-commit.sh`） | intentional-gap |
| VERSION staged 時 docs-lint gate | mirrored（`version-docs-lint-gate` PreToolUse） | mirrored（`codex-guarded-git-commit.sh`） | intentional-gap |
| push 前 delivery 品質 gate | mirrored（`pre-push-quality-gate`） | mirrored（`codex-guarded-git-push.sh`） | intentional-gap |
| PR `--base` 防呆 | mirrored（`pr-base-gate` PreToolUse） | advisory | intentional-gap |
| writer-side language policy 攔截 | mirrored（`pre-write-language-policy` PreToolUse） | advisory（`.codex/AGENTS.md` Markdown Authoring Contract） | advisory（`copilot-instructions.md`） |
| 禁止直寫 evidence / specs-bound markdown | mirrored（`no-direct-evidence-write` PreToolUse） | advisory | advisory |
| memory write contract 攔截 | mirrored（`pre-memory-write` PreToolUse） | intentional-gap | intentional-gap |
| memory index 自動再生 | mirrored（`post-memory-index-regenerate` PostToolUse） | intentional-gap | intentional-gap |
| 禁止繞過 work-order resolver 手搜 | mirrored（`no-manual-work-order-search` PreToolUse） | advisory | advisory |
| pipeline artifact schema gate | mirrored（`pipeline-artifact-gate` PreToolUse） | advisory | intentional-gap |
| 提前 stop / 待辦清查 | mirrored（`stop-todo-check` Stop） | intentional-gap | intentional-gap |
| compaction 前後 session state 保存 / 還原 | mirrored（`session-summary-precompact` + `post-compact-context-restore`） | intentional-gap | intentional-gap |
| session 結束摘要備援 | mirrored（`session-summary-stop` Stop） | intentional-gap | intentional-gap |
| feedback reflection / trigger 提醒 | mirrored（`feedback-*` Stop / PostToolUse） | intentional-gap | intentional-gap |
| memory decay scan / warm scan 提示 | mirrored（`memory-decay-scan` SessionStart + `cross-session-warm-scan` UserPromptSubmit） | intentional-gap | intentional-gap |
| version bump 提醒 | mirrored（`version-bump-reminder` PostToolUse） | advisory | advisory |
| specs sidebar 同步（legacy no-op） | mirrored（`specs-sidebar-sync` PostToolUse no-op） | intentional-gap | intentional-gap |

## 逐 hook parity entry

每筆 entry 採 D2 8 欄 schema：`| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |`。
`role` 欄細分為三個 runtime 的 parity disposition（格式 `Claude=… / Codex=… / Copilot=…`）。

### 1. ci-local-gate.sh

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| `.claude/hooks/ci-local-gate.sh` | Claude=mirrored（PreToolUse git commit / push / `gh pr create`） / Codex=mirrored（`scripts/codex-guarded-git-commit.sh`、`scripts/gates/gate-ci-local.sh`） / Copilot=intentional-gap | governance | `scripts/codex-guarded-git-commit.sh`、`scripts/gates/gate-ci-local.sh`、`scripts/verification-evidence-gate.sh` | active | portable gate 邏輯共用 | keep；Codex parity 已由 guarded-git wrapper 覆蓋 | DP-245 |

Copilot 為 intentional-gap：Copilot 在本 workspace 沒有 git lifecycle 介入點，commit-time CI mirror 在 Copilot runtime 由人工 / CI pipeline 兜底而非 agent hook。

### 2. version-docs-lint-gate.sh

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| `.claude/hooks/version-docs-lint-gate.sh` | Claude=mirrored（PreToolUse git commit） / Codex=mirrored（`scripts/codex-guarded-git-commit.sh`） / Copilot=intentional-gap | governance | `scripts/codex-guarded-git-commit.sh`、`scripts/check-version-bump-reminder.sh`、`scripts/gates/gate-version-lint.sh` | active | portable gate 邏輯共用 | keep | DP-245 |

Copilot 為 intentional-gap：Copilot 無 commit-time hook 事件，VERSION-staged docs-lint 防呆在該 runtime 改由 CI 與 reviewer 接手，不需要 agent 端機械攔截。

### 3. pre-push-quality-gate.sh

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| `.claude/hooks/pre-push-quality-gate.sh` | Claude=mirrored（pre-push delivery gate） / Codex=mirrored（`scripts/codex-guarded-git-push.sh`） / Copilot=intentional-gap | governance | `scripts/codex-guarded-git-push.sh`、`scripts/verify-cross-llm-parity.sh`、`scripts/sync-from-upstream.sh` | active | portable gate 邏輯共用 | keep | DP-245 |

Copilot 為 intentional-gap：Copilot 沒有 push lifecycle 攔截點，push 前品質檢查在該 runtime 由 remote CI 作為第一道與唯一一道機械防線。

### 4. pr-base-gate.sh

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| `.claude/hooks/pr-base-gate.sh` | Claude=mirrored（PreToolUse `gh pr create` / `gh pr edit`） / Codex=advisory / Copilot=intentional-gap | governance | `scripts/revision-rebase.sh`、`scripts/resolve-task-base.sh`、`scripts/resolve-task-md-by-branch.sh` | active | base 由 task.md resolve | DP-245 決定 Codex 是否升級為 guarded-`gh` wrapper | DP-245 |

Copilot 為 intentional-gap：Copilot 不執行 `gh pr create`，PR base 防呆對該 runtime 無對應操作面，因此刻意不提供。

### 5. pre-write-language-policy.sh

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| `.claude/hooks/pre-write-language-policy.sh` | Claude=mirrored（PreToolUse Write / Edit / MultiEdit；fallback `scripts/validate-language-policy.sh`） / Codex=advisory（`.codex/AGENTS.md` Markdown Authoring Contract） / Copilot=advisory（`.github/copilot-instructions.md`） | governance | `.claude/settings.json`、`scripts/validate-language-policy.sh` | active | `claude-code-only` runtime，fallback script portable | keep；Codex / Copilot 靠 rendered prose adapter | DP-245 |

（無 intentional-gap：language policy 規範已 render 進兩個 adapter，為 advisory 而非 gap。）

### 6. no-direct-evidence-write.sh

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| `.claude/hooks/no-direct-evidence-write.sh` | Claude=mirrored（PreToolUse Write / Edit / MultiEdit；fallback `scripts/validate-specs-bound-write-contract.sh`） / Codex=advisory / Copilot=advisory | governance | `.claude/settings.json`、`scripts/validate-specs-bound-write-contract.sh` | active | `claude-code-only` runtime，fallback script portable | keep | DP-245 |

（無 intentional-gap：producer-path 規範在兩個 adapter 為 advisory 覆蓋。）

### 7. pre-memory-write.sh

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| `.claude/hooks/pre-memory-write.sh` | Claude=mirrored（PreToolUse Write / Edit / MultiEdit） / Codex=intentional-gap / Copilot=intentional-gap | governance | `.claude/settings.json`、`scripts/validate-memory-write.sh` | active | memory 是 Claude session 概念 | keep | DP-245 |

Codex / Copilot 為 intentional-gap：`memory/` tier 系統是 Claude Code session 專屬概念，Codex / Copilot 無對應 memory write surface，因此 memory write contract 攔截在這兩個 runtime 刻意不存在。

### 8. post-memory-index-regenerate.sh

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| `.claude/hooks/post-memory-index-regenerate.sh` | Claude=mirrored（PostToolUse Write / Edit / MultiEdit） / Codex=intentional-gap / Copilot=intentional-gap | governance | `.claude/settings.json`、`scripts/memory-hygiene-tiering.py --emit-index` | active | 依附 memory 系統 | keep | DP-245 |

Codex / Copilot 為 intentional-gap：MEMORY.md index 再生依附於 Claude 專屬的 memory tier 系統，其他 runtime 無 memory 寫入故無需 index 再生，這是刻意的範圍邊界。

### 9. no-manual-work-order-search.sh

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| `.claude/hooks/no-manual-work-order-search.sh` | Claude=mirrored（PreToolUse Bash） / Codex=advisory / Copilot=advisory | governance | `.claude/settings.json` | active | resolver-lock 紀律 | DP-245 決定 Codex Bash 攔截可行性 | DP-245 |

（無 intentional-gap：work-order resolver 紀律已寫入 routing prose，為 advisory 覆蓋。）

### 10. pipeline-artifact-gate.sh

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| `.claude/hooks/pipeline-artifact-gate.sh` | Claude=mirrored（PreToolUse；delegate `scripts/pipeline-artifact-gate.sh`） / Codex=advisory / Copilot=intentional-gap | governance | `.claude/settings.json`、`scripts/pipeline-artifact-gate.sh`、`scripts/validate-task-md.sh` | active | runtime-agnostic entrypoint | keep；Codex 經 runtime-agnostic entrypoint | DP-245 |

Copilot 為 intentional-gap：Copilot 不執行 Polaris pipeline 的 artifact 寫入步驟，pipeline artifact schema gate 在該 runtime 無對應寫入時機，刻意不掛載。

### 11. stop-todo-check.sh

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| `.claude/hooks/stop-todo-check.sh` | Claude=mirrored（Stop） / Codex=intentional-gap / Copilot=intentional-gap | governance | `.claude/settings.json` | active | 依附 Claude Stop 事件 | keep | DP-245 |

Codex / Copilot 為 intentional-gap：premature-stop 攔截依賴 Claude Code 的 `Stop` 事件，Codex / Copilot 沒有等價的 turn-stop hook 事件，因此刻意不提供對等攔截。

### 12. session-summary-precompact.sh

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| `.claude/hooks/session-summary-precompact.sh` | Claude=mirrored（PreCompact） / Codex=intentional-gap / Copilot=intentional-gap | observability | `.claude/settings.json` | active | 依附 Claude compaction 事件 | keep | DP-245 |

Codex / Copilot 為 intentional-gap：compaction-before-write 摘要依賴 Claude 專屬的 `PreCompact` 事件，其他 runtime 沒有對等的 context compaction 生命週期事件可掛載。

### 13. post-compact-context-restore.sh

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| `.claude/hooks/post-compact-context-restore.sh` | Claude=mirrored（PostCompact） / Codex=intentional-gap / Copilot=intentional-gap | governance | `.claude/settings.json` | active | 依附 Claude compaction 事件 | keep | DP-245 |

Codex / Copilot 為 intentional-gap：compaction 後 context 還原依賴 Claude 專屬的 `PostCompact` 事件，其他 runtime 無等價 compaction 還原時機，故刻意不提供。

### 14. session-summary-stop.sh

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| `.claude/hooks/session-summary-stop.sh` | Claude=mirrored（Stop 備援路徑） / Codex=intentional-gap / Copilot=intentional-gap | observability | `.claude/settings.json` | active | 依附 Claude Stop 事件 | keep | DP-245 |

Codex / Copilot 為 intentional-gap：短 session 的摘要備援同樣依賴 Claude 的 `Stop` 事件，其他 runtime 無等價事件，是 observability-only 缺口而非 governance 風險。

### 15. feedback-read-logger.sh

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| `.claude/hooks/feedback-read-logger.sh` | Claude=mirrored（PostToolUse Read） / Codex=intentional-gap / Copilot=intentional-gap | observability | `.claude/settings.json` | active | 依附 Claude Read 事件 + memory 系統 | keep | DP-245 |

Codex / Copilot 為 intentional-gap：feedback trigger-count 觀測依賴 Claude `PostToolUse(Read)` 事件與 Claude 專屬 memory 系統，其他 runtime 既無 Read 事件也無 feedback memory，刻意不複製。

### 16. feedback-reflection-stop.sh

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| `.claude/hooks/feedback-reflection-stop.sh` | Claude=mirrored（Stop） / Codex=intentional-gap / Copilot=intentional-gap | governance | `.claude/settings.json` | active | 依附 Claude Stop 事件 + memory 系統 | keep | DP-245 |

Codex / Copilot 為 intentional-gap：post-task reflection 提醒依賴 Claude `Stop` 事件與 feedback memory 寫入面，其他 runtime 無對等事件與 memory，刻意不提供機械提醒。

### 17. feedback-trigger-advisory.sh

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| `.claude/hooks/feedback-trigger-advisory.sh` | Claude=mirrored（Stop） / Codex=intentional-gap / Copilot=intentional-gap | observability | `.claude/settings.json` | active | 依附 Claude Stop 事件 + memory 系統 | keep | DP-245 |

Codex / Copilot 為 intentional-gap：trigger-count 提醒同樣綁定 Claude `Stop` 事件與 feedback memory 機制，是 observability-only 缺口，其他 runtime 無對應面，刻意不複製。

### 18. memory-decay-scan.sh

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| `.claude/hooks/memory-decay-scan.sh` | Claude=mirrored（SessionStart） / Codex=intentional-gap / Copilot=intentional-gap | observability | `.claude/settings.json`（SessionStart） | active | 依附 Claude SessionStart 事件 + memory 系統 | keep | DP-245 |

Codex / Copilot 為 intentional-gap：memory tier decay scan 依賴 Claude `SessionStart` 事件與 memory tier index，其他 runtime 無 session-start hook 也無 memory tier，故刻意不提供。

### 19. cross-session-warm-scan.sh

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| `.claude/hooks/cross-session-warm-scan.sh` | Claude=mirrored（UserPromptSubmit） / Codex=intentional-gap / Copilot=intentional-gap | governance | `.claude/manifest.json`、`scripts/cross-session-warm-scan-selftest.sh` | active | 依附 Claude UserPromptSubmit 事件 + memory 系統 | keep | DP-245 |

Codex / Copilot 為 intentional-gap：「繼續 X」warm memory 提示依賴 Claude `UserPromptSubmit` 事件與 Warm topic folder，其他 runtime 無 prompt-submit hook 也無 memory folder，刻意不複製。

### 20. version-bump-reminder.sh

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| `.claude/hooks/version-bump-reminder.sh` | Claude=mirrored（PostToolUse git commit） / Codex=advisory / Copilot=advisory | governance | `.claude/settings.json` | active | reminder 語義已寫入 framework-iteration 規範 | keep；Codex / Copilot 靠 rendered prose | DP-245 |

（無 intentional-gap：version-bump reminder 規範已 render 進兩個 adapter，為 advisory 覆蓋。）

### 21. specs-sidebar-sync.sh

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| `.claude/hooks/specs-sidebar-sync.sh` | Claude=mirrored（PostToolUse，legacy no-op） / Codex=intentional-gap / Copilot=intentional-gap | governance | `.claude/settings.json` | legacy-noop | 已 no-op，docs-manager 直讀 canonical specs | sunset 評估交 DP-245 / DP-243 | DP-245 |

Codex / Copilot 為 intentional-gap：此 hook 已是 legacy no-op（無實際行為），無需在任何其他 runtime 複製一個空操作；其 sunset 與否交由 follow-up DP 決定。

## Summary

- **盤點總數**：21 個 hook（`.claude/hooks/**` 全量逐 hook 列 entry）。
- **Claude column**：21 / 21 = mirrored（所有 hook 在 Claude Code 原生掛載，這是 source-of-truth runtime）。
- **Codex column**：4 mirrored（`ci-local-gate`、`version-docs-lint-gate`、`pre-push-quality-gate` 經 guarded-git wrapper；註：`pipeline-artifact-gate` 經 runtime-agnostic entrypoint 視為 advisory）、6 advisory（`pre-write-language-policy`、`no-direct-evidence-write`、`pr-base-gate`、`no-manual-work-order-search`、`pipeline-artifact-gate`、`version-bump-reminder`）、11 intentional-gap（memory / session / compaction / feedback 類，全依附 Claude 專屬 runtime 事件或 memory 系統）。
- **Copilot column**：0 mirrored、4 advisory（`pre-write-language-policy`、`no-direct-evidence-write`、`no-manual-work-order-search`、`version-bump-reminder`）、17 intentional-gap（Copilot 在本 workspace 無 git lifecycle / runtime hook 介入點）。
- **核心結論**：所有 `intentional-gap` 都源自一個共同根因——**Codex / Copilot 沒有與 Claude Code 對等的 hook 事件機制與 memory 系統**。governance-critical 的 git-lifecycle 行為（commit / push / version-lint）已透過 Codex guarded-git wrapper 達成 behavior parity；其餘缺口屬於 Claude-session 專屬功能（memory tier、compaction、Stop / SessionStart reflection），刻意不在其他 runtime 複製。
- **disposition 一致性**：本 audit 與 `.claude/rules/mechanism-registry.md` § Runtime Annotation Registry 的 `runtime` / `fallback_script` 欄位一致；`claude-code-only` 標記者（`pre-write-language-policy`、`no-direct-evidence-write` 對應 `specs-collection-shape-write-gate`）已對齊其 portable fallback script。

## Open Questions for follow-up DP

下列 design item 在 DP-242 audit 階段**刻意 defer** 給 DP-245（cross-LLM hook parity / adapter）refinement 階段決定，不在本 audit-only DP scope 內做結論。

| 題目 | 為何 defer | 期望 DP-245 refinement 階段 decide 什麼 |
|------|-----------|------------------------------------------|
| Codex hook parity 的 canonical 形式：`.codex/hooks/` mirror file（真的放可執行檔）vs 純靠 `.codex/AGENTS.md` adapter wording vs guarded-git wrapper 擴張 | 需要先確認 Codex runtime 是否支援自訂 hook 載入點，屬於 runtime fact-check（Heuristic 2 Fact-Check Before LOCK），本 audit 不做 runtime probe | 決定 Codex 端 parity 的單一 canonical 實作面，並把對應 disposition 從 advisory 升 mirrored 或正式記為 intentional-gap |
| 新增 hook 時是否強制 same-PR 補三方 runtime adapter（Claude hook + Codex wrapper + Copilot prose），或允許 follow-up adapter task | 此為 contract design 取捨（Deterministic-First vs delivery 切片粒度），會新增 PR gate 義務，影響開發節奏，需 refinement 權衡 | 決定是否新增 deterministic gate 強制三方 adapter 同 PR，或定義 adapter backfill 的 owner / removal criteria |
| `intentional-gap` rationale 的權威來源：由 validator 接受**作者宣告**（本 audit 採此）即可，還是需要 **reviewer signoff** 才生效 | 牽涉 governance 強度與 reviewer 負擔的 trade-off，且需與 `mechanism-runtime-annotations` validator 的 schema 對齊，屬契約層決策 | 決定 intentional-gap rationale 的 enforcement 模型（validator-accepted author declaration vs reviewer-gated），並對應更新 `validate-mechanism-runtime-annotations.sh` |
| memory / session / compaction 類 intentional-gap 是否永久接受，還是 DP-245 要為 Codex / Copilot 設計等價的 session-state 持久化機制 | 牽涉是否要在非 Claude runtime 重建 memory tier / compaction 還原，成本高且需 runtime 能力 fact-check，本 audit 僅標記不評估 | 決定 11 個 Claude-session-only intentional-gap 是 steady-state 接受，還是排入未來 cross-runtime session-state parity 設計 |
