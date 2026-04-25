#!/usr/bin/env bash
# write-deliverable.sh — DP-033 A8
#
# Atomically inject / replace the `deliverable` frontmatter block in a task.md
# after `gh pr create` succeeds.
#
# Usage:
#   scripts/write-deliverable.sh <task-md-path> <pr-url> <pr-state> <head-sha>
#
# Arguments:
#   task-md-path   Absolute or workspace-relative path to the T{n}.md file.
#   pr-url         GitHub PR URL (https://github.com/.../pull/NNN)
#   pr-state       OPEN | MERGED | CLOSED
#   head-sha       7+ character hex commit SHA
#
# Exit codes:
#   0  — success; deliverable block written and verified
#   1  — transient failure (all 3 retries failed); inconsistent state — caller must HALT
#   2  — argument error / pre-condition failure
#
# Contract (spec § 2.1, DP-033 D7):
#   1. Validate args.
#   2. Write to <file>.tmp in the same directory, then `mv` over the original (atomic on POSIX).
#   3. Retry up to 3 times with exponential backoff (1s, 2s, 4s) on any failure.
#   4. After successful mv, re-read the file and verify pr_url matches.
#   5. On permanent failure → exit 1 with the human-readable inconsistent-state message.
#
# Idempotency:
#   If a `deliverable:` block already exists in the frontmatter, it is REPLACED (not appended).

set -uo pipefail

# ── Constants ──────────────────────────────────────────────────────────────────

SCRIPT_NAME="$(basename "$0")"
MAX_RETRIES=3

# ── Helpers ────────────────────────────────────────────────────────────────────

die() {
  local msg="$1"
  printf '[write-deliverable] ERROR: %s\n' "$msg" >&2
  exit 2
}

fail_inconsistent() {
  local pr_url="$1" task_path="$2" cause="$3"
  printf '\n' >&2
  printf '====================================================================\n' >&2
  printf 'HARD STOP — inconsistent state detected\n' >&2
  printf '====================================================================\n' >&2
  printf 'PR URL     : %s\n' "$pr_url" >&2
  printf 'task.md    : %s\n' "$task_path" >&2
  printf 'Cause      : %s\n' "$cause" >&2
  printf '%s\n' '--------------------------------------------------------------------' >&2
  printf 'task is in inconsistent state — PR created but task.md not updated. Manual recovery required.\n' >&2
  printf '====================================================================\n' >&2
  exit 1
}

log() {
  printf '[write-deliverable] %s\n' "$1" >&2
}

# ── Argument validation ─────────────────────────────────────────────────────────

[[ $# -eq 4 ]] || die "Usage: $SCRIPT_NAME <task-md-path> <pr-url> <pr-state> <head-sha>"

TASK_MD="$1"
PR_URL="$2"
PR_STATE="$3"
HEAD_SHA="$4"

# Validate task.md exists and is a regular file
[[ -f "$TASK_MD" ]] || die "task.md not found: $TASK_MD"

# Validate PR URL format
if ! printf '%s' "$PR_URL" | grep -qE '^https://github\.com/.+/pull/[0-9]+$'; then
  die "pr-url does not match expected pattern (https://github.com/.../pull/NNN): $PR_URL"
fi

# Validate pr-state enum
case "$PR_STATE" in
  OPEN|MERGED|CLOSED) ;;
  *) die "pr-state must be OPEN | MERGED | CLOSED, got: $PR_STATE" ;;
esac

# Validate head-sha (7+ hex chars)
if ! printf '%s' "$HEAD_SHA" | grep -qE '^[0-9a-fA-F]{7,}$'; then
  die "head-sha must be 7+ hex characters, got: $HEAD_SHA"
fi

# Resolve to absolute path
TASK_MD="$(cd "$(dirname "$TASK_MD")" && pwd)/$(basename "$TASK_MD")"
TASK_DIR="$(dirname "$TASK_MD")"
TMP_FILE="${TASK_MD}.tmp"

# ── Python rewriter (atomic frontmatter replacement) ──────────────────────────
#
# Uses Python for reliable YAML frontmatter handling (nested maps, quoting,
# existing deliverable replacement).  Writes to TMP_FILE; caller does the mv.

REWRITER=$(cat <<'PYEOF'
import sys, re

task_path = sys.argv[1]
tmp_path  = sys.argv[2]
pr_url    = sys.argv[3]
pr_state  = sys.argv[4]
head_sha  = sys.argv[5]

with open(task_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Detect and strip existing deliverable block from frontmatter.
# Frontmatter is the first --- ... --- block.
fm_pattern = re.compile(r'^---\n(.*?)^---\n', re.DOTALL | re.MULTILINE)
match = fm_pattern.match(content)

if not match:
    # No frontmatter at all — prepend one
    deliverable_fm = (
        '---\n'
        f'deliverable:\n'
        f'  pr_url: {pr_url}\n'
        f'  pr_state: {pr_state}\n'
        f'  head_sha: {head_sha}\n'
        '---\n'
    )
    new_content = deliverable_fm + content
else:
    fm_body = match.group(1)

    # Remove any existing deliverable: block (multiline, indented sub-keys)
    cleaned_fm = re.sub(
        r'^deliverable:(?:\n(?:[ \t]+[^\n]*))*\n?',
        '',
        fm_body,
        flags=re.MULTILINE
    )
    # Ensure trailing newline
    if cleaned_fm and not cleaned_fm.endswith('\n'):
        cleaned_fm += '\n'

    # Append deliverable block
    cleaned_fm += (
        f'deliverable:\n'
        f'  pr_url: {pr_url}\n'
        f'  pr_state: {pr_state}\n'
        f'  head_sha: {head_sha}\n'
    )

    new_content = '---\n' + cleaned_fm + '---\n' + content[match.end():]

with open(tmp_path, 'w', encoding='utf-8') as f:
    f.write(new_content)

sys.exit(0)
PYEOF
)

# ── Verifier (read-back check) ─────────────────────────────────────────────────

VERIFIER=$(cat <<'PYEOF'
import sys, re

task_path = sys.argv[1]
expected_url = sys.argv[2]

with open(task_path, 'r', encoding='utf-8') as f:
    content = f.read()

fm_pattern = re.compile(r'^---\n(.*?)^---\n', re.DOTALL | re.MULTILINE)
match = fm_pattern.match(content)
if not match:
    print('NO_FRONTMATTER', end='')
    sys.exit(1)

fm_body = match.group(1)
url_match = re.search(r'^  pr_url:\s*(.+)$', fm_body, re.MULTILINE)
if not url_match:
    print('NO_PR_URL', end='')
    sys.exit(1)

found_url = url_match.group(1).strip()
if found_url != expected_url:
    print(f'MISMATCH:{found_url}', end='')
    sys.exit(1)

print('OK', end='')
sys.exit(0)
PYEOF
)

# ── Retry loop ─────────────────────────────────────────────────────────────────

attempt=0
last_error=""

while [[ $attempt -lt $MAX_RETRIES ]]; do
  attempt=$(( attempt + 1 ))
  log "Attempt ${attempt}/${MAX_RETRIES}: writing deliverable block..."

  # Step 1: Run Python rewriter → TMP_FILE
  write_error=""
  if ! write_error=$(python3 - "$TASK_MD" "$TMP_FILE" "$PR_URL" "$PR_STATE" "$HEAD_SHA" <<< "$REWRITER" 2>&1); then
    last_error="Python rewriter failed (attempt ${attempt}): ${write_error}"
    log "$last_error"
  else
    # Step 2: Atomic mv (POSIX: same filesystem → rename(2) is atomic)
    mv_error=""
    if ! mv_error=$(mv "$TMP_FILE" "$TASK_MD" 2>&1); then
      last_error="mv failed (attempt ${attempt}): ${mv_error}"
      log "$last_error"
      # Clean up orphaned tmp if it exists
      rm -f "$TMP_FILE" 2>/dev/null || true
    else
      # Step 3: Verify by re-reading
      verify_result=""
      verify_result=$(python3 - "$TASK_MD" "$PR_URL" <<< "$VERIFIER" 2>&1) || true

      if [[ "$verify_result" == "OK" ]]; then
        log "Success: deliverable block written and verified in $TASK_MD"
        exit 0
      else
        last_error="Verification failed (attempt ${attempt}): $verify_result"
        log "$last_error"
        # Verification mismatch is a hard error — no retry makes sense for content mismatch
        # (the write completed but the content is wrong; retry would just repeat same wrong write)
        # Exception: if it's a race condition or transient read issue, retry once.
      fi
    fi
  fi

  # Exponential backoff before retry: 1s, 2s, 4s
  if [[ $attempt -lt $MAX_RETRIES ]]; then
    backoff=$(( 2 ** (attempt - 1) ))
    log "Retrying in ${backoff}s..."
    sleep "$backoff"
  fi
done

# All retries exhausted
fail_inconsistent "$PR_URL" "$TASK_MD" "$last_error"
