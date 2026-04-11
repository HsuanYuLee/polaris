# Docs Editorial Guideline

Writing style rules for public-facing documentation (README.md, docs/*.md). Applied by docs-sync sub-agents and any skill that generates or updates documentation.

## Core Principle

**新使用者 5 秒內知道這段在講什麼。** Every section, every paragraph — lead with the conclusion, not the background.

## Style Rules

| Rule | Do | Don't |
|------|-----|-------|
| **一句能講完不用三句** | "Polaris routes JIRA tickets to skills." | "In order to provide a seamless workflow, Polaris has been designed to route JIRA tickets to the appropriate skills." |
| **第一句是結論** | "Skills load on-demand." then explain why | "Claude Code has a context window. To save tokens, skills are designed to..." |
| **Show don't tell** | Code block with actual command | "You can use the work-on skill by typing the command..." |
| **中英對照用 `/`** | `"work on PROJ-123" / 「做 PROJ-123」` | 分段重複同一內容的中英版 |
| **術語首次解釋，之後直接用** | "Skills (reusable workflow modules) automate..." → 後文直接說 "skills" | 每次都加括號解釋 |
| **Section ≤ 15 行** | 超過就拆成子 section 或砍贅字 | 一個 section 塞 30 行散文 |
| **表格優先於散文列舉** | 3+ 項目用 table 或 bullet | "There are three types: A which does X, B which does Y, and C which does Z." |
| **動詞開頭的 bullet** | "Reads JIRA ticket → estimates → opens PR" | "The system will read the JIRA ticket and then proceed to estimate..." |

## Structured vs Editorial Sections

README 和 docs 混合兩種內容。生成/更新時區分對待：

| Type | Examples | Generation | Style enforcement |
|------|----------|-----------|-------------------|
| **Structured** | Skill list table, trigger examples, directory tree | Auto-generate from SKILL.md metadata | Template-driven, no editorial judgment |
| **Editorial** | "Who is this for?", "How it works", "About the name" | Human-written, AI reviews for style | Apply style rules above, preserve author voice |

**Rule:** Auto-generation only touches structured sections. Editorial sections get style review (suggestions), not rewrite.

## Tone

- **Confident, not salesy** — state what it does, don't oversell
- **Practical, not academic** — "run this command" beats "one might consider executing"
- **Inclusive** — assume reader knows git/JIRA basics, don't assume they know Claude Code internals
- **Bilingual-friendly** — key concepts show both EN and 中文 on first mention; after that, use whichever is shorter
