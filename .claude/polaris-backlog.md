# Xuanji Backlog

Improvement candidates for the Xuanji framework. Items flow in from:
- Feedback memories (daily usage pain points)
- `/learning` external mode recommendations
- User requests during "繼續 Xuanji" sessions
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

(empty — will populate from daily usage signals)

## Medium — Clear improvement, not urgent

- [ ] **Skill marketplace** — skills as installable packages (`xuanji install review-pr`), decouple from monorepo — source: roadmap
- [ ] **Template variants** — `xuanji-dev` (software), `xuanji-ops` (ops), `xuanji-research` — source: roadmap
- [ ] **Skill script extraction** — extract deterministic logic from skills into bundled .sh scripts (review-inbox done, others pending) — source: memory/project_skill_script_extraction.md

## Low — Explore / nice-to-have

- [ ] **Cross-org knowledge sharing** — multiple orgs learn from each other's skills/patterns, distill into universal rules — source: roadmap
- [ ] **Dashboard** — lightweight web UI for task progress, skill usage frequency, quality trends — source: roadmap
- [ ] **Non-technical skill packs** — legal review, financial analysis, HR process skills — source: roadmap
- [ ] **Multi-agent orchestration** — plug in different AI providers, Xuanji as unified dispatch layer — source: roadmap
- [ ] **Team mode** — shared workspace with individual memory but shared rules — source: roadmap

## Observe — Needs real-world data before acting

- [ ] **Feedback → Rule graduation pipeline** — mechanism built, needs live validation (does trigger_count tracking work? do rules graduate smoothly?) — source: v0.8.0
- [ ] **Context monitoring rule** — built, needs long-conversation stress test — source: v0.8.0
- [ ] **/init v3 smartSelect UX** — built, needs a real `/init` run to validate flow — source: v0.9.0

---

## Done

- [x] Three-layer architecture (L1 Workspace / L2 Company / L3 Project) — v0.5.0
- [x] Two-layer config + `/init` wizard — v0.7.0
- [x] Xuanji template repo + genericize pipeline — v0.6.0
- [x] Bidirectional sync + CLAUDE.md genericization — v0.8.0
- [x] Context monitoring + feedback auto-evolution rules — v0.8.0
- [x] /init v3 smartSelect + AI repo detection + audit trail — v0.9.0
- [x] Learning attribution mechanism — v0.9.0
- [x] VERSION + CHANGELOG + this backlog — v0.9.0
