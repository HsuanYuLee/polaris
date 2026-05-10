#!/usr/bin/env bash
# post-skill-reflection.sh — PostToolUse hook (on Skill tool)
# After a skill completes, injects a reflection prompt.
# Exit 0 = continue (inject message via stdout)

set -euo pipefail

input=$(cat)

tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)

[[ "$tool_name" == "Skill" ]] || exit 0

# Inject reflection reminder after skill execution
cat <<'EOF'
[Post-Skill Reflection Checkpoint]
Skill execution complete. Before proceeding, check:
1. Did the user correct any behavior during this task? → Write feedback memory NOW (do not defer)
2. Were any commands self-corrected (wrong path, wrong API)? → Record the correction
3. Was a non-obvious technical insight discovered? → Write cross-session learning
This checkpoint is deterministic — you cannot skip it.
EOF

exit 0
