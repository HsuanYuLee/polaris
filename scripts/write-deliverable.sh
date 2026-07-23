#!/usr/bin/env bash
# write-deliverable.sh — DP-033 A8
#
# Atomically inject / replace the `deliverable` frontmatter block in a task.md
# after `gh pr create` succeeds.
#
# Usage:
#   scripts/write-deliverable.sh <task-md-path> <pr-url> <pr-state> <head-sha>
#   scripts/write-deliverable.sh --verification-pass <task-md-path> <pr-url> <pr-state> <head-sha> --repo <repo-root>
#   scripts/write-deliverable.sh --no-pr <task-md-path> <head-sha> --repo <repo-root>
#   scripts/write-deliverable.sh --verification-aggregate-head <task-md-path> <aggregate-head-sha>
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
#   The --verification-aggregate-head mode updates only
#   deliverable.verification.aggregate_head_sha and preserves the top-level
#   deliverable head_sha as the task PR head authority.

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

# 驗證 PR PASS materialization 只接受同一 task / head 的 durable Layer B evidence 與 report。
validate_pr_verification_proof() {
  local task_md="$1"
  local head_sha="$2"
  local repo_root="$3"
  local script_dir=""
  local work_item_id=""
  local delivery_ticket=""
  local verify_evidence=""
  local report_path=""

  [[ -f "$task_md" ]] || die "task.md not found: $task_md"
  [[ -d "$repo_root" ]] || die "repo root not found: $repo_root"
  git -C "$repo_root" rev-parse --show-toplevel >/dev/null 2>&1 \
    || die "--repo must be a Git repository"

  script_dir="$(cd "$(dirname "$0")" && pwd)"
  work_item_id="$(bash "$script_dir/parse-task-md.sh" "$task_md" --no-resolve --field work_item_id 2>/dev/null || true)"
  [[ -n "$work_item_id" ]] || die "cannot resolve work_item_id from task.md"
  delivery_ticket="$(bash "$script_dir/parse-task-md.sh" "$task_md" --no-resolve --field delivery_ticket_key 2>/dev/null || true)"
  case "$delivery_ticket" in
    ""|N/A|null) delivery_ticket="$work_item_id" ;;
  esac

  # shellcheck source=lib/verification-evidence.sh
  . "$script_dir/lib/verification-evidence.sh"
  verify_evidence="$(verification_evidence_durable_path "$repo_root" "$delivery_ticket" "$head_sha" 2>/dev/null || true)"
  [[ -n "$verify_evidence" && -f "$verify_evidence" ]] \
    || die "canonical durable verify evidence not found for ${delivery_ticket}@${head_sha}"
  verification_evidence_validate_file "$verify_evidence" "$delivery_ticket" "$head_sha" >/dev/null \
    || die "verify evidence is invalid or stale for ${delivery_ticket}@${head_sha}"
  verification_evidence_is_pass "$verify_evidence" >/dev/null \
    || die "verify evidence is not PASS for ${delivery_ticket}@${head_sha}"

report_path="$(python3 - "$task_md" <<'PY'
from pathlib import Path
import sys

task = Path(sys.argv[1]).resolve()
print(task.parent / "verify-report.md" if task.name == "index.md" else task.with_suffix("") / "verify-report.md")
PY
)"
  [[ -f "$report_path" ]] \
    || die "task-bound verify report not found for ${delivery_ticket}@${head_sha}: ${report_path}"
  python3 - "$report_path" "$delivery_ticket" "$head_sha" <<'PY' \
    || die "task-bound verify report is stale or invalid for ${delivery_ticket}@${head_sha}"
from pathlib import Path
import re
import sys

report = Path(sys.argv[1])
ticket = sys.argv[2]
head = sys.argv[3]
text = report.read_text(encoding="utf-8")

if not text.startswith("---\n"):
    raise SystemExit(1)
end = text.find("\n---\n", 4)
if end == -1:
    raise SystemExit(1)
frontmatter = text[4:end]
if "title:" not in frontmatter or "description:" not in frontmatter:
    raise SystemExit(1)
if ticket not in text or head not in text:
    raise SystemExit(1)
if not re.search(r"^- 狀態：`PASS`$", text, re.MULTILINE):
    raise SystemExit(1)
PY
}

# ── task_shape-first no-PR mode ───────────────────────────────────────────────

if [[ "${1:-}" == "--no-pr" ]]; then
  [[ $# -eq 5 && "${4:-}" == "--repo" ]] || die "Usage: $SCRIPT_NAME --no-pr <task-md-path> <head-sha> --repo <repo-root>"

  TASK_MD="$2"
  HEAD_SHA="$3"
  REPO_ROOT="$5"
  [[ -f "$TASK_MD" ]] || die "task.md not found: $TASK_MD"
  [[ -d "$REPO_ROOT" ]] || die "repo root not found: $REPO_ROOT"
  REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"
  CURRENT_HEAD="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
  [[ -n "$CURRENT_HEAD" ]] || die "--repo must be a Git repository with a current HEAD"
  if ! printf '%s' "$HEAD_SHA" | grep -qE '^[0-9a-fA-F]{7,}$'; then
    die "head-sha must be 7+ hex characters, got: $HEAD_SHA"
  fi
  [[ "$HEAD_SHA" == "$CURRENT_HEAD" ]] || die "head-sha must exactly match current repository HEAD (${CURRENT_HEAD})"

  TASK_SHAPE="$(awk '
    BEGIN { fm=0 }
    /^---$/ { fm++; next }
    fm == 1 && /^task_shape:[[:space:]]*/ {
      value=$0; sub(/^task_shape:[[:space:]]*/, "", value); gsub(/^['\"']|['\"']$/, "", value)
      print value; exit
    }
  ' "$TASK_MD")"
  case "$TASK_SHAPE" in
    audit|confirmation) ;;
    *) die "--no-pr requires task_shape audit or confirmation (got: ${TASK_SHAPE:-implementation})" ;;
  esac

  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  WORK_ITEM_ID="$(bash "$SCRIPT_DIR/parse-task-md.sh" "$TASK_MD" --no-resolve --field work_item_id 2>/dev/null || true)"
  [[ -n "$WORK_ITEM_ID" ]] || die "cannot resolve work_item_id from task.md"
  # shellcheck source=lib/verification-evidence.sh
  . "$SCRIPT_DIR/lib/verification-evidence.sh"
  VERIFY_EVIDENCE="$(verification_evidence_durable_path "$REPO_ROOT" "$WORK_ITEM_ID" "$HEAD_SHA" 2>/dev/null || true)"
  [[ -n "$VERIFY_EVIDENCE" && -f "$VERIFY_EVIDENCE" ]] || die "canonical durable verify evidence not found for ${WORK_ITEM_ID}@${HEAD_SHA}"
  if ! verification_evidence_validate_file "$VERIFY_EVIDENCE" "$WORK_ITEM_ID" "$HEAD_SHA" >/dev/null; then
    die "verify evidence is invalid or stale for ${WORK_ITEM_ID}@${HEAD_SHA}"
  fi
  if ! verification_evidence_is_pass "$VERIFY_EVIDENCE" >/dev/null; then
    die "verify evidence is not PASS for ${WORK_ITEM_ID}@${HEAD_SHA}"
  fi

  TASK_MD="$(cd "$(dirname "$TASK_MD")" && pwd)/$(basename "$TASK_MD")"
  TASK_DIR="$(dirname "$TASK_MD")"
  TMP_DIR="$(mktemp -d "${TASK_DIR}/.write-deliverable.XXXXXX")" || die "cannot create same-directory unique temp"
  TMP_FILE="${TMP_DIR}/$(basename "$TASK_MD")"

  log "Writing canonical no-PR deliverable for ${TASK_SHAPE} task..."
  if ! python3 - "$TASK_MD" "$TMP_FILE" "$HEAD_SHA" <<'PY'
import re
import sys
from pathlib import Path

task_path = Path(sys.argv[1])
tmp_path = Path(sys.argv[2])
head_sha = sys.argv[3]
text = task_path.read_text(encoding="utf-8")
match = re.match(r"^---\n(.*?)^---\n", text, re.DOTALL | re.MULTILINE)
if not match:
    raise SystemExit("task.md must contain frontmatter")

lines = match.group(1).splitlines(keepends=True)
start = next((i for i, line in enumerate(lines) if re.match(r"^deliverable:\s*(?:#.*)?$", line.rstrip("\n"))), None)
if start is not None:
    end = len(lines)
    for i in range(start + 1, len(lines)):
        line = lines[i]
        if line.strip() and not line.startswith((" ", "\t", "#")):
            end = i
            break
    lines = lines[:start] + lines[end:]

if lines and not lines[-1].endswith("\n"):
    lines[-1] += "\n"
lines.extend([
    "deliverable:\n",
    f"  head_sha: {head_sha}\n",
    "  verification:\n",
    "    status: PASS\n",
    "    ac_counts:\n",
    "      ac_total: 0\n",
    "      ac_pass: 0\n",
    "      ac_fail: 0\n",
    "      ac_manual_required: 0\n",
    "      ac_uncertain: 0\n",
])
tmp_path.write_text("---\n" + "".join(lines) + "---\n" + text[match.end():], encoding="utf-8")
PY
  then
    rm -rf "$TMP_DIR" 2>/dev/null || true
    die "no-PR deliverable rewriter failed"
  fi

  if ! python3 - "$TMP_FILE" "$HEAD_SHA" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
head = sys.argv[2]
fm = re.match(r"^---\n(.*?)^---\n", text, re.DOTALL | re.MULTILINE)
assert fm, "missing frontmatter"
body = fm.group(1)
assert not re.search(r"^  pr_(?:url|state):", body, re.MULTILINE), "PR fields present"
assert re.search(rf"^  head_sha:\s*{re.escape(head)}$", body, re.MULTILINE), "head mismatch"
assert re.search(r"^    status:\s*PASS$", body, re.MULTILINE), "verification status missing"
PY
  then
    rm -rf "$TMP_DIR" 2>/dev/null || true
    die "no-PR deliverable read-back validation failed"
  fi

  if ! bash "$SCRIPT_DIR/validate-task-md.sh" "$TMP_FILE" >/dev/null; then
    rm -rf "$TMP_DIR" 2>/dev/null || true
    die "no-PR deliverable task schema validation failed; original preserved"
  fi

  if ! mv "$TMP_FILE" "$TASK_MD"; then
    rm -rf "$TMP_DIR" 2>/dev/null || true
    die "no-PR deliverable atomic replacement failed; original preserved"
  fi
  rmdir "$TMP_DIR" 2>/dev/null || true

  log "Success: canonical no-PR deliverable written and verified in $TASK_MD"
  exit 0
fi

# ── Verification-only aggregate head mode ───────────────────────────────────────

if [[ "${1:-}" == "--verification-aggregate-head" ]]; then
  [[ $# -eq 3 ]] || die "Usage: $SCRIPT_NAME --verification-aggregate-head <task-md-path> <aggregate-head-sha>"

  TASK_MD="$2"
  AGGREGATE_HEAD_SHA="$3"

  [[ -f "$TASK_MD" ]] || die "task.md not found: $TASK_MD"
  if ! printf '%s' "$AGGREGATE_HEAD_SHA" | grep -qE '^[0-9a-fA-F]{7,}$'; then
    die "aggregate-head-sha must be 7+ hex characters, got: $AGGREGATE_HEAD_SHA"
  fi

  TASK_MD="$(cd "$(dirname "$TASK_MD")" && pwd)/$(basename "$TASK_MD")"
  TMP_FILE="${TASK_MD}.tmp"

  VERIFY_HEAD_REWRITER=$(cat <<'PYEOF'
import re
import sys

task_path = sys.argv[1]
tmp_path = sys.argv[2]
aggregate_head = sys.argv[3]

with open(task_path, "r", encoding="utf-8") as f:
    content = f.read()

fm_pattern = re.compile(r"^---\n(.*?)^---\n", re.DOTALL | re.MULTILINE)
match = fm_pattern.match(content)
if not match:
    print("NO_FRONTMATTER", end="")
    sys.exit(1)

fm_body = match.group(1)
lines = fm_body.splitlines(keepends=True)

deliverable_start = None
for index, line in enumerate(lines):
    if re.match(r"^deliverable:\s*(?:#.*)?$", line.rstrip("\n")):
        deliverable_start = index
        break

if deliverable_start is None:
    print("NO_DELIVERABLE", end="")
    sys.exit(1)

deliverable_end = len(lines)
for index in range(deliverable_start + 1, len(lines)):
    line = lines[index]
    stripped = line.strip()
    is_top_level = line[:1] not in (" ", "\t") and stripped and not stripped.startswith("#")
    if is_top_level:
        deliverable_end = index
        break

verification_start = None
verification_end = None
for index in range(deliverable_start + 1, deliverable_end):
    if re.match(r"^[ \t]{2}verification:\s*(?:#.*)?$", lines[index].rstrip("\n")):
        verification_start = index
        break

if verification_start is None:
    lines[deliverable_end:deliverable_end] = [
        "  verification:\n",
        f"    aggregate_head_sha: {aggregate_head}\n",
    ]
else:
    verification_end = deliverable_end
    for index in range(verification_start + 1, deliverable_end):
        line = lines[index]
        stripped = line.strip()
        indent = len(line) - len(line.lstrip(" \t"))
        if stripped and indent <= 2:
            verification_end = index
            break

    replaced = False
    for index in range(verification_start + 1, verification_end):
        if re.match(r"^[ \t]{4}aggregate_head_sha:", lines[index]):
            lines[index] = f"    aggregate_head_sha: {aggregate_head}\n"
            replaced = True
            break
    if not replaced:
        lines[verification_end:verification_end] = [f"    aggregate_head_sha: {aggregate_head}\n"]

new_content = "---\n" + "".join(lines) + "---\n" + content[match.end():]

with open(tmp_path, "w", encoding="utf-8") as f:
    f.write(new_content)
PYEOF
)

  VERIFY_HEAD_VERIFIER=$(cat <<'PYEOF'
import re
import sys

task_path = sys.argv[1]
expected = sys.argv[2]

with open(task_path, "r", encoding="utf-8") as f:
    content = f.read()

fm_pattern = re.compile(r"^---\n(.*?)^---\n", re.DOTALL | re.MULTILINE)
match = fm_pattern.match(content)
if not match:
    print("NO_FRONTMATTER", end="")
    sys.exit(1)

found = re.search(r"^    aggregate_head_sha:\s*(.+)$", match.group(1), re.MULTILINE)
if not found:
    print("NO_AGGREGATE_HEAD", end="")
    sys.exit(1)
if found.group(1).strip() != expected:
    print(f"MISMATCH:{found.group(1).strip()}", end="")
    sys.exit(1)

print("OK", end="")
PYEOF
)

  log "Writing verification aggregate head in $TASK_MD..."
  if ! write_error=$(python3 - "$TASK_MD" "$TMP_FILE" "$AGGREGATE_HEAD_SHA" <<< "$VERIFY_HEAD_REWRITER" 2>&1); then
    rm -f "$TMP_FILE" 2>/dev/null || true
    die "verification aggregate head rewriter failed: $write_error"
  fi
  if ! mv_error=$(mv "$TMP_FILE" "$TASK_MD" 2>&1); then
    rm -f "$TMP_FILE" 2>/dev/null || true
    die "verification aggregate head mv failed: $mv_error"
  fi
  verify_result=$(python3 - "$TASK_MD" "$AGGREGATE_HEAD_SHA" <<< "$VERIFY_HEAD_VERIFIER" 2>&1) || true
  [[ "$verify_result" == "OK" ]] || die "verification aggregate head read-back failed: $verify_result"
  log "Success: verification aggregate head written in $TASK_MD"
  exit 0
fi

# ── Argument validation ─────────────────────────────────────────────────────────

VERIFICATION_PASS=0
REPO_ROOT=""
if [[ "${1:-}" == "--verification-pass" ]]; then
  VERIFICATION_PASS=1
  [[ $# -eq 7 && "${6:-}" == "--repo" ]] \
    || die "Usage: $SCRIPT_NAME --verification-pass <task-md-path> <pr-url> <pr-state> <head-sha> --repo <repo-root>"
  TASK_MD="$2"
  PR_URL="$3"
  PR_STATE="$4"
  HEAD_SHA="$5"
  REPO_ROOT="$7"
else
  [[ $# -eq 4 ]] || die "Usage: $SCRIPT_NAME <task-md-path> <pr-url> <pr-state> <head-sha>"
  TASK_MD="$1"
  PR_URL="$2"
  PR_STATE="$3"
  HEAD_SHA="$4"
fi

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

if [[ "$VERIFICATION_PASS" -eq 1 ]]; then
  [[ -d "$REPO_ROOT" ]] || die "repo root not found: $REPO_ROOT"
  REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"
  validate_pr_verification_proof "$TASK_MD" "$HEAD_SHA" "$REPO_ROOT"
fi

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
verification_pass = sys.argv[6] == '1'

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
    )
    if verification_pass:
        deliverable_fm += (
            '  verification:\n'
            '    status: PASS\n'
            '    ac_counts:\n'
            '      ac_total: 0\n'
            '      ac_pass: 0\n'
            '      ac_fail: 0\n'
            '      ac_manual_required: 0\n'
            '      ac_uncertain: 0\n'
        )
    deliverable_fm += '---\n'
    new_content = deliverable_fm + content
else:
    fm_body = match.group(1)

    lines = fm_body.splitlines(keepends=True)
    deliverable_start = None
    deliverable_end = None

    for index, line in enumerate(lines):
        if re.match(r'^deliverable:\s*(?:#.*)?$', line.rstrip('\n')):
            deliverable_start = index
            break

    verification_lines = []
    if deliverable_start is not None:
        deliverable_end = len(lines)
        for index in range(deliverable_start + 1, len(lines)):
            line = lines[index]
            stripped = line.strip()
            is_top_level = line[:1] not in (' ', '\t') and stripped and not stripped.startswith('#')
            if is_top_level:
                deliverable_end = index
                break

        deliverable_lines = lines[deliverable_start:deliverable_end]
        verification_start = None
        verification_end = None

        for index, line in enumerate(deliverable_lines):
            if re.match(r'^[ \t]{2}verification:\s*(?:#.*)?$', line.rstrip('\n')):
                verification_start = index
                break

        if verification_start is not None:
            verification_end = len(deliverable_lines)
            for index in range(verification_start + 1, len(deliverable_lines)):
                line = deliverable_lines[index]
                stripped = line.strip()
                indent = len(line) - len(line.lstrip(' \t'))
                if stripped and indent <= 2:
                    verification_end = index
                    break
            verification_lines = deliverable_lines[verification_start:verification_end]

        cleaned_lines = lines[:deliverable_start] + lines[deliverable_end:]
        cleaned_fm = ''.join(cleaned_lines)
    else:
        cleaned_fm = fm_body

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
    if verification_lines:
        if verification_pass:
            status_replaced = False
            status_lines = []
            for line in verification_lines:
                if re.match(r'^[ \t]{4}status:', line):
                    status_lines.append('    status: PASS\n')
                    status_replaced = True
                else:
                    status_lines.append(line)
            if not status_replaced:
                status_lines.insert(1, '    status: PASS\n')
            if not any(re.match(r'^[ \t]{4}ac_counts:', line) for line in status_lines):
                status_lines.extend([
                    '    ac_counts:\n',
                    '      ac_total: 0\n',
                    '      ac_pass: 0\n',
                    '      ac_fail: 0\n',
                    '      ac_manual_required: 0\n',
                    '      ac_uncertain: 0\n',
                ])
            else:
                existing_count_fields = {
                    match.group(1)
                    for line in status_lines
                    for match in [re.match(r'^[ \t]{6}(ac_(?:total|pass|fail|manual_required|uncertain)):', line)]
                    if match
                }
                for field in ('ac_total', 'ac_pass', 'ac_fail', 'ac_manual_required', 'ac_uncertain'):
                    if field not in existing_count_fields:
                        status_lines.append(f'      {field}: 0\n')
            verification_lines = status_lines
        cleaned_fm += ''.join(verification_lines)
    elif verification_pass:
        cleaned_fm += (
            '  verification:\n'
            '    status: PASS\n'
            '    ac_counts:\n'
            '      ac_total: 0\n'
            '      ac_pass: 0\n'
            '      ac_fail: 0\n'
            '      ac_manual_required: 0\n'
            '      ac_uncertain: 0\n'
        )
    if not cleaned_fm.endswith('\n'):
        cleaned_fm += '\n'

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
expect_verification_pass = sys.argv[3] == '1'

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

if expect_verification_pass:
    status_match = re.search(r'^    status:\s*PASS\s*$', fm_body, re.MULTILINE)
    if not status_match:
        print('NO_VERIFICATION_PASS', end='')
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
  if ! write_error=$(python3 - "$TASK_MD" "$TMP_FILE" "$PR_URL" "$PR_STATE" "$HEAD_SHA" "$VERIFICATION_PASS" <<< "$REWRITER" 2>&1); then
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
      verify_result=$(python3 - "$TASK_MD" "$PR_URL" "$VERIFICATION_PASS" <<< "$VERIFIER" 2>&1) || true

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
