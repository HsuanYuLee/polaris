# Multi-Company Isolation Strategy

## How Rules Load

Claude Code loads **all** `.md` files under `.claude/rules/` recursively into every conversation. There is no native scoping mechanism — files in `.claude/rules/acme/` load even when working on `bigcorp` tickets.

Polaris works around this with **convention-based isolation**.

## Directory Convention

```
.claude/rules/
├── *.md                    # L1 — Universal rules (apply to ALL companies)
├── {company-a}/            # L2 — Company A rules
└── {company-b}/            # L2 — Company B rules

_template/rule-examples/    # Reference templates (NOT under rules/ — never auto-loaded)
```

## Defensive Rule Writing

Since all rules load globally, every company-specific rule file **must** include a scope header:

```markdown
# Rule Title

> **Scope: {company-name}** — applies only when working on {company-name} tickets or projects.

(rule content)
```

The Strategist uses this header to determine whether a rule applies to the current context. Rules without a scope header are treated as universal.

## Rule Examples (Reference Templates)

Rule examples live in `_template/rule-examples/` — **outside** `.claude/rules/` so they never auto-load into conversations. They show the structure and content patterns for L2 company rules.

- When `/init` creates a new company, it copies relevant templates into `.claude/rules/{company}/` with company-specific values and a scope header
- To browse examples manually, read files in `_template/rule-examples/`

## Context Cost

Every rule file consumes context window tokens. With multiple companies:

- Keep rule files concise — one concern per file
- Merge related rules into a single file rather than splitting into many small files
- If a company has > 10 rule files, consider consolidating

## Routing Disambiguation

When a JIRA ticket key is ambiguous (could belong to multiple companies):

1. Read `workspace-config.yaml` to match the JIRA project prefix against `jira.projects`
2. If matched, apply that company's L2 rules
3. If not matched, check `default_company` in `workspace-config.yaml` — if set, use it as the fallback company context
4. If `default_company` is also absent, ask the user which company context to use
5. Use `/which-company PROJ-123` for explicit diagnostics
6. If two companies share the same project prefix, automatic routing cannot distinguish them — use `/use-company` to explicitly set context before starting work

## Diagnostic Tool

Run `/validate-isolation` to scan for isolation violations: missing scope headers, untagged memories, cross-company conflicts. Recommended after adding a new company or before a version release.

## Known Limitations

- **No conditional loading**: all rule files load regardless of active company context. Defensive headers mitigate but don't eliminate wasted context tokens
- **Cross-contamination risk**: if a rule omits its scope header, the Strategist may apply it to the wrong company. The scope header convention is the primary safeguard
