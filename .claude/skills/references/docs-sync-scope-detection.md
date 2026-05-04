---
title: "Docs Sync Scope Detection"
description: "docs-sync 的 deterministic lint、git diff scoping、change classification、coverage score 與不需同步的情境。"
---

# Scope Detection Contract

這份 reference 決定 docs-sync 是否需要寫文件，以及要寫哪些文件。

## Deterministic Lint

先跑 README/docs lint。它負責抓不需要 AI 判斷的問題：

- docs reference phantom skills。
- existing skills 沒有出現在 trigger docs。
- skill count drift。
- chinese-triggers table mismatch。
- Mermaid diagram node phantom。

若 lint clean 且 relevant git diff 沒有 user-facing change，回報 docs in sync，停止。

## Git Diff Scoping

找最近一次 docs-sync commit 或合理 fallback range，檢查 changed `SKILL.md` frontmatter 與
user-facing docs/rules workflow surface。

只把以下變更視為 docs-impacting：

| Change | Impact |
|---|---|
| skill name or rename | full docs update |
| trigger keywords | trigger docs |
| description | trigger docs and README skill lists |
| new skill | trigger docs, README, workflow guide if relevant, quick start if primary |
| removed skill | remove stale references |
| workflow surface changed | workflow guide or quick start |

SKILL internal procedure changes、typo、formatting、rule-only implementation details，不進 docs
sync，除非 user explicitly asks。

## Coverage Score

對每個 flagged skill 檢查 docs coverage：

| Dimension | File |
|---|---|
| Triggers | `docs/chinese-triggers.md` |
| Pillar | `README.md` and `README.zh-TW.md` |
| Diagram | `docs/workflow-guide.md` when skill belongs to development flow |
| Quick Start | `docs/quick-start-zh.md` when skill is primary workflow |

Standalone/config skills，例如 `init`、`use-company`、`validate`、`docs-sync`、`checkpoint`，
可免 Diagram 與 Quick Start dimensions。

只處理 score 未滿的 skills；coverage 已滿的 unchanged skills 不重掃全文。

## Gap Report

寫檔前先輸出 gap report：

- new skills
- updated skills
- removed skills
- changed workflow surface
- files needing updates
- files intentionally skipped and reason

若需要 broad rewrite，先取得使用者確認，除非使用者已明確要求直接更新。

## When Not To Sync

不要為以下情況同步 public docs：

- draft skills
- internal procedure slimming only
- rule file changes without user-facing workflow impact
- company-specific local skills
- generated runtime targets
