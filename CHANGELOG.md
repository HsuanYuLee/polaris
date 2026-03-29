# Changelog

All notable changes to the Polaris framework are documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/). Versions follow [Semantic Versioning](https://semver.org/):
- **Major**: Architectural changes, brand/identity changes
- **Minor**: New skills, major skill features, new rules/references
- **Patch**: Skill bugfixes, rule tweaks, doc updates

## [1.0.0] - 2026-03-30

### Changed
- **Identity established**: Polaris — AI that helps you navigate, build, and reach where you're going. Inspired by Zhang Liang (張良).
- Persona: Commander → Strategist (軍師) — "listen first, then orchestrate"
- README.md rewritten: framework-perspective introduction, genericized structure, Quick Start via `/init`
- CLAUDE.md: updated title, persona, added "continuous learning" responsibility

## [0.9.0] - 2026-03-29

### Added
- `/init` v3: smartSelect interaction pattern, AI repo detection, audit trail ([SKILL.md](.claude/skills/init/SKILL.md))
- `learning` Meta: Attribution — auto-credit external repos in README Acknowledgements ([SKILL.md](.claude/skills/learning/SKILL.md))
- `README.md` Acknowledgements section for crediting inspiration sources
- `VERSION` file and this `CHANGELOG.md` for framework-level versioning
- `polaris-backlog.md` for tracking improvement candidates

### Changed
- `/init` bumped to v3.0.0 (was v2.0.0)
- `learning` bumped to v1.4.0 (was v1.3.0)

## [0.8.0] - 2026-03-29

### Added
- Phase 5.5: Bidirectional sync scripts, CLAUDE.md genericization, company skills subdirectory
- `context-monitoring` rule for context window self-management
- `feedback-and-memory` rule with auto-evolution pipeline (feedback -> rule graduation)
- Dual sync: `sync-from-upstream.sh` (Polaris -> instance) + `sync-from-polaris.sh` (instance -> Polaris)

### Changed
- CLAUDE.md genericized — company-specific content moved to `rules/your-company/`
- Skills directory restructured: `skills/your-company/` for company-specific skills

## [0.7.0] - 2026-03-29

### Added
- Phase 4: Two-layer config architecture (root + company `workspace-config.yaml`)
- `/init` skill v2.0.0: interactive wizard for company setup
- `_template/` directory with workspace-config template and genericize sed files
- `workspace-config-reader.md` reference for skill config resolution
- Multi-company support: root config routes to company configs by `base_dir` or JIRA key

### Changed
- All skills migrated from hardcoded paths to config-driven resolution
- `workspace-config.example.yaml` replaced by `_template/workspace-config.yaml`

## [0.6.0] - 2026-03-28

### Added
- Phase 3: Polaris template repo (HsuanYuLee/polaris) extracted from work/
- Genericize pipeline: sed scripts strip company-specific references before upstream push

## [0.5.0] - 2026-03-28

### Changed
- Phase 2: Skill rename — all skills moved from company-specific names to generic names
- Phase 1: Config consolidation — scattered config values unified into `workspace-config.yaml`
- Phase 0: Initial three-layer architecture design (Workspace / Company / Project)

## [Pre-0.5] - Prior work

Skills, rules, and references developed organically during daily YourOrg usage. No formal versioning.
