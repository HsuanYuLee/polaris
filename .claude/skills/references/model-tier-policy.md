# Model Tier Policy

Provider-neutral model selection policy for Polaris skills and sub-agent dispatch.

## Purpose

Skills must describe model choice with semantic classes, not raw provider model names. Runtime adapters then map those classes to concrete Codex, Claude Code, or future provider settings.

This keeps skill workflow prose portable across LLM runtimes and prevents stale provider-specific policy from spreading through `SKILL.md` files.

## Source Of Truth

This file is the only approved policy source for model tier semantics and concrete runtime mappings.

Allowed concrete model-name locations:

- This file, including runtime mapping tables and examples.
- Runtime config examples that explicitly say they are examples.
- Migration notes and release notes that describe historical model-name changes.
- Provider docs citations in research artifacts.

Disallowed locations:

- General skill workflow prose.
- Sub-agent dispatch instructions outside this policy reference.
- Mechanism canary prose that duplicates concrete model mappings instead of pointing here.

## Semantic Classes

| Class | Use For | Do Not Use For |
|-------|---------|----------------|
| `small_fast` | Low-risk extraction, checklist comparison, summarization, log parsing, read-only exploration, template-style batch work | Implementation, CI fixes, PR approval decisions, architecture, irreversible planning decisions, final user-visible synthesis |
| `realtime_fast` | Latency-sensitive interactive coding iteration when runtime support and account access are known | Long-running background work, final decisions, irreversible edits, high-risk review |
| `standard_coding` | Codebase exploration with decisions, implementation, tests, CI/debug analysis, PR review findings | Deep architecture tradeoffs with high ambiguity |
| `frontier_reasoning` | Architecture, difficult planning, high-risk review, cross-system tradeoffs, final arbitration when correctness matters more than latency | Mechanical batch work |
| `inherit` | Use the main session model when override is unnecessary, unsupported, or risky | Any case where policy explicitly requires downgrade or upgrade |

## Runtime Mapping

Mappings are defaults, not immutable facts. Provider availability changes by account, plan, API mode, enterprise policy, and runtime surface.

### Codex

| Class | Default Mapping | Notes |
|-------|-----------------|-------|
| `small_fast` | runtime-configured light coding model; current baseline: `gpt-5.4-mini` | Use for low-risk read-heavy subagents and batch extraction. Keep this mapping config-driven when possible. |
| `realtime_fast` | `gpt-5.3-codex-spark` | Research preview / account-gated. Use only as explicit low-latency override. Fall back to `small_fast` or `inherit` when unavailable. |
| `standard_coding` | `inherit` or current recommended coding model | Prefer inherited session model unless a local runtime config intentionally pins a standard coding model. |
| `frontier_reasoning` | strongest available Codex model, such as `gpt-5.5` when available | Use for architecture, final arbitration, high-risk review, and difficult planning. |
| `inherit` | omit model override | Safe default when the parent session already selected the right model. |

Approved Codex small-model candidates:

- `gpt-5.4-mini` for lighter coding tasks and subagents.
- Future OpenAI light coding models may be added here after official docs or internal runtime policy confirms the mapping.

`gpt-5.3-codex-spark` is not the universal `small_fast` default. It belongs to `realtime_fast` or a clearly named explicit low-latency override.

### Claude Code

| Class | Default Mapping | Notes |
|-------|-----------------|-------|
| `small_fast` | `haiku` alias | For simple, low-risk, high-volume work. Teams may pin the concrete model with `ANTHROPIC_DEFAULT_HAIKU_MODEL`. |
| `realtime_fast` | no default | Use `small_fast` or `inherit` until Claude Code has an approved low-latency coding-specific mapping. |
| `standard_coding` | `sonnet` alias | Daily coding, exploration with decisions, implementation, review, and CI/debug work. |
| `frontier_reasoning` | `opus` alias | Complex reasoning, architecture, and high-risk review. |
| `inherit` | `inherit` or omitted `model` frontmatter | Claude Code defaults omitted subagent model to inherit. |

Approved Claude small-model candidates:

- `haiku` alias.
- A concrete Haiku model pinned through `ANTHROPIC_DEFAULT_HAIKU_MODEL` when a team or provider policy requires version pinning.

## Effort Is Separate

Model class is not the same as reasoning effort.

Examples:

- `small_fast` can still use medium effort when the extraction is broad but low-risk.
- `frontier_reasoning` can use runtime default effort when the provider already adapts reasoning depth.
- Codex `model_reasoning_effort` and Claude Code `effort` / `CLAUDE_CODE_EFFORT_LEVEL` are runtime adapter settings, not replacements for this class taxonomy.

Runtime adapters may define default effort per class, but skills should continue to choose the semantic model class first.

## Runtime Adapter Examples

These examples are adapter examples, not new policy sources. If a concrete provider model changes, update the Runtime Mapping tables above first and keep examples aligned.

### Codex TOML Example

Use semantic class in Polaris workflow prose, then let the Codex adapter write concrete runtime settings. Keep `model` and `model_reasoning_effort` separate.

```toml
# Example only: .codex/agents/readiness-scan.toml
model_class = "small_fast"
model = "gpt-5.4-mini"
model_reasoning_effort = "medium"
```

```toml
# Example only: .codex/agents/interactive-iteration.toml
model_class = "realtime_fast"
model = "gpt-5.3-codex-spark"
model_reasoning_effort = "low"
fallback_model_class = "small_fast"
```

```toml
# Example only: omit model when inheriting the parent session.
model_class = "inherit"
model_reasoning_effort = "inherit"
```

Codex adapters must treat `realtime_fast` as opt-in. If the account or runtime does not expose `gpt-5.3-codex-spark`, fall back to `small_fast` for low-risk work or `inherit` when preserving the parent model is safer.

### Claude Code Frontmatter Example

Claude Code supports subagent frontmatter aliases and `inherit`. Use semantic class in Polaris prose, then map to Claude Code frontmatter at dispatch time.

```yaml
---
name: readiness-scanner
model_class: small_fast
model: haiku
effort: medium
---
```

```yaml
---
name: implementation-reviewer
model_class: standard_coding
model: sonnet
effort: inherit
---
```

```yaml
---
name: parent-model-continuation
model_class: inherit
model: inherit
effort: inherit
---
```

Teams that need a specific Claude small-model version should pin it in environment or runtime config, not in skill prose:

```bash
export ANTHROPIC_DEFAULT_HAIKU_MODEL="claude-3-5-haiku-latest"
```

### Adapter Fallback Rules

- `small_fast` unavailable → use `inherit` for safety unless the task is purely batch/template work and another approved small model is configured.
- `realtime_fast` unavailable → use `small_fast` for low-risk interactive work; use `inherit` when the task touches implementation, review, CI, or final synthesis.
- `frontier_reasoning` unavailable → use the strongest configured runtime model and record the fallback in the dispatch summary.
- Effort fallback must be handled independently from model fallback. Do not lower effort just because the model class is `small_fast`.

## Dispatch Rules

When a skill dispatches a sub-agent:

1. Classify the work risk and decision authority.
2. Choose a semantic class from this file.
3. Let the runtime adapter map the class to a provider value.
4. If the runtime cannot honor the mapping, fall back to `inherit` unless the work requires a stronger class.
5. Never allow `small_fast` or `realtime_fast` to produce final architecture decisions, implementation approval, PR approval, or final user-visible synthesis.

## Risk Gates

Use `small_fast` only when all are true:

- The task is low-risk and reversible.
- The expected output is evidence gathering, extraction, comparison, summarization, or template-style batch work.
- A stronger agent or main session will consume the result before final decisions.
- The sub-agent cannot silently make irreversible changes.

Use `standard_coding` or stronger when any are true:

- The task edits code.
- The task diagnoses CI or debug failures.
- The task reviews PR correctness, security, behavior regressions, or missing tests.
- The task decides architecture, scope, acceptance, release, or final user-facing summary.

Use `frontier_reasoning` when the task involves high ambiguity, cross-system tradeoffs, irreversible planning, or costly failure.

## Mirror Requirement

`.claude/skills` is the canonical source. `.agents/skills` is the Codex runtime-facing mirror and must remain a symlink to `../.claude/skills`.

Run:

```bash
bash scripts/check-skills-mirror-mode.sh
```

If it fails, restore the mirror before changing model policy references.

## Migration Guidance

Replace raw provider wording in skill prose:

| Old wording | New wording |
|-------------|-------------|
| `model: "haiku"` for batch low-risk work | `model class: small_fast` |
| `model: "sonnet"` for implementation or review | `model class: standard_coding` |
| `opus` / strongest model for architecture | `model class: frontier_reasoning` |
| no override needed | `model class: inherit` |
| `gpt-5.3-codex-spark` for fast interactive Codex work | `model class: realtime_fast` |

Concrete model names may stay in this file so validators and humans can audit the runtime mapping in one place.
