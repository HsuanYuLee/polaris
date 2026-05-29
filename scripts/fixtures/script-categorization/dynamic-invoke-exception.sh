#!/usr/bin/env bash
# dynamic-invoke-exception.sh — fixture for validate-script-categorization.sh.
#
# Purpose: simulate a root script that is invoked dynamically (e.g. via
# `bash "$script_name"` with a runtime-resolved name) from a single skill.
# When the script is declared in the validator's
# `script-categorization-exception.txt` allowlist with an owning-skill +
# reason, the gate must NOT classify it as `skill_local` misplaced.
#
# AC4 adversarial pass (EC3): dynamic-invoke fixture must NOT block, but
# the exception entry MUST carry an owning-skill + reason; otherwise the
# fixture is still treated as single-skill misplaced.
set -euo pipefail
echo "dynamic-invoke exception fixture"
