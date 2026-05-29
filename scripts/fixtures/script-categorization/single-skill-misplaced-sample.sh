#!/usr/bin/env bash
# single-skill-misplaced-sample.sh — fixture for validate-script-categorization.sh.
#
# Purpose: simulate a root script whose only callsite lives inside one
# .claude/skills/{skill}/ directory. The categorization gate must classify
# it as `skill_local` and FAIL in diff mode (POLARIS_SCRIPT_MISPLACED:{path})
# with a migration hint pointing at .claude/skills/{skill}/scripts/.
#
# Selftest populates a synthetic single-skill consumer pointing at this
# fixture and asserts the migration hint surfaces in the error output.
set -euo pipefail
echo "single-skill misplaced fixture"
