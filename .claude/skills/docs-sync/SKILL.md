---
name: docs-sync
description: >
  Detects skill/workflow changes and updates all documentation files (README, workflow-guide,
  chinese-triggers, quick-start) in both English and zh-TW. Keeps docs in sync with the actual
  skill catalog. Trigger: "同步文件", "sync docs", "更新文件", "update docs",
  "文件有跟上嗎", "docs out of date", or after creating/modifying skills.
metadata:
  author: Polaris
  version: 2.0.0
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

## Step 1: Detect What Changed

Scan for discrepancies between skills and docs:

1. **Scan `.claude/skills/*/SKILL.md` frontmatter** — get current skill catalog (name, description, trigger keywords, version)
2. **Read `docs/chinese-triggers.md`** — compare trigger keywords table against skill frontmatter
3. **Read `README.md`** — check skill lists in each Pillar section
4. **Read `docs/workflow-guide.md`** — check skill references and workflow steps
5. **Scan mermaid diagrams in `docs/workflow-guide.md`** — extract all node IDs and skill names from `flowchart` code blocks. Compare against current skill catalog:
   - Skills in diagrams but no longer in catalog → flag for removal
   - Skills in catalog that belong in the dev flow but missing from diagrams → flag for addition
   - Standalone/config skills (`init`, `use-company`, `validate-*`, `which-company`) are intentionally excluded from diagrams — do not flag

For each file, identify:
- New skills not documented
- Removed skills still referenced
- Changed trigger keywords or descriptions
- Version mismatches
- Workflow step changes
- **Mermaid diagram nodes out of sync** with skill catalog

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
- Keep backtick skill names as-is: `work-on`, `standup`, etc.
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
| Learning, review-lessons | 自我學習 | 品質保障 |
| Standup, sprint, worklog | 日常紀錄 | 專案管理 |
| Tools, config, init | — | 工具與設定 |
