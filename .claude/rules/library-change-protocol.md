# Library Change Protocol

When a task involves replacing, upgrading, or removing a dependency, follow this protocol. Applies to all repos, all companies.

## Default Stance

All libraries are installed for a reason. "Doesn't seem to work" ≠ "can't work." The first response to a library limitation should be "am I using it wrong?", not "let's replace it."

## Before Concluding a Library Can't Do X

Exhaust three layers of investigation before proposing a replacement:

| Layer | What to check | Why |
|-------|---------------|-----|
| **Official docs** | API surface, config options, migration guide | Compiled source hides overloads, wrappers, build transforms |
| **GitHub issues / discussions** | Has someone asked the same question? | 90% of "can't do X" has been solved by someone |
| **Plugin / config combinations** | Framework-level plugin mechanisms, config options | Frameworks have runtime overrides invisible in source code |

All three layers checked and confirmed insufficient → proceed to replacement evaluation.

**Never read `node_modules/` compiled source as the sole basis for "module doesn't support X."** Compiled/bundled JS ≠ API surface.

## Replacement Evaluation (Four Questions)

Before proposing a replacement, answer all four:

| Question | Purpose |
|----------|---------|
| **Import count** — how many files use this library? | Scope of change |
| **Config registration** — is it registered in framework config (`nuxt.config`, `webpack.config`, `composer.json` plugins)? | Config-level dependencies are invisible to `grep import` but affect global behavior |
| **Test coverage** — do existing tests depend on its behavior? | Regression risk |
| **Transitive dependents** — do other libs/modules depend on it? Diff the lock file (`pnpm-lock.yaml` / `composer.lock`) | Cascade impact |

## Upgrade Evaluation (Additional Checks)

Upgrades share the same four questions above, plus:

| Check | What to look for | Why |
|-------|-----------------|-----|
| **CHANGELOG / Release notes** | Breaking changes, deprecated API, behavior changes | Minor versions can change behavior (especially 0.x) |
| **Migration guide** | Official upgrade path | Framework-level libs (Vue 2→3, Nuxt 2→3) have dedicated guides |
| **Peer dependencies** | Does upgrading A require upgrading B? | Common cascade: Vue → Vuex → Vue Router |
| **Lock file diff** | What transitive dependencies changed silently? | Upgrading A may silently upgrade B with breaking changes |

## Runtime vs Build-Time Distinction

| Type | Examples | Risk profile | Rollback |
|------|---------|-------------|----------|
| **Runtime** | axios, vue-router, nuxt-schema-org | Affects live user behavior | Requires redeploy |
| **Build-time** | babel plugin, webpack loader, PostCSS plugin | Affects compiled output | Rebuild + redeploy |
| **Framework module** | Nuxt module, CI2 library | Affects both build and runtime | Often irreversible without significant rework |

Framework modules carry the highest risk — they interleave with the framework lifecycle and are hardest to swap out.

## Decision Tier

| Operation | Reversible? | Tier |
|-----------|------------|------|
| Patch upgrade (2.7.15 → 2.7.16) | Easy to revert | **T1** — automatic |
| Minor upgrade (2.7 → 2.8), no breaking changes listed | Usually revertible | **T2** — decide and note |
| Major upgrade (Vue 2 → 3) or has breaking changes | Hard to reverse | **T3** — user confirms |
| Replace utility lib (lodash → native) and reversible | Yes | **T2** — decide and note |
| Replace framework-level module | Hard to reverse | **T3** — user confirms |
| Remove a dependency | Check import count first | **T2** if 0 imports + no config registration; **T3** otherwise |

**When uncertain between T2 and T3 → choose T3.** The cost of asking is low; the cost of a wrong replacement is high.

## Handbook Integration

Repo handbooks may include a **Key Libraries** section listing concern → library bindings with official docs links. When a sub-agent encounters a library in this list:

1. The library is the **designated solution** for that concern — do not replace without the full protocol above
2. The docs link is the **first place to check** when the library seems insufficient
3. The section title "替換需 user 確認" reinforces T3 escalation

## Config Not Working — Systematic Elimination

When a library's config option appears to be silently ignored, enumerate all possible injection points before trial-and-error:

1. **Confirm the option exists** — read official docs for the config API, not compiled source
2. **List all injection points** for the framework (e.g., Nuxt: `nuxt.config module option → app.head → layout useHead → page useHead → plugin useHead → unhead hook`)
3. **Test each point once**, top-down, recording PASS/FAIL per point
4. **When results contradict** (same code, different outcomes), trust the FAIL and re-test. Dev servers cache aggressively; a PASS after a FAIL may be stale

Do not bounce between injection points based on intuition. The systematic list prevents wasted cycles (and wasted dev server restarts for the user).

## Workaround Documentation Standard

When the only working approach bypasses the library's official API (hooks, monkey patches, custom plugins), the code comment must include the full decision chain:

| Section | Content |
|---------|---------|
| **Goal** | What behavior we want |
| **What we tried** | Which official approaches were attempted, and why each failed (with evidence: ModuleOptions type, source code line, config override behavior) |
| **Why this approach** | Why hook/patch/plugin instead of fork, PR, or alternative library |
| **Removal condition** | When this workaround can be replaced with the official API (e.g., "when module exposes `tagPosition` in ModuleOptions") |

**The comment can be longer than the code — this is expected.** A 5-line hook with a 30-line explanation saves the next developer from repeating a multi-hour investigation.

Applies to: work-on sub-agents, fix-pr-review, any code-writing context. Code review should flag workarounds missing the decision chain.

## Common Rationalizations

| Thought | Reality |
|---------|---------|
| "This module can't do what we need" | Did you check all three layers (docs, issues, config)? Compiled source ≠ API surface |
| "It's easier to just use X instead" | Easier now, harder when 20 files depend on the old pattern and tests break |
| "It's just a minor upgrade" | Check the lock file diff — "minor" can pull in major transitive changes |
| "Nobody uses this lib anyway" | Did you check config registration? Nuxt modules don't show up in `grep import` |
| "I'll add a compatibility layer" | That's a workaround. Use the existing lib correctly first |
| "Config didn't work, let me try a hook" | Did you enumerate all injection points first? You may be setting the right value in the wrong place |
| "It worked on the second try" | Did it fail the first time? Trust the FAIL — the second PASS may be cached |
| "The workaround is simple, no need for a long comment" | The next developer will ask "why not just use the config?" — save them the 2-hour investigation |
