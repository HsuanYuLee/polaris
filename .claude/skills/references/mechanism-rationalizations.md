# Mechanism Rationalizations

> **When to load**: when you notice yourself rationalizing a decision that might violate a mechanism. These are real escape patterns observed in prior sessions — reading them before acting can prevent drift. Loaded on-demand.

## Common Rationalizations — Skill Routing

These are real escape patterns observed in prior sessions. When you notice yourself thinking any of these, it is evidence you are about to violate `skill-first-invoke`.

| Thought | Reality |
|---------|---------|
| "Let me investigate what went wrong first" | The skill handles investigation. Invoke it — don't pre-read PRs, diffs, or JIRA tickets |
| "I already know how to do this" | Skills encode quality gates and side effects (lesson extraction, Slack notifications) that manual execution misses. Read the current version |
| "I need to read the ticket/PR before invoking" | Skills fetch their own data. Your pre-read wastes context and bypasses the skill's own flow |
| "I'll run quality-check first, then create the PR separately" | That's manually decomposing `engineer-delivery-flow`. The flow runs quality + verify + PR as one unit |
| "Let me check the sub-agents before invoking" | The skill defines the delegation strategy, not you. Invoke first |
| "I can fix these review comments by hand quickly" | Manual fix skips comment replies, quality checks, and lesson extraction. Use `engineering` revision mode |
| "This is just a simple question, no skill needed" | If a trigger matches, invoke the skill. Simple tasks become complex |

## Common Rationalizations — Reference Discovery

| Thought | Reality |
|---------|---------|
| "I already know what this reference says" | References get updated. Read the working tree version, not your memory |
| "The SKILL.md doesn't mention any references" | SKILL.md is not the discovery mechanism. INDEX.md is. New references may not be listed in any SKILL.md yet |
| "This is a simple JIRA operation, no reference needed" | Simple operations have structural rules (verification structure, SP field ID, subtask creation flow) that silently produce wrong output when skipped |

## Common Rationalizations — Delegation

| Thought | Reality |
|---------|---------|
| "I already did this analysis before, so I don't need to re-delegate" | Sub-agents read the latest rules and code. Your in-memory analysis may be stale. Re-delegate |
| "The scope is small enough to read a few files directly" | Each "small" read chains to the next. By read #6 you've blown the limit without noticing. Delegate at #3 |
| "Dispatching an explorer sub-agent adds overhead for a quick check" | 5 consecutive reads in main session costs more context than one sub-agent round-trip |
| "I'll do the analysis first, then hand off the JIRA writes" | Analysis is the expensive part. Only simple MCP writes and routing decisions stay in main session |
| "The sub-agent read the source code and confirmed it works this way" | Source code ≠ runtime. Frameworks have plugins, configs, and overrides. Verify with curl/test before stating as fact |

## Common Rationalizations — Handbook vs Feedback

| Thought | Reality |
|---------|---------|
| "I'll save this as feedback for now and migrate later" | Feedback memories are invisible to sub-agents. Handbook is auto-loaded. Save it right the first time |
| "This correction is small, doesn't warrant a handbook update" | Small corrections accumulate into wrong mental models. One wrong routing assumption → cascade of wrong decisions |
| "The handbook doesn't have a sub-file for this topic yet" | Create one. Sub-files are created on demand, triggered by the first correction on that topic |

## Common Rationalizations — Debugging & Verification

| Thought | Reality |
|---------|---------|
| "Let me add a helper function to work around this failure" | That's a bandaid. Ask: why did the original design not work? Read the design before patching |
| "Each workaround looks reasonable individually" | 2+ workarounds for the same feature = design-implementation gap. Stop and reconcile |
| "The implementation failed, let me try a different approach" | Before switching, query the source-of-truth (original caller, API spec). You may be fixing the wrong thing |
| "Verification passed in one repo, so it's fine" | If `workspace-config.requires` lists dependencies, verify with the full stack running |
| "Data looks correct" | Did you check HTTP status code? 200 is the minimum bar. "Looks correct" without status is speculation |
| "I'm confident this fix is right" | Confidence ≠ evidence. Run the verification command. Skip = lying, not efficiency |
| "One more fix attempt should do it" | After 3 failed fixes, stop. This is an architectural problem, not a missing patch |
| "Compiled source shows only one parameter" | Compiled/bundled JS ≠ API surface. Overloads, wrapper layers, and build transforms hide parameters. Check official docs or npm README first |
| "This module can't do what we need, let me replace it" | Replacement is T3 — confirm with user. First exhaust: (1) official API docs, (2) npm README, (3) GitHub issues/discussions. GT-521 lost 3 rounds because compiled source was treated as API truth |

## Common Rationalizations — Library Changes

> See `skills/references/library-change-protocol.md` § Common Rationalizations (canonical source).

## Common Rationalizations — Version Bump Reminder

| Thought | Reality |
|---------|---------|
| "This is a small change, not worth a version" | The user decides grouping, not you. Your job is to **remind**, not to judge whether the change is big enough |
| "I'll remind after the next task" | You won't. 6 consecutive sessions forgot. Remind NOW, at the commit boundary |
| "The session is about to end, version bump would be disruptive" | A 1-line reminder is not disruptive. Skipping it means the next session also forgets |
| "This commit only touched docs/references, not core skills" | `skills/references/` IS under `skills/`. The rule says `rules/` or `skills/` — no exceptions for subdirectories |

## Common Rationalizations — Design Plan

| Thought | Reality |
|---------|---------|
| "這次討論沒那麼複雜，不用建 plan" | check-pr-approvals v2.10.0 也是這樣想的，結果掉棒。門檻是「非 ticket 架構決策」，不是「很複雜」 |
| "等討論完再整理成 plan" | 整理時要回憶每個決策 = 回到原本的記憶模式。建檔要在討論開始，不是結束 |
| "我記得我們討論過 X 了" | 你記得的可能是最後一輪的 phrasing，不是早期的決策。讀 plan file，別依賴記憶 |
| "實作時偏離 plan 沒關係，等實作完再更新" | 那就是掉棒。發現偏離 → 立刻停下更新 plan + 加 Decision 條目 |

## Deterministic Quality Hooks — Detail

These mechanisms are enforced by **scripts + hooks** (exit code driven), not behavioral rules. They physically block the action — the Strategist cannot bypass them without env var override.

### Evidence file spec (`/tmp/polaris-verified-{TICKET}.json`)

```json
{
  "ticket": "KB2CW-1234",
  "timestamp": "2026-04-10T08:30:00Z",
  "branch": "task/KB2CW-1234-desc",
  "summary": { "total": 3, "pass": 2, "fail": 0, "skip": 1 },
  "results": [
    { "status": "PASS", "detail": "PASS: AC1 breadcrumb position" },
      { "status": "PASS", "detail": "PASS: AC2 JSON-LD in head" },
      { "status": "SKIP", "detail": "SKIP: AC3 not applicable" }
  ],
  "runtime_contract": {
    "level": "runtime",
    "runtime_verify_target": "https://dev.kkday.com/zh-tw",
    "runtime_verify_target_host": "dev.kkday.com",
    "verify_command": "curl -sk https://dev.kkday.com/zh-tw | ...",
    "verify_command_url": "https://dev.kkday.com/zh-tw",
    "verify_command_url_host": "dev.kkday.com"
  }
}
```

**Writer**: `scripts/run-verify-command.sh --ticket KB2CW-1234 --task-md <path/to/task.md> --repo <repo> -- <verify command>` — called by engineering (engineer-delivery-flow Step 3). Manual verification must still go through this script so evidence is tied to the current `head_sha`.

`runtime_contract` 是 PR gate 的硬門檻。`level=runtime` 時，gate 會檢查 live target 與 verify URL host 對齊，不合規直接 block `gh pr create`。

**Bypass**: `POLARIS_SKIP_EVIDENCE=1` for non-ticket PRs (framework, docs). Branch names without `[A-Z]+-[0-9]+` pattern are auto-allowed.

### Script reference

| Hook ID | Script | Bypass |
|---------|--------|--------|
| `verification-evidence-required` | `scripts/verification-evidence-gate.sh` (Dimension A only post-D12-c) | `POLARIS_SKIP_EVIDENCE=1` |
| `ci-local-required` | `.claude/hooks/ci-local-gate.sh` + `scripts/ci-local-run.sh` + `{company}/polaris-config/{project}/generated-scripts/ci-local.sh` | `POLARIS_SKIP_CI_LOCAL=1` (emergency only) |
| `test-sequence-warning` | `scripts/test-sequence-tracker.sh` | — (advisory only) |
| `context-pressure-monitor` | `scripts/context-pressure-monitor.sh` | — (advisory only) |
| `version-docs-lint-gate` | `.claude/hooks/version-docs-lint-gate.sh` | `POLARIS_SKIP_DOCS_LINT=1` |
| `design-plan-checklist-done` | `scripts/design-plan-checklist-gate.sh` | — (no bypass; resolve items first) |
