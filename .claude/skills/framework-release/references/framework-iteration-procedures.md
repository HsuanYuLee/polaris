# Framework Iteration Procedures

> **When to load**: when executing the version bump chain, backlog hygiene, or validated pattern promotion. Loaded on-demand.
>
> 這份檔案自己就是那份程序。它以前說內容摘自 rules/framework-iteration.md，而那一層在 DP-462
> 被拆掉之後就不存在了——指向一個不存在的地方，讀起來跟指向一個權威一模一樣。
>
> **它 2026-08-13 從 `standup/references/` 搬過來**（DP-536）：講的是這個框架自己怎麼迭代、
> 怎麼壓版、怎麼掃待辦，跟「產出每日站會報告」沒有關係，住在那支 skill 裡只是歷史。
>
> **底下有兩段已經被脊椎取代，留著是為了不在搬家時弄丟內容，但它們不再是權威**：
> 〈Backlog Hygiene〉描述的是 DP-462 之前那種「一行一個 `[ ]` 加日期標籤」的待辦，而現在
> 一張單是一個目錄、停滯只出現在 `{單樹根}/OPEN.md` 上，且刻意不設天數門檻；〈Release
> Preflight Enforcement〉後半講的 DP-392 topology guard 與 `bundle_branch_alias` 屬於脊椎
> 之前那一套交付層。現在的答案分別在 `.claude/rules/document-flow.md` 與這支 skill 的 SKILL.md 裡。

## Iteration Cadence Map

| Cadence | When | Mechanism | Source |
|---------|------|-----------|--------|
| Micro | After every task | Post-task reflection → feedback memory / 開一張單 | `.claude/skills/memory-hygiene/references/feedback-memory-procedures.md` |
| Meso | After every PR | PR review → handbook direct write | 那家公司自己的 repo-notes skill（company handbook 的主人） |
| Macro | — | **沒有了** | 見下 |

Daily iteration is driven by **real usage** (Micro + Meso), not simulated review.

Macro 那一格以前是 Challenger Audit：開六個人格 sub-agent 從外部使用者角度審框架，發現寫進
polaris-backlog。那套東西連同它的散文與那份 backlog 在 DP-462／DP-479 一起被拆掉了，**而且沒有
替代品**。這一格留著寫「沒有了」，不留空白：一個空格看起來像還沒填，一句「沒有了」看得出來是
一個決定。

## Framework Experience Frontmatter Template

```yaml
---
name: Descriptive title
description: One-line summary
type: framework-experience
last_triggered: YYYY-MM-DD
---

Pattern: [what the framework element is]
Evidence: [the concrete task/signal that validated it]
Why it works: [one-sentence hypothesis]
```

## Post-Version-Bump Chain

After a VERSION bump is committed, execute these steps in order — no user confirmation needed:

0. **One commit for everything** — first write `VERSION` + `CHANGELOG.md`, then run `git add -A` to stage all changes together (framework code + VERSION + CHANGELOG), then commit once. Never run `git add -A` before writing VERSION/CHANGELOG (they won't be staged), and never commit VERSION/CHANGELOG separately while code diffs remain in the working tree

1. **docs-lint** — run `python3 .claude/skills/framework-release/scripts/readme-lint.py --fix` as a fast deterministic check against `README.md`: skill count, phantom skills (named but no SKILL.md), undocumented skills (SKILL.md but never named). Auto-fixes the count; reports the other two
2. **改 README** — docs-lint 報的幽靈與缺漏就直接改 `README.md`，沒有第二支 skill 代勞。以前這一格寫「invoke `/docs-sync`」，而那支 skill 在 DP-462 就不在了——指向一個不存在的東西，讀起來跟指向一個權威一模一樣。有改動就單獨一個 `docs:` commit
3. **backlog-staleness-scan** — scan `issues/` for stale items (see § Backlog Hygiene below)
4. **同步到 template repo** — 這一步屬釋出尾段，由 `framework-release` 做（它自己帶著那支腳本）。這裡只記它在鏈上的位置。

This chain ensures documentation is always up-to-date and backlog stays clean at release boundaries.

## Release Preflight Enforcement

Before `framework-release` merges or syncs a workspace PR, run the deterministic
release preflight. If the terminal release diff touches framework
distribution/tooling files and does not include `VERSION`, preflight must block
until one of these is true:

1. `VERSION` + `CHANGELOG.md` are added to the release PR.

The release lane must not silently reinterpret this signal as advisory-only.

DP-392 topology guard 屬於同一個 release preflight boundary。Framework DP release
只能是 single PR 或 declared stack PR；multi-head sibling task PR release 一律 invalid。
legacy non-stack repair 必須 fail-stop，附 repair guidance 與 SHA ancestry disposition，
不得靠 `bundle_branch_alias` 或 prose metadata 放行。PR-gated fast-forward promotion
後，`main` 的 release range 不得包含 final merge bubble、per-task merge commit 或
GitHub merge commit。

## Backlog Hygiene

`issues/` entries carry a date tag `(YYYY-MM-DD)` and optional exemption tags (`[platform]`, `[next-epic]`).

**Triggers:**
1. **Post-version-bump chain** (primary) — Step 3 above
2. **Monthly standup fallback** — first `/standup` of each month, if no version bump happened that month

**Scan rules:**

| Condition | Action |
|-----------|--------|
| `[ ]` item with no exemption tag, date > 60 days ago | Suggest closing — present to user |
| `[ ]` item with `[platform]` or `[next-epic]` tag, date > 90 days ago | Ask user to confirm tag is still valid |
| `[ ]` item with no date tag | Add today's date (backfill) |

**Execution:** scan is silent — only surface items that match a rule. If nothing is stale, no output. Present stale candidates as a numbered list; user says which to close or keep (with updated date).

## Validated Pattern Promotion

During `organize-memory` / `clean up memory` runs:

1. Scan all `type: framework-experience` entries
2. If >= 3 entries describe the **same pattern** across different tasks → surface to user as a "Validated Pattern" candidate
3. User confirms → write a rationale note into the appropriate rule file (not as an imperative rule, but as a "this works because..." annotation)
4. After promotion, delete the consolidated framework-experience memories
