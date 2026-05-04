#!/usr/bin/env bash
# cross-session-warm-scan.sh — UserPromptSubmit hook
#
# Detects "繼續 X" / "continue X" prompts (X = topic keyword) and emits an
# advisory list of memory files matching the keyword across the Hot flat root
# AND every Warm topic folder. Prevents the failure mode where the Strategist
# only scans `ls memory/ | grep` (non-recursive, misses Warm folders) and
# then reports "memory lost".
#
# Mechanism canary: cross-session-warm-folder-scan
# Rule ref:         CLAUDE.md § Cross-Session Continuity
# Feedback memory:  feedback_cross_session_warm_folder_scan.md
# Backlog source:   polaris-backlog.md § Roadmap to Done item #2 (2026-04-26)
#
# Hook type: UserPromptSubmit
# Input:     JSON on stdin with field `user_prompt` (or `prompt` fallback)
# Stdout:    advisory text injected into prompt context
# Exit 0:    always — advisory only, never blocks user prompts
#
# Note on event choice: the backlog phrasing said "SessionStart hook" but
# SessionStart fires before any prompt is visible — it can't extract the
# keyword. UserPromptSubmit is the semantically correct event; the spirit
# of the backlog item (deterministic find on `繼續 X` triggers) is preserved.

set -uo pipefail

# Memory directory — override via POLARIS_MEMORY_DIR for selftests.
MEMORY_DIR="${POLARIS_MEMORY_DIR:-/Users/hsuanyu.lee/.claude/projects/-Users-hsuanyu-lee-work/memory}"

# Skip if memory dir absent (fresh workstation)
[ -d "$MEMORY_DIR" ] || exit 0

# Capture full hook input JSON
INPUT=$(cat)
[ -n "$INPUT" ] || exit 0

# Single python invocation: parse JSON, detect trigger, scan memory, emit advisory.
# The hook input is passed via env var (POLARIS_HOOK_INPUT) so the heredoc can
# supply the python script via stdin without colliding.
ADVISORY=$(POLARIS_HOOK_INPUT="$INPUT" python3 - "$MEMORY_DIR" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

memory_dir = Path(sys.argv[1])

try:
    data = json.loads(os.environ.get('POLARIS_HOOK_INPUT', '{}'))
except json.JSONDecodeError:
    sys.exit(0)

text = data.get('user_prompt') or data.get('prompt') or ''
if not text or not isinstance(text, str):
    sys.exit(0)

# Trigger detection: 繼續 / continue followed by optional whitespace + non-empty topic.
# Zero-input forms ("繼續", "繼續。", "下一步") have no captured tail → no fire.
# Note: no `\b` — Chinese chars on both sides of 繼續 (e.g., 繼續做) make `\b` fail
# because the ASCII word boundary requires \w on one side.
trigger_re = re.compile(r'(?:繼續|continue)\s*([^\n。.!?]{1,120})', re.IGNORECASE)
m = trigger_re.search(text)
if not m:
    sys.exit(0)

tail = m.group(1).strip()
if not tail:
    sys.exit(0)

# Strip leading verb particles ("繼續做 TASK-3711" → "TASK-3711")
tail = re.sub(r'^[做修看辦弄寫改\s]+', '', tail).strip()
if not tail:
    sys.exit(0)

# Reject "continue" as part of unrelated English phrases (e.g., "the loop will continue")
# Heuristic: tail must start with an alphanumeric or have a JIRA key — otherwise skip
if not re.match(r'^[A-Za-z0-9_一-鿿-]', tail):
    sys.exit(0)

# Extract candidate keywords:
#  - JIRA-style keys (e.g., EPIC-478, TASK-3711, DP-015)
#  - Alphanumeric tokens length ≥ 3
jira_keys = re.findall(r'\b[A-Z][A-Z0-9]+-\d+\b', tail)
words = re.findall(r'[A-Za-z][A-Za-z0-9_-]{2,}', tail)

stop_words = {
    'the', 'and', 'this', 'that', 'work', 'item', 'task',
    'next', 'last', 'session', 'continue', 'pls', 'please',
    'on', 'for', 'from'
}

keywords = []
seen = set()
for kw in jira_keys + words:
    kl = kw.lower()
    if kl in stop_words or kl in seen:
        continue
    seen.add(kl)
    keywords.append(kw)

if not keywords:
    sys.exit(0)

# Cap at 3 keywords to avoid noise on rich prompts
keywords = keywords[:3]

# Recursive case-insensitive name match across all tiers (flat root + Warm + archive).
# Match against full relative path (so folder slug like `polaris-framework/` counts).
# Normalize dashes — file names typically strip them ("project_gt478_*.md") while
# user keywords keep them ("EPIC-478").
hits = {}
for kw in keywords:
    needle = kw.lower()
    needle_norm = needle.replace('-', '')
    found = []
    for p in memory_dir.rglob('*.md'):
        rel = p.relative_to(memory_dir)
        rel_lower = str(rel).lower()
        rel_norm = rel_lower.replace('-', '')
        if needle in rel_lower or needle_norm in rel_norm:
            # Skip the top-level MEMORY.md index itself — it's a pointer, not content
            if rel.name == 'MEMORY.md' and len(rel.parts) == 1:
                continue
            found.append(str(rel))
    if found:
        hits[kw] = sorted(found)

if not hits:
    sys.exit(0)

# Emit advisory (stdout becomes additional prompt context for Claude)
print('[繼續] Memory matches detected — read these BEFORE responding:')
print()
for kw, files in hits.items():
    print(f'**Keyword `{kw}`:**')
    for f in files[:8]:
        print(f'  - `{f}`')
    if len(files) > 8:
        print(f'  ... +{len(files) - 8} more')
    print()

print('Cross-Session Continuity reminder (CLAUDE.md):')
print('  1. Read the full memory file(s) — index one-liner is not enough')
print('  2. Read linked plans / checkpoints / artifacts referenced inside')
print('  3. Reconstruct context (decided / done / next) and confirm with user')
print('  4. Never report "memory lost" when files matched above')
PY
)

[ -n "$ADVISORY" ] || exit 0

printf '%s\n' "$ADVISORY"
exit 0
