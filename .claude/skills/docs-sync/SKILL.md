---
name: docs-sync
description: >
  Detects skill/workflow changes and updates all documentation files (README, workflow-guide,
  chinese-triggers, quick-start) in both English and zh-TW. Keeps docs in sync with the actual
  skill catalog. Trigger: "同步文件", "sync docs", "更新文件", "update docs",
  "文件有跟上嗎", "docs out of date", or after creating/modifying skills.
metadata:
  author: Polaris
  version: 3.0.0
  scope: maintainer-only
---

# Documentation Sync

Detects changes in skills and workflows, then updates all documentation files to stay in sync. Handles bilingual (English + zh-TW) docs automatically.

## Source of Truth

| Content | Source | Targets |
|---------|--------|---------|
| Skill catalog (name, description, triggers) | `.claude/skills/*/SKILL.md` frontmatter | `docs/chinese-triggers.md`, README skill lists |
| Three Pillars narrative | `README.md` § The Three Pillars | `README.zh-TW.md` § 三大支柱 |
| Developer workflow | `docs/workflow-guide.md` | `docs/workflow-guide.zh-TW.md` |
| PM checklist | `docs/pm-setup-checklist.md` | `docs/pm-setup-checklist.zh-TW.md` |
| Quick Start | `README.md` § Quick Start | `docs/quick-start-zh.md` |

**Rule**: English docs are the source of truth. zh-TW docs are translations that must stay in sync.

## Bilingual File Pairs

| English (source) | zh-TW (translation) |
|-------------------|---------------------|
| `README.md` | `README.zh-TW.md` |
| `docs/workflow-guide.md` | `docs/workflow-guide.zh-TW.md` |
| `docs/pm-setup-checklist.md` | `docs/pm-setup-checklist.zh-TW.md` |
| `docs/quick-start-zh.md` | (already zh-TW, standalone) |
| `docs/chinese-triggers.md` | (already zh-TW, standalone) |

## Step 0: Scope the Sync (git diff + lint)

Before scanning all docs, narrow down what actually changed.

### 0a. Run deterministic lint

```bash
python3 scripts/readme-lint.py
```

This catches structural issues without AI: phantom skills (doc references a name with no SKILL.md), undocumented skills, skill count drift, chinese-triggers table mismatches, and mermaid diagram node phantoms.

If lint passes clean (exit 0) **and** no git diff in Step 0b → docs are in sync, skip to Step 4 (verify).

### 0b. Git diff — what skills changed since last sync?

```bash
# Find the last docs-sync commit
LAST_SYNC=$(git log --oneline --all --grep="docs: sync" -1 --format="%H")

# What SKILL.md files changed?
git diff --name-only ${LAST_SYNC:-HEAD~20}..HEAD -- '.claude/skills/*/SKILL.md'

# What specifically changed in frontmatter?
git diff ${LAST_SYNC:-HEAD~20}..HEAD -- '.claude/skills/*/SKILL.md' | grep '^[+-]' | grep -E 'name:|trigger|description:'
```

### 0c. Classify changes (borrowing from `/learning` baseline→classify pattern)

For each changed skill, classify the sync depth needed:

| Change Type | Sync Depth | What to Update |
|-------------|-----------|----------------|
| **Name/rename** | Full — all 4 docs | Every file that references the old name |
| **Trigger keywords** | chinese-triggers only | Update the trigger row |
| **Description** | chinese-triggers + README Pillar list | Update description text |
| **New skill added** | Full — all 4 docs | Add to chinese-triggers, README Pillar, workflow-guide diagram, quick-start if relevant |
| **Skill removed** | Full — all 4 docs | Remove from all references |
| **SKILL.md internal changes** (steps, logic) | None | Docs describe triggers and purpose, not internal steps |

### 0d. Completeness score (borrowing from `/refinement` N/M dimensions)

For each changed skill, check coverage across 4 docs:

| Dimension | File | Check |
|-----------|------|-------|
| **Triggers** | `docs/chinese-triggers.md` | Skill name appears in table with correct triggers |
| **Pillar** | `README.md` + `README.zh-TW.md` | Skill listed in correct Pillar's **Skills:** line |
| **Diagram** | `docs/workflow-guide.md` | Skill has a node in Diagram 2 (if part of dev flow) |
| **Quick Start** | `docs/quick-start-zh.md` | Skill mentioned if it's a primary workflow skill |

Score: `N/4` per skill. Only skills scoring < 4/4 need Step 1-3 treatment. Standalone/config skills (`init`, `use-company`, `validate`, `docs-sync`, `checkpoint`) are exempt from Diagram and Quick Start dimensions (score out of 2 instead of 4).

**If Step 0a lint passes clean AND Step 0b shows no changes → report "Docs in sync" and stop.**

## Step 1: Detect What Changed (scoped by Step 0)

Focus only on skills flagged by Step 0 (lint failures or git diff changes). For each flagged skill:

1. **Read its SKILL.md frontmatter** — name, description, trigger keywords
2. **Compare against each doc dimension** from Step 0d — identify specific gaps

For unchanged skills with full coverage (4/4), skip entirely.

Present the diff report:

```
── Documentation Sync Report ────────────
New skills to document:
  + new-skill — description

Updated skills:
  ~ existing-skill — trigger keywords changed

Removed:
  - old-skill — no longer exists

Files needing updates:
  📝 docs/chinese-triggers.md — add/update trigger entries
  📝 README.md — update Pillar skill lists
  📝 README.zh-TW.md — sync translation
  📝 docs/workflow-guide.md — add workflow section
  📝 docs/workflow-guide.zh-TW.md — sync translation
```

## Step 2: Update English Docs (source of truth)

Update in this order:

### 2a. `docs/chinese-triggers.md`
- Add new skills to the appropriate category section (pillar-tagged)
- Update changed trigger keywords
- Remove deleted skills
- Keep the existing table format: 功能 | 中文觸發詞 | 英文觸發詞 | 說明

### 2b. `README.md`
- Update skill lists in the Three Pillars sections (comma-separated inline)
- Only if a skill was added/removed from a pillar category

### 2c. `docs/workflow-guide.md`
- **Mermaid diagrams**: add/remove nodes and edges in both diagrams (Ticket Lifecycle + Skill Orchestration) to match current skill catalog. Assign new nodes to the correct style class (orchestrator, quality, review, planning, standalone, internal). Update the connectivity check prose below Diagram 2
- **Prose steps**: add new workflow-relevant skills as steps. Only if the skill is part of the development flow (not standalone tools). Match existing format: Step N with emoji markers, trigger keyword callout

### 2d. `docs/quick-start-zh.md`
- Update if Quick Start examples or pillar summaries changed

**Get user confirmation before writing changes.**

## Step 3: Sync zh-TW Translations

For each English file that was modified in Step 2, update its zh-TW pair:

1. Read the English file's changed sections
2. Read the zh-TW file's corresponding sections
3. Translate only the changed parts — do not re-translate unchanged sections
4. Keep technical terms, skill names, code blocks, and commands as-is

Translation rules:
- Use Traditional Chinese (zh-TW) natural Taiwan usage
- Keep backtick skill names as-is: `engineering`, `standup`, etc.
- Keep code blocks, commands, file paths untouched
- Keep mermaid diagram labels in English

## Step 4: Verify

After all updates:
1. Confirm all bilingual file pairs are in sync (section count, skill count)
2. Verify internal links (anchor links between files)
3. Report:

```
── Sync Complete ────────────────────────
✅ docs/chinese-triggers.md — 2 skills added
✅ README.md — Pillar 1 skill list updated
✅ README.zh-TW.md — translation synced
✅ docs/workflow-guide.md — no changes needed
✅ docs/workflow-guide.zh-TW.md — no changes needed
```

## When NOT to Sync

- **Draft skills** — wait until committed
- **Minor SKILL.md edits** (typo, formatting) — not worth a docs update
- **Rule file changes** — these are for Claude Code, not user-facing docs
- **Company-specific skills** (under `.claude/skills/{company}/`) — not in shared docs

## Pillar → Category Mapping

When adding a new skill to docs, determine which pillar it belongs to:

| Skill Type | Pillar | chinese-triggers Category |
|------------|--------|--------------------------|
| Dev workflow (branch, code, PR) | 輔助開發 | 開發流程 or 程式碼審查 |
| Learning | 自我學習 | 品質保障 |
| Standup, sprint, worklog | 日常紀錄 | 專案管理 |
| Tools, config, init | — | 工具與設定 |


## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
