# Polaris Backlog

Improvement candidates for the Polaris framework. Items flow in from:
- Feedback memories (daily usage pain points)
- `/learning` external mode recommendations
- User requests during "繼續 Polaris" sessions
- Hook blocks / permission friction

## Priority Guide

```
1. Blocking — friction that hits daily work (fix ASAP)
2. Validated — feedback trigger_count ≥ 2 or repeated user mention
3. Leverage — low cost, high impact
4. Roadmap — vision items, by user interest
5. Explore — try when inspired
```

---

## High — Blocking or validated pain points

- [ ] **skill-routing 中英文混合** — 觸發詞半中文半英文，非中文使用者無法使用核心操作文件。需全面英文化或加英文 alias — source: challenger v1.0.0
- [ ] **`rules/company/` 泛化殘留** — 部分 rule 檔案含公司特定內容（JIRA status ID、field ID），新使用者無法區分哪些要改哪些通用 — source: challenger v1.0.0

## Medium — Clear improvement, not urgent

- [ ] **pre-push hook 新使用者體驗** — 預設 hook 會在首次使用就 block push，需加首次 bypass 或文件說明 — source: challenger v1.0.0
- [ ] **CHANGELOG 風格調整** — 目前像個人 refactoring 日誌，需改為面向使用者的 release notes 風格 — source: challenger v1.0.0
- [ ] **polaris-backlog.md 不應出現在 template** — 公開在 template 裡讓使用者困惑，應只在 work/ instance 保留 — source: challenger v1.0.0
- [ ] **clone 路徑 `~/work` 預設值** — 多數開發者已有 ~/work 目錄，README 需更安全的建議 — source: challenger v1.0.0

- [ ] **Skill marketplace** — skills as installable packages (`polaris install review-pr`), decouple from monorepo — source: roadmap
- [ ] **Template variants** — `polaris-dev` (software), `polaris-ops` (ops), `polaris-research` — source: roadmap
- [ ] **Skill script extraction** — extract deterministic logic from skills into bundled .sh scripts (review-inbox done, others pending) — source: memory/project_skill_script_extraction.md

## Low — Explore / nice-to-have

- [ ] **Cross-org knowledge sharing** — multiple orgs learn from each other's skills/patterns, distill into universal rules — source: roadmap
- [ ] **Dashboard** — lightweight web UI for task progress, skill usage frequency, quality trends — source: roadmap
- [ ] **Non-technical skill packs** — legal review, financial analysis, HR process skills — source: roadmap
- [ ] **Multi-agent orchestration** — plug in different AI providers, Polaris as unified dispatch layer — source: roadmap
- [ ] **Team mode** — shared workspace with individual memory but shared rules — source: roadmap

## Observe — Needs real-world data before acting

- [ ] **Feedback → Rule graduation pipeline** — mechanism built, needs live validation (does trigger_count tracking work? do rules graduate smoothly?) — source: v0.8.0
- [ ] **Context monitoring rule** — built, needs long-conversation stress test — source: v0.8.0
- [ ] **/init v3 smartSelect UX** — built, needs a real `/init` run to validate flow — source: v0.9.0

---

## Done

- [x] Three-layer architecture (L1 Workspace / L2 Company / L3 Project) — v0.5.0
- [x] Two-layer config + `/init` wizard — v0.7.0
- [x] Polaris template repo + genericize pipeline — v0.6.0
- [x] Bidirectional sync + CLAUDE.md genericization — v0.8.0
- [x] Context monitoring + feedback auto-evolution rules — v0.8.0
- [x] /init v3 smartSelect + AI repo detection + audit trail — v0.9.0
- [x] Learning attribution mechanism — v0.9.0
- [x] VERSION + CHANGELOG + this backlog — v0.9.0
- [x] Polaris v1.0.0 identity: Strategist persona, README rewrite, Zhang Liang inspiration — v1.0.0
- [x] MIT LICENSE + GitHub topics + concrete repo description — v1.0.1
- [x] Challenger mechanism (sub-agent UX audit) — v1.0.1
- [x] README rewrite: clear positioning, prerequisites, concrete walkthrough — v1.1.0
- [x] ONBOARDING.md absorbed into README (single entry point) — v1.1.0
- [x] MCP server prerequisites documented — v1.1.0
