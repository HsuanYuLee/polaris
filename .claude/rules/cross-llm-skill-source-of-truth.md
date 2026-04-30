# Cross-LLM Skill Source Of Truth

## Core Rule

Shared Polaris skills are edited in `.claude/skills/` only.

- `.claude/skills/` is the single source of truth for shared skill definitions and shared references
- `.agents/skills/` is a runtime-facing mirror path for Codex compatibility
- Do not treat `.agents/skills/` as an independent authoring surface

## Required Mirror Mode

`.agents/skills` must be a symlink to `../.claude/skills`.

This avoids copy drift between Claude-facing and Codex-facing paths. If the mirror is a physical copied directory, the workspace is in a degraded compatibility state and must be repaired before release or framework validation passes.

## Editing Rules

- When updating a shared skill, edit `.claude/skills/{skill}/SKILL.md`
- When updating a shared reference consumed by skills, edit `.claude/skills/references/*`
- Company-specific skills remain under `.claude/skills/{company}/`
- Maintainer-only skills remain under `.claude/skills/` with their existing scope controls
- Runtime-specific adapter examples must point back to `.claude/skills/references/model-tier-policy.md`; do not duplicate concrete model policy in `.agents/skills`, generated prompts, or runtime notes

## Verification

Before declaring cross-LLM parity healthy:

1. Verify `.agents/skills` is a symlink to `../.claude/skills`
2. Run `scripts/validate-model-tier-policy.sh`
3. Verify Codex rule transpile is in sync
4. Verify parity checks pass

## Why

Rules can tell every LLM where to edit, but only a symlink removes the possibility of mirror drift. The rule defines intent; the symlink enforces it mechanically.

## Platform Notes

On Windows or systems with `core.symlinks=false`, `git checkout` may materialize
`.agents/skills` as a regular text file containing `../.claude/skills` instead
of a real symlink. In that state, `scripts/check-skills-mirror-mode.sh` will fail.

Fix options:

```bash
git config core.symlinks true
git rm --cached .agents/skills
git checkout HEAD -- .agents/skills
```

Or recreate the alias directly:

```bash
bash scripts/sync-skills-cross-runtime.sh --to-agents --link
```
