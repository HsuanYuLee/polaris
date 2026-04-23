#!/usr/bin/env bash
# test-sequence-tracker.sh — PostToolUse hook on Bash
# Tracks the sequence: test fail → production file edit → test pass
# When this pattern is detected, injects a warning.
#
# State file: /tmp/polaris-test-sequence.json
# Tracks: last_test_status, last_test_time, prod_files_edited_after_fail
#
# Exit 0 = continue (stdout = injected message, if any)

set -euo pipefail

STATE_FILE="/tmp/polaris-test-sequence.json"

input=$(cat)

tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)

# --- PostToolUse on Bash: detect test commands ---
if [[ "$tool_name" == "Bash" ]]; then
  command=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || true)
  tool_output=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_output','')[:2000])" 2>/dev/null || true)
  exit_code=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_exit_code', 0))" 2>/dev/null || echo "0")

  # Detect test commands
  is_test=false
  if printf '%s' "$command" | grep -qiE '(pnpm|npx|yarn)[[:space:]]+(test|vitest|jest)|vitest\b|jest\b'; then
    is_test=true
  fi

  if [[ "$is_test" == "true" ]]; then
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if [[ "$exit_code" != "0" ]]; then
      # Test FAILED — record state
      python3 -c "
import json
state = {
    'last_test_status': 'fail',
    'last_test_time': '${timestamp}',
    'last_test_command': $(python3 -c "import json; print(json.dumps('${command}'[:200]))" 2>/dev/null || echo '""'),
    'prod_files_edited_after_fail': [],
    'sequence_active': True
}
with open('${STATE_FILE}', 'w') as f:
    json.dump(state, f, indent=2)
" 2>/dev/null || true
    else
      # Test PASSED — check if we're in a fail→edit→pass sequence
      if [[ -f "$STATE_FILE" ]]; then
        warning=$(python3 -c "
import json
with open('${STATE_FILE}') as f:
    state = json.load(f)
if state.get('sequence_active') and state.get('last_test_status') == 'fail':
    edited = state.get('prod_files_edited_after_fail', [])
    if len(edited) > 0:
        files = ', '.join(edited[:5])
        extra = f' (+{len(edited)-5} more)' if len(edited) > 5 else ''
        print(f'⚠️ TEST SEQUENCE WARNING: Tests previously failed, then you edited production files ({files}{extra}), and now tests pass. Confirm this is the correct fix — not a workaround that makes tests green by wrong means. If you changed production code to accommodate test expectations rather than fixing the actual bug, STOP and reconsider.')
    else:
        print('')  # tests failed then passed without prod edits — normal
else:
    print('')
" 2>/dev/null || echo "")

        if [[ -n "$warning" ]]; then
          echo "$warning"
        fi

        # Reset state
        rm -f "$STATE_FILE"
      fi
    fi

    exit 0
  fi

  exit 0
fi

# --- PostToolUse on Edit: track production file edits ---
if [[ "$tool_name" == "Edit" || "$tool_name" == "Write" ]]; then
  # Only track if we have an active fail sequence
  [[ -f "$STATE_FILE" ]] || exit 0

  file_path=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || true)

  # Only track production files (not test files, not config, not .claude/)
  if [[ -n "$file_path" ]] && \
     [[ ! "$file_path" =~ \.(test|spec)\.(ts|js|tsx|jsx)$ ]] && \
     [[ ! "$file_path" =~ __tests__/ ]] && \
     [[ ! "$file_path" =~ \.claude/ ]] && \
     [[ ! "$file_path" =~ /scripts/ ]] && \
     [[ ! "$file_path" =~ /\.github/ ]] && \
     [[ ! "$file_path" =~ (package\.json|tsconfig|\.config\.) ]]; then

    python3 -c "
import json
with open('${STATE_FILE}') as f:
    state = json.load(f)
if state.get('sequence_active'):
    edited = state.get('prod_files_edited_after_fail', [])
    fp = '${file_path}'.split('/')[-1]  # just filename for readability
    if fp not in edited:
        edited.append(fp)
    state['prod_files_edited_after_fail'] = edited
    with open('${STATE_FILE}', 'w') as f:
        json.dump(state, f, indent=2)
" 2>/dev/null || true
  fi

  exit 0
fi

exit 0
